import SwiftUI

struct OnboardingView: View {
    @State private var viewModel = OnboardingViewModel()
    var onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Page Content
            TabView(selection: $viewModel.currentPage) {
                // Page 1: Welcome
                OnboardingPageView(
                    icon: "waveform.circle.fill",
                    title: "Welcome to SpeakUp",
                    subtitle: "Practice speaking, reduce filler words, and become a more confident communicator.",
                    accentColor: .teal
                )
                .tag(0)

                // Page 2: How It Works
                OnboardingPageView(
                    icon: "arrow.triangle.2.circlepath",
                    title: "How It Works",
                    subtitle: "Record your speech, get instant analysis on pace, clarity, and filler words, then track your improvement over time.",
                    accentColor: .blue
                )
                .tag(1)

                // Page 3: Scoring
                scoringPage
                    .tag(2)

                // Page 4: Listen Back
                listenBackPage
                    .tag(3)

                // Page 5: Mic Permission
                micPermissionPage
                    .tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: viewModel.currentPage)

            // Bottom controls
            VStack(spacing: 16) {
                // Page dots
                HStack(spacing: 8) {
                    ForEach(0..<viewModel.totalPages, id: \.self) { index in
                        Circle()
                            .fill(index == viewModel.currentPage ? Color.teal : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                            .animation(.easeInOut, value: viewModel.currentPage)
                    }
                }

                // Action button
                Button {
                    if viewModel.isLastPage {
                        onComplete()
                    } else {
                        viewModel.nextPage()
                    }
                } label: {
                    Text(viewModel.isLastPage ? (viewModel.hasMicPermission ? "Get Started" : "Continue Without Mic") : "Continue")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.teal)
                        )
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 40)
        }
        .onAppear {
            viewModel.checkMicPermission()
        }
    }

    // MARK: - Scoring Page

    private var scoringPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "chart.bar.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)

            VStack(spacing: 12) {
                Text("Your Speech Score")
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)

                Text("Every session is scored across four dimensions to help you improve.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // Subscore preview
            VStack(spacing: 12) {
                ScorePreviewRow(icon: "waveform", title: "Clarity", color: .blue)
                ScorePreviewRow(icon: "speedometer", title: "Pace", color: .green)
                ScorePreviewRow(icon: "text.badge.minus", title: "Filler Usage", color: .orange)
                ScorePreviewRow(icon: "pause.circle", title: "Pause Quality", color: .purple)
            }
            .padding(.horizontal, 40)

            Spacer()
            Spacer()
        }
        .padding()
    }

    // MARK: - Listen Back Page

    private var listenBackPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "headphones")
                .font(.system(size: 72))
                .foregroundStyle(.purple)

            VStack(spacing: 12) {
                Text("About Hearing Your Voice")
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)

                Text("Hearing your own voice feels weird at first — that's completely normal! Everyone sounds different to themselves. Listening back is actually a superpower for improvement.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
            Spacer()
        }
        .padding()
    }

    // MARK: - Mic Permission Page

    private var micPermissionPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: viewModel.hasMicPermission ? "mic.circle.fill" : "mic.slash.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(viewModel.hasMicPermission ? .green : .orange)

            VStack(spacing: 12) {
                Text(viewModel.hasMicPermission ? "Microphone Enabled" : "Microphone Access")
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)

                Text(viewModel.hasMicPermission
                     ? "You're all set! SpeakUp can now record and analyze your speech."
                     : "SpeakUp needs microphone access to record and analyze your speech. Your recordings stay on your device.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if !viewModel.hasMicPermission {
                Button {
                    Task {
                        await viewModel.requestMicPermission()
                    }
                } label: {
                    Label("Enable Microphone", systemImage: "mic.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.orange)
                        )
                }
                .disabled(viewModel.isRequestingPermission)
            }

            Spacer()
            Spacer()
        }
        .padding()
    }
}

// MARK: - Score Preview Row

private struct ScorePreviewRow: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)
                .frame(width: 24)

            Text(title)
                .font(.subheadline.weight(.medium))

            Spacer()

            RoundedRectangle(cornerRadius: 3)
                .fill(color.opacity(0.3))
                .frame(width: 80, height: 6)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: CGFloat.random(in: 40...75))
                }
        }
    }
}
