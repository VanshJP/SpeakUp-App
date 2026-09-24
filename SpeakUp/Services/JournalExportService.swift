import Foundation
import SwiftUI
import UIKit

// MARK: - Snapshot

/// Everything the journal prints for one take, read from a background
/// `ModelContext` so rendering never touches a model object.
nonisolated struct JournalEntry: Sendable {
    /// The analysis numbers the journal prints. Only headline fields, so the
    /// lossy SwiftData `analysis` is enough - no `fullAnalysis` mirror decode.
    nonisolated struct Stats: Sendable {
        let overall: Int
        let subscores: SpeechSubscores
        let wordsPerMinute: Double
        let totalWords: Int
        let totalFillerCount: Int
        let pauseCount: Int
        let fillerWords: [FillerWord]
        let vocabWordsUsed: [VocabWordUsage]
    }

    let date: Date
    let displayTitle: String
    let actualDuration: TimeInterval
    let category: String?
    let drillMode: String?
    let stats: Stats?
    let transcript: String?

    /// Decodes `analysis` once. Call on the context that fetched `recording`.
    init(_ recording: Recording) {
        date = recording.date
        displayTitle = recording.displayTitle
        actualDuration = recording.actualDuration
        category = recording.prompt?.category
        drillMode = recording.drillMode
        stats = recording.analysis.map { analysis in
            Stats(
                overall: analysis.speechScore.overall,
                subscores: analysis.speechScore.subscores,
                wordsPerMinute: analysis.wordsPerMinute,
                totalWords: analysis.totalWords,
                totalFillerCount: analysis.totalFillerCount,
                pauseCount: analysis.pauseCount,
                fillerWords: analysis.fillerWords,
                vocabWordsUsed: analysis.vocabWordsUsed
            )
        }
        transcript = Self.resolvedTranscript(for: recording)
    }

    private static func resolvedTranscript(for recording: Recording) -> String? {
        let wordsTranscript = recording.transcriptionWords?
            .map(\.word)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let wordsTranscript, !wordsTranscript.isEmpty {
            return wordsTranscript
        }

        let fallbackText = recording.transcriptionText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let fallbackText, !fallbackText.isEmpty {
            return fallbackText
        }

        return nil
    }
}

/// An unlocked achievement as the journal prints it.
nonisolated struct JournalAchievement: Sendable {
    let icon: String
    let title: String
}

// MARK: - Renderer

/// Lays out the journal PDF from value snapshots. Pure UIKit drawing, safe to
/// run off the main actor - `JournalExportView` runs it in a detached task.
nonisolated class JournalExportService {

    private let pageWidth: CGFloat = 612
    private let pageHeight: CGFloat = 792
    private let margin: CGFloat = 50
    private var contentWidth: CGFloat { pageWidth - margin * 2 }

    // Reusable text styles
    private let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 28, weight: .bold),
        .foregroundColor: UIColor.black
    ]
    private let headerAttrs: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 18, weight: .semibold),
        .foregroundColor: UIColor.black
    ]
    private let subheaderAttrs: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
        .foregroundColor: UIColor.darkGray
    ]
    private let bodyAttrs: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 12),
        .foregroundColor: UIColor.black
    ]
    private let captionAttrs: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 11),
        .foregroundColor: UIColor.gray
    ]
    private let footerAttrs: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 10),
        .foregroundColor: UIColor.gray
    ]

    /// `entries` must be oldest first. `achievements` holds the unlocked ones
    /// to print; pass none to leave the section out.
    func generatePDF(
        entries: [JournalEntry],
        dateRange: String,
        achievements: [JournalAchievement]
    ) -> Data {
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        let analyzed = entries.compactMap(\.stats)

        let totalSessions = entries.count
        let totalMinutes = Int(entries.reduce(0.0) { $0 + $1.actualDuration }) / 60
        let scores = analyzed.map(\.overall)
        let avgScore = scores.isEmpty ? 0 : scores.reduce(0, +) / scores.count
        let improvement = scores.count >= 2 ? (scores.last ?? 0) - (scores.first ?? 0) : 0

        let data = pdfRenderer.pdfData { context in
            var y = beginNewPage(context)

            // MARK: - Title
            y = drawText("Big Talk Progress Journal", at: y, attrs: titleAttrs)
            y = drawText(dateRange, at: y, attrs: captionAttrs)
            y += 8
            y = drawSeparator(at: y, context: context)

            // MARK: - Summary
            y = drawText("Summary", at: y, attrs: headerAttrs)
            y += 4

            let summaryLines = [
                "Total Sessions: \(totalSessions)",
                "Total Practice Time: \(totalMinutes) minutes",
                "Average Score: \(avgScore)/100",
                "Score Change: \(improvement >= 0 ? "+" : "")\(improvement) points",
                "Most Improved: \(mostImprovedMetric(analyzed))"
            ]
            for line in summaryLines {
                y = drawText(line, at: y, attrs: bodyAttrs, indent: 10)
            }

            // Subscore averages
            if !analyzed.isEmpty {
                y += 8
                y = drawText("Average Subscores", at: y, attrs: subheaderAttrs, indent: 10)
                let subscores = analyzed.map(\.subscores)
                let avgClarity = subscores.map(\.clarity).reduce(0, +) / subscores.count
                let avgPace = subscores.map(\.pace).reduce(0, +) / subscores.count
                let avgFiller = subscores.map(\.fillerUsage).reduce(0, +) / subscores.count
                let avgPause = subscores.map(\.pauseQuality).reduce(0, +) / subscores.count
                y = drawText("Clarity: \(avgClarity)/100  •  Pace: \(avgPace)/100  •  Filler Usage: \(avgFiller)/100  •  Pauses: \(avgPause)/100", at: y, attrs: bodyAttrs, indent: 10)
            }

            // Top filler words across all sessions
            let allFillers = aggregateFillerWords(from: analyzed)
            if !allFillers.isEmpty {
                y += 8
                y = drawText("Most Common Filler Words", at: y, attrs: subheaderAttrs, indent: 10)
                let fillerSummary = allFillers.prefix(5).map { "\"\($0.word)\" (\($0.count)x)" }.joined(separator: ", ")
                y = drawText(fillerSummary, at: y, attrs: bodyAttrs, indent: 10)
            }

            y += 10
            y = drawSeparator(at: y, context: context)

            // MARK: - Achievements
            if !achievements.isEmpty {
                y = checkPageBreak(y: y, needed: 60, context: context)
                y = drawText("Achievements Unlocked (\(achievements.count))", at: y, attrs: headerAttrs)
                y += 4

                for achievement in achievements {
                    y = checkPageBreak(y: y, needed: 20, context: context)
                    y = drawText("\(achievement.icon) \(achievement.title)", at: y, attrs: bodyAttrs, indent: 10)
                }

                y += 10
                y = drawSeparator(at: y, context: context)
            }

            // MARK: - Individual Sessions
            y = checkPageBreak(y: y, needed: 60, context: context)
            y = drawText("Session Details (\(entries.count) sessions)", at: y, attrs: headerAttrs)
            y += 6

            for (index, entry) in entries.enumerated() {
                // Estimate space needed for this session
                let estimatedHeight: CGFloat = entry.stats != nil ? 160 : 60
                y = checkPageBreak(y: y, needed: estimatedHeight, context: context)

                // Session header
                let sessionNum = index + 1
                let dateStr = entry.date.formatted(date: .abbreviated, time: .shortened)
                let title = entry.displayTitle
                let durationStr = entry.actualDuration.minutesSeconds

                y = drawText("Session \(sessionNum): \(title)", at: y, attrs: subheaderAttrs)
                y = drawText("\(dateStr)  •  Duration: \(durationStr)", at: y, attrs: captionAttrs, indent: 0)
                y += 2

                if let category = entry.category {
                    y = drawText("Category: \(category)", at: y, attrs: captionAttrs, indent: 0)
                }

                if let drillMode = entry.drillMode {
                    y = drawText("Mode: \(drillMode)", at: y, attrs: captionAttrs, indent: 0)
                }

                if let analysis = entry.stats {
                    y += 4

                    // Score + subscores
                    let scoreStr = "Score: \(analysis.overall)/100"
                    let sub = analysis.subscores
                    let subscoreStr = "Clarity: \(sub.clarity)  •  Pace: \(sub.pace)  •  Fillers: \(sub.fillerUsage)  •  Pauses: \(sub.pauseQuality)"
                    y = drawText(scoreStr, at: y, attrs: bodyAttrs, indent: 10)
                    y = drawText(subscoreStr, at: y, attrs: captionAttrs, indent: 10)
                    y += 2

                    // Key metrics
                    let metricsStr = "WPM: \(Int(analysis.wordsPerMinute))  •  Words: \(analysis.totalWords)  •  Fillers: \(analysis.totalFillerCount)  •  Pauses: \(analysis.pauseCount)"
                    y = drawText(metricsStr, at: y, attrs: bodyAttrs, indent: 10)

                    // Filler breakdown for this session
                    if !analysis.fillerWords.isEmpty {
                        let topFillers = analysis.fillerWords.prefix(5).map { "\"\($0.word)\" (\($0.count)x)" }.joined(separator: ", ")
                        y = drawText("Fillers: \(topFillers)", at: y, attrs: captionAttrs, indent: 10)
                    }

                    // Vocab words used
                    if !analysis.vocabWordsUsed.isEmpty {
                        let vocabStr = analysis.vocabWordsUsed.map { "\($0.word) (\($0.count)x)" }.joined(separator: ", ")
                        y = drawText("Vocab used: \(vocabStr)", at: y, attrs: captionAttrs, indent: 10)
                    }
                }

                // Transcript
                if let transcript = entry.transcript {
                    y += 4
                    y = checkPageBreak(y: y, needed: 40, context: context)
                    y = drawText("Transcript:", at: y, attrs: subheaderAttrs, indent: 10)

                    let transcriptAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 10),
                        .foregroundColor: UIColor.darkGray
                    ]

                    // Draw transcript with word wrapping, handling page breaks
                    y = drawWrappedText(transcript, at: y, attrs: transcriptAttrs, indent: 10, context: context)
                }

                y += 12

                // Light separator between sessions
                if index < entries.count - 1 {
                    y = drawLightSeparator(at: y, context: context)
                    y += 6
                }
            }

            // MARK: - Footer on last page
            drawFooter(context: context)
        }

        return data
    }

    // MARK: - Drawing Helpers

    private func beginNewPage(_ context: UIGraphicsPDFRendererContext) -> CGFloat {
        context.beginPage()
        UIColor.white.setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
        return margin
    }

    private func drawText(_ text: String, at y: CGFloat, attrs: [NSAttributedString.Key: Any], indent: CGFloat = 0) -> CGFloat {
        let x = margin + indent
        let maxWidth = contentWidth - indent
        let size = (text as NSString).boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: attrs,
            context: nil
        )
        (text as NSString).draw(in: CGRect(x: x, y: y, width: maxWidth, height: size.height), withAttributes: attrs)
        return y + size.height + 4
    }

    private func drawWrappedText(_ text: String, at startY: CGFloat, attrs: [NSAttributedString.Key: Any], indent: CGFloat, context: UIGraphicsPDFRendererContext) -> CGFloat {
        let x = margin + indent
        let maxWidth = contentWidth - indent
        let maxChunkHeight: CGFloat = pageHeight - margin - 30 // leave room for footer

        // Split into paragraphs to handle page breaks gracefully
        let paragraphs = text.components(separatedBy: "\n")
        var y = startY

        for paragraph in paragraphs {
            let trimmed = paragraph.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            let fullSize = (trimmed as NSString).boundingRect(
                with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                attributes: attrs,
                context: nil
            )

            // Check if we need a page break
            if y + min(fullSize.height, 40) > maxChunkHeight {
                drawFooter(context: context)
                y = beginNewPage(context)
            }

            // If the paragraph fits on the remaining page, draw it
            let availableHeight = maxChunkHeight - y
            if fullSize.height <= availableHeight {
                (trimmed as NSString).draw(in: CGRect(x: x, y: y, width: maxWidth, height: fullSize.height), withAttributes: attrs)
                y += fullSize.height + 2
            } else {
                // Text is taller than remaining page space - draw what fits, continue on next page
                let drawHeight = availableHeight
                (trimmed as NSString).draw(in: CGRect(x: x, y: y, width: maxWidth, height: drawHeight), withAttributes: attrs)
                y += drawHeight + 2

                // If there's significant overflow, start a new page and draw the rest
                if fullSize.height > availableHeight + 20 {
                    drawFooter(context: context)
                    y = beginNewPage(context)
                    let remainingHeight = fullSize.height - availableHeight
                    (trimmed as NSString).draw(in: CGRect(x: x, y: y, width: maxWidth, height: remainingHeight), withAttributes: attrs)
                    y += remainingHeight + 2
                }
            }
        }

        return y
    }

    private func drawSeparator(at y: CGFloat, context: UIGraphicsPDFRendererContext) -> CGFloat {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: margin, y: y))
        path.addLine(to: CGPoint(x: pageWidth - margin, y: y))
        UIColor.black.withAlphaComponent(0.15).setStroke()
        path.lineWidth = 1
        path.stroke()
        return y + 16
    }

    private func drawLightSeparator(at y: CGFloat, context: UIGraphicsPDFRendererContext) -> CGFloat {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: margin + 20, y: y))
        path.addLine(to: CGPoint(x: pageWidth - margin - 20, y: y))
        UIColor.black.withAlphaComponent(0.08).setStroke()
        path.lineWidth = 0.5
        path.stroke()
        return y + 8
    }

    private func drawFooter(context: UIGraphicsPDFRendererContext) {
        let footer = "Generated by Big Talk on \(Date().formatted(date: .long, time: .shortened))"
        (footer as NSString).draw(at: CGPoint(x: margin, y: pageHeight - margin + 10), withAttributes: footerAttrs)
    }

    private func checkPageBreak(y: CGFloat, needed: CGFloat, context: UIGraphicsPDFRendererContext) -> CGFloat {
        let maxY = pageHeight - margin - 30
        if y + needed > maxY {
            drawFooter(context: context)
            return beginNewPage(context)
        }
        return y
    }

    // MARK: - Data Helpers

    private func mostImprovedMetric(_ analyzed: [JournalEntry.Stats]) -> String {
        guard analyzed.count >= 2, let f = analyzed.first?.subscores, let l = analyzed.last?.subscores else { return "N/A" }

        let improvements = [
            ("Clarity", l.clarity - f.clarity),
            ("Pace", l.pace - f.pace),
            ("Filler Usage", l.fillerUsage - f.fillerUsage),
            ("Pause Quality", l.pauseQuality - f.pauseQuality)
        ]

        return improvements.max(by: { $0.1 < $1.1 })?.0 ?? "N/A"
    }

    private func aggregateFillerWords(from analyzed: [JournalEntry.Stats]) -> [FillerWord] {
        var totals: [String: Int] = [:]

        for stats in analyzed {
            for filler in stats.fillerWords {
                totals[filler.word, default: 0] += filler.count
            }
        }

        return totals.map { FillerWord(word: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }
}
