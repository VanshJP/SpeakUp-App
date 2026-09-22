import SwiftUI
import SwiftData

/// Editor for the practice routine: which links are in the chain and in what
/// order. Reached from Settings and from the routine card on Today.
///
/// Arrows rather than drag. The chain is at most six rows, a drag needs a
/// gesture the rest of Settings does not use, and arrows are already reachable
/// by every assistive technology without an accessibility action of their own.
struct RoutineSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var userSettings: [UserSettings]

    private var settings: UserSettings? { userSettings.first }
    private var steps: [RoutineStep] { settings?.practiceRoutine ?? RoutineStep.defaultSteps }
    private var available: [RoutineStep] { RoutineStep.allCases.filter { !steps.contains($0) } }

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            PageScrollView {
                VStack(alignment: .leading, spacing: AppLayout.chapterSpacing) {
                    Text("Your routine is the order Big Talk walks you through. Finish one link and the next one comes to you.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    chainSection

                    if !available.isEmpty {
                        addSection
                    }
                }
                .pageContentInsets()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Routine")
        .navigationBarTitleDisplayMode(.inline)
        .restoresNavigationBar()
    }

    // MARK: - Chain

    private var chainSection: some View {
        VStack(spacing: 10) {
            GlassSectionHeader("In your routine", icon: TodayHomeModule.routine.icon)

            GlassCard(padding: 4) {
                VStack(spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.element) { index, step in
                        if index > 0 { divider }
                        chainRow(step, index: index)
                    }
                }
            }
        }
    }

    private func chainRow(_ step: RoutineStep, index: Int) -> some View {
        HStack(spacing: 12) {
            IconChip(icon: step.icon, tint: step.tint, size: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(step.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            HStack(spacing: 2) {
                moveButton(step, by: -1, icon: "chevron.up", enabled: index > 0)
                moveButton(step, by: 1, icon: "chevron.down", enabled: index < steps.count - 1)
                removeButton(step)
            }
        }
        .frame(minHeight: AppLayout.minHitTarget)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func moveButton(_ step: RoutineStep, by offset: Int, icon: String, enabled: Bool) -> some View {
        Button {
            Haptics.light()
            apply(PracticeRoutine.moving(step, by: offset, in: steps))
        } label: {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(enabled ? .secondary : .tertiary)
                .frame(width: 32, height: AppLayout.minHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(offset < 0 ? "Move \(step.title) earlier" : "Move \(step.title) later")
    }

    /// The scored take has no remove control at all rather than a disabled one:
    /// a greyed button invites the tap that explains why it cannot be tapped.
    @ViewBuilder
    private func removeButton(_ step: RoutineStep) -> some View {
        if step.isPinned {
            StatusPill(text: "Always", color: AppColors.primary, glyph: .dot)
        } else {
            Button {
                Haptics.light()
                apply(PracticeRoutine.removing(step, from: steps))
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: AppLayout.minHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(step.title)")
        }
    }

    // MARK: - Add

    private var addSection: some View {
        VStack(spacing: 10) {
            GlassSectionHeader("Add a link", icon: "plus.circle")

            GlassCard(padding: 4) {
                VStack(spacing: 0) {
                    ForEach(Array(available.enumerated()), id: \.element) { index, step in
                        if index > 0 { divider }
                        Button {
                            Haptics.light()
                            apply(PracticeRoutine.adding(step, to: steps))
                        } label: {
                            HStack(spacing: 12) {
                                IconChip(icon: step.icon, tint: step.tint, size: 30)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(step.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)
                                    Text(step.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer(minLength: 8)

                                Image(systemName: "plus")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(minHeight: AppLayout.minHitTarget)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(GlassPressStyle())
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                    }
                }
            }
        }
    }

    private var divider: some View {
        Divider()
            .overlay(AppColors.cardStroke)
            .padding(.leading, 54)
    }

    // MARK: - Persistence

    private func apply(_ updated: [RoutineStep]) {
        guard let settings else { return }
        settings.apply(routine: updated)
        try? modelContext.save()
    }
}

// MARK: - Previews

#Preview("Routine settings") {
    NavigationStack {
        RoutineSettingsView()
            .modelContainer(for: UserSettings.self, inMemory: true)
    }
}
