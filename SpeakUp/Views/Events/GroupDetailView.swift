import SwiftUI
import SwiftData

struct GroupDetailView: View {
    let group: RecordingGroup
    @Query private var groupRecordings: [Recording]
    @State private var selectedRecordingId: String?

    init(group: RecordingGroup) {
        self.group = group
        let groupId = group.id
        _groupRecordings = Query(
            filter: #Predicate<Recording> { $0.groupId == groupId },
            sort: \Recording.date,
            order: .reverse
        )
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
                                Button {
                                    selectedRecordingId = recording.id.uuidString
                                } label: {
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
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle(group.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedRecordingId) { recordingId in
            RecordingDetailView(recordingId: recordingId)
        }
    }
}
