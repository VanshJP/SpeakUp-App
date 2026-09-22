import SwiftUI
import SwiftData

/// Browse every word the app can teach, look one up, and add it to your bank.
///
/// The word bank was previously write-only: Settings → Word Lists is a form
/// for typing words in, and the curated lexicon the daily workout draws from
/// was visible one word a day and nowhere else. This is the reading end of the
/// same data - the whole lexicon with its glosses, your own words beside it,
/// and a search box that falls through to the system dictionary so a word the
/// app has never heard of is still a word you can look up and keep.
struct WordLibraryView: View {
    @Environment(\.modelContext) private var modelContext

    /// Same ownership shape as `WordBankView`: the settings view model is
    /// where word-bank safety, de-duplication and persistence already live,
    /// and forking a second path to `UserSettings.vocabWords` would be two
    /// definitions of what counts as an addable word.
    @State private var viewModel = SettingsViewModel()
    @State private var pronunciation = PronunciationService()
    @State private var query = ""
    @State private var selection: WordLibraryEntry?
    /// Built once on appear. `GeneratedVocabStore.entries()` decodes JSON out
    /// of `UserDefaults` and the curated lexicon needs a merge plus a sort -
    /// neither belongs on the path a keystroke in the search field takes.
    /// Filtering this per keystroke is cheap; rebuilding it would not be.
    @State private var catalog: [WordLibraryTier: [WordLibraryEntry]] = [:]
    @State private var catalogKeys: Set<String> = []

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            content
        }
        .navigationTitle("Words")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selection) { entry in
            WordLibraryDetailSheet(
                entry: entry,
                pronunciation: pronunciation,
                isSaved: isSaved(entry.word),
                onAdd: { add(entry.word) },
                onRemove: { viewModel.removeVocabWord(entry.word) }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            viewModel.configure(with: modelContext)
            if catalog.isEmpty { buildCatalog() }
        }
        .onDisappear { pronunciation.stop() }
    }

    private var content: some View {
        // Resolved once per pass. Each of these walks the lexicon, and the
        // empty state needs the same answers the sections do.
        let ownWords = matchingOwnWords
        let tiers = Dictionary(
            uniqueKeysWithValues: WordLibraryTier.allCases.map { ($0, matchingCatalog(in: $0)) }
        )
        let unknown = unmatchedQuery
        let isEmpty = !trimmedQuery.isEmpty
            && unknown == nil
            && ownWords.isEmpty
            && tiers.values.allSatisfy(\.isEmpty)

        return PageScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                InlineSearchField(text: $query, prompt: "Search any word…") {
                    EmptyView()
                }

                if let unknown {
                    lookupCard(unknown)
                }

                if !ownWords.isEmpty {
                    section(title: "Your words", icon: "bookmark.fill", entries: ownWords)
                }

                ForEach(WordLibraryTier.allCases) { tier in
                    let entries = tiers[tier] ?? []
                    if !entries.isEmpty {
                        section(title: tier.title, icon: tier.icon, entries: entries)
                    }
                }

                if isEmpty {
                    EmptyStateCard(
                        icon: "character.book.closed",
                        title: "No words match",
                        message: "Nothing here matches \u{201C}\(trimmedQuery)\u{201D}. Search a single word to look it up in the dictionary."
                    )
                }
            }
            .padding(.top, 8)
            .pageContentInsets()
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Sections

    private func section(title: String, icon: String, entries: [WordLibraryEntry]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassSectionHeader(title, icon: icon) {
                Text("\(entries.count)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: 8) {
                ForEach(entries) { entry in
                    WordLibraryRow(
                        entry: entry,
                        isSaved: isSaved(entry.word),
                        onOpen: {
                            Haptics.light()
                            selection = entry
                        },
                        onAdd: { add(entry.word) }
                    )
                }
            }
        }
    }

    /// The fall-through door: a search that matches nothing in the app is
    /// still a word, and the system dictionary knows far more of them than a
    /// four-hundred-entry lexicon ever will.
    private func lookupCard(_ word: String) -> some View {
        Button {
            Haptics.light()
            selection = WordLibraryEntry(word: word, gloss: nil, prompt: nil, tier: nil)
        } label: {
            GlassCard(cornerRadius: 16, tint: AppColors.primary.opacity(0.08), padding: 14) {
                HStack(spacing: 12) {
                    IconChip(icon: "magnifyingglass", size: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Look up \u{201C}\(word)\u{201D}")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text("Definition, pronunciation, and add to your words")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityLabel("Look up \(word)")
    }

    // MARK: - Data

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Curated lexicon first, then anything the on-device model has produced.
    /// A generated word never shadows a curated one, same rule as the picker.
    private func buildCatalog() {
        let known = DefaultVocabLexicon.keys
        let generated = GeneratedVocabStore.standard.entries()
            .filter { !known.contains($0.word.lowercased()) }
        let all = DefaultVocabLexicon.entries + generated

        var byTier: [WordLibraryTier: [WordLibraryEntry]] = [:]
        for tier in WordLibraryTier.allCases {
            byTier[tier] = all
                .filter { $0.level == tier.rawValue }
                .sorted { $0.word.localizedStandardCompare($1.word) == .orderedAscending }
                .map {
                    WordLibraryEntry(word: $0.word, gloss: $0.gloss, prompt: $0.prompt, tier: tier)
                }
        }
        catalog = byTier
        catalogKeys = Set(all.map { $0.word.lowercased() })
    }

    private func matches(_ text: String) -> Bool {
        trimmedQuery.isEmpty || text.localizedStandardContains(trimmedQuery)
    }

    private func matchingCatalog(in tier: WordLibraryTier) -> [WordLibraryEntry] {
        guard let entries = catalog[tier] else { return [] }
        guard !trimmedQuery.isEmpty else { return entries }
        return entries.filter { matches($0.word) || matches($0.gloss ?? "") }
    }

    /// Words the user added that the lexicon does not already list - listing
    /// them twice would make the page look like it double-counts the bank.
    private var matchingOwnWords: [WordLibraryEntry] {
        viewModel.vocabWords
            .filter { !catalogKeys.contains($0.lowercased()) }
            .filter { matches($0) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { WordLibraryEntry(word: $0, gloss: nil, prompt: nil, tier: nil) }
    }

    /// A one-word search that matched nothing by name. A multi-word query is
    /// not a dictionary headword, so it gets no lookup card.
    private var unmatchedQuery: String? {
        let word = trimmedQuery
        guard word.count >= 2,
              !word.contains(" "),
              PronunciationService.canDefine(word) else { return nil }
        let key = word.lowercased()
        let inBank = viewModel.vocabWords.contains { $0.lowercased() == key }
        return (catalogKeys.contains(key) || inBank) ? nil : word
    }

    private func isSaved(_ word: String) -> Bool {
        viewModel.vocabWords.contains { $0.caseInsensitiveCompare(word) == .orderedSame }
    }

    private func add(_ word: String) {
        viewModel.newVocabWord = word
        viewModel.addVocabWord()
    }
}

// MARK: - Entry

/// One row on the page. Flattens a lexicon entry and a bare bank word into the
/// same shape so the list does not branch on where a word came from.
struct WordLibraryEntry: Identifiable, Hashable {
    let word: String
    let gloss: String?
    let prompt: String?
    let tier: WordLibraryTier?

    var id: String { word.lowercased() }
}

/// The lexicon's three difficulty tiers, named for what they are to a speaker
/// rather than for the integer they are stored as.
enum WordLibraryTier: Int, CaseIterable, Identifiable {
    case everyday = 0
    case sharper = 1
    case advanced = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .everyday: return "Everyday"
        case .sharper: return "Sharper"
        case .advanced: return "Advanced"
        }
    }

    var icon: String {
        switch self {
        case .everyday: return "text.bubble"
        case .sharper: return "sparkles"
        case .advanced: return "graduationcap"
        }
    }

    var tint: Color {
        switch self {
        case .everyday: return AppColors.categorySage
        case .sharper: return AppColors.primary
        case .advanced: return AppColors.categoryIndigo
        }
    }
}

// MARK: - Row

private struct WordLibraryRow: View {
    let entry: WordLibraryEntry
    let isSaved: Bool
    let onOpen: () -> Void
    let onAdd: () -> Void

    private var tint: Color { entry.tier?.tint ?? AppColors.categoryNeutralCool }

    /// Two sibling buttons inside one card, not a button inside a button:
    /// nesting them makes which one a tap reaches a matter of luck.
    var body: some View {
        GlassCard(cornerRadius: 14, padding: 12) {
            HStack(alignment: .top, spacing: 12) {
                Button(action: onOpen) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.word)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        Text(entry.gloss ?? "Your word. Tap for the definition.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, minHeight: AppLayout.minHitTarget - 12, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(entry.word)
                .accessibilityValue(entry.gloss ?? (isSaved ? "In your words" : ""))
                .accessibilityHint("Opens the definition")

                addControl
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var addControl: some View {
        if isSaved {
            Image(systemName: "checkmark.circle.fill")
                .font(.body)
                .foregroundStyle(AppColors.success)
                .frame(width: AppLayout.minHitTarget, height: AppLayout.minHitTarget - 12)
                .accessibilityLabel("In your words")
        } else {
            Button {
                Haptics.light()
                onAdd()
            } label: {
                Image(systemName: "plus.circle")
                    .font(.body)
                    .foregroundStyle(tint)
                    .frame(width: AppLayout.minHitTarget, height: AppLayout.minHitTarget - 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(entry.word) to your words")
        }
    }
}

// MARK: - Detail

private struct WordLibraryDetailSheet: View {
    let entry: WordLibraryEntry
    let pronunciation: PronunciationService
    let isSaved: Bool
    let onAdd: () -> Void
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingDictionary = false
    @State private var savedLocally: Bool

    init(
        entry: WordLibraryEntry,
        pronunciation: PronunciationService,
        isSaved: Bool,
        onAdd: @escaping () -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.entry = entry
        self.pronunciation = pronunciation
        self.isSaved = isSaved
        self.onAdd = onAdd
        self.onRemove = onRemove
        _savedLocally = State(initialValue: isSaved)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground(style: .subtle)

                PageScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        headerCard

                        if let gloss = entry.gloss {
                            meaningCard(gloss)
                        }

                        if let prompt = entry.prompt {
                            promptCard(prompt)
                        }

                        GlassButton(
                            title: "Full definition",
                            icon: "book.fill",
                            style: .secondary,
                            fullWidth: true
                        ) {
                            Haptics.light()
                            showingDictionary = true
                        }
                        .disabled(!PronunciationService.canDefine(entry.word))

                        GlassButton(
                            title: savedLocally ? "Remove from your words" : "Add to your words",
                            icon: savedLocally ? "bookmark.slash" : "bookmark.fill",
                            style: savedLocally ? .secondary : .primary,
                            fullWidth: true
                        ) {
                            Haptics.medium()
                            if savedLocally { onRemove() } else { onAdd() }
                            savedLocally.toggle()
                        }
                    }
                    .padding(.top, 8)
                    .pageContentInsets()
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(entry.word)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingDictionary) {
                DictionaryView(term: entry.word)
            }
        }
    }

    private var headerCard: some View {
        GlassCard(tint: (entry.tier?.tint ?? AppColors.primary).opacity(0.10), padding: 18) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.word)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    if let tier = entry.tier {
                        StatusPill(text: tier.title, color: tier.tint, glyph: .dot)
                    } else if savedLocally {
                        StatusPill(text: "Your word", color: AppColors.success, glyph: .dot)
                    }
                }

                Spacer(minLength: 8)

                Button {
                    Haptics.light()
                    pronunciation.speak(word: entry.word)
                } label: {
                    Image(systemName: pronunciation.isSpeaking ? "speaker.wave.3.fill" : "speaker.wave.2.fill")
                        .font(.title3)
                        .foregroundStyle(AppColors.primary)
                        .frame(width: 48, height: 48)
                        .background { Circle().fill(.ultraThinMaterial) }
                }
                .buttonStyle(GlassPressStyle())
                .disabled(pronunciation.isSpeaking)
                .accessibilityLabel("Hear \(entry.word)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func meaningCard(_ gloss: String) -> some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Meaning")
                    .eyebrowStyle()

                Text(gloss)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func promptCard(_ prompt: String) -> some View {
        GlassCard(tint: AppColors.categorySage.opacity(0.08), padding: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Say it out loud")
                    .eyebrowStyle()

                Text(prompt)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Entry row for the Tools landing

/// The door on Library → Tools. A full-width row rather than a fifth tile:
/// the practice grid is four tools that open the mic, and a word list is not
/// one of them.
struct WordLibraryEntryRow: View {
    private var summary: String {
        "\(DefaultVocabLexicon.entries.count) words"
    }

    var body: some View {
        NavigationLink(value: WordLibraryRoute()) {
            GlassCard(cornerRadius: 16, tint: AppColors.categorySage.opacity(0.07), padding: 14) {
                HStack(spacing: 12) {
                    IconChip(icon: "character.book.closed.fill", tint: AppColors.categorySage, size: 36)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Words")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)

                        Text("Look up a word, keep the ones worth using")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)

                        Text(summary)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .padding(.top, 1)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityLabel("Words. Look up a word, keep the ones worth using. \(summary).")
    }
}

/// Route value so the row can push from inside Library's own stack.
struct WordLibraryRoute: Hashable {}

#Preview {
    NavigationStack {
        WordLibraryView()
    }
    .modelContainer(for: [UserSettings.self], inMemory: true)
}
