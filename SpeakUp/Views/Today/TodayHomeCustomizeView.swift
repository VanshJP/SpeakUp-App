import SwiftUI
import SwiftData

/// Bevel-style Today layout editor: toggle modules on/off, drag to reorder.
/// Session stays pinned — it is the action the home screen exists to start.
struct TodayHomeCustomizeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var userSettings: [UserSettings]

    /// Sheet presentations need a Done control; Settings pushes this in an
    /// existing NavigationStack and uses the back button instead.
    var showsDoneButton: Bool = true

    @State private var visible: [TodayHomeModule] = TodayHomeModule.defaultVisible
    @State private var didLoad = false

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            PageScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Show, hide, and reorder the blocks on Today. Today's session stays on — it is how you start a take.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    GlassCard(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(visible.enumerated()), id: \.element.id) { index, module in
                                moduleRow(module, index: index)
                                if index < visible.count - 1 || !hiddenModules.isEmpty {
                                    Divider().opacity(0.35)
                                }
                            }

                            ForEach(Array(hiddenModules.enumerated()), id: \.element.id) { index, module in
                                moduleRow(module, index: nil)
                                if index < hiddenModules.count - 1 {
                                    Divider().opacity(0.35)
                                }
                            }
                        }
                    }

                    Button {
                        Haptics.light()
                        withAnimation(AppMotion.slide) {
                            visible = TodayHomeModule.defaultVisible
                        }
                        guard let settings = userSettings.first else { return }
                        settings.todayHomeLayoutRaw = []
                        try? modelContext.save()
                    } label: {
                        Text("Reset to default")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(GlassPressStyle())
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(AppColors.cardStroke, lineWidth: 0.5)
                            }
                    }
                }
                .padding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Customize Today")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        persist()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            visible = TodayHomeLayout.resolve(userSettings.first?.todayHomeLayoutRaw ?? [])
        }
    }

    private var hiddenModules: [TodayHomeModule] {
        TodayHomeModule.allCases.filter { !visible.contains($0) && !$0.isPinned }
    }

    @ViewBuilder
    private func moduleRow(_ module: TodayHomeModule, index: Int?) -> some View {
        let isVisible = visible.contains(module)

        HStack(spacing: 12) {
            Image(systemName: module.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isVisible ? AppColors.primary : .secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(module.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isVisible ? .primary : .secondary)
                    if module.isPinned {
                        Text("Required")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background {
                                Capsule().fill(AppColors.surfaceLift)
                            }
                    }
                }
                Text(module.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            if !module.isPinned {
                Toggle("", isOn: Binding(
                    get: { isVisible },
                    set: { on in
                        Haptics.selection()
                        withAnimation(AppMotion.slide) {
                            setVisible(module, on)
                        }
                        persist()
                    }
                ))
                .labelsHidden()
                .tint(AppColors.primary)
            }

            if let index, isVisible, !module.isPinned {
                VStack(spacing: 2) {
                    Button {
                        Haptics.light()
                        move(module, from: index, by: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.caption.weight(.bold))
                            .frame(width: 28, height: 24)
                    }
                    .disabled(index == 0)
                    .opacity(index == 0 ? 0.3 : 1)

                    Button {
                        Haptics.light()
                        move(module, from: index, by: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .frame(width: 28, height: 24)
                    }
                    .disabled(index >= visible.count - 1)
                    .opacity(index >= visible.count - 1 ? 0.3 : 1)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Reorder \(module.title)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .opacity(isVisible ? 1 : 0.72)
    }

    private func setVisible(_ module: TodayHomeModule, _ on: Bool) {
        if on {
            guard !visible.contains(module) else { return }
            if module == .weeklyRecap, let rings = visible.firstIndex(of: .rings) {
                visible.insert(module, at: rings + 1)
            } else if module == .focus, let session = visible.firstIndex(of: .session) {
                visible.insert(module, at: session)
            } else {
                visible.append(module)
            }
        } else {
            guard !module.isPinned else { return }
            visible.removeAll { $0 == module }
        }
    }

    private func move(_ module: TodayHomeModule, from index: Int, by delta: Int) {
        let destination = index + delta
        guard visible.indices.contains(destination) else { return }
        withAnimation(AppMotion.slide) {
            visible.swapAt(index, destination)
        }
        persist()
    }

    private func persist() {
        guard let settings = userSettings.first else { return }
        // Always persist an explicit list once customized so "reset" is the
        // only path back to factory defaults (empty raw).
        settings.todayHomeLayoutRaw = TodayHomeLayout.encode(visible)
        try? modelContext.save()
    }
}

#Preview {
    NavigationStack {
        TodayHomeCustomizeView()
    }
    .modelContainer(for: [UserSettings.self], inMemory: true)
}
