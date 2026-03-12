import SwiftUI
import SwiftData

struct FeedbackSettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            ScrollView {
                VStack(spacing: 20) {
                    GlassCard {
                        VStack(spacing: 0) {
                            Toggle(isOn: $viewModel.sessionFeedbackEnabled) {
                                Label("Ask After Recording", systemImage: "checkmark.message")
                                    .font(.subheadline)
                            }
                            .tint(.teal)
                            .frame(minHeight: 40)

                            if viewModel.sessionFeedbackEnabled {
                                Divider().padding(.vertical, 8)

                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Questions")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)

                                    ForEach(viewModel.activeFeedbackQuestions) { question in
                                        HStack(spacing: 10) {
                                            Image(systemName: question.type == .scale ? "star.fill" : "hand.thumbsup.fill")
                                                .font(.caption)
                                                .foregroundStyle(.teal)
                                                .frame(width: 16)

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(question.text)
                                                    .font(.subheadline)
                                                Text(question.type == .scale ? "1-5 Scale" : "Yes / No")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }

                                            Spacer()

                                            if viewModel.customFeedbackQuestions.contains(where: { $0.id == question.id }) {
                                                Button {
                                                    viewModel.removeFeedbackQuestion(question)
                                                } label: {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .font(.caption)
                                                        .foregroundStyle(.white.opacity(0.3))
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                    }
                                }

                                Divider().padding(.vertical, 8)

                                Button {
                                    Haptics.light()
                                    viewModel.showingAddFeedbackQuestion = true
                                } label: {
                                    HStack {
                                        Label("Add Custom Question", systemImage: "plus.circle")
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .frame(minHeight: 40)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Text("Quick self-assessment questions shown while your speech is being analyzed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                .padding()
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
            addFeedbackQuestionSheet
        }
    }

    private var addFeedbackQuestionSheet: some View {
        NavigationStack {
            ZStack {
                AppBackground(style: .subtle)

                VStack(spacing: 20) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Question Text")
                                .font(.subheadline.weight(.medium))

                            TextField("e.g. How confident did you feel?", text: $viewModel.newFeedbackQuestionText)
                                .textFieldStyle(.plain)
                                .padding(12)
                                .background {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(.white.opacity(0.06))
                                }

                            Text("Answer Type")
                                .font(.subheadline.weight(.medium))

                            Picker("Type", selection: $viewModel.newFeedbackQuestionType) {
                                Text("1-5 Scale").tag(FeedbackQuestionType.scale)
                                Text("Yes / No").tag(FeedbackQuestionType.yesNo)
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    GlassButton(title: "Add Question", icon: "plus", style: .primary) {
                        viewModel.addFeedbackQuestion()
                    }
                    .disabled(viewModel.newFeedbackQuestionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

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
                        viewModel.showingAddFeedbackQuestion = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
