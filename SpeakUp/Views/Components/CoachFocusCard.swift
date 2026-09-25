import SwiftUI

/// The one thing the speaker is working on, and whether it is moving.
/// Carries no action on Recording Detail, because `NextStepCard` already owns
/// the action on that screen.
struct CoachFocusCard: View {
    let plan: CoachPlan
    var onPractice: ((CoachPracticeRoute) -> Void)?
    var onPracticeAgain: (() -> Void)?
    /// Today draws the title as a section header above the card, like every
    /// other block there; Recording Detail keeps it inside.
    var showsHeader = true

    private var showsCTA: Bool { onPractice != nil || onPracticeAgain != nil }

    var body: some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                if showsHeader { header }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: plan.focus.icon)
                        .font(.subheadline)
                        .foregroundStyle(AppColors.tint(for: plan.focus))

                    Text(plan.focus.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)

                    Spacer()

                    Text("\(plan.focusAverage)")
                        .font(.statValue)
                        .foregroundStyle(AppColors.scoreColor(for: plan.focusAverage))
                    Text("/ \(plan.target)")
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(plan.focus.title): \(plan.focusAverage) of \(plan.target) target")

                TickMeter(
                    fraction: min(1, max(0, Double(plan.focusAverage) / Double(max(plan.target, 1)))),
                    color: AppColors.tint(for: plan.focus)
                )
                .frame(height: 8)

                // `focusNote`, not `headline`: the row above already draws
                // the dimension, the score, the target and the arrow, and the
                // headline's job is to state all four for a reader who has
                // none of them - the LLM prompt.
                Text(plan.focusNote)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(plan.graduationLine)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if showsCTA { actionButton }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Subviews

    private var header: some View {
        GlassCardTitle(showsCTA ? "Today's focus" : "Your focus") {
            HStack(spacing: 6) {
                Text("Last \(plan.sessionCount)")
                    .font(.caption2.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)

                TrendChip(trend: plan.trend)
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if plan.isGraduating, let onPracticeAgain {
            GlassButton(
                title: "Practice again",
                icon: "mic.fill",
                style: .secondary,
                fullWidth: true
            ) {
                Haptics.medium()
                onPracticeAgain()
            }
        } else if let onPractice, let display = plan.focus.practiceRoute.display {
            // The same words as Today's prep suggestion ("Start with Warm-Up"),
            // so the focus card and the banner name one tool one way.
            GlassButton(
                title: "Start with \(display.title)",
                icon: display.icon,
                style: .secondary,
                fullWidth: true
            ) {
                Haptics.medium()
                onPractice(plan.focus.practiceRoute)
            }
        } else if let onPracticeAgain {
            GlassButton(
                title: "Practice again",
                icon: "mic.fill",
                style: .secondary,
                fullWidth: true
            ) {
                Haptics.medium()
                onPracticeAgain()
            }
        }
    }
}

// MARK: - Practice route display

extension CoachPracticeRoute {
    /// Name and icon for the tool, from the tool catalog - this used to say
    /// "Vocal Warm-Up" for the tool every other surface calls "Warm-Up".
    /// `nil` only for a drill raw value that no longer resolves, which is a
    /// data problem rather than something to put a button on.
    var display: (title: String, icon: String)? {
        switch self {
        case .readAloud:
            return (PracticeToolKind.readAloud.shortTitle, PracticeToolKind.readAloud.icon)
        case .warmUp:
            return (PracticeToolKind.warmUp.shortTitle, PracticeToolKind.warmUp.icon)
        case .drill(let raw):
            guard let mode = DrillMode(rawValue: raw) else { return nil }
            return (mode.title, mode.icon)
        }
    }
}

// MARK: - Trend

struct TrendChip: View {
    let trend: CoachPlan.Trend

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(label)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.15)))
        .accessibilityLabel("Trend: \(accessibilityLabel)")
    }

    private var label: String {
        switch trend {
        case .new: return "Baseline"
        case .improving(let delta): return "+\(delta)"
        case .flat: return "Flat"
        case .slipping(let delta): return "−\(delta)"
        case .holding: return "Holding"
        }
    }

    private var accessibilityLabel: String {
        switch trend {
        case .new: return "baseline"
        case .improving(let delta): return "up \(delta) points"
        case .flat: return "flat"
        case .slipping(let delta): return "down \(delta) points"
        case .holding: return "holding"
        }
    }

    private var icon: String {
        switch trend {
        case .new: return "circle.dashed"
        case .improving: return "arrow.up.right"
        case .flat: return "arrow.right"
        case .slipping: return "arrow.down.right"
        case .holding: return "checkmark"
        }
    }

    private var color: Color {
        switch trend {
        case .improving, .holding: return AppColors.success
        case .slipping: return AppColors.warning
        case .new, .flat: return AppColors.categoryNeutralCool
        }
    }
}

// MARK: - Dimension tints

extension AppColors {
    /// Category identity, not judgement - these name which area a tip is about,
    /// so they come from the jewel/tool tones rather than the state colors.
    static func tint(for dimension: CoachDimension) -> Color {
        switch dimension {
        case .fillers: return AppColors.warning
        // Not `categoryTeal` - it aliases `primary`, which `.clarity` holds.
        case .pace: return AppColors.categoryNeutralCool
        case .pauses: return AppColors.categoryPlum
        case .clarity: return AppColors.primary
        case .structure: return AppColors.categoryIndigo
        case .delivery: return AppColors.categoryBrandBright
        case .vocalVariety: return AppColors.categoryCopper
        case .vocabulary: return AppColors.categorySage
        case .relevance: return AppColors.categoryAmber
        }
    }
}
