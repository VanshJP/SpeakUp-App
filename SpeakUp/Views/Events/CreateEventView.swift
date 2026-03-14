import SwiftUI

struct CreateEventView: View {
    @Bindable var viewModel: EventViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: SessionType = .speech
    @State private var title = ""
    @State private var eventDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var selectedDuration: Int = 5
    @State private var audienceType: AudienceType?
    @State private var venue = ""
    @State private var notes = ""
    @State private var scriptText = ""
    @State private var isOpenEnded = false
    @State private var step = 0

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground(style: .subtle)

                ScrollView {
                    VStack(spacing: 24) {
                        // Step indicator
                        HStack(spacing: 8) {
                            ForEach(0..<3) { i in
                                Capsule()
                                    .fill(i <= step ? Color.teal : Color.white.opacity(0.15))
                                    .frame(height: 4)
                            }
                        }
                        .padding(.horizontal)

                        switch step {
                        case 0: sessionTypeStep
                        case 1: detailsStep
                        case 2: scriptStep
                        default: EmptyView()
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if step > 0 { step -= 1 } else { dismiss() }
                    } label: {
                        Image(systemName: step > 0 ? "chevron.left" : "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Step 1: Session Type

    private var sessionTypeStep: some View {
        VStack(spacing: 16) {
            Text("What are you preparing for?")
                .font(.title3.weight(.semibold))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(SessionType.allCases) { type in
                    Button {
                        Haptics.light()
                        selectedType = type
                        selectedDuration = type.defaultDurationMinutes
                    } label: {
                        GlassCard(tint: selectedType == type ? Color.teal.opacity(0.15) : nil, accentBorder: selectedType == type ? .teal : nil) {
                            VStack(spacing: 10) {
                                Image(systemName: type.icon)
                                    .font(.title2)
                                    .foregroundStyle(selectedType == type ? .teal : .secondary)

                                Text(type.rawValue)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(selectedType == type ? .primary : .secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 80)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)

            GlassButton(title: "Next", icon: "arrow.right", style: .primary) {
                Haptics.medium()
                step = 1
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Step 2: Details

    private var detailsStep: some View {
        VStack(spacing: 16) {
            Text("Event Details")
                .font(.title3.weight(.semibold))

            VStack(spacing: 12) {
                // Title
                GlassCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Title")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        TextField(selectedType.titlePlaceholder, text: $title)
                            .textFieldStyle(.plain)
                    }
                }

                // Date / Open-ended toggle
                GlassCard(padding: 12) {
                    VStack(spacing: 12) {
                        Toggle(isOn: $isOpenEnded) {
                            Label("Open-ended (no deadline)", systemImage: "infinity")
                                .font(.subheadline)
                        }
                        .tint(.teal)

                        if !isOpenEnded {
                            DatePicker("Event Date", selection: $eventDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                                .font(.subheadline)
                        }
                    }
                }

                // Duration
                GlassCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Expected Duration")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(selectedType.durationOptions, id: \.self) { minutes in
                                    Button {
                                        Haptics.selection()
                                        selectedDuration = minutes
                                    } label: {
                                        Text("\(minutes) min")
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(selectedDuration == minutes ? .white : .primary)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                            .background {
                                                if selectedDuration == minutes {
                                                    Capsule().fill(Color.teal)
                                                } else {
                                                    Capsule().fill(.ultraThinMaterial)
                                                }
                                            }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                // Audience & Venue
                if selectedType.showsAudience {
                    GlassCard(padding: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Audience")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(selectedType.suggestedAudienceTypes) { type in
                                        Button {
                                            Haptics.selection()
                                            audienceType = audienceType == type ? nil : type
                                        } label: {
                                            Text(type.rawValue)
                                                .font(.caption.weight(.medium))
                                                .foregroundStyle(audienceType == type ? .white : .primary)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background {
                                                    if audienceType == type {
                                                        Capsule().fill(Color.teal)
                                                    } else {
                                                        Capsule().fill(.ultraThinMaterial)
                                                    }
                                                }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }

                if selectedType.showsVenue {
                    GlassCard(padding: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(selectedType.venueLabel)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            TextField("Optional", text: $venue)
                                .textFieldStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal)

            GlassButton(title: "Next", icon: "arrow.right", style: .primary) {
                Haptics.medium()
                step = 2
            }
            .padding(.horizontal, 20)
            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(title.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
        }
    }

    // MARK: - Step 3: Script

    private var scriptStep: some View {
        VStack(spacing: 16) {
            Text("Add a Script (Optional)")
                .font(.title3.weight(.semibold))

            Text("Paste your script below. Separate paragraphs to create sections.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            GlassCard(padding: 12) {
                TextEditor(text: $scriptText)
                    .frame(minHeight: 200)
                    .scrollContentBackground(.hidden)
                    .font(.body)
            }
            .padding(.horizontal)

            if !scriptText.isEmpty {
                HStack {
                    Label("\(scriptText.split(separator: " ").count) words", systemImage: "text.word.spacing")
                    Spacer()
                    let sectionCount = scriptText.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
                    Label("\(sectionCount) section\(sectionCount == 1 ? "" : "s")", systemImage: "doc.text")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
            }

            VStack(spacing: 12) {
                GlassButton(title: "Create Event", icon: "checkmark", style: .primary) {
                    Haptics.success()
                    let _ = viewModel.createEvent(
                        title: title,
                        sessionType: selectedType,
                        eventDate: isOpenEnded ? Calendar.current.date(byAdding: .year, value: 10, to: Date())! : eventDate,
                        expectedDurationMinutes: selectedDuration,
                        audienceType: audienceType,
                        venue: venue.isEmpty ? nil : venue,
                        notes: notes.isEmpty ? nil : notes,
                        scriptText: scriptText.isEmpty ? nil : scriptText,
                        isOpenEnded: isOpenEnded
                    )
                    dismiss()
                }

                GlassButton(title: "Skip Script", icon: "forward.fill", style: .ghost) {
                    Haptics.light()
                    let _ = viewModel.createEvent(
                        title: title,
                        sessionType: selectedType,
                        eventDate: isOpenEnded ? Calendar.current.date(byAdding: .year, value: 10, to: Date())! : eventDate,
                        expectedDurationMinutes: selectedDuration,
                        audienceType: audienceType,
                        venue: venue.isEmpty ? nil : venue,
                        isOpenEnded: isOpenEnded
                    )
                    dismiss()
                }
            }
            .padding(.horizontal, 20)
        }
    }
}
