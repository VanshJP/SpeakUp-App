import SwiftUI

/// A lesson's reading, set like a short article rather than a stack of cards.
///
/// Every section used to be its own tinted plate with the same chip-and-title
/// anatomy, so a concept, a tip and the takeaway all weighed the same and
/// nothing read as the point. Now the page is type on the canvas - section
/// heads over running text, numbered points, spoken examples on a quote rail,
/// a tip as an aside - and exactly one surface: the key takeaway.
///
/// **One margin.** Every marker - a point's numeral, the tip's bulb, the
/// example's quote mark and rail - hangs in the same column, so all indented
/// text starts on one edge and paragraphs and heads on the page's.
struct LessonContentView: View {
    let content: LessonContent
    /// The lesson's identity colour (`LessonIdentity.accent`): point numerals
    /// and the takeaway plate.
    var accent: Color = AppColors.primary

    /// Running text: brighter than `.secondary`, which is too dim to read at
    /// length, and a step under the white of the heads and spoken lines.
    private static let ink = Color.white.opacity(0.8)
    private static let gutter: CGFloat = 12

    @ScaledMetric(relativeTo: .body) private var margin: CGFloat = 20

    private var indent: CGFloat { margin + Self.gutter }

    var body: some View {
        VStack(alignment: .leading, spacing: 36) {
            ForEach(content.sections) { section in
                sectionView(for: section)
                    .frame(maxWidth: .infinity, alignment: .leading)
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

    /// A head over its lines. Points hang a numeral in the lesson's colour -
    /// the order of PREP, the count of "four types of pauses" - and plain
    /// lines are paragraphs, not bullets.
    private func conceptsSection(_ section: LessonSection) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let title = section.title {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }

            ForEach(Array(numbered(LessonLine.parse(section.body)).enumerated()), id: \.offset) { _, item in
                switch item.line {
                case .paragraph(let text):
                    paragraph(text)
                case .point(let term, let detail):
                    point(number: item.number, term: term, detail: detail)
                }
            }
        }
    }

    /// Points count from 1; paragraphs between them take no number.
    private func numbered(_ lines: [LessonLine]) -> [(line: LessonLine, number: Int)] {
        var count = 0
        return lines.map { line in
            guard case .point = line else { return (line, 0) }
            count += 1
            return (line, count)
        }
    }

    private func point(number: Int, term: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Self.gutter) {
            Text("\(number)")
                .font(.system(.body, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(accent)
                .frame(width: margin, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(term)
                    .font(.headline)
                    .foregroundStyle(.white)

                if !detail.isEmpty {
                    Text(detail)
                        .font(.body)
                        .foregroundStyle(Self.ink)
                        .lineSpacing(3)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Example

    /// Something said out loud, so it reads like a script: each labelled line
    /// on one quote rail, the verdict under it. Lines after the last labelled
    /// one ("Same idea, half the words") are that verdict.
    private func exampleSection(_ section: LessonSection) -> some View {
        let lines = LessonLine.parse(section.body)
        let lastLabelled = lines.lastIndex { if case .point = $0 { true } else { false } }
        let script = lastLabelled.map { Array(lines[...$0]) } ?? []
        let verdict = lastLabelled.map { Array(lines[($0 + 1)...]) } ?? lines

        return VStack(alignment: .leading, spacing: 14) {
            marginHead(icon: section.icon ?? "quote.opening", tint: .secondary) {
                Text(section.title ?? "Example")
                    .font(.headline)
                    .foregroundStyle(.white)
            }

            if !script.isEmpty {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(script.enumerated()), id: \.offset) { _, line in
                        switch line {
                        case .point(let label, let text):
                            scriptLine(label: label, text: text)
                        case .paragraph(let text):
                            paragraph(text)
                        }
                    }
                }
                .padding(.vertical, 2)
                .padding(.leading, indent)
                .overlay(alignment: .leading) {
                    // Under the quote mark, which sits at the margin's edge.
                    Capsule()
                        .fill(Color.white.opacity(0.16))
                        .frame(width: 2)
                        .padding(.leading, 5)
                }
            }

            ForEach(Array(verdict.enumerated()), id: \.offset) { _, line in
                if case .paragraph(let text) = line {
                    paragraph(text)
                        .padding(.leading, indent)
                }
            }
        }
    }

    /// A label over a line - "Before" over the rambling version. A spoken
    /// line (it opens on a quotation mark) prints white; a description, ink.
    private func scriptLine(label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .eyebrowStyle()

            if !text.isEmpty {
                Text(text)
                    .font(.body)
                    .foregroundStyle(text.hasPrefix("\u{201C}") ? Color.white : Self.ink)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Tip

    /// An aside: its bulb in the margin and the amber label, no plate. A
    /// tinted card per tip was one of five boxes in a row.
    private func tipSection(_ section: LessonSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            marginHead(icon: section.icon ?? "lightbulb.fill", tint: AppColors.warning) {
                Text(section.title ?? "Pro tip")
                    .eyebrowStyle(AppColors.warning)
            }

            paragraph(section.body)
                .padding(.leading, indent)
        }
    }

    // MARK: - Key Takeaway

    /// The one plate in the reading, and the one line set large: what to keep
    /// if you keep nothing else. It sits right above "Got it".
    private func keyTakeawaySection(_ section: LessonSection) -> some View {
        FeaturedGlassCard(gradientColors: [accent.opacity(0.10)], padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                // The star carries the lesson's colour; the label stays
                // secondary - small caps in the accent on its own tinted plate
                // fell to about 3:1.
                HStack(spacing: 6) {
                    Image(systemName: section.icon ?? "star.fill")
                        .foregroundStyle(accent)
                    Text(section.title ?? "Key takeaway")
                }
                .eyebrowStyle()
                .accessibilityElement(children: .combine)

                Text(section.body)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Callout

    /// A milestone opener ("Milestone reached!"): its glyph and a head over
    /// the text, on the canvas like the rest of the reading.
    private func calloutSection(_ section: LessonSection) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                IconChip(icon: section.icon ?? "info.circle.fill", tint: AppColors.success, size: 40)

                Text(section.title ?? "Note")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }

            paragraph(section.body)
        }
    }

    // MARK: - Shared

    /// A glyph in the margin beside a head, centred on it.
    private func marginHead<Tint: ShapeStyle, Head: View>(
        icon: String,
        tint: Tint,
        @ViewBuilder head: () -> Head
    ) -> some View {
        HStack(spacing: Self.gutter) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: margin, alignment: .leading)
                .accessibilityHidden(true)

            head()
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(Self.ink)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Previews

/// Sized to fit, so the whole reading renders - most lessons are locked in a
/// fresh simulator.
#Preview("PREP", traits: .sizeThatFitsLayout) {
    LessonContentPreview(lessonId: "w3_l1")
}

#Preview("Milestone", traits: .sizeThatFitsLayout) {
    LessonContentPreview(lessonId: "w4_l4")
}

private struct LessonContentPreview: View {
    let lessonId: String

    var body: some View {
        let lesson = DefaultCurriculum.phases.flatMap(\.lessons).first { $0.id == lessonId }!
        LessonContentView(
            content: lesson.activities.compactMap(\.content).first!,
            accent: LessonIdentity.forLesson(id: lessonId).accent
        )
        .padding(AppLayout.pageHorizontal)
        .frame(width: 402)
        .background(AppBackground())
    }
}
