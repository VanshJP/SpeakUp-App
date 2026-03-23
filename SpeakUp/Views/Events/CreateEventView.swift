import SwiftUI

struct CreateEventView: View {
    @Bindable var viewModel: EventViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: SessionType = .speech
    @State private var title = ""
    @State private var eventDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var selectedDuration: Int = 5
    @State private var maxDailyPracticeMinutes = 45
    @State private var audienceType: AudienceType?
    @State private var audienceSizeText = ""
    @State private var venue = ""
    @State private var notes = ""
    @State private var scriptText = ""
    @State private var isOpenEnded = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground(style: .subtle)

                ScrollView {
                    VStack(spacing: 16) {
                        introCard
                        sessionTypeSection
                        essentialsSection
                        optionalContextSection
                        scriptSection
                        createActions
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private var introCard: some View {
        FeaturedGlassCard(gradientColors: [AppColors.glassTintPrimary, AppColors.glassTintAccent], padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Set one clear target")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Pick your event type, deadline, and daily effort. Optional context can be added below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var sessionTypeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassSectionHeader("What are you preparing for?", icon: "sparkles")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(SessionType.allCases) { type in
                    Button {
                        Haptics.selection()
                        selectedType = type
                        selectedDuration = type.defaultDurationMinutes
                    } label: {
                        GlassCard(
                            tint: selectedType == type ? AppColors.glassTintPrimary : nil,
                            padding: 12,
                            accentBorder: selectedType == type ? AppColors.primary : nil
                        ) {
                            VStack(spacing: 8) {
                                Image(systemName: type.icon)
                                    .font(.headline)
                                    .foregroundStyle(selectedType == type ? AppColors.primary : .secondary)
                                Text(type.rawValue)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, minHeight: 70)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var essentialsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassSectionHeader("Essentials", icon: "checkmark.seal")

            GlassCard(tint: AppColors.glassTintPrimary.opacity(0.65), padding: 14) {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Event title")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField(selectedType.titlePlaceholder, text: $title)
                            .textFieldStyle(.plain)
                    }

                    Divider()

                    Toggle(isOn: $isOpenEnded) {
                        Label("Open-ended (no deadline)", systemImage: "infinity")
                            .font(.subheadline)
                    }
                    .tint(AppColors.primary)

                    if !isOpenEnded {
                        DatePicker(
                            "Event date",
                            selection: $eventDate,
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .font(.subheadline)
                        .tint(AppColors.primary)
                    }

                    Divider()

                    Stepper(value: $selectedDuration, in: 1...180, step: 1) {
                        HStack {
                            Label("Expected speaking time", systemImage: "clock")
                                .font(.subheadline)
                            Spacer()
                            Text("\(selectedDuration) min")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppColors.primary)
                        }
                    }

                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(selectedType.durationOptions, id: \.self) { minutes in
                                Button {
                                    Haptics.selection()
                                    selectedDuration = minutes
                                } label: {
                                    Text("\(minutes)m")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(selectedDuration == minutes ? .white : .secondary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background {
                                            Capsule()
                                                .fill(selectedDuration == minutes ? AppColors.primary.opacity(0.8) : AppColors.accent.opacity(0.12))
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)

                    Divider()

                    Stepper(value: $maxDailyPracticeMinutes, in: 10...240, step: 5) {
                        HStack {
                            Label("Daily practice capacity", systemImage: "timer")
                                .font(.subheadline)
                            Spacer()
                            Text("\(maxDailyPracticeMinutes) min/day")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppColors.primary)
                        }
                    }
                }
            }
        }
    }

    private var optionalContextSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassSectionHeader("Optional context", icon: "text.badge.plus")

            GlassCard(padding: 14) {
                VStack(spacing: 12) {
                    if selectedType.showsAudience {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Audience")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            ScrollView(.horizontal) {
                                HStack(spacing: 8) {
                                    ForEach(selectedType.suggestedAudienceTypes) { type in
                                        Button {
                                            Haptics.selection()
                                            audienceType = audienceType == type ? nil : type
                                        } label: {
                                            Text(type.rawValue)
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(audienceType == type ? .white : .secondary)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background {
                                                    Capsule()
                                                        .fill(audienceType == type ? AppColors.primary.opacity(0.8) : AppColors.accent.opacity(0.12))
                                                }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .scrollIndicators(.hidden)

                            TextField("Audience size (optional)", text: $audienceSizeText)
                                .textFieldStyle(.plain)
                                .keyboardType(.numberPad)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(.ultraThinMaterial)
                                }
                        }

                        Divider()
                    }

                    if selectedType.showsVenue {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(selectedType.venueLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            TextField("Optional", text: $venue)
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(.ultraThinMaterial)
                                }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("Optional context or constraints", text: $notes, axis: .vertical)
                            .lineLimit(2...4)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(.ultraThinMaterial)
                            }
                    }
                }
            }
        }
    }

    private var scriptSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassSectionHeader("Script (optional)", icon: "doc.text")

            GlassCard(tint: AppColors.glassTintAccent, padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    TextEditor(text: $scriptText)
                        .frame(minHeight: 170)
                        .scrollContentBackground(.hidden)
                        .font(.body)

                    HStack {
                        Label("\(scriptText.split(separator: " ").count) words", systemImage: "text.word.spacing")
                        Spacer()
                        let sectionCount = scriptText
                            .components(separatedBy: "\n\n")
                            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                            .count
                        Label("\(sectionCount) sections", systemImage: "doc.text")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var createActions: some View {
        VStack(spacing: 10) {
            GlassButton(
                title: "Create Event",
                icon: "checkmark",
                style: .primary,
                isLoading: viewModel.isCreating
            ) {
                Haptics.success()
                createEvent(includeScript: !scriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .disabled(viewModel.isCreating || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity((viewModel.isCreating || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? 0.5 : 1)

            if !scriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                GlassButton(title: "Create Without Script", icon: "forward.fill", style: .ghost, isLoading: viewModel.isCreating) {
                    Haptics.light()
                    createEvent(includeScript: false)
                }
                .disabled(viewModel.isCreating)
            }
        }
    }

    private func createEvent(includeScript: Bool) {
        Task {
            _ = await viewModel.createEvent(
                title: title,
                sessionType: selectedType,
                eventDate: isOpenEnded
                    ? Calendar.current.date(byAdding: .year, value: 10, to: Date()) ?? Date()
                    : eventDate,
                expectedDurationMinutes: selectedDuration,
                maxDailyPracticeMinutes: maxDailyPracticeMinutes,
                audienceType: audienceType,
                audienceSize: parsedAudienceSize,
                venue: venue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : venue,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
                scriptText: includeScript ? scriptText.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                isOpenEnded: isOpenEnded
            )
            dismiss()
        }
    }

    private var parsedAudienceSize: Int? {
        let digits = audienceSizeText.filter(\.isNumber)
        guard let value = Int(digits), value > 0 else { return nil }
        return value
    }
}

