import SwiftUI

struct FrameworkOverlayView: View {
    let framework: SpeechFramework
    let elapsedTime: TimeInterval
    let totalDuration: TimeInterval

    private var currentSectionIndex: Int {
        let progress = min(1.0, elapsedTime / max(1, totalDuration))
        var accumulated = 0.0
        for (index, section) in framework.sections.enumerated() {
            accumulated += section.suggestedDurationRatio
            if progress < accumulated {
                return index
            }
        }
        return framework.sections.count - 1
    }

    private var currentSection: FrameworkSection {
        framework.sections[currentSectionIndex]
    }

    var body: some View {
        VStack(spacing: 8) {
            // Section name and hint
            VStack(spacing: 4) {
                Text(currentSection.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)

                Text(currentSection.hint)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }

            // Progress dots
            HStack(spacing: 6) {
                ForEach(Array(framework.sections.enumerated()), id: \.offset) { index, section in
                    HStack(spacing: 3) {
                        Text(section.abbreviation)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(index == currentSectionIndex ? .white : .white.opacity(0.4))

                        Circle()
                            .fill(index < currentSectionIndex ? .green :
                                    index == currentSectionIndex ? .white : .white.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }

                    if index < framework.sections.count - 1 {
                        Rectangle()
                            .fill(index < currentSectionIndex ? .green.opacity(0.6) : .white.opacity(0.15))
                            .frame(height: 1)
                            .frame(maxWidth: 20)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.1), lineWidth: 0.5)
                }
        }
        .animation(.easeInOut(duration: 0.3), value: currentSectionIndex)
    }
}
