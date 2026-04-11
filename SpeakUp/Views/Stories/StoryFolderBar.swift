import SwiftUI

struct StoryFolderBar: View {
    @Bindable var viewModel: StoriesViewModel
    var onCreateFolder: () -> Void
    var onEditFolder: (StoryFolder) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(
                    selection: .all,
                    title: "All",
                    symbol: "tray.full.fill",
                    color: AppColors.primary
                )

                chip(
                    selection: .pinned,
                    title: "Pinned",
                    symbol: "pin.fill",
                    color: .yellow
                )

                if !viewModel.folders.isEmpty {
                    divider
                }

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
    }

    private var divider: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(width: 1, height: 20)
    }

    private func chip(selection: FolderSelection, title: String, symbol: String, color: Color) -> some View {
        let isSelected = viewModel.folderSelection == selection
        let count = viewModel.countForFolder(selection)

        return Button {
            Haptics.light()
            withAnimation(.spring(response: 0.3)) {
                viewModel.setFolderSelection(selection)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isSelected ? color : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background {
                            Capsule()
                                .fill(isSelected ? Color.white.opacity(0.9) : Color.white.opacity(0.08))
                        }
                }
            }
            .foregroundStyle(isSelected ? .white : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                Capsule()
                    .fill(isSelected ? color.opacity(0.75) : Color.white.opacity(0.04))
                    .overlay {
                        Capsule()
                            .stroke(
                                isSelected ? Color.white.opacity(0.15) : Color.white.opacity(0.08),
                                lineWidth: 0.5
                            )
                    }
            }
        }
        .buttonStyle(.plain)
    }

    private var newFolderChip: some View {
        Button {
            Haptics.medium()
            onCreateFolder()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                Text("Folder")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                Capsule()
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
                    .foregroundStyle(.quaternary)
            }
        }
        .buttonStyle(.plain)
    }
}
