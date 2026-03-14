import SwiftUI
import SwiftData

struct GroupDetailView: View {
    let group: RecordingGroup
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recording.date, order: .reverse) private var allRecordings: [Recording]

    var groupRecordings: [Recording] {
        let groupId = group.id
        return allRecordings.filter { $0.groupId == groupId }
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 16) {
                    // Group info
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            if let desc = group.groupDescription, !desc.isEmpty {
                                Text(desc)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            HStack {
                                Label("\(groupRecordings.count) recordings", systemImage: "waveform")
                                Spacer()
                                Text("Created \(group.createdDate.formatted(date: .abbreviated, time: .omitted))")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }

                    if groupRecordings.isEmpty {
                        EmptyStateCard(
                            icon: "folder",
                            title: "No Recordings",
                            message: "Recordings linked to this group will appear here."
                        )
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(groupRecordings) { recording in
                                GlassCard(padding: 12) {
                                    HStack(spacing: 12) {
                                        Image(systemName: recording.mediaType.iconName)
                                            .foregroundStyle(.teal)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(recording.displayTitle)
                                                .font(.subheadline.weight(.medium))
                                                .lineLimit(1)

                                            HStack(spacing: 8) {
                                                Text(recording.formattedDate)
                                                Text("•")
                                                Text(recording.formattedDuration)
                                            }
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        if let score = recording.analysis?.speechScore.overall {
                                            Text("\(score)")
                                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                                .foregroundStyle(AppColors.scoreColor(for: score))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle(group.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
