import SwiftUI
import SwiftData

/// Bevel-style Today layout editor: switch blocks on or off, drag to reorder.
/// Session stays pinned — it is the action the home screen exists to start.
///
/// Built on `List` rather than the app's usual card stack because reordering is
/// the whole point of the screen: `.onMove` in a permanently-active edit mode
/// gives real drag handles, which is what the old up/down chevron pair was
/// imitating with three controls per row.
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

            List {
                Section {
                    ForEach(visible) { module in
                        moduleRow(module)
                    }
                    .onMove(perform: move)
                } header: {
                    sectionHeader("On Today", hint: visible.count > 1 ? "Drag to reorder" : nil)
                } footer: {
                    footnote("Today's session can't be switched off — it is how you start a take.")
                }

                if !hiddenModules.isEmpty {
                    Section {
                        ForEach(hiddenModules) { module in
                            moduleRow(module)
                        }
                    } header: {
                        sectionHeader("Hidden", hint: nil)
                    } footer: {
                        footnote("Switch one back on and it returns to Today in its usual place.")
                    }
                }

                Section {
                    Button {
                        Haptics.light()
                        resetToDefault()
                    } label: {
                        Text("Reset to default")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColors.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(glassRowBackground)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            // Always-on edit mode: the handles are the affordance, so hiding
            // them behind an Edit button would just be the old problem again.
            .environment(\.editMode, .constant(.active))
        }
        .navigationTitle("Customize Today")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
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

    // MARK: - Rows

    private var hiddenModules: [TodayHomeModule] {
        TodayHomeModule.allCases.filter { !visible.contains($0) && !$0.isPinned }
    }

    private func moduleRow(_ module: TodayHomeModule) -> some View {
        let isVisible = visible.contains(module)

        return HStack(spacing: 12) {
            Image(systemName: module.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isVisible ? AppColors.primary : Color.secondary)
                .frame(width: 32, height: 32)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill((isVisible ? AppColors.primary : Color.white).opacity(0.14))
                }

            // The description is the point of this screen — you are choosing
            // blocks by what they do, not by name — so it reads at caption on
            // secondary and wraps instead of truncating.
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(module.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isVisible ? .white : .white.opacity(0.6))

                    if module.isPinned {
                        Text("Always on")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background { Capsule().fill(AppColors.surfaceLift) }
                    }
                }

                Text(module.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .listRowBackground(glassRowBackground)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(module.title). \(module.subtitle)")
    }

    // MARK: - Chrome

    private var glassRowBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppColors.surfaceLift)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppColors.cardStroke, lineWidth: 0.5)
            }
    }

    private func sectionHeader(_ title: String, hint: String?) -> some View {
        HStack {
            Text(title)
                .eyebrowStyle()
            Spacer(minLength: 0)
            if let hint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .textCase(nil)
        .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 6, trailing: 20))
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .textCase(nil)
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 4, trailing: 20))
    }

    // MARK: - Mutations

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

    private func move(from source: IndexSet, to destination: Int) {
        visible.move(fromOffsets: source, toOffset: destination)
        Haptics.light()
        persist()
    }

    private func resetToDefault() {
        withAnimation(AppMotion.slide) {
            visible = TodayHomeModule.defaultVisible
        }
        guard let settings = userSettings.first else { return }
        // Empty raw is the "never customized" marker TodayHomeLayout resolves
        // back to the factory default, so reset clears rather than rewrites.
        settings.todayHomeLayoutRaw = []
        try? modelContext.save()
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
