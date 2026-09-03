import SwiftUI

/// Stories' filter row — the same `FilterChip` the Prompts tab uses.
///
/// It used to be a bespoke chip: a saturated capsule filled with the folder's
/// own color when selected, a white count bubble inside it, and a hairline
/// divider splitting built-ins from folders. Two tabs of the same Library then
/// filtered by two different-looking controls, and the selected story chip was
/// the loudest thing on the page. Selection now reads the same everywhere —
/// solid white pill — and the folder's color survives on the glyph, which is
/// where identity belongs. Do not fork the chip again: change `FilterChip` and
/// both tabs move together.
struct StoryFolderBar: View {
    @Bindable var viewModel: StoriesViewModel
    var onCreateFolder: () -> Void
    var onEditFolder: (StoryFolder) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip(selection: .all, title: "All", symbol: "tray.full.fill", color: nil)

                chip(selection: .pinned, title: "Pinned", symbol: "pin.fill", color: AppColors.warning)

                ForEach(viewModel.folders) { folder in
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
                            viewModel.deleteFolder(folder)
                            Haptics.warning()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }

                newFolderChip
            }
        }
        .scrollIndicators(.hidden)
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

    /// An action, not a filter — dashed so it never reads as a fifth folder.
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
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New folder")
    }
}
