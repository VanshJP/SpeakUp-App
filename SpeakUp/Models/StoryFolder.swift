import Foundation
import SwiftData

@Model
final class StoryFolder {
    var id: UUID = UUID()
    var name: String = ""
    var systemImage: String = "folder.fill"
    var colorHex: String = "#0D8488"
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        name: String,
        systemImage: String = "folder.fill",
        colorHex: String = "#0D8488",
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.systemImage = systemImage
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}

// MARK: - Default Folders

extension StoryFolder {
    static let defaults: [(name: String, symbol: String, colorHex: String)] = [
        ("Personal", "heart.fill", "#EC4899"),
        ("Work", "briefcase.fill", "#0D8488"),
        ("Practice Ideas", "lightbulb.fill", "#F59E0B")
    ]
}

// MARK: - Palette

enum StoryFolderPalette {
    static let symbols: [String] = [
        "folder.fill",
        "star.fill",
        "bookmark.fill",
        "heart.fill",
        "briefcase.fill",
        "graduationcap.fill",
        "bolt.fill",
        "lightbulb.fill",
        "mic.fill",
        "person.2.fill",
        "flag.fill",
        "book.fill"
    ]

    static let colors: [String] = [
        "#0D8488", // teal (AppColors.primary)
        "#6366F1", // indigo
        "#F59E0B", // orange
        "#EC4899", // pink
        "#22C55E", // green
        "#EF4444", // red
        "#A855F7", // purple
        "#64748B"  // slate
    ]
}
