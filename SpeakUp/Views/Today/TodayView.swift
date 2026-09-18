import SwiftUI
import SwiftData

/// Today tab. Modules via `TodayHomeModule`; widget reloads fingerprint-gated in `TodayViewModel`.
struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LLMService.self) private var llmService
    @State private var viewModel = TodayViewModel()

    @Query private var userSettings: [UserSettings]
    @Environment(\.appTour) private var tour
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingFirstRecordingSetup = false

    // Arrival moment - fires once per calendar day, on the first open.
    @AppStorage("lastArrivalDay") private var lastArrivalDay = ""
    @State private var arrived = false
    @State private var challengeStore = SharedChallengeStore.shared
    @State private var coachMoments = CoachMomentService.shared
    @State private var routine = PracticeRoutineService.shared
    @State private var showingRoutineSettings = false

    @State private var focusDrill: DrillMode?
    @State private var showingFocusWarmUp = false
    @State private var showingFocusReadAloud = false
    @State private var isEditingLayout = false
    @State private var dropTarget: TodayHomeModule?
    @State private var trayTargeted = false

    /// True only when Today is visible and onboarding is not covering the app.
    /// First-run setup must wait for this edge because Today can mount before
    /// onboarding creates the baseline recording.
    var isActiveTab: Bool
    var onStartRecording: (Prompt?, RecordingDuration) -> Void
    var onShowReadAloud: () -> Void
    var onShowWarmUps: () -> Void
    var onShowDrills: () -> Void
    var onShowConfidence: () -> Void
    var onShowCurriculum: () -> Void
    var onStartStoryPractice: ((Story, RecordingDuration) -> Void)?

    private var homeModules: [TodayHomeModule] {
        userSettings.first?.todayHomeModules ?? TodayHomeModule.defaultVisible
    }

    var body: some View {
        PageScrollView {
            VStack(spacing: AppLayout.chapterSpacing) {

                // 1. Header - date + streak chip (customize lives at the bottom)
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

                if let moment = coachMoments.pendingToday {
                    CoachMomentCard(
                        moment: moment,
                        onAccept: { acceptCoachMoment(moment) },
                        onDismiss: { dismissCoachMoment(moment) }
                    )
                }

                ForEach(homeModules) { module in
                    editableModule(module)
                }

                if isEditingLayout {
                    hiddenTray.transition(.identity)
                    resetLayoutButton.transition(.identity)
                }

                if !isEditingLayout {
                    editHomepageButton
                }
            }
            .padding(.top, 8)
            .pageContentInsets()
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isEditingLayout {
                doneEditingBar
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            await viewModel.loadData()
            if isActiveTab {
                await checkFirstRunSurfaces()
            }
        }
        .onAppear {
            viewModel.configure(with: modelContext)
        }
        .task {
            playArrivalIfNeeded()
            if isActiveTab {
                await checkFirstRunSurfaces()
            }
            viewModel.warmVocabFreshWords(llmService: llmService)
        }
        .onChange(of: isActiveTab) { _, active in
            guard active else { return }
            Task { await checkFirstRunSurfaces() }
            // Also here, not only on the request: a handoff raised from another
            // tab sets the step and *then* switches, so the request is already
            // waiting by the time Today becomes active.
            startPendingRoutineStepIfNeeded()
        }
        .onChange(of: routine.pendingStep) { _, _ in
            startPendingRoutineStepIfNeeded()
        }
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
        .sheet(isPresented: $showingRoutineSettings) {
            NavigationStack {
                RoutineSettingsView()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
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

    @ViewBuilder
    private func moduleBody(_ module: TodayHomeModule) -> some View {
        if isEditingLayout, !moduleHasContent(module) {
            dormantModuleCard(module)
                .transition(.identity)
        } else {
            homeModuleView(module)
                .transition(.identity)
        }
    }

    @ViewBuilder
    private func editableModule(_ module: TodayHomeModule) -> some View {
        if isEditingLayout {
            moduleBody(module)
                .allowsHitTesting(false)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.white.opacity(0.001))
                }
                .overlay(alignment: .topLeading) {
                    if !module.isPinned {
                        removeBadge(module).offset(x: -16, y: -16)
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
                    withAnimation(AppMotion.settle) {
                        if targeted { dropTarget = module }
                        else if dropTarget == module { dropTarget = nil }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(module.title)
                .accessibilityActions {
                    Button("Move up") { shiftModule(module, by: -1) }
                    Button("Move down") { shiftModule(module, by: 1) }
                    if !module.isPinned {
                        Button("Hide") { setModuleVisible(module, false) }
                    }
                }
                .transition(.identity)
        } else {
            moduleBody(module)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.9).onEnded { _ in
                        Haptics.medium()
                        withAnimation(AppMotion.settle) { isEditingLayout = true }
                    }
                )
                .transition(.identity)
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
                .frame(width: AppLayout.minHitTarget, height: AppLayout.minHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hide \(module.title)")
    }

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
        case .routine:
            // A chain of one is the session module wearing a second hat.
            return routine.steps.count > 1
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
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AppColors.cardStroke, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
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

    private var hiddenTray: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hidden")
                .eyebrowStyle()
                .frame(maxWidth: .infinity, alignment: .leading)

            if hiddenModules.isEmpty {
                Text("Nothing hidden. Every block is on Today.")
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
            withAnimation(AppMotion.settle) { trayTargeted = targeted }
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
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
        }
        .buttonStyle(GlassPressStyle())
        .draggable(module.rawValue)
        .accessibilityLabel("Add \(module.title) to Today. \(module.subtitle)")
    }

    private var resetLayoutButton: some View {
        Button {
            Haptics.light()
            withAnimation(AppMotion.settle) {
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

    /// Drop resolution lives in `TodayHomeLayout.reorder` so it can be pinned
    /// by a test - dropping a block below another used to silently do nothing.
    private func insertModule(_ dragged: TodayHomeModule, before target: TodayHomeModule) {
        let list = TodayHomeLayout.reorder(homeModules, moving: dragged, onto: target)
        guard list != homeModules else { return }
        Haptics.selection()
        withAnimation(AppMotion.settle) {
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
        withAnimation(AppMotion.settle) { writeLayout(list) }
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
        withAnimation(AppMotion.settle) { writeLayout(list) }
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
        case .routine:
            routineSection
        case .focus:
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

    /// The routine block. Hidden at a chain of one, because a routine with
    /// nothing but the take in it is the session module said twice.
    @ViewBuilder
    private var routineSection: some View {
        let steps = routine.steps
        if steps.count > 1 {
            RoutineCard(
                steps: steps,
                completed: routine.progress.completed,
                onStart: startRoutineStep,
                onEdit: { showingRoutineSettings = true }
            )
        }
    }

    /// `.session` is handled here and nowhere else: the day's prompt and the
    /// duration pill live on this screen, so this is the only place that can
    /// start the take the routine means. Everything else bubbles to
    /// `ContentView`, which owns the tool sheets.
    private func startRoutineStep(_ step: RoutineStep) {
        if step == .session {
            onStartRecording(viewModel.todaysPrompt, viewModel.selectedDuration)
        } else {
            routine.start(step)
        }
    }

    /// Takes the `.session` request `ContentView` leaves standing for Today.
    private func startPendingRoutineStepIfNeeded() {
        guard routine.pendingStep == .session, isActiveTab else { return }
        routine.clearPendingStep()
        onStartRecording(viewModel.todaysPrompt, viewModel.selectedDuration)
    }

    /// The card owns the whole brief now - topic, length, words, and Start - 
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

    private var shouldShowWeeklyRecap: Bool {
        guard let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start else {
            return false
        }
        guard let dismissed = userSettings.first?.lastWeeklySummaryDate else { return true }
        return dismissed < weekStart
    }

    // MARK: - Focus Section

    private static let focusMinimumSessions = 2

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

    // MARK: - Coach notes

    private func acceptCoachMoment(_ moment: CoachMoment) {
        coachMoments.consume(moment, context: modelContext)
        performCoachMomentAction(moment.action)
    }

    private func dismissCoachMoment(_ moment: CoachMoment) {
        coachMoments.dismiss(moment, context: modelContext)
    }

    private func performCoachMomentAction(_ action: CoachMomentAction) {
        switch action {
        case .openConfidence:
            onShowConfidence()
        case .practiceAgain:
            onStartRecording(viewModel.todaysPrompt, viewModel.selectedDuration)
        case .close:
            break
        }
    }

    // MARK: - First Run Surfaces

    private func checkFirstRunSurfaces() async {
        guard let settings = userSettings.first else { return }
        let needsSetup = !settings.hasShownFirstRecordingSetup
        guard needsSetup || !settings.hasSeenAppTour else { return }

        let hasRecorded = ((try? modelContext.fetchCount(FetchDescriptor<Recording>())) ?? 0) >= 1

        // Two ways to land here without the sheet. A user who skipped the
        // baseline said they wanted to look around first, and the walkthrough is
        // the answer to the question they actually asked - waiting for a take
        // they may not make for days leaves them on a map-less home screen. And
        // a user who has already seen the sheet gets straight to the tour.
        // The sheet itself still waits for a score: every row on it is about a
        // number, and before the first take there is none.
        guard hasRecorded, needsSetup else {
            startTourIfNeeded()
            return
        }
        showingFirstRecordingSetup = true
        settings.hasShownFirstRecordingSetup = true
        try? modelContext.save()
    }

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
                        .font(.caption)
                        .foregroundStyle(
                            viewModel.practicedToday
                                ? AnyShapeStyle(AppColors.success)
                                : AnyShapeStyle(.secondary)
                        )
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }

            Spacer()

            NavigationLink {
                StreakDetailView()
            } label: {
                StreakChip(streak: viewModel.userStats.currentStreak)
                    .scaleEffect(arrived ? 1 : 0.6)
                    .opacity(arrived ? 1 : 0)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { Haptics.light() })
        }
        .padding(.top, 4)
    }

    /// What the streak is actually worth right now. Never claims a day the
    /// user has not earned - before today's session it names the stake.
    private var arrivalLine: String? {
        let streak = viewModel.userStats.currentStreak
        guard arrived, streak >= 1 else { return nil }
        return viewModel.practicedToday
            ? "Day \(streak) · nice work"
            : "Day \(streak) · ready when you are"
    }

    private var editHomepageButton: some View {
        GlassButton(
            title: "Edit homepage",
            icon: "slider.horizontal.3",
            style: .secondary,
            size: .medium,
            fullWidth: true
        ) {
            Haptics.light()
            withAnimation(AppMotion.settle) { isEditingLayout = true }
        }
        .accessibilityLabel("Customize Today")
        .padding(.top, 4)
    }

    private var doneEditingBar: some View {
        GlassButton(
            title: "Done",
            icon: "checkmark",
            style: .primary,
            size: .medium,
            fullWidth: true
        ) {
            finishEditingLayout()
        }
        .accessibilityLabel("Finish customizing Today")
        .padding(.horizontal, AppLayout.pageHorizontal)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func finishEditingLayout() {
        Haptics.light()
        withAnimation(AppMotion.settle) { isEditingLayout = false }
    }

    private func playArrivalIfNeeded() {
        let today = Calendar.current.startOfDay(for: .now).ISO8601Format()
        guard lastArrivalDay != today else {
            arrived = true
            return
        }
        guard !viewModel.isLoading else { return }
        lastArrivalDay = today

        let streak = viewModel.userStats.currentStreak
        if reduceMotion {
            arrived = true
        } else {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55).delay(0.15)) {
                arrived = true
            }
        }
        if streak >= 1 {
            Haptics.success()
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
        if isAwaitingStartingLine {
            return name.isEmpty ? "Set your starting line" : "\(name), set your starting line"
        }
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

    /// A user who skipped the guided baseline still needs a named way back
    /// into activation. Reframe the existing hero instead of adding a second
    /// competing card or sending them into prompt-less free practice.
    private var isAwaitingStartingLine: Bool {
        !viewModel.isLoading && viewModel.userStats.totalRecordings == 0
    }

    /// The one hero action on Today, handed to whichever brief card renders so
    /// button and subject are the same object. Twin capsules and a segmented
    /// picker both failed here; read `docs/features/today-library.md`
    /// invariants 11-13 before changing it.
    private var sessionStartFooter: SessionStartFooter {
        SessionStartFooter(
            startTitle: isAwaitingStartingLine ? "Set My Starting Line" : "Start Speaking",
            showFreeTalk: !isAwaitingStartingLine,
            startHint: isAwaitingStartingLine
                ? "Records your first \(viewModel.selectedDuration.displayName) take on the topic above"
                : "Records a \(viewModel.selectedDuration.displayName) take on the topic above",
            freeHint: "Records a \(viewModel.selectedDuration.displayName) take with no topic",
            onStart: {
                if viewModel.storyPracticeEnabled, let story = viewModel.todaysStory {
                    onStartStoryPractice?(story, viewModel.selectedDuration)
                } else {
                    onStartRecording(viewModel.todaysPrompt, viewModel.selectedDuration)
                }
            },
            onFreeTalk: {
                onStartRecording(nil, viewModel.selectedDuration)
            }
        )
    }

    // MARK: - Interactive Prompt Section

    private var promptSectionTitle: String {
        if isAwaitingStartingLine {
            return "Your first prompt"
        }
        return (viewModel.storyPracticeEnabled && viewModel.todaysStory != nil)
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
                    .accessibilityLabel("\(tool.title). \(tool.outcome)")
                }
            }
        }
    }

    /// A suggestion with the reason attached.
    ///
    /// The banner is personalised - it follows your coach plan, or falls back
    /// to a warm-up on a day you have not practised - but it never said so,
    /// so it read as a stray duplicate of the grid directly beneath it. The
    /// reason is what makes it a recommendation rather than a fifth tile.
    private struct PrepSuggestion {
        let tool: PracticeToolKind
        let reason: String
    }

    private var recommendedPrepTool: PrepSuggestion? {
        if let plan = viewModel.coachPlan,
           plan.sessionCount >= Self.focusMinimumSessions,
           let tool = PracticeToolKind.recommended(for: plan.focus.practiceRoute) {
            return PrepSuggestion(
                tool: tool,
                reason: "Your last \(plan.sessionCount) takes point at \(plan.focus.title.lowercased())"
            )
        }
        if !viewModel.practicedToday {
            return PrepSuggestion(tool: .warmUp, reason: "You haven't practised yet today")
        }
        return nil
    }

    private func recommendedToolBanner(_ suggestion: PrepSuggestion) -> some View {
        let tool = suggestion.tool

        return Button {
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
                    Text(suggestion.reason)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

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
            .glassEffect(.regular.tint(tool.color.opacity(0.10)).interactive(), in: .rect(cornerRadius: 14))
            // Same plate as the `ToolTileLabel` grid directly below it - same
            // radius, same shadow. Without this the banner sat flat while the
            // tiles it introduces floated.
            .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityLabel(
            "Suggested: start with \(tool.title). \(suggestion.reason). \(tool.outcome)"
        )
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


#Preview {
    NavigationStack {
        TodayView(
            isActiveTab: true,
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
    var wigglePhase: Double {
        Double(TodayHomeModule.allCases.firstIndex(of: self) ?? 0) * 0.09
    }
}

private extension View {
    /// Home-screen jiggle. Off under Reduce Motion, where a permanently moving
    /// page is exactly the thing the setting exists to stop.
    func wiggle(active: Bool, phase: Double) -> some View {
        modifier(WiggleModifier(active: active, phase: phase))
    }
}

/// Rocks ±0.3° on a 0.9s period. Driven by `TimelineView` so a drop or
/// re-render cannot restart the swing - the old `@State` + `repeatForever`
/// version jumped back to the start of the ease every time a block moved,
private struct WiggleModifier: ViewModifier {
    let active: Bool
    let phase: Double

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !active)) { context in
            let period = 0.9
            let t = context.date.timeIntervalSinceReferenceDate + phase
            let angle = active ? 0.3 * sin(t * (2 * .pi / period)) : 0
            content.rotationEffect(.degrees(angle))
        }
    }
}
