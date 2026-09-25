import SwiftUI

/// Stories' filter row - the same `FilterChip` the Prompts tab uses.
/// Do not fork the chip: change `FilterChip` / `SelectedFilterChrome` and both
/// Library halves move together.
struct StoryFolderBar: View {
    @Bindable var viewModel: StoriesViewModel
    var onCreateFolder: () -> Void
    var onEditFolder: (StoryFolder) -> Void

    @State private var pendingDelete: PendingFolderDelete?

    /// What the confirmation shows, copied out before the folder is deleted.
    private struct PendingFolderDelete {
        let folder: StoryFolder
        let storyCount: Int
    }

    /// Zero stories → All + New Folder only. Seeded Personal/Work/Practice Ideas
    /// chips add noise and look like leftover filters when the list is empty.
    private var showsFolderChips: Bool {
        !viewModel.stories.isEmpty
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                tagFilterChip

                chip(selection: .all, title: "All", symbol: "tray.full.fill", color: nil)

                if showsFolderChips {
                    chip(selection: .pinned, title: "Pinned", symbol: "pin.fill", color: AppColors.warning)

                    ForEach(viewModel.foldersForDisplay) { folder in
                        chip(
                            selection: .folder(folder.id),
                            title: folder.name,
                            symbol: folder.systemImage,
                            color: Color(hex: folder.colorHex)
                        )
                        .contextMenu {
                            Button {
                                onEditFolder(folder)
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                pendingDelete = PendingFolderDelete(
                                    folder: folder,
                                    storyCount: viewModel.countForFolder(.folder(folder.id))
                                )
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }

                newFolderChip
            }
        }
        .scrollIndicators(.hidden)
        .alert(
            "Delete Folder?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { pending in
            Button("Delete", role: .destructive) {
                viewModel.deleteFolder(pending.folder)
                Haptics.warning()
            }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(Self.deleteMessage(storyCount: pending.storyCount))
        }
    }

    /// One confirmation wherever a folder is deleted (this chip's menu, the
    /// folder sheet). It used to be instant: deleting unfiles every story in
    /// the folder and in any same-name duplicate, and cannot be undone.
    static func deleteMessage(storyCount: Int) -> String {
        switch storyCount {
        case 0: return "The folder is empty."
        case 1: return "Its story stays in your library, with no folder."
        default: return "Its \(storyCount) stories stay in your library, with no folder."
        }
    }

    private func chip(selection: FolderSelection, title: String, symbol: String, color: Color?) -> some View {
        FilterChip(
            title: title,
            icon: symbol,
            isSelected: viewModel.folderSelection == selection,
            count: viewModel.countForFolder(selection),
            tint: color
        ) {
            Haptics.light()
            withAnimation(.spring(duration: 0.3)) {
                viewModel.setFolderSelection(selection)
            }
        }
    }

    /// A tag tapped on a story's page narrows this list. It used to do so
    /// invisibly, with All still selected and the full count beside it. Now
    /// it is a selected chip, and tapping it clears it - the same rule as
    /// re-tapping a folder.
    @ViewBuilder
    private var tagFilterChip: some View {
        if let tag = viewModel.selectedTagValue {
            FilterChip(title: tag, icon: "xmark", isSelected: true) {
                Haptics.light()
                withAnimation(.spring(duration: 0.3)) {
                    viewModel.clearTagFilter()
                }
            }
            .accessibilityLabel("Tag filter: \(tag)")
            .accessibilityHint("Clears the tag filter")
        }
    }

    /// An action, not a filter - dashed so it never reads as a fifth folder.
    private var newFolderChip: some View {
        Button {
            Haptics.medium()
            onCreateFolder()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.caption2.weight(.bold))
                Text("Folder")
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                Capsule()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.quaternary)
            }
            // Same 44pt target as the FilterChips beside it.
            .frame(minHeight: AppLayout.minHitTarget)
            .contentShape(Capsule())
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityLabel("New folder")
    }
}
