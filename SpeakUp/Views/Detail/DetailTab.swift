import SwiftUI

enum DetailTab: String, CaseIterable, Identifiable {
    /// Renamed from "Analysis": the tab now holds the evidence behind the
    /// score rather than being one of three peer sections.
    case breakdown = "Breakdown"
    case transcript = "Transcript"
    case coaching = "Coaching"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .breakdown: return "chart.bar.fill"
        case .transcript: return "text.alignleft"
        case .coaching: return "lightbulb.fill"
        }
    }
}
