import Foundation

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
            .appendingPathComponent("BigTalk_Prompts_\(Date().formatted(.dateTime.year().month().day()))")
            .appendingPathExtension("csv")

        try csv.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    }

    @MainActor
    func shareCSV(prompts: [Prompt]) {
        guard let url = try? exportToCSV(prompts: prompts) else { return }
        SharePresenter.present(url: url)
    }

    // MARK: - Import

    /// The file's prompts, and how many rows were skipped for having no
    /// prompt text. One bad row used to abort the whole file.
    func parseCSV(from url: URL) throws -> (prompts: [PromptImportData], skipped: Int) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let content = try String(contentsOf: url, encoding: .utf8)
        let result = Self.parse(content)
        guard !result.prompts.isEmpty else { throw PromptCSVError.emptyFile }
        return result
    }

    /// `text,category,difficulty` rows under a header row. Only the text is
    /// required: an unknown category files under Personal Growth, an unknown
    /// difficulty reads as medium, and a row with no text is skipped and
    /// counted rather than failing the import.
    static func parse(_ content: String) -> (prompts: [PromptImportData], skipped: Int) {
        let rows = records(in: content).filter { row in
            row.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }

        var prompts: [PromptImportData] = []
        var skipped = 0
        for fields in rows.dropFirst() {
            let text = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                skipped += 1
                continue
            }

            let category = fields.count > 1
                ? PromptCategory(rawValue: fields[1].trimmingCharacters(in: .whitespacesAndNewlines))
                : nil
            let difficulty = fields.count > 2
                ? PromptDifficulty(rawValue: fields[2].trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
                : nil

            prompts.append(PromptImportData(
                text: text,
                category: (category ?? .personalGrowth).rawValue,
                difficulty: difficulty ?? .medium
            ))
        }
        return (prompts, skipped)
    }

    // MARK: - Duplicates

    /// `items` without any prompt the library already has or that repeats an
    /// earlier item - case and surrounding whitespace do not make a prompt
    /// new. CSV import and batch add share this one rule.
    static func removingDuplicates<Item>(
        _ items: [Item],
        text: (Item) -> String,
        existing: [String]
    ) -> (unique: [Item], duplicates: Int) {
        var seen = Set(existing.map(dedupeKey))
        let unique = items.filter { seen.insert(dedupeKey(text($0))).inserted }
        return (unique, items.count - unique.count)
    }

    private static func dedupeKey(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - CSV Helpers (RFC 4180)

    private func escapeCSVField(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains(where: \.isNewline) {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }

    /// Splits CSV text into rows of fields. Quotes hold across lines: a comma
    /// or a line break inside quotes belongs to the field, and `""` is a
    /// literal quote. The file used to be split into lines first, so a prompt
    /// exported with a line break came back as two broken rows.
    static func records(in content: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var previous: Character?

        for char in content {
            if inQuotes {
                if char == "\"" {
                    inQuotes = false
                } else {
                    field.append(char)
                }
            } else if char == "\"" {
                // Straight after a closing quote, a quote is an escaped one.
                if previous == "\"" { field.append(char) }
                inQuotes = true
            } else if char == "," {
                row.append(field)
                field = ""
            } else if char.isNewline {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(char)
            }
            previous = char
        }

        if !row.isEmpty || !field.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
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
    /// No row with prompt text: an empty file, a header on its own, or every
    /// row missing its first column.
    case emptyFile

    var errorDescription: String? {
        "No prompts found. Put one prompt per row in the first column, under a header row: text, category, difficulty."
    }
}
