import SwiftUI

/// The one thing the speaker is working on, and whether it is moving.
///
/// One card, two placements. On Today it is the instruction you read *before*
/// you speak, with the button that trains it; on a session's coaching tab it is
/// the standing context the session's tips sit inside, and the CTA is dropped
/// because `NextStepCard` already owns the action on that screen.
///
/// There used to be two of these — `TodayFocusCard` ranking by lowest rolling
/// subscore over ten sessions, and a private card on the detail screen ranking
/// by weighted deficit over twenty. They disagreed routinely, which is worse
/// than either alone: the app told you to work on two different things on two
/// different screens on the same day.
struct CoachFocusCard: View {
    let plan: CoachPlan
    /// Launches the tool that trains the focus. Omitted where another card on
    /// the same screen already owns the action.
    var onPractice: ((CoachPracticeRoute) -> Void)?
    /// Used instead once every dimension has cleared the bar and there is no
    /// weakness left to route at.
    var onPracticeAgain: (() -> Void)?

    private var showsCTA: Bool { onPractice != nil || onPracticeAgain != nil }

    var body: some View {
        // Never `elevated`: Start Speaking in the prompt card owns the white
        // primary. This card's CTA is GlassButton.secondary — same family,
        // quieter volume.
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                header

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: plan.focus.icon)
                        .font(.subheadline)
                        .foregroundStyle(AppColors.tint(for: plan.focus))

                    Text(plan.focus.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)

                    Spacer()

                    Text("\(plan.focusAverage)")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.scoreColor(for: plan.focusAverage))
                    Text("/ \(plan.target)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                }

                ProgressTrack(
                    value: plan.focusAverage,
                    target: plan.target,
                    tint: AppColors.tint(for: plan.focus)
                )

                Text(plan.headline)
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
        HStack(spacing: 6) {
            Text(showsCTA ? "Today's Focus" : "Your Focus")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)

            Spacer()

            Text("Last \(plan.sessionCount)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)

            TrendChip(trend: plan.trend)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        // GlassButton.secondary — same capsule language as Start Speaking /
        // GlassButton.primary, just the quieter variant so Today still has one
        // white hero in the prompt card.
        if plan.isGraduating, let onPracticeAgain {
            GlassButton(
                title: "Practice Again",
                icon: "mic.fill",
                style: .secondary,
                fullWidth: true
            ) {
                Haptics.medium()
                onPracticeAgain()
            }
        } else if let onPractice, let display = plan.focus.practiceRoute.display {
            GlassButton(
                title: display.title,
                icon: display.icon,
                style: .secondary,
                fullWidth: true
            ) {
                Haptics.medium()
                onPractice(plan.focus.practiceRoute)
            }
        } else if let onPracticeAgain {
            GlassButton(
                title: "Practice Again",
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
    /// Title and icon for the tool. `nil` only for a drill raw value that no
    /// longer resolves, which is a data problem rather than something to put a
    /// button on.
    var display: (title: String, icon: String)? {
        switch self {
        case .readAloud:
            return ("Read Aloud", "text.book.closed")
        case .warmUp:
            return ("Vocal Warm-Up", "wind")
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

/// Distance to the graduation bar, as a bar. A number alone does not say how
/// close "72 out of 85" is.
struct ProgressTrack: View {
    let value: Int
    let target: Int
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            let fraction = min(1, max(0, Double(value) / Double(max(target, 1))))
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.08))
                Capsule()
                    .fill(tint)
                    .frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}

// MARK: - Dimension tints

extension AppColors {
    /// Category identity, not judgement — these name which area a tip is about,
    /// so they come from the jewel/tool tones rather than the state colors.
    static func tint(for dimension: CoachDimension) -> Color {
        switch dimension {
        case .fillers: return AppColors.warning
        // Not `categoryTeal` — it aliases `primary`, which `.clarity` holds.
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
