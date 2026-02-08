import SwiftUI

struct GlassCard<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat
    var tint: Color?
    var padding: CGFloat
    var accentBorder: Color?
    var elevated: Bool

    init(
        cornerRadius: CGFloat = 20,
        tint: Color? = nil,
        padding: CGFloat = 16,
        accentBorder: Color? = nil,
        elevated: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.padding = padding
        self.accentBorder = accentBorder
        self.elevated = elevated
    }

    var body: some View {
        content
            .padding(padding)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)

                    // Tint overlay
                    if let tint {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(tint.opacity(0.12))
                    }

                    // Inner glow gradient for depth against dark backgrounds
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.06), .clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )

                    // Top edge highlight
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.3), .white.opacity(0.08), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                }
            }
            .overlay {
                if let accentBorder {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            LinearGradient(
                                colors: [accentBorder.opacity(0.6), accentBorder.opacity(0.2), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    }
}

// MARK: - Featured Glass Card (for hero/prominent content)

struct FeaturedGlassCard<Content: View>: View {
    let content: Content
    var gradientColors: [Color]
    var cornerRadius: CGFloat
    var padding: CGFloat

    init(
        gradientColors: [Color] = [.teal.opacity(0.15), .cyan.opacity(0.08)],
        cornerRadius: CGFloat = 24,
        padding: CGFloat = 20,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.gradientColors = gradientColors
        self.cornerRadius = cornerRadius
        self.padding = padding
    }

    var body: some View {
        content
            .padding(padding)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)

                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    // Inner glow for premium depth
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.08), .clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )

                    // Top edge highlight
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.35), .white.opacity(0.1), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: gradientColors.first?.opacity(0.25) ?? .clear, radius: 20, y: 8)
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    var icon: String? = nil
    var tint: Color = .teal
    var trend: ScoreTrend? = nil
    
    var body: some View {
        GlassCard(tint: tint.opacity(0.3)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if let icon {
                        Image(systemName: icon)
                            .foregroundStyle(tint)
                    }
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    if let trend {
                        Image(systemName: trend.iconName)
                            .font(.caption)
                            .foregroundStyle(trend.color)
                    }
                }
                
                Text(value)
                    .font(.title.weight(.bold))
                    .foregroundStyle(.primary)
            }
        }
    }
}

// MARK: - Score Display Card

struct ScoreDisplayCard: View {
    let score: Int
    var trend: ScoreTrend = .stable
    var showTrend: Bool = true
    
    var body: some View {
        GlassCard(tint: AppColors.scoreColor(for: score).opacity(0.2)) {
            VStack(spacing: 12) {
                HStack {
                    Text("Speech Score")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    if showTrend {
                        HStack(spacing: 4) {
                            Image(systemName: trend.iconName)
                            Text(trend.rawValue.capitalized)
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(trend.color)
                    }
                }
                
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(score)")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.scoreColor(for: score))
                    
                    Text("/100")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                }
                
                // Score bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.gray.opacity(0.2))
                        
                        Capsule()
                            .fill(AppColors.scoreGradient(for: score))
                            .frame(width: geometry.size.width * CGFloat(score) / 100)
                    }
                }
                .frame(height: 8)
            }
        }
    }
}

// MARK: - Info Row

struct GlassInfoRow: View {
    let label: String
    let value: String
    var icon: String? = nil
    
    var body: some View {
        HStack {
            if let icon {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
            }
            
            Text(label)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}

// MARK: - Empty State Card

struct EmptyStateCard: View {
    let icon: String
    let title: String
    let message: String
    var buttonTitle: String? = nil
    var buttonAction: (() -> Void)? = nil
    
    var body: some View {
        GlassCard {
            VStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                
                Text(title)
                    .font(.headline)
                
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                if let buttonTitle, let buttonAction {
                    GlassButton(title: buttonTitle, style: .primary, action: buttonAction)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }
}

// MARK: - Previews

#Preview("Glass Cards") {
    ScrollView {
        VStack(spacing: 20) {
            ScoreDisplayCard(score: 78, trend: .improving)
            
            HStack(spacing: 12) {
                StatCard(title: "Streak", value: "7 days", icon: "flame.fill", tint: .orange)
                StatCard(title: "Sessions", value: "23", icon: "mic.fill", tint: .teal)
            }
            
            GlassCard {
                VStack(spacing: 12) {
                    GlassInfoRow(label: "Duration", value: "1:32", icon: "clock")
                    Divider()
                    GlassInfoRow(label: "Words", value: "245", icon: "text.word.spacing")
                    Divider()
                    GlassInfoRow(label: "WPM", value: "156", icon: "speedometer")
                }
            }
            
            EmptyStateCard(
                icon: "mic.slash",
                title: "No Recordings Yet",
                message: "Start your first practice session to see your progress here.",
                buttonTitle: "Start Recording",
                buttonAction: {}
            )
        }
        .padding()
    }
    .background(Color.gray.opacity(0.1))
}
