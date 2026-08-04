import Foundation
import Observation
import os

/// Where recorded events go. One implementation ships (on-device); a network
/// sink can be added later without touching a single call site.
protocol AnalyticsSink: AnyObject {
    func record(_ event: RecordedAnalyticsEvent)
    func allEvents() -> [RecordedAnalyticsEvent]
    func reset()
}

/// Coarse behavioural measurement that keeps the no-account, nothing-uploaded
/// promise intact.
///
/// Events are buffered in memory and flushed to a JSON file inside the app's
/// own container. Nothing is transmitted. That is enough to run the launch
/// gates — activation rate, time to value, qualified paywall conversion — from
/// a TestFlight device, and it means adopting a hosted analytics vendor later
/// is a sink swap rather than an instrumentation project.
@MainActor
@Observable
final class AnalyticsService {
    static let shared = AnalyticsService()

    private let logger = Logger(subsystem: "com.vansh.SpeakUpMore", category: "Analytics")
    private var sink: AnalyticsSink

    /// Mirrors the most recent events so the diagnostics screen can render
    /// without re-reading the file on every keystroke.
    private(set) var recentEvents: [RecordedAnalyticsEvent] = []

    private init(sink: AnalyticsSink = LocalAnalyticsSink()) {
        self.sink = sink
        recentEvents = sink.allEvents()
    }

    /// Swap in a different destination (a hosted sink, or a no-op in tests).
    func use(sink newSink: AnalyticsSink) {
        sink = newSink
        recentEvents = newSink.allEvents()
    }

    func log(_ event: AnalyticsEvent) {
        let recorded = RecordedAnalyticsEvent(event: event)
        sink.record(recorded)
        recentEvents.append(recorded)
        if recentEvents.count > LocalAnalyticsSink.retainedEventLimit {
            recentEvents.removeFirst(recentEvents.count - LocalAnalyticsSink.retainedEventLimit)
        }
        logger.debug("\(event.name, privacy: .public)")
    }

    /// Logs an event at most once for the lifetime of the install.
    func logOnce(_ event: AnalyticsEvent, key: String) {
        let flag = "analytics.once.\(key)"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        UserDefaults.standard.set(true, forKey: flag)
        log(event)
    }

    func reset() {
        sink.reset()
        recentEvents = []
    }

    // MARK: - Scorecard

    /// The weekly scorecard, computed on-device from the local event log.
    func scorecard() -> AnalyticsScorecard {
        AnalyticsScorecard(events: sink.allEvents())
    }

    func exportJSON() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(sink.allEvents())
    }
}

// MARK: - Local Sink

/// Append-only on-device log with a hard cap. Writes are debounced to avoid a
/// file write per event during a burst.
final class LocalAnalyticsSink: AnalyticsSink {
    static let retainedEventLimit = 2000

    private let queue = DispatchQueue(label: "com.vansh.SpeakUpMore.analytics", qos: .utility)
    private var events: [RecordedAnalyticsEvent]
    private var flushScheduled = false

    private let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("analytics-events.json")
    }()

    init() {
        events = Self.load(from: fileURL)
    }

    func record(_ event: RecordedAnalyticsEvent) {
        queue.async { [weak self] in
            guard let self else { return }
            self.events.append(event)
            if self.events.count > Self.retainedEventLimit {
                self.events.removeFirst(self.events.count - Self.retainedEventLimit)
            }
            self.scheduleFlush()
        }
    }

    func allEvents() -> [RecordedAnalyticsEvent] {
        queue.sync { events }
    }

    func reset() {
        queue.async { [weak self] in
            guard let self else { return }
            self.events = []
            try? FileManager.default.removeItem(at: self.fileURL)
        }
    }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            self.flushScheduled = false
            self.flush()
        }
    }

    private func flush() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(events) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func load(from url: URL) -> [RecordedAnalyticsEvent] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([RecordedAnalyticsEvent].self, from: data)) ?? []
    }
}

// MARK: - Scorecard

/// The launch metrics the plan governs stage gates with, derived from the
/// local event log. Pure computation over a snapshot — no I/O.
struct AnalyticsScorecard {
    let firstOpens: Int
    let activations: Int
    let practiceStarts: Int
    let analysesCompleted: Int
    let qualifiedPaywallViews: Int
    let purchases: Int
    let shares: Int
    let timeToValueBuckets: [String: Int]

    init(events: [RecordedAnalyticsEvent]) {
        firstOpens = events.filter { $0.name == "first_open" }.count
        activations = events.filter { $0.name == "activated" }.count
        practiceStarts = events.filter { $0.name == "practice_start" }.count
        analysesCompleted = events.filter { $0.name == "analysis_complete" }.count
        qualifiedPaywallViews = events.filter { $0.name == "paywall_qualified" }.count
        purchases = events.filter {
            $0.name == "purchase_result" && $0.dimensions["result"] == "purchased"
        }.count
        shares = events.filter { $0.name == "share_complete" }.count

        var buckets: [String: Int] = [:]
        for event in events where event.name == "activated" {
            guard let bucket = event.dimensions["time_to_value_bucket"] else { continue }
            buckets[bucket, default: 0] += 1
        }
        timeToValueBuckets = buckets
    }

    /// First completed analyses over first opens. On a single device this is
    /// 0 or 1 — it becomes meaningful once beta logs are pooled by hand.
    var activationRate: Double? {
        guard firstOpens > 0 else { return nil }
        return Double(activations) / Double(firstOpens)
    }

    var qualifiedPaywallConversion: Double? {
        guard qualifiedPaywallViews > 0 else { return nil }
        return Double(purchases) / Double(qualifiedPaywallViews)
    }

    /// Sessions that reached a score over sessions that were started. A low
    /// number here means people are recording and then bailing before the
    /// result — a different problem from never recording at all.
    var startToScoreRate: Double? {
        guard practiceStarts > 0 else { return nil }
        return Double(analysesCompleted) / Double(practiceStarts)
    }
}
