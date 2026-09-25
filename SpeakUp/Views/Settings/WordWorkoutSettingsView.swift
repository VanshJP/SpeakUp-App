import SwiftUI

struct WordWorkoutSettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            PageScrollView {
                VStack(spacing: AppLayout.listSpacing) {
                    VocabChallengeSettingsCard(viewModel: viewModel)

                    GlassRowGroup {
                        NavigationLink {
                            WordBankView(viewModel: viewModel, showDismissButton: false, initialTab: .words)
                                .restoresNavigationBar()
                        } label: {
                            HStack(spacing: 14) {
                                IconChip(icon: "list.bullet.rectangle", tint: AppColors.categorySage, size: 30)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Your words")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(wordCountText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 8)

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                    }
                }
                .padding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Word Workout")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var wordCountText: String {
        switch viewModel.vocabWords.count {
        case 0: "Add words for the workout to draw from"
        case 1: "1 word the workout draws from"
        case let count: "\(count) words the workout draws from"
        }
    }
}
