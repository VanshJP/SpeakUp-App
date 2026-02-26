import Foundation
import UIKit

// MARK: - CSV Service

@Observable
class PromptCSVService {

    // MARK: - Export

    func exportToCSV(prompts: [Prompt]) throws -> URL {
        guard !prompts.isEmpty else { throw PromptCSVError.emptyFile }

        var csv = "text,category,difficulty\n"
        for prompt in prompts {
            let escapedText = escapeCSVField(prompt.text)
            let escapedCategory = escapeCSVField(prompt.category)
            csv += "\(escapedText),\(escapedCategory),\(prompt.difficulty.rawValue)\n"
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpeakUp_Prompts_\(Date().formatted(.dateTime.year().month().day()))")
            .appendingPathExtension("csv")

        try csv.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    }

    @MainActor
    func shareCSV(prompts: [Prompt]) {
        guard let url = try? exportToCSV(prompts: prompts) else { return }

        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = rootVC.view
                popover.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            rootVC.present(activityVC, animated: true)
        }
    }

    // MARK: - Import

    func parseCSV(from url: URL) throws -> [PromptImportData] {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        guard lines.count > 1 else { throw PromptCSVError.emptyFile }

        var results: [PromptImportData] = []

        for (index, line) in lines.dropFirst().enumerated() {
            let row = index + 2 // 1-indexed, skip header
            let fields = parseCSVLine(line)

            guard fields.count >= 1 else {
                throw PromptCSVError.parseError(row: row, detail: "Empty row")
            }

            let text = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw PromptCSVError.parseError(row: row, detail: "Empty prompt text")
            }

            let category: String
            if fields.count >= 2 {
                let raw = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
                // Validate category or default to Personal Growth
                if PromptCategory(rawValue: raw) != nil {
                    category = raw
                } else {
                    category = PromptCategory.personalGrowth.rawValue
                }
            } else {
                category = PromptCategory.personalGrowth.rawValue
            }

            let difficulty: PromptDifficulty
            if fields.count >= 3 {
                let raw = fields[2].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                difficulty = PromptDifficulty(rawValue: raw) ?? .medium
            } else {
                difficulty = .medium
            }

            results.append(PromptImportData(text: text, category: category, difficulty: difficulty))
        }

        guard !results.isEmpty else { throw PromptCSVError.emptyFile }
        return results
    }

    // MARK: - CSV Helpers (RFC 4180)

    private func escapeCSVField(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var chars = line.makeIterator()

        while let char = chars.next() {
            if inQuotes {
                if char == "\"" {
                    // Check for escaped quote
                    if let next = chars.next() {
                        if next == "\"" {
                            current.append("\"")
                        } else {
                            inQuotes = false
                            if next == "," {
                                fields.append(current)
                                current = ""
                            } else {
                                current.append(next)
                            }
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    current.append(char)
                }
            } else {
                if char == "\"" {
                    inQuotes = true
                } else if char == "," {
                    fields.append(current)
                    current = ""
                } else {
                    current.append(char)
                }
            }
        }
        fields.append(current)
        return fields
    }
}

// MARK: - Import Data

struct PromptImportData {
    let text: String
    let category: String
    let difficulty: PromptDifficulty
}

// MARK: - Errors

enum PromptCSVError: LocalizedError {
    case invalidFormat
    case emptyFile
    case parseError(row: Int, detail: String)

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "The CSV file format is invalid."
        case .emptyFile:
            return "The file contains no prompts to import."
        case .parseError(let row, let detail):
            return "Error on row \(row): \(detail)"
        }
    }
}
