import Foundation
import SwiftData

@Model
final class RecordingGroup {
    var id: UUID = UUID()
    var title: String = ""
    var groupDescription: String?
    var createdDate: Date = Date()
    var isArchived: Bool = false

    init(
        id: UUID = UUID(),
        title: String,
        groupDescription: String? = nil,
        createdDate: Date = Date(),
        isArchived: Bool = false
    ) {
        self.id = id
        self.title = title
        self.groupDescription = groupDescription
        self.createdDate = createdDate
        self.isArchived = isArchived
    }
}
