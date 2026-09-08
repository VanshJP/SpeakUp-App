import SwiftUI

struct WordWorkoutSettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            PageScrollView {
                VStack(spacing: 16) {
                    VocabChallengeSettingsCard(viewModel: viewModel)

                    NavigationLink {
                        WordBankView(viewModel: viewModel, showDismissButton: false)
                    } label: {
                        GlassCard(padding: 14) {
                            HStack(spacing: 14) {
                                Image(systemName: "list.bullet.rectangle")
                                    .font(.body)
                                    .foregroundStyle(AppColors.categorySage)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Your word bank")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("\(viewModel.vocabWords.count) word\(viewModel.vocabWords.count == 1 ? "" : "s") the workout draws from")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Word Workout")
        .navigationBarTitleDisplayMode(.inline)
    }
}
