import SwiftUI

struct ScriptEditorView: View {
    let event: SpeakingEvent
    @Bindable var viewModel: EventViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var scriptText: String = ""
    @State private var changeNote: String = ""
    @State private var showingVersionHistory = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground(style: .subtle)

                VStack(spacing: 0) {
                    // Stats bar
                    HStack {
                        Label("\(wordCount) words", systemImage: "text.word.spacing")
                        Spacer()
                        Label("\(sectionCount) section\(sectionCount == 1 ? "" : "s")", systemImage: "doc.text")
                        Spacer()
                        if event.currentVersionNumber > 0 {
                            Button {
                                showingVersionHistory = true
                            } label: {
                                Label("v\(event.currentVersionNumber)", systemImage: "clock.arrow.circlepath")
                            }
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    // Editor
                    TextEditor(text: $scriptText)
                        .scrollContentBackground(.hidden)
                        .font(.body)
                        .padding(.horizontal)

                    // Bottom bar
                    VStack(spacing: 12) {
                        if hasChanges {
                            GlassCard(padding: 10) {
                                TextField("What changed? (optional)", text: $changeNote)
                                    .font(.caption)
                                    .textFieldStyle(.plain)
                            }
                            .padding(.horizontal)

                            GlassButton(title: event.currentVersionNumber == 0 ? "Save Script" : "Save as Version \(nextVersion)", icon: "square.and.arrow.down", style: .primary) {
                                Haptics.success()
                                viewModel.saveNewScriptVersion(
                                    for: event,
                                    scriptText: scriptText,
                                    changeNote: changeNote.isEmpty ? nil : changeNote
                                )
                                dismiss()
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("Script Editor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(AppColors.primary)
                }
            }
            .onAppear {
                scriptText = event.scriptText ?? ""
            }
            .sheet(isPresented: $showingVersionHistory) {
                versionHistorySheet
            }
        }
    }

    // MARK: - Computed

    private var wordCount: Int {
        scriptText.split(separator: " ").count
    }

    private var sectionCount: Int {
        scriptText.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    private var hasChanges: Bool {
        scriptText != (event.scriptText ?? "")
    }

    private var nextVersion: Int {
        (event.currentVersionNumber) + 1
    }

    // MARK: - Version History

    private var versionHistorySheet: some View {
        NavigationStack {
            ZStack {
                AppBackground(style: .subtle)

                ScrollView {
                    LazyVStack(spacing: 12) {
                        if let versions = event.scriptVersions?.sorted(by: { $0.versionNumber > $1.versionNumber }) {
                            ForEach(versions) { version in
                                GlassCard(padding: 12) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text("Version \(version.versionNumber)")
                                                .font(.subheadline.weight(.semibold))

                                            Spacer()

                                            Text(version.createdDate.formatted(date: .abbreviated, time: .shortened))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }

                                        if let note = version.changeNote, !note.isEmpty {
                                            Text(note)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        HStack {
                                            Text("\(version.wordCount) words")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)

                                            Spacer()

                                            Button("Restore") {
                                                scriptText = version.scriptText
                                                showingVersionHistory = false
                                            }
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(AppColors.primary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Version History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showingVersionHistory = false }
                }
            }
        }
    }
}
