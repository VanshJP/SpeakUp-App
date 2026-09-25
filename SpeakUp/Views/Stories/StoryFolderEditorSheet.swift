import SwiftUI

struct StoryFolderEditorSheet: View {
    @Bindable var viewModel: StoriesViewModel
    var editing: StoryFolder?

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var selectedSymbol: String = "folder.fill"
    @State private var selectedColorHex: String = "#0D8488"
    @State private var confirmingDelete = false
    /// Counted when Delete is tapped, so the confirmation never reads the
    /// folder once it is gone.
    @State private var deleteStoryCount = 0

    /// VoiceOver names for `StoryFolderPalette.colors`; a swatch is otherwise
    /// an unnamed button.
    private static let colorNames: [String: String] = [
        "#0D8488": "Teal", "#6366F1": "Indigo", "#F59E0B": "Orange", "#EC4899": "Pink",
        "#22C55E": "Green", "#EF4444": "Red", "#A855F7": "Purple", "#64748B": "Slate"
    ]

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            PageScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    previewHeader

                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            GlassCardTitle("Name")
                            TextField("e.g. Wedding toast", text: $name)
                                .textFieldStyle(.plain)
                                .font(.body)
                                .foregroundStyle(.white)
                                .padding(.vertical, 8)
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            GlassCardTitle("Icon")

                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                                ForEach(StoryFolderPalette.symbols, id: \.self) { symbol in
                                    symbolButton(symbol)
                                }
                            }
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            GlassCardTitle("Color")

                            // A grid, not an HStack: eight fixed swatches plus gaps
                            // and insets needed 392pt, wider than a 375pt phone.
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 6) {
                                ForEach(StoryFolderPalette.colors, id: \.self) { hex in
                                    colorButton(hex)
                                }
                            }
                        }
                    }

                    if let folder = editing {
                        GlassButton(
                            title: "Delete folder",
                            icon: "trash",
                            style: .danger,
                            size: .medium
                        ) {
                            deleteStoryCount = viewModel.countForFolder(.folder(folder.id))
                            confirmingDelete = true
                        }
                    }
                }
                .padding(.horizontal, AppLayout.pageHorizontal)
                .padding(.vertical, 20)
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
        .alert("Delete Folder?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                if let folder = editing {
                    viewModel.deleteFolder(folder)
                    Haptics.warning()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(StoryFolderBar.deleteMessage(storyCount: deleteStoryCount))
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
            IconChip(icon: selectedSymbol, tint: selectedColor, size: 56)

            VStack(alignment: .leading, spacing: 2) {
                Text(name.isEmpty ? "Folder name" : name)
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

    // MARK: - Pickers

    private func symbolButton(_ symbol: String) -> some View {
        let isSelected = selectedSymbol == symbol
        return Button {
            Haptics.light()
            selectedSymbol = symbol
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 40, height: 40)
                .background {
                    Circle()
                        .fill(isSelected ? selectedColor.opacity(0.8) : Color.white.opacity(0.05))
                }
                .frame(maxWidth: .infinity, minHeight: AppLayout.minHitTarget)
                .contentShape(.rect)
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func colorButton(_ hex: String) -> some View {
        let isSelected = selectedColorHex == hex
        return Button {
            Haptics.light()
            selectedColorHex = hex
        } label: {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 32, height: 32)
                .overlay {
                    Circle()
                        .stroke(.white, lineWidth: isSelected ? 2 : 0)
                }
                .frame(maxWidth: .infinity, minHeight: AppLayout.minHitTarget)
                .contentShape(.rect)
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityLabel(Self.colorNames[hex] ?? "Color")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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

            PageScrollView {
                // One plate of rows; hairlines start at the names
                // (row padding + chip + gap).
                GlassRowGroup(dividerInset: 60) {
                    destinationRow(
                        title: "No folder",
                        symbol: "tray",
                        color: AppColors.accent,
                        isSelected: story.folderId == nil
                    ) {
                        viewModel.moveStory(story, toFolder: nil)
                        onMove?(nil)
                        dismiss()
                    }

                    ForEach(viewModel.foldersForDisplay) { folder in
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
                .padding(.horizontal, AppLayout.pageHorizontal)
                .padding(.vertical, 20)
            }
        }
        .navigationTitle("Move to Folder")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Picking a row is the commit, so there is nothing to cancel.
            ToolbarItem(placement: .topBarLeading) {
                Button(role: .close) { dismiss() }
            }
        }
    }

    private func destinationRow(title: String, symbol: String, color: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: 14) {
                IconChip(icon: symbol, tint: color, size: 32)

                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .accessibilityHidden(true)
                }
            }
            .padding(14)
            .contentShape(.rect)
        }
        .buttonStyle(RowPressStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Folder Chip

/// A story's folder as a chip that opens the Move sheet - on the detail hero
/// and under the editor's title. Painted, not glass: on the hero it sits on a
/// `GlassCard` (rule 13b). The folder's colour stays on its glyph, and an
/// unfiled story says "No folder" rather than naming the All filter.
struct StoryFolderChip: View {
    let folder: StoryFolder?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: folder?.systemImage ?? "tray")
                    .foregroundStyle(folder.map { Color(hex: $0.colorHex) } ?? Color.secondary)
                Text(folder?.name ?? "No folder")
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background { Capsule().fill(Color.white.opacity(0.10)) }
            .overlay { Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1) }
            .frame(minHeight: AppLayout.minHitTarget)
            .contentShape(.rect)
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityLabel("Folder: \(folder?.name ?? "none")")
        .accessibilityHint("Moves the story to another folder")
    }
}
