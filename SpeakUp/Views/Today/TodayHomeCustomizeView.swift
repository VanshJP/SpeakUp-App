import SwiftUI
import SwiftData

/// Direct-manipulation editor for Today's layout — the Home-screen jiggle-mode
/// idea rather than a settings list.
///
/// The previous version was a list of names and switches, which asked you to
/// imagine the result: nothing on screen resembled the page you were editing.
/// Here each block is a scaled schematic of the real thing (rings look like
/// rings, the session block has its prompt lines and Start pill), the stack is
/// in the order Today will render it, everything wiggles to say "this is
/// movable", and you drag a block where you want it. A ⊖ badge drops one into
/// the Hidden tray; ⊕ — or a drag back out — returns it.
///
/// Reorder rides on `draggable`/`dropDestination` rather than a hand-rolled
/// `DragGesture`: the tiles live in a scroll view, and the system drag is the
/// one that doesn't fight the scroll and auto-scrolls when you reach an edge.
struct TodayHomeCustomizeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var userSettings: [UserSettings]

    /// Sheet presentations need a Done control; Settings pushes this in an
    /// existing NavigationStack and uses the back button instead.
    var showsDoneButton: Bool = true

    @State private var visible: [TodayHomeModule] = TodayHomeModule.defaultVisible
    @State private var didLoad = false
    @State private var wiggling = false
    @State private var dropTarget: TodayHomeModule?
    @State private var trayTargeted = false

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            PageScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Drag a block to reorder it. Tap ⊖ to move one to Hidden.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    canvas

                    tray

                    Button {
                        Haptics.light()
                        resetToDefault()
                    } label: {
                        Text("Reset to default")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColors.primary)
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
            // Kicks the repeating wiggle. Held in state rather than started per
            // tile so every block shares one clock.
            wiggling = true
        }
    }

    // MARK: - Canvas

    /// The stack, in render order. Deliberately not a `List`: these are
    /// previews of page blocks, not rows of settings.
    private var canvas: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("On Today", hint: "\(visible.count) blocks")

            VStack(spacing: 12) {
                ForEach(visible) { module in
                    moduleTile(module)
                }
            }
        }
    }

    private func moduleTile(_ module: TodayHomeModule) -> some View {
        TodayModulePreview(module: module)
            .overlay(alignment: .topLeading) {
                if !module.isPinned {
                    removeBadge(module)
                        .offset(x: -7, y: -7)
                }
            }
            .overlay(alignment: .topTrailing) {
                if module.isPinned {
                    Text("Always on")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background { Capsule().fill(AppColors.surfaceLift) }
                        .padding(8)
                }
            }
            .overlay {
                // Where the dragged block will land.
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppColors.primary, lineWidth: dropTarget == module ? 2 : 0)
            }
            .wiggle(active: wiggling && !reduceMotion, phase: module.wigglePhase)
            .draggable(module.rawValue) {
                TodayModulePreview(module: module)
                    .frame(width: 240)
                    .opacity(0.9)
            }
            .dropDestination(for: String.self) { items, _ in
                guard let dragged = items.compactMap(TodayHomeModule.init(rawValue:)).first else { return false }
                insert(dragged, before: module)
                return true
            } isTargeted: { targeted in
                withAnimation(AppMotion.slide) {
                    if targeted { dropTarget = module }
                    else if dropTarget == module { dropTarget = nil }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(module.title). \(module.subtitle)")
            .accessibilityActions {
                // Drag and drop is unreachable for assistive tech, so the same
                // moves are spelled out as actions.
                Button("Move up") { shift(module, by: -1) }
                Button("Move down") { shift(module, by: 1) }
                if !module.isPinned {
                    Button("Hide") { setVisible(module, false) }
                }
            }
    }

    private func removeBadge(_ module: TodayHomeModule) -> some View {
        Button {
            Haptics.selection()
            withAnimation(AppMotion.slide) { setVisible(module, false) }
            persist()
        } label: {
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 21))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.black.opacity(0.55))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hide \(module.title)")
    }

    // MARK: - Tray

    /// Where hidden blocks wait. Also a drop target, so a block can be dragged
    /// down here instead of hunting for its ⊖.
    @ViewBuilder
    private var tray: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Hidden", hint: hiddenModules.isEmpty ? nil : "Tap ⊕ to add back")

            if hiddenModules.isEmpty {
                Text("Nothing hidden — every block is on Today.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
                    .padding(.horizontal, 14)
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(hiddenModules) { module in
                        trayChip(module)
                    }
                }
                .padding(10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.black.opacity(0.16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            trayTargeted ? AppColors.primary : AppColors.cardStroke,
                            style: StrokeStyle(lineWidth: trayTargeted ? 2 : 1, dash: [5, 4])
                        )
                }
        }
        .dropDestination(for: String.self) { items, _ in
            guard let dragged = items.compactMap(TodayHomeModule.init(rawValue:)).first,
                  !dragged.isPinned else { return false }
            Haptics.selection()
            withAnimation(AppMotion.slide) { setVisible(dragged, false) }
            persist()
            return true
        } isTargeted: { targeted in
            withAnimation(AppMotion.slide) { trayTargeted = targeted }
        }
    }

    private func trayChip(_ module: TodayHomeModule) -> some View {
        Button {
            Haptics.selection()
            withAnimation(AppMotion.slide) { setVisible(module, true) }
            persist()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: module.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                    }

                Text(module.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 0)

                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(AppColors.primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppColors.cardStroke, lineWidth: 0.5)
                    }
            }
        }
        .buttonStyle(GlassPressStyle())
        .draggable(module.rawValue) {
            TodayModulePreview(module: module).frame(width: 240).opacity(0.9)
        }
        .accessibilityLabel("Add \(module.title) to Today. \(module.subtitle)")
    }

    private func sectionLabel(_ title: String, hint: String?) -> some View {
        HStack {
            Text(title).eyebrowStyle()
            Spacer(minLength: 0)
            if let hint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Mutations

    private var hiddenModules: [TodayHomeModule] {
        TodayHomeModule.allCases.filter { !visible.contains($0) && !$0.isPinned }
    }

    /// Drop semantics: the dragged block takes the target's slot, whether it
    /// came from elsewhere in the stack or from the tray.
    private func insert(_ dragged: TodayHomeModule, before target: TodayHomeModule) {
        guard dragged != target else { return }
        withAnimation(AppMotion.slide) {
            visible.removeAll { $0 == dragged }
            let index = visible.firstIndex(of: target) ?? visible.count
            visible.insert(dragged, at: index)
            dropTarget = nil
        }
        Haptics.selection()
        persist()
    }

    private func shift(_ module: TodayHomeModule, by delta: Int) {
        guard let index = visible.firstIndex(of: module) else { return }
        let destination = index + delta
        guard visible.indices.contains(destination) else { return }
        withAnimation(AppMotion.slide) { visible.swapAt(index, destination) }
        Haptics.light()
        persist()
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

// MARK: - Wiggle

private extension TodayHomeModule {
    /// Stable per-block offset so the stack doesn't wobble in lockstep — the
    /// Home screen's icons are each a little out of phase with their neighbours.
    var wigglePhase: Double {
        Double(TodayHomeModule.allCases.firstIndex(of: self) ?? 0) * 0.035
    }
}

private extension View {
    /// Home-screen jiggle. Off under Reduce Motion, where a permanently moving
    /// page is exactly the thing the setting exists to stop.
    func wiggle(active: Bool, phase: Double) -> some View {
        modifier(WiggleModifier(active: active, phase: phase))
    }
}

/// Rocks between -0.5° and +0.5°. The rest angle has to be one end of the
/// swing rather than zero, or `autoreverses` tilts the block one way only and
/// the stack looks like it is leaning instead of wiggling.
private struct WiggleModifier: ViewModifier {
    let active: Bool
    let phase: Double

    @State private var swung = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(active ? (swung ? 0.5 : -0.5) : 0))
            .animation(
                active
                    ? .easeInOut(duration: 0.16).repeatForever(autoreverses: true).delay(phase)
                    : nil,
                value: swung
            )
            .onAppear { swung = active }
            .onChange(of: active) { _, isActive in swung = isActive }
    }
}

// MARK: - Module Preview

/// A scaled stand-in for one Today block: enough of the real shape to be
/// recognised at a glance, none of the real data. Built from skeleton bars
/// rather than the live views because the editor must render identically with
/// an empty database, mid-drag, and inside a drag preview.
struct TodayModulePreview: View {
    let module: TodayHomeModule

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: module.icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(module.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer(minLength: 0)
            }

            sketch
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: module.previewHeight, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppColors.surfaceLift)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppColors.cardStroke, lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.2), radius: 7, y: 4)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var sketch: some View {
        switch module {
        case .rings:
            HStack(spacing: 14) {
                ring(0.7, AppColors.primary)
                ring(0.45, AppColors.categorySage)
                ring(0.85, AppColors.categoryAmber)
                Spacer(minLength: 0)
            }

        case .weeklyRecap:
            HStack(alignment: .bottom, spacing: 5) {
                ForEach([0.35, 0.55, 0.4, 0.75, 0.6, 0.9], id: \.self) { height in
                    Capsule()
                        .fill(AppColors.primary.opacity(0.55))
                        .frame(width: 7, height: 26 * height)
                }
                Spacer(minLength: 0)
            }
            .frame(height: 26, alignment: .bottom)

        case .focus:
            HStack(spacing: 9) {
                Image(systemName: "scope")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.categoryAmber)
                VStack(alignment: .leading, spacing: 5) {
                    bar(96)
                    bar(58, opacity: 0.10)
                }
                Spacer(minLength: 0)
            }

        case .session:
            VStack(alignment: .leading, spacing: 7) {
                bar(150)
                bar(112, opacity: 0.10)
                // The one light pill on the page — the Start capsule.
                Capsule()
                    .fill(.white.opacity(0.9))
                    .frame(width: 92, height: 20)
                    .padding(.top, 3)
            }

        case .tools:
            HStack(spacing: 7) {
                toolChip(AppColors.toolWarmUp)
                toolChip(AppColors.toolDrill)
                toolChip(AppColors.toolCalm)
                toolChip(AppColors.toolReadAloud)
                Spacer(minLength: 0)
            }

        case .learn:
            HStack(spacing: 9) {
                Image(systemName: "map.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.primary)
                bar(84)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func ring(_ progress: Double, _ color: Color) -> some View {
        RingProgress(progress: progress, color: color, lineWidth: 3)
            .frame(width: 26, height: 26)
    }

    private func bar(_ width: CGFloat, opacity: Double = 0.18) -> some View {
        Capsule()
            .fill(.white.opacity(opacity))
            .frame(width: width, height: 6)
    }

    private func toolChip(_ tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(tint.opacity(0.30))
            .frame(width: 34, height: 30)
    }
}

private extension TodayHomeModule {
    /// Roughly proportional to the real block, so the stack reads as the page
    /// it edits — the session block should look like the tall one.
    var previewHeight: CGFloat {
        switch self {
        case .rings: return 92
        case .weeklyRecap: return 88
        case .focus: return 78
        case .session: return 122
        case .tools: return 92
        case .learn: return 66
        }
    }
}

#Preview {
    NavigationStack {
        TodayHomeCustomizeView()
    }
    .modelContainer(for: [UserSettings.self], inMemory: true)
}
