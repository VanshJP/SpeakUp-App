import Foundation
import PDFKit
import UniformTypeIdentifiers

nonisolated struct ImportedReadAloudDocument: Sendable {
    let name: String
    let text: String
}

nonisolated enum ReadAloudDocumentImportError: LocalizedError {
    case unsupportedFormat
    case unreadableDocument
    case emptyDocument

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "Choose a TXT, RTF, HTML, or PDF document."
        case .unreadableDocument:
            return "This document could not be read. Try another file or paste its text."
        case .emptyDocument:
            return "No selectable text was found. Scanned PDFs need OCR before they can be imported."
        }
    }
}

nonisolated enum ReadAloudDocumentImporter {
    static let supportedContentTypes: [UTType] = [
        .plainText,
        .rtf,
        .rtfd,
        .html,
        .pdf
    ]

    static func importDocument(from url: URL) async throws -> ImportedReadAloudDocument {
        try await Task.detached(priority: .userInitiated) {
            let canAccess = url.startAccessingSecurityScopedResource()
            defer {
                if canAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let text = try loadText(from: url)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw ReadAloudDocumentImportError.emptyDocument
            }

            return ImportedReadAloudDocument(
                name: url.deletingPathExtension().lastPathComponent,
                text: text
            )
        }.value
    }

    private static func loadText(from url: URL) throws -> String {
        let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        let pathExtension = url.pathExtension.lowercased()

        if contentType?.conforms(to: .pdf) == true || pathExtension == "pdf" {
            guard let document = PDFDocument(url: url) else {
                throw ReadAloudDocumentImportError.unreadableDocument
            }
            return (0..<document.pageCount)
                .compactMap { document.page(at: $0)?.string }
                .joined(separator: "\n\n")
        }

        if contentType?.conforms(to: .rtf) == true || pathExtension == "rtf" {
            return try attributedText(from: url, type: .rtf)
        }

        if contentType?.conforms(to: .rtfd) == true || pathExtension == "rtfd" {
            return try attributedText(from: url, type: .rtfd)
        }

        if contentType?.conforms(to: .html) == true
            || pathExtension == "html"
            || pathExtension == "htm" {
            return try attributedText(from: url, type: .html)
        }

        if contentType?.conforms(to: .plainText) == true
            || ["txt", "text", "md", "markdown"].contains(pathExtension) {
            return try plainText(from: url)
        }

        throw ReadAloudDocumentImportError.unsupportedFormat
    }

    private static func attributedText(
        from url: URL,
        type: NSAttributedString.DocumentType
    ) throws -> String {
        do {
            return try NSAttributedString(
                url: url,
                options: [.documentType: type],
                documentAttributes: nil
            ).string
        } catch {
            throw ReadAloudDocumentImportError.unreadableDocument
        }
    }

    private static func plainText(from url: URL) throws -> String {
        do {
            let data = try Data(contentsOf: url)
            for encoding in [String.Encoding.utf8, .utf16, .unicode, .ascii] {
                if let text = String(data: data, encoding: encoding) {
                    return text
                }
            }
            throw ReadAloudDocumentImportError.unreadableDocument
        } catch let error as ReadAloudDocumentImportError {
            throw error
        } catch {
            throw ReadAloudDocumentImportError.unreadableDocument
        }
    }
}
