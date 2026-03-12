import SwiftUI
import SwiftData

struct CreateEventView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = EventPrepViewModel()

    var onCreated: (SpeakingEvent) -> Void

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            ScrollView {
                VStack(spacing: 20) {
                    // Title
                    formSection(title: "Event Title", icon: "textformat") {
                        TextField("e.g., Team Presentation", text: $viewModel.newTitle)
                            .font(.body)
                            .foregroundStyle(.white)
                            .padding(14)
                            .background {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.ultraThinMaterial)
                            }
                    }

                    // Date
                    formSection(title: "Event Date", icon: "calendar") {
                        DatePicker(
                            "Date",
                            selection: $viewModel.newEventDate,
                            in: Calendar.current.date(byAdding: .day, value: 1, to: Date())!...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.compact)
                        .tint(AppColors.primary)
                        .padding(14)
                        .background {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.ultraThinMaterial)
                        }
                    }

                    // Duration
                    formSection(title: "Speech Duration", icon: "clock") {
                        HStack(spacing: 8) {
                            ForEach(EventPrepViewModel.durationOptions, id: \.self) { mins in
                                Button {
                                    Haptics.light()
                                    viewModel.newDurationMinutes = mins
                                } label: {
                                    Text("\(mins)m")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(viewModel.newDurationMinutes == mins ? .white : .secondary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background {
                                            Capsule()
                                                .fill(viewModel.newDurationMinutes == mins ? AppColors.primary : Color.white.opacity(0.08))
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Audience Type
                    formSection(title: "Audience", icon: "person.3") {
                        HStack(spacing: 8) {
                            ForEach(AudienceType.allCases) { type in
                                Button {
                                    Haptics.light()
                                    viewModel.newAudienceType = viewModel.newAudienceType == type.rawValue ? nil : type.rawValue
                                } label: {
                                    Text(type.rawValue)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(viewModel.newAudienceType == type.rawValue ? .white : .secondary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .background {
                                            Capsule()
                                                .fill(viewModel.newAudienceType == type.rawValue ? AppColors.primary : Color.white.opacity(0.08))
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Venue & Notes
                    formSection(title: "Venue (optional)", icon: "mappin") {
                        TextField("e.g., Conference Room B", text: $viewModel.newVenue)
                            .font(.body)
                            .foregroundStyle(.white)
                            .padding(14)
                            .background {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.ultraThinMaterial)
                            }
                    }

                    formSection(title: "Notes (optional)", icon: "note.text") {
                        TextField("Any additional notes...", text: $viewModel.newNotes, axis: .vertical)
                            .font(.body)
                            .foregroundStyle(.white)
                            .lineLimit(3...6)
                            .padding(14)
                            .background {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.ultraThinMaterial)
                            }
                    }

                    // Script
                    formSection(title: "Paste Your Script (optional)", icon: "doc.text") {
                        VStack(alignment: .trailing, spacing: 6) {
                            TextEditor(text: $viewModel.newScriptText)
                                .font(.body)
                                .foregroundStyle(.white)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 120, maxHeight: 300)
                                .padding(10)
                                .background {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(.ultraThinMaterial)
                                }

                            if !viewModel.newScriptText.isEmpty {
                                let wordCount = viewModel.newScriptText.split(separator: " ").count
                                Text("\(wordCount) words")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Create Button
                    GlassButton(title: "Create Prep Plan", icon: "sparkles", style: .primary, size: .large, fullWidth: true) {
                        Haptics.success()
                        if let event = viewModel.createEvent() {
                            onCreated(event)
                            dismiss()
                        }
                    }
                    .disabled(!viewModel.canCreate)
                    .opacity(viewModel.canCreate ? 1 : 0.5)
                    .padding(.top, 8)
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("New Event")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            viewModel.configure(with: modelContext)
        }
    }

    // MARK: - Form Section Helper

    private func formSection<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            content()
        }
    }
}
