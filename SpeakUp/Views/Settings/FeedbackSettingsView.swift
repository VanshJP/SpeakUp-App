import SwiftUI

struct FeedbackSettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    private static let askCaption = "Quick self-check questions while your take is analyzed."

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            PageScrollView {
                VStack(alignment: .leading, spacing: AppLayout.chapterSpacing) {
                    GlassRowGroup(dividerInset: Self.dividerInset) {
                        row {
                            Toggle(isOn: $viewModel.sessionFeedbackEnabled) {
                                Label("Ask after recording", systemImage: "checkmark.message")
                                    .font(.subheadline)
                            }
                            .tint(AppColors.primary)
                            .accessibilityHint(Self.askCaption)

                            Text(Self.askCaption)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.leading, 36)
                                .accessibilityHidden(true)
                        }
                    }

                    if viewModel.sessionFeedbackEnabled {
                        VStack(alignment: .leading, spacing: 10) {
                            GlassSectionHeader("Questions")

                            GlassRowGroup(dividerInset: Self.dividerInset) {
                                ForEach(viewModel.activeFeedbackQuestions) { question in
                                    questionRow(question)
                                }

                                Button {
                                    Haptics.light()
                                    viewModel.showingAddFeedbackQuestion = true
                                } label: {
                                    row {
                                        Label("Add a custom question", systemImage: "plus.circle")
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(RowPressStyle())
                            }

                            // Built-in questions have no remove control yet; say so
                            // rather than leave a row that looks broken.
                            Text("Built-in questions are always asked. Questions you add can be removed.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 4)
                        }
                    }
                }
                .padding()
                .labelStyle(.row)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Session Feedback")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewModel.sessionFeedbackEnabled) { _, _ in
            guard !viewModel.isSyncing else { return }
            Task { await viewModel.saveSettings() }
        }
        .sheet(isPresented: $viewModel.showingAddFeedbackQuestion) {
            AddFeedbackQuestionSheet(viewModel: viewModel)
        }
    }

    // MARK: - Rows

    /// Rules start under the row titles: 14pt row inset + the 24pt glyph
    /// column + the 12pt gap of `RowLabelStyle`.
    private static let dividerInset: CGFloat = 50

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: AppLayout.minHitTarget, alignment: .leading)
    }

    private func questionRow(_ question: FeedbackQuestion) -> some View {
        let isCustom = viewModel.customFeedbackQuestions.contains { $0.id == question.id }
        return row {
            HStack(spacing: 8) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(question.text)
                            .font(.subheadline)
                        Text(question.type.answerLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: question.type == .scale ? "star" : "hand.thumbsup")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if isCustom {
                    Button {
                        viewModel.removeFeedbackQuestion(question)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .frame(width: AppLayout.minHitTarget, height: AppLayout.minHitTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(GlassPressStyle())
                    // A 44pt target laid out at 28pt, like `DismissButton`.
                    .padding(-8)
                    .accessibilityLabel("Remove \(question.text)")
                } else {
                    Text("Built in")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

// MARK: - Add Question Sheet

/// A form that saves, so it keeps Cancel / Add in the bar: the in-page Add
/// button sat under the keyboard at the medium detent, and Return did nothing.
private struct AddFeedbackQuestionSheet: View {
    @Bindable var viewModel: SettingsViewModel
    @FocusState private var isQuestionFocused: Bool

    private var canAdd: Bool {
        !viewModel.newFeedbackQuestionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground(style: .subtle)

                VStack(spacing: 20) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Question")
                                .font(.subheadline.weight(.medium))

                            TextField("e.g. How confident did you feel?", text: $viewModel.newFeedbackQuestionText)
                                .textFieldStyle(.plain)
                                .focused($isQuestionFocused)
                                .submitLabel(.done)
                                .onSubmit {
                                    if canAdd { viewModel.addFeedbackQuestion() }
                                }
                                .padding(12)
                                .background {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.white.opacity(0.10))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                                        }
                                }

                            Text("Answer type")
                                .font(.subheadline.weight(.medium))

                            Picker("Answer type", selection: $viewModel.newFeedbackQuestionType) {
                                Text(FeedbackQuestionType.scale.answerLabel).tag(FeedbackQuestionType.scale)
                                Text(FeedbackQuestionType.yesNo.answerLabel).tag(FeedbackQuestionType.yesNo)
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("New Question")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.newFeedbackQuestionText = ""
                        viewModel.newFeedbackQuestionType = .scale
                        viewModel.showingAddFeedbackQuestion = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        viewModel.addFeedbackQuestion()
                    }
                    .disabled(!canAdd)
                }
            }
            .onAppear { isQuestionFocused = true }
        }
        .presentationDetents([.medium])
    }
}

private extension FeedbackQuestionType {
    var answerLabel: String {
        switch self {
        case .scale: "1–5 scale"
        case .yesNo: "Yes or no"
        }
    }
}
