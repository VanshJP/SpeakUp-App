import SwiftUI

struct StoryFolderEditorSheet: View {
    @Bindable var viewModel: StoriesViewModel
    var editing: StoryFolder?

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var selectedSymbol: String = "folder.fill"
    @State private var selectedColorHex: String = "#0D8488"

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    previewHeader

                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Name")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            TextField("e.g. Wedding Toast", text: $name)
                                .textFieldStyle(.plain)
                                .font(.body)
                                .foregroundStyle(.white)
                                .padding(.vertical, 8)
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Icon")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                                ForEach(StoryFolderPalette.symbols, id: \.self) { symbol in
                                    Button {
                                        Haptics.light()
                                        selectedSymbol = symbol
                                    } label: {
                                        Image(systemName: symbol)
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(selectedSymbol == symbol ? .white : .secondary)
                                            .frame(width: 40, height: 40)
                                            .background {
                                                Circle()
                                                    .fill(selectedSymbol == symbol ? selectedColor.opacity(0.8) : Color.white.opacity(0.05))
                                            }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Color")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            HStack(spacing: 10) {
                                ForEach(StoryFolderPalette.colors, id: \.self) { hex in
                                    Button {
                                        Haptics.light()
                                        selectedColorHex = hex
                                    } label: {
                                        Circle()
                                            .fill(Color(hex: hex))
                                            .frame(width: 32, height: 32)
                                            .overlay {
                                                Circle()
                                                    .stroke(.white, lineWidth: selectedColorHex == hex ? 2 : 0)
                                            }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    if editing != nil {
                        GlassButton(
                            title: "Delete Folder",
                            icon: "trash",
                            style: .danger,
                            size: .medium
                        ) {
                            if let folder = editing {
                                viewModel.deleteFolder(folder)
                                Haptics.warning()
                                dismiss()
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle(editing == nil ? "New Folder" : "Edit Folder")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .fontWeight(.semibold)
            }
        }
        .onAppear {
            if let folder = editing {
                name = folder.name
                selectedSymbol = folder.systemImage
                selectedColorHex = folder.colorHex
            }
        }
    }

    private var selectedColor: Color {
        Color(hex: selectedColorHex)
    }

    private var previewHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(selectedColor.opacity(0.18))
                    .frame(width: 56, height: 56)
                Image(systemName: selectedSymbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(selectedColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(name.isEmpty ? "Folder Name" : name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(name.isEmpty ? Color.white.opacity(0.4) : Color.white)
                Text(editing == nil ? "New folder" : "Editing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if let folder = editing {
            viewModel.updateFolder(folder, name: trimmed, systemImage: selectedSymbol, colorHex: selectedColorHex)
        } else {
            viewModel.createFolder(name: trimmed, systemImage: selectedSymbol, colorHex: selectedColorHex)
        }
        Haptics.success()
        dismiss()
    }
}

// MARK: - Move Story Sheet

struct StoryMoveFolderSheet: View {
    @Bindable var viewModel: StoriesViewModel
    let story: Story
    var onMove: ((UUID?) -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            ScrollView {
                VStack(spacing: 10) {
                    destinationRow(
                        title: "All Notes",
                        symbol: "tray.full.fill",
                        color: AppColors.primary,
                        isSelected: story.folderId == nil
                    ) {
                        viewModel.moveStory(story, toFolder: nil)
                        onMove?(nil)
                        dismiss()
                    }

                    ForEach(viewModel.folders) { folder in
                        destinationRow(
                            title: folder.name,
                            symbol: folder.systemImage,
                            color: Color(hex: folder.colorHex),
                            isSelected: story.folderId == folder.id
                        ) {
                            viewModel.moveStory(story, toFolder: folder.id)
                            onMove?(folder.id)
                            dismiss()
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Move to Folder")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private func destinationRow(title: String, symbol: String, color: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.2))
                        .frame(width: 40, height: 40)
                    Image(systemName: symbol)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(color)
                }

                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(AppColors.primary)
                }
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
        .buttonStyle(.plain)
    }
}
