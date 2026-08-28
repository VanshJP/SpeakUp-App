import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LLMService.self) private var llmService
    @State private var viewModel = TodayViewModel()

    @Query private var userSettings: [UserSettings]
    @Environment(\.appTour) private var tour
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingFirstRecordingSetup = false

    // Arrival moment — fires once per calendar day, on the first open.
    @AppStorage("lastArrivalDay") private var lastArrivalDay = ""
    @State private var arrived = false
    @State private var showArrivalConfetti = false
    @State private var challengeStore = SharedChallengeStore.shared

    // Focus-card routing — mirrors the post-session NextStep sheets in
    // RecordingDetailView so both entry points land on the same tool.
    @State private var focusDrill: DrillMode?
    @State private var showingFocusWarmUp = false
    @State private var showingFocusReadAloud = false
    /// Home-screen edit mode, in place. The blocks below are the real ones —
    /// frozen, wiggling, and draggable — not stand-ins on a sheet.
    @State private var isEditingLayout = false
    @State private var dropTarget: TodayHomeModule?
    @State private var trayTargeted = false

    var onStartRecording: (Prompt?, RecordingDuration) -> Void
    var onShowReadAloud: () -> Void
    var onShowWarmUps: () -> Void
    var onShowDrills: () -> Void
    var onShowConfidence: () -> Void
    var onShowCurriculum: () -> Void
    var onStartStoryPractice: ((Story, RecordingDuration) -> Void)?

    /// Ordered visible modules from Settings. Empty storage → factory default.
    private var homeModules: [TodayHomeModule] {
        userSettings.first?.todayHomeModules ?? TodayHomeModule.defaultVisible
    }

    var body: some View {
        ZStack {
            AppBackground()

            // Vertical only, and `PageScrollView` is what makes that true: an
            // over-wide child used to let this page pan sideways. No horizontal
            // paging, no TabView page style, no horizontal scroller.
            PageScrollView {
                VStack(spacing: 20) {

                    // 1. Header — date + streak chip + customize
                    topHeaderRow
                        .allowsHitTesting(!isEditingLayout)

                    if isEditingLayout {
                        Text("Drag a block to move it. Tap ⊖ to hide one.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let challenge = challengeStore.pending {
                        FriendChallengeCard(
                            challenge: challenge,
                            onAccept: { acceptFriendChallenge(challenge) },
                            onDismiss: { challengeStore.dismiss() }
                        )
                    }

                    // Modular home — Bevel-style. Order and visibility come from
                    // `UserSettings.todayHomeLayoutRaw`; session is always forced on.
                    // Editing happens right here: same blocks, wiggling in place.
                    ForEach(homeModules) { module in
                        editableModule(module)
                    }

                    if isEditingLayout {
                        hiddenTray
                        resetLayoutButton
                    }
                }
                .padding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.light()
                    withAnimation(AppMotion.slide) { isEditingLayout.toggle() }
                } label: {
                    if isEditingLayout {
                        Text("Done").fontWeight(.semibold)
                    } else {
                        Image(systemName: "slider.horizontal.3")
                            .font(.body.weight(.semibold))
                    }
                }
                .accessibilityLabel(isEditingLayout ? "Finish customizing Today" : "Customize Today")
            }
        }
        .refreshable {
            await viewModel.loadData()
        }
        .onAppear {
            viewModel.configure(with: modelContext)
        }
        .task {
            playArrivalIfNeeded()
            await checkFirstRunSurfaces()
            // Fire-and-forget: tops up the fresh-word pool while the user is
            // looking at Today, so tomorrow's workout has novel words ready.
            viewModel.warmVocabFreshWords(llmService: llmService)
        }
        // The streak is only known once the load finishes, so the moment waits
        // for it rather than celebrating a zero.
        .onChange(of: viewModel.isLoading) { _, loading in
            if !loading { playArrivalIfNeeded() }
        }
        .sheet(isPresented: $showingFirstRecordingSetup, onDismiss: startTourIfNeeded) {
            FirstRecordingSetupSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $focusDrill) { mode in
            DrillSelectionView(initialMode: mode)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showingFocusWarmUp) {
            WarmUpListView()
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showingFocusReadAloud) {
            ReadAloudSelectionView()
                .presentationDetents([.large])
        }
    }

    // MARK: - Layout Editing

    /// A Today block, editable in place. Not a preview of the block — the block
    /// itself, frozen and wiggling, which is the whole point: you rearrange the
    /// page while looking at the page.
    @ViewBuilder
    private func editableModule(_ module: TodayHomeModule) -> some View {
        if isEditingLayout {
            Group {
                if moduleHasContent(module) {
                    homeModuleView(module)
                } else {
                    dormantModuleCard(module)
                }
            }
            .allowsHitTesting(false)
            .overlay {
                // Grab layer above the frozen block: gives the drag something
                // to catch, and swallows taps meant for the controls beneath.
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.white.opacity(0.001))
            }
            .overlay(alignment: .topLeading) {
                if !module.isPinned {
                    removeBadge(module).offset(x: -8, y: -8)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppColors.primary, lineWidth: dropTarget == module ? 2 : 0)
            }
            .wiggle(active: !reduceMotion, phase: module.wigglePhase)
            .draggable(module.rawValue)
            .dropDestination(for: String.self) { items, _ in
                guard let dragged = items.compactMap(TodayHomeModule.init(rawValue:)).first else { return false }
                insertModule(dragged, before: module)
                return true
            } isTargeted: { targeted in
                withAnimation(AppMotion.slide) {
                    if targeted { dropTarget = module }
                    else if dropTarget == module { dropTarget = nil }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(module.title)
            .accessibilityActions {
                // Drag is unreachable for assistive tech; same moves, spelled out.
                Button("Move up") { shiftModule(module, by: -1) }
                Button("Move down") { shiftModule(module, by: 1) }
                if !module.isPinned {
                    Button("Hide") { setModuleVisible(module, false) }
                }
            }
        } else {
            homeModuleView(module)
                // The Home-screen gesture: hold the page to rearrange it.
                // Simultaneous so it never eats a tap meant for a control.
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.6).onEnded { _ in
                        Haptics.medium()
                        withAnimation(AppMotion.slide) { isEditingLayout = true }
                    }
                )
        }
    }

    private func removeBadge(_ module: TodayHomeModule) -> some View {
        Button {
            Haptics.selection()
            setModuleVisible(module, false)
        } label: {
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 22))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.black.opacity(0.6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hide \(module.title)")
    }

    /// Weekly recap and Coach focus render nothing until they have data. In edit
    /// mode that would be an invisible, undraggable gap where a block should be,
    /// so the block states itself and says when it will show up for real.
    private func moduleHasContent(_ module: TodayHomeModule) -> Bool {
        switch module {
        case .rings, .session, .tools, .learn:
            return true
        case .weeklyRecap:
            guard let progress = viewModel.weeklyProgress else { return false }
            return progress.hasRecap && shouldShowWeeklyRecap
        case .focus:
            guard let plan = viewModel.coachPlan else { return false }
            return plan.sessionCount >= Self.focusMinimumSessions
        }
    }

    private func dormantModuleCard(_ module: TodayHomeModule) -> some View {
        HStack(spacing: 12) {
            Image(systemName: module.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(module.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text(dormantHint(module))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(AppColors.cardStroke, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                }
        }
    }

    private func dormantHint(_ module: TodayHomeModule) -> String {
        switch module {
        case .weeklyRecap: return "Shows up once there's a week worth comparing"
        case .focus: return "Shows up after \(Self.focusMinimumSessions) analyzed sessions"
        default: return "Nothing to show right now"
        }
    }

    // MARK: - Hidden Tray

    /// Where hidden blocks wait, and a drop target — so hiding a block is
    /// either its ⊖ or a drag down here.
    private var hiddenTray: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hidden")
                .eyebrowStyle()
                .frame(maxWidth: .infinity, alignment: .leading)

            if hiddenModules.isEmpty {
                Text("Nothing hidden — every block is on Today.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 14)
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(hiddenModules) { module in
                        trayChip(module)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.black.opacity(0.16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            trayTargeted ? AppColors.primary : AppColors.cardStroke,
                            style: StrokeStyle(lineWidth: trayTargeted ? 2 : 1, dash: [5, 4])
                        )
                }
        }
        .dropDestination(for: String.self) { items, _ in
            guard let dragged = items.compactMap(TodayHomeModule.init(rawValue:)).first,
                  !dragged.isPinned else { return false }
            Haptics.selection()
            setModuleVisible(dragged, false)
            return true
        } isTargeted: { targeted in
            withAnimation(AppMotion.slide) { trayTargeted = targeted }
        }
    }

    private func trayChip(_ module: TodayHomeModule) -> some View {
        Button {
            Haptics.selection()
            setModuleVisible(module, true)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: module.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                    }

                Text(module.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 0)

                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(AppColors.primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppColors.cardStroke, lineWidth: 0.5)
                    }
            }
        }
        .buttonStyle(GlassPressStyle())
        .draggable(module.rawValue)
        .accessibilityLabel("Add \(module.title) to Today. \(module.subtitle)")
    }

    private var resetLayoutButton: some View {
        Button {
            Haptics.light()
            withAnimation(AppMotion.slide) {
                // Empty raw is the "never customized" marker TodayHomeLayout
                // resolves back to the factory default.
                userSettings.first?.todayHomeLayoutRaw = []
                try? modelContext.save()
            }
        } label: {
            Text("Reset to default")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
        }
        .buttonStyle(GlassPressStyle())
    }

    // MARK: - Layout Mutations

    private var hiddenModules: [TodayHomeModule] {
        TodayHomeModule.allCases.filter { !homeModules.contains($0) && !$0.isPinned }
    }

    /// The dragged block takes the target's slot, whether it came from
    /// elsewhere in the stack or from the tray.
    private func insertModule(_ dragged: TodayHomeModule, before target: TodayHomeModule) {
        guard dragged != target else { return }
        var list = homeModules
        list.removeAll { $0 == dragged }
        let index = list.firstIndex(of: target) ?? list.count
        list.insert(dragged, at: index)
        Haptics.selection()
        withAnimation(AppMotion.slide) {
            dropTarget = nil
            writeLayout(list)
        }
    }

    private func shiftModule(_ module: TodayHomeModule, by delta: Int) {
        var list = homeModules
        guard let index = list.firstIndex(of: module) else { return }
        let destination = index + delta
        guard list.indices.contains(destination) else { return }
        list.swapAt(index, destination)
        withAnimation(AppMotion.slide) { writeLayout(list) }
    }

    private func setModuleVisible(_ module: TodayHomeModule, _ on: Bool) {
        var list = homeModules
        if on {
            guard !list.contains(module) else { return }
            // Put a re-added block back where it belongs rather than at the end.
            if module == .weeklyRecap, let rings = list.firstIndex(of: .rings) {
                list.insert(module, at: rings + 1)
            } else if module == .focus, let session = list.firstIndex(of: .session) {
                list.insert(module, at: session)
            } else {
                list.append(module)
            }
        } else {
            guard !module.isPinned else { return }
            list.removeAll { $0 == module }
        }
        withAnimation(AppMotion.slide) { writeLayout(list) }
    }

    private func writeLayout(_ list: [TodayHomeModule]) {
        guard let settings = userSettings.first else { return }
        settings.todayHomeLayoutRaw = TodayHomeLayout.encode(list)
        try? modelContext.save()
    }

    // MARK: - Home Modules

    @ViewBuilder
    private func homeModuleView(_ module: TodayHomeModule) -> some View {
        switch module {
        case .rings:
            ringStatsSection
                .tourAnchor(.todayStats)
        case .weeklyRecap:
            weeklyRecapSection
        case .focus:
            // What to do about the rings. Sits above the prompt so the focus
            // is an instruction for the take, not a post-session report.
            focusSection
        case .session:
            sessionModule
                .tourAnchor(.todayPrompt)
        case .tools:
            prepToolsSection
                .tourAnchor(.todayTools)
        case .learn:
            learnShortcutCard
        }
    }

    /// The card owns the whole brief now — topic, length, words, and Start —
    /// so the module is just the header plus that one object. The header takes
    /// `promptSectionTitle` because a story day is not a prompt day.
    private var sessionModule: some View {
        VStack(alignment: .leading, spacing: 14) {
            GlassSectionHeader(promptSectionTitle, icon: "mic.fill")

            interactivePromptSection
        }
    }

    // MARK: - Weekly Recap

    @ViewBuilder
    private var weeklyRecapSection: some View {
        if let progress = viewModel.weeklyProgress, progress.hasRecap, shouldShowWeeklyRecap {
            WeeklyRecapCard(progress: progress) {
                userSettings.first?.lastWeeklySummaryDate = Date()
                try? modelContext.save()
            }
        }
    }

    /// Visible until dismissed; a dismissal stamps lastWeeklySummaryDate, which
    /// hides the card until the next calendar week starts.
    private var shouldShowWeeklyRecap: Bool {
        guard let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start else {
            return false
        }
        guard let dismissed = userSettings.first?.lastWeeklySummaryDate else { return true }
        return dismissed < weekStart
    }

    // MARK: - Focus Section

    /// Hidden until there is something to average. One analyzed session is a
    /// mood, not a pattern — below the threshold the prompt card is the honest
    /// primary action.
    private static let focusMinimumSessions = 2

    /// The instruction the user reads *before* they speak.
    ///
    /// This is the placement that makes the focus a training instruction rather
    /// than a report — the session screen can only ever tell you what to work
    /// on after the take you could have applied it to.
    @ViewBuilder
    private var focusSection: some View {
        if let plan = viewModel.coachPlan, plan.sessionCount >= Self.focusMinimumSessions {
            CoachFocusCard(
                plan: plan,
                onPractice: self.handleFocusRoute,
                onPracticeAgain: {
                    onStartRecording(viewModel.todaysPrompt, viewModel.selectedDuration)
                }
            )
        }
    }

    private func handleFocusRoute(_ route: CoachPracticeRoute) {
        switch route {
        case .drill(let raw):
            focusDrill = DrillMode(rawValue: raw)
        case .warmUp:
            showingFocusWarmUp = true
        case .readAloud:
            showingFocusReadAloud = true
        }
    }

    /// Today's words, built here because the handlers need the `modelContext`,
    /// then handed down as a value so both cards render the identical footer
    /// without four more init parameters each.
    private var sessionWords: SessionWordsRow {
        SessionWordsRow(
            workout: viewModel.vocabChallenge,
            bankWords: userSettings.first?.vocabWords ?? [],
            onSkip: { viewModel.skipVocabWord($0) },
            onAddToBank: { addSpotlightWordToBank($0) }
        )
    }

    private func addSpotlightWordToBank(_ word: VocabChallengeWord) {
        guard let settings = userSettings.first else { return }
        guard WordSafety.allows(word.text) else { return }
        settings.addVocabWord(word.text)
        try? modelContext.save()
        Haptics.success()
    }

    /// Rebuilds the SwiftData prompt (catalog row or the shared insert) so
    /// ContentView can attach challenge chrome via the matching id.
    private func acceptFriendChallenge(_ challenge: SharedChallenge) {
        let payload = SharedPromptPayload(
            promptID: challenge.promptID,
            text: challenge.promptText,
            category: challenge.category,
            difficulty: challenge.difficulty,
            beatScore: challenge.beatScore,
            source: SharedPromptLink.shareSource
        )
        let prompt = SharedPromptResolver.resolve(payload, in: modelContext)
        onStartRecording(prompt, viewModel.selectedDuration)
    }

    // MARK: - First Run Surfaces

    /// The two things that wait for a score before they earn the user's
    /// attention: the deferred setup sheet (calibration, AI model, reminders)
    /// and the layout tour. Strictly sequential — the tour spotlights cut out
    /// of a dimmed layer, which a presented sheet would sit on top of.
    ///
    /// Both are gated on a recording existing, so a user who skipped the
    /// baseline meets them after their first real session instead.
    private func checkFirstRunSurfaces() async {
        guard let settings = userSettings.first else { return }
        let needsSetup = !settings.hasShownFirstRecordingSetup
        guard needsSetup || !settings.hasSeenAppTour else { return }

        let count = (try? modelContext.fetchCount(FetchDescriptor<Recording>())) ?? 0
        guard count >= 1 else { return }

        guard needsSetup else {
            startTourIfNeeded()
            return
        }
        showingFirstRecordingSetup = true
        settings.hasShownFirstRecordingSetup = true
        try? modelContext.save()
    }

    /// Called on setup-sheet dismissal and directly when that sheet has
    /// already been seen. Callers have established that a recording exists.
    private func startTourIfNeeded() {
        guard userSettings.first?.hasSeenAppTour == false else { return }
        tour?.begin()
    }

    // MARK: - Top Header

    private var topHeaderRow: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .textCase(.uppercase)
                    .tracking(0.8)
                Text(headline)
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                if let line = arrivalLine {
                    Text(line)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppColors.warning)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }

            Spacer()

            NavigationLink {
                StreakDetailView()
            } label: {
                StreakChip(streak: viewModel.userStats.currentStreak)
                    // The chip is the reward, so it is what moves: one spring
                    // pop on the day's first open, nothing on later ones.
                    .scaleEffect(arrived ? 1 : 0.6)
                    .opacity(arrived ? 1 : 0)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { Haptics.light() })
        }
        .padding(.top, 4)
        .overlay {
            if showArrivalConfetti {
                ConfettiView()
                    .frame(height: 400)
                    .allowsHitTesting(false)
            }
        }
    }

    /// What the streak is actually worth right now. Never claims a day the
    /// user has not earned — before today's session it names the stake.
    private var arrivalLine: String? {
        let streak = viewModel.userStats.currentStreak
        guard arrived, streak >= 1 else { return nil }
        return viewModel.practicedToday
            ? "Day \(streak) locked in"
            : "Day \(streak), one session keeps it"
    }

    /// Runs once per calendar day: pops the streak chip, fires a haptic, and
    /// adds confetti on every seventh day so the milestone still feels rare.
    private func playArrivalIfNeeded() {
        let today = Calendar.current.startOfDay(for: .now).ISO8601Format()
        guard lastArrivalDay != today else {
            arrived = true
            return
        }
        guard !viewModel.isLoading else { return }
        lastArrivalDay = today

        let streak = viewModel.userStats.currentStreak
        withAnimation(.spring(response: 0.5, dampingFraction: 0.55).delay(0.15)) {
            arrived = true
        }
        if streak >= 1 {
            Haptics.success()
        }
        if streak >= 7, streak % 7 == 0 {
            showArrivalConfetti = true
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Hello"
        }
    }

    private var headline: String {
        let name = userSettings.first?.userName.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? "Ready to practice?" : "\(greeting), \(name)"
    }

    // MARK: - Ring Stats Section

    private var ringStatsSection: some View {
        NavigationLink {
            ProgressChartsView()
        } label: {
            RingStatsView(
                sessions: viewModel.userStats.weeklySessionCount,
                sessionsGoal: viewModel.userStats.weeklyGoalSessions,
                score: Int(viewModel.userStats.averageScore),
                bestScore: viewModel.userStats.bestScore,
                improvement: viewModel.userStats.improvementRate
            )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { Haptics.medium() })
    }

    // MARK: - Start Footer

    /// The one hero action on Today, handed to whichever brief card renders so
    /// button and subject are the same object. Twin capsules and a segmented
    /// picker both failed here; read `docs/features/today-library.md`
    /// invariants 11–13 before changing it.
    private var sessionStartFooter: SessionStartFooter {
        SessionStartFooter(
            startHint: "Records a \(viewModel.selectedDuration.displayName) take on the topic above",
            freeHint: "Records a \(viewModel.selectedDuration.displayName) take with no topic",
            onStart: {
                Haptics.medium()
                if viewModel.storyPracticeEnabled, let story = viewModel.todaysStory {
                    onStartStoryPractice?(story, viewModel.selectedDuration)
                } else {
                    onStartRecording(viewModel.todaysPrompt, viewModel.selectedDuration)
                }
            },
            onFreeTalk: {
                Haptics.medium()
                onStartRecording(nil, viewModel.selectedDuration)
            }
        )
    }

    // MARK: - Interactive Prompt Section

    /// Story days practice a story, so the label above the card says which
    /// brief sits below — the card header alone didn't say whose take it was.
    private var promptSectionTitle: String {
        (viewModel.storyPracticeEnabled && viewModel.todaysStory != nil)
            ? "Today's story"
            : "Today's prompt"
    }

    @ViewBuilder
    private var interactivePromptSection: some View {
        if viewModel.storyPracticeEnabled, let story = viewModel.todaysStory {
            StoryPromptCard(
                story: story,
                selectedDuration: $viewModel.selectedDuration,
                words: sessionWords,
                footer: sessionStartFooter,
                onRefresh: { Task { await viewModel.refreshStory() } }
            )
        } else {
            InteractivePromptCard(
                prompt: viewModel.todaysPrompt,
                selectedDuration: $viewModel.selectedDuration,
                words: sessionWords,
                footer: sessionStartFooter,
                onRefresh: { Task { await viewModel.refreshPrompt() } }
            )
        }
    }

    // MARK: - Prep Tools

    /// Four doors, icon and name only. The tiles used to carry a two-line
    /// outcome apiece, which turned a 2x2 grid into a wall of small grey text;
    /// the one tool worth explaining is explained by the banner above it, and
    /// the rest introduce themselves on arrival. No inline Edit control here —
    /// this section is not what it edits, and Today's toolbar already owns it.
    private var prepToolsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionHeader("Prep tools", icon: "wrench.and.screwdriver.fill")

            if let recommended = recommendedPrepTool {
                recommendedToolBanner(recommended)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(PracticeToolKind.todayStripDefaults) { tool in
                    Button {
                        Haptics.light()
                        openPrepTool(tool)
                    } label: {
                        ToolTileLabel(icon: tool.icon, title: tool.shortTitle, tint: tool.color)
                    }
                    .buttonStyle(GlassPressStyle())
                }
            }
        }
    }

    /// Coach route wins when we have enough sessions; otherwise warm-up is the
    /// honest default before a cold take.
    private var recommendedPrepTool: PracticeToolKind? {
        if let plan = viewModel.coachPlan, plan.sessionCount >= Self.focusMinimumSessions {
            return PracticeToolKind.recommended(for: plan.focus.practiceRoute)
        }
        if !viewModel.practicedToday {
            return .warmUp
        }
        return nil
    }

    private func recommendedToolBanner(_ tool: PracticeToolKind) -> some View {
        Button {
            Haptics.medium()
            openPrepTool(tool)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: tool.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tool.color)
                    .frame(width: 36, height: 36)
                    .background {
                        Circle().fill(tool.color.opacity(0.18))
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Start with \(tool.shortTitle)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(tool.outcome)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(tool.color.opacity(0.08))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(tool.color.opacity(0.3), lineWidth: 0.5)
                    }
            }
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityLabel("Start with \(tool.title). \(tool.outcome)")
    }

    private func openPrepTool(_ tool: PracticeToolKind) {
        switch tool {
        case .warmUp: onShowWarmUps()
        case .drills: onShowDrills()
        case .calm: onShowConfidence()
        case .readAloud: onShowReadAloud()
        case .learn: onShowCurriculum()
        }
    }

    // MARK: - Learn Shortcut

    private var learnShortcutCard: some View {
        Button {
            Haptics.medium()
            onShowCurriculum()
        } label: {
            GlassCard(tint: AppColors.primary.opacity(0.08), padding: 16) {
                HStack(spacing: 14) {
                    Image(systemName: PracticeToolKind.learn.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.primary)
                        .frame(width: 40, height: 40)
                        .background {
                            Circle().fill(AppColors.primary.opacity(0.18))
                        }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(PracticeToolKind.learn.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(PracticeToolKind.learn.outcome)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityLabel("\(PracticeToolKind.learn.title). \(PracticeToolKind.learn.outcome)")
    }

}

// MARK: - Interactive Prompt Card

/// Today's topic: the brief and its action in one object. Header, prompt text,
/// words row, then the Start capsule as the footer — the button used to float
/// between this card and the tools strip, a third island that belonged to
/// neither neighbor.
///
/// Still not a control: no whole-card tap (the invisible gesture fought the
/// duration `Menu` for the same taps). The Start button is the only way to
/// begin.
///
/// Never line-limit the prompt: it clipped at four lines, which is the one
/// thing a prompt card must not do. The size comes from 14pt padding and 18pt
/// type instead.
struct InteractivePromptCard: View {
    let prompt: Prompt?
    @Binding var selectedDuration: RecordingDuration
    let words: SessionWordsRow
    let footer: SessionStartFooter
    let onRefresh: () -> Void

    private var redaction: RedactionReasons {
        prompt == nil ? .placeholder : []
    }

    var body: some View {
        GlassCard(padding: 14, elevated: true) {
            VStack(alignment: .leading, spacing: 10) {
                // Everything *about* the take on one line, so the space under
                // the text belongs to the words alone.
                HStack(spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: categoryIcon)
                            .font(.system(size: 10, weight: .semibold))
                        Text(prompt?.category ?? "Loading...")
                            .font(.system(size: 11, weight: .semibold))
                            .textCase(.uppercase)
                            .tracking(0.6)
                            .lineLimit(1)
                            // Shrinks before it truncates; "Current Events &
                            // Opinions" is the one that needs the headroom.
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(categoryColor)

                    Spacer(minLength: 4)

                    if let difficulty = prompt?.difficulty {
                        StatusPill.difficulty(difficulty)
                    }

                    DurationPill(selectedDuration: $selectedDuration)

                    // Reroll belongs beside the thing it rerolls; in a footer
                    // it cost a whole 44pt row. The negative gutter trims the
                    // layout box back to the header's height and edge, while
                    // the tap target itself stays 44pt.
                    SmallIconButton(icon: "arrow.clockwise", label: "Different prompt", action: onRefresh)
                        .padding(.trailing, -6)
                        .padding(.vertical, -6)
                }
                .redacted(reason: redaction)

                Text(prompt?.text ?? "Loading today's prompt...")
                    .font(.system(size: 18, weight: .semibold))
                    .lineSpacing(2)
                    .foregroundStyle(prompt == nil ? .secondary : .primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .redacted(reason: redaction)

                // Carries its own divider, so a day with no word workout ends
                // the brief at the prompt text.
                words
                    .redacted(reason: redaction)

                // The action lives with the brief it starts; loading state
                // never redacts it into looking broken.
                footer
                    .padding(.top, 4)
            }
            .accessibilityElement(children: .contain)
        }
    }

    private var categoryColor: Color {
        guard let category = prompt?.category else { return AppColors.accent }
        return PromptCategory(rawValue: category)?.color ?? AppColors.accent
    }

    private var categoryIcon: String {
        guard let category = prompt?.category else { return "questionmark.circle" }
        return PromptCategory(rawValue: category)?.iconName ?? "text.bubble"
    }
}

// MARK: - Session Start Footer

/// The page's one hero action: a filled capsule and one quiet escape hatch.
/// Lives inside whichever brief card renders so the button can't drift away
/// from the thing it starts.
///
/// No prompt is not a mode you set and then confirm — it is a different way to
/// start, so it is a second start: quiet, unmistakably subordinate, one tap,
/// always visible. Give it a filled or stroked shape and it becomes the twin
/// capsule again; contrast only.
struct SessionStartFooter: View {
    var showFreeTalk = true
    let startHint: String
    let freeHint: String
    let onStart: () -> Void
    let onFreeTalk: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Button {
                onStart()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Start Speaking")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.08))
                .background {
                    Capsule()
                        .fill(Color.white.opacity(0.94))
                        .shadow(color: .black.opacity(0.3), radius: 12, y: 5)
                }
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint(startHint)

            if showFreeTalk {
                Button {
                    onFreeTalk()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Talk without a prompt")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    // 0.8 white on glass reads as a control only because it
                    // sits beside the capsule; alone it would be a caption.
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(freeHint)
            }
        }
    }
}

// MARK: - Small Icon Button (for card actions)

struct SmallIconButton: View {
    let icon: String
    /// VoiceOver / Voice Control name — required so icon-only control is not silent.
    var label: String
    let action: () -> Void

    var body: some View {
        Button(label, systemImage: icon) {
            Haptics.light()
            action()
        }
        .labelStyle(.iconOnly)
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
        .frame(width: 32, height: 32)
        .background {
            Circle()
                .fill(.ultraThinMaterial)
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .buttonStyle(GlassPressStyle())
    }
}

// MARK: - Duration Pill Selector

struct DurationPill: View {
    @Binding var selectedDuration: RecordingDuration

    var body: some View {
        Menu {
            ForEach(RecordingDuration.allCases) { duration in
                Button {
                    withAnimation(.spring(duration: 0.3)) {
                        selectedDuration = duration
                    }
                } label: {
                    HStack {
                        Text(duration.displayName)
                        if duration == selectedDuration {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.caption2)
                Text(selectedDuration.displayName)
                    .font(.caption.weight(.medium))
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
            }
        }
    }
}

#Preview {
    NavigationStack {
        TodayView(
            onStartRecording: { _, _ in },
            onShowReadAloud: {},
            onShowWarmUps: {},
            onShowDrills: {},
            onShowConfidence: {},
            onShowCurriculum: {},
            onStartStoryPractice: { _, _ in }
        )
    }
    .modelContainer(for: [Recording.self, Prompt.self, UserGoal.self, UserSettings.self, Achievement.self], inMemory: true)
}

// MARK: - Wiggle

private extension TodayHomeModule {
    /// Stable per-block offset so the stack doesn't wobble in lockstep — the
    /// Home screen's icons are each a little out of phase with their neighbours.
    var wigglePhase: Double {
        Double(TodayHomeModule.allCases.firstIndex(of: self) ?? 0) * 0.035
    }
}

private extension View {
    /// Home-screen jiggle. Off under Reduce Motion, where a permanently moving
    /// page is exactly the thing the setting exists to stop.
    func wiggle(active: Bool, phase: Double) -> some View {
        modifier(WiggleModifier(active: active, phase: phase))
    }
}

/// Rocks between -0.4° and +0.4°. The rest angle has to be one end of the
/// swing rather than zero, or `autoreverses` tilts the block one way only and
/// the page looks like it is leaning instead of wiggling.
private struct WiggleModifier: ViewModifier {
    let active: Bool
    let phase: Double

    @State private var swung = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(active ? (swung ? 0.4 : -0.4) : 0))
            .animation(
                active
                    ? .easeInOut(duration: 0.17).repeatForever(autoreverses: true).delay(phase)
                    : nil,
                value: swung
            )
            .onAppear { swung = active }
            .onChange(of: active) { _, isActive in swung = isActive }
    }
}
