import SwiftUI

struct LessonContentView: View {
    let content: LessonContent

    var body: some View {
        VStack(spacing: 14) {
            ForEach(content.sections) { section in
                sectionView(for: section)
            }
        }
    }

    // MARK: - Section Dispatch

    @ViewBuilder
    private func sectionView(for section: LessonSection) -> some View {
        switch section.type {
        case .concepts:
            conceptsSection(section)
        case .tip:
            tipSection(section)
        case .example:
            exampleSection(section)
        case .keyTakeaway:
            keyTakeawaySection(section)
        case .callout:
            calloutSection(section)
        }
    }

    // MARK: - Concepts

    private func conceptsSection(_ section: LessonSection) -> some View {
        GlassCard(tint: AppColors.info.opacity(0.08), padding: 16) {
            VStack(alignment: .leading, spacing: 16) {
                sectionChrome(
                    title: section.title ?? "Concepts",
                    icon: section.icon ?? "book",
                    color: AppColors.info
                )

                let bullets = section.body.components(separatedBy: "\n").filter { !$0.isEmpty }
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
                        HStack(alignment: .top, spacing: 12) {
                            Circle()
                                .fill(AppColors.info.opacity(0.7))
                                .frame(width: 6, height: 6)
                                .padding(.top, 8)

                            Text(bullet)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Tip

    private func tipSection(_ section: LessonSection) -> some View {
        GlassCard(tint: AppColors.warning.opacity(0.08), padding: 16) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(AppColors.warning)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 12) {
                    sectionChrome(
                        title: section.title ?? "Pro Tip",
                        icon: section.icon ?? "lightbulb.fill",
                        color: AppColors.warning
                    )

                    Text(section.body)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Example

    private func exampleSection(_ section: LessonSection) -> some View {
        GlassCard(tint: AppColors.categoryNeutralCool.opacity(0.10), padding: 16) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(AppColors.categoryNeutralCool)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 12) {
                    sectionChrome(
                        title: section.title ?? "Example",
                        icon: section.icon ?? "quote.opening",
                        color: AppColors.categoryNeutralCool
                    )

                    Text(section.body)
                        .font(.callout)
                        .italic()
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Key Takeaway

    private func keyTakeawaySection(_ section: LessonSection) -> some View {
        FeaturedGlassCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: section.icon ?? "star.fill")
                    .font(.title2)
                    .foregroundStyle(AppColors.primary)
                    .frame(width: 48, height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AppColors.primary.opacity(0.15))
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text(section.title ?? "Key Takeaway")
                        .font(.subheadline.weight(.semibold))

                    Text(section.body)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Callout

    private func calloutSection(_ section: LessonSection) -> some View {
        GlassCard(tint: AppColors.glassTintSuccess, padding: 16) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(AppColors.success)
                    .frame(width: 3)

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: section.icon ?? "info.circle.fill")
                        .font(.title2)
                        .foregroundStyle(AppColors.success)
                        .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 8) {
                        if let title = section.title {
                            Text(title)
                                .font(.subheadline.weight(.semibold))
                        }

                        Text(section.body)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Shared chrome

    private func sectionChrome(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(color.opacity(0.15))
                )

            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}
