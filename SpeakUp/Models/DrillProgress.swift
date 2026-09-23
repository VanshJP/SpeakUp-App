import Foundation

// MARK: - Drill Record

/// What the app remembers about one drill between sessions: the best and
/// latest scores, how many runs, and the rung of its duration ladder.
///
/// Drill results used to evaporate the moment the result screen closed, so a
/// drill had no memory of the last attempt and nothing to beat. Deliberate
/// practice runs on exactly that loop - a target, a try, a number to compare.
nonisolated struct DrillRecord: Codable, Equatable, Sendable {
    var best: Int = 0
    var last: Int = 0
    var runs: Int = 0
    /// Index into `DrillMode.durationLadder`. Climbs on a pass, never falls.
    var level: Int = 0

    init(best: Int = 0, last: Int = 0, runs: Int = 0, level: Int = 0) {
        self.best = best
        self.last = last
        self.runs = runs
        self.level = level
    }

    /// The record after one more run. Pure, so the ladder rules are pinned
    /// without `UserDefaults`.
    ///
    /// - Parameters:
    ///   - rungs: How many rungs the drill's ladder has. A pass on the top
    ///     rung stays there.
    ///   - ranLevel: The rung the run used; nil means the highest one open.
    ///     Only a pass at the highest open rung opens the next. A pass on a
    ///     shorter round someone chose to repeat used to climb too, so two
    ///     easy 15-second runs unlocked 45 seconds without ever running 30.
    static func folding(
        _ previous: DrillRecord?,
        score: Int,
        passed: Bool,
        rungs: Int,
        ranLevel: Int? = nil
    ) -> DrillRecord {
        var record = previous ?? DrillRecord()
        record.best = max(record.best, score)
        record.last = score
        record.runs += 1
        let ran = ranLevel ?? record.level
        if passed, ran >= record.level {
            record.level = min(ran + 1, max(0, rungs - 1))
        }
        return record
    }
}

// MARK: - Drill Progress Store

/// Drill records in `UserDefaults`, one JSON blob for every mode. Drills never
/// produce a `Recording`, so there is no SwiftData row to hang this on, and a
/// handful of integers per drill does not justify a schema change.
enum DrillProgressStore {
    private static let recordsKey = "drills.records.v1"

    private static var defaults: UserDefaults { .standard }

    /// Decoded once per launch. `DrillMode.description` reads through here,
    /// and view bodies read that on every render.
    private static var cached: [String: DrillRecord]?

    static func record(for mode: DrillMode) -> DrillRecord? {
        records[mode.rawValue]
    }

    /// Folds a finished run into the mode's record and saves it.
    ///
    /// - Returns: The updated record and the one it replaced, so the result
    ///   screen can say what changed.
    @discardableResult
    static func recordRun(
        mode: DrillMode,
        score: Int,
        passed: Bool,
        ranLevel: Int? = nil
    ) -> (previous: DrillRecord?, updated: DrillRecord) {
        var all = records
        let previous = all[mode.rawValue]
        let updated = DrillRecord.folding(
            previous,
            score: score,
            passed: passed,
            rungs: mode.durationLadder.count,
            ranLevel: ranLevel
        )
        all[mode.rawValue] = updated
        save(all)
        return (previous, updated)
    }

    private static var records: [String: DrillRecord] {
        if let cached { return cached }
        let decoded = defaults.data(forKey: recordsKey)
            .flatMap { try? JSONDecoder().decode([String: DrillRecord].self, from: $0) }
            ?? [:]
        cached = decoded
        return decoded
    }

    private static func save(_ records: [String: DrillRecord]) {
        cached = records
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: recordsKey)
    }
}
