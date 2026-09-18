import SwiftUI

// MARK: - Duration Pill Selector

/// Compact duration control. Matches `StatusPill` / refresh visual height (28pt)
/// while keeping a 44pt hit target.
struct DurationPill: View {
    @Binding var selectedDuration: RecordingDuration

    var body: some View {
        Menu {
            ForEach(RecordingDuration.allCases) { duration in
                Button {
                    withAnimation(.spring(duration: 0.3)) {
                        selectedDuration = duration
                    }
                } label: {
                    HStack {
                        Text(duration.displayName)
                        if duration == selectedDuration {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 10, weight: .semibold))
                Text(selectedDuration.displayName)
                    .font(.caption2.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel("Recording length, \(selectedDuration.displayName)")
        .accessibilityHint("Opens recording length options")
    }
}
