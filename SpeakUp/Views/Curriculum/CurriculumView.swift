import SwiftUI
import SwiftData

struct CurriculumView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = CurriculumViewModel()
    @State private var showingAwards = false

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 20) {
                    // Overall progress
                    progressHeader

                    // Phase list
                    ForEach(viewModel.phases) { phase in
                        phaseSection(phase)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Learning Path")
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.light()
                    showingAwards = true
                } label: {
                    Image(systemName: "trophy.fill")
                        .foregroundStyle(.yellow)
                }
            }
        }
        .sheet(isPresented: $showingAwards) {
            NavigationStack {
                AchievementGalleryView()
                    .appBackground(.subtle)
            }
        }
        .onAppear {
            viewModel.loadProgress(context: modelContext)
        }
    }

    private var progressHeader: some View {
        FeaturedGlassCard(gradientColors: [.teal.opacity(0.15), .cyan.opacity(0.08)]) {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your Progress")
                            .font(.headline)

                        Text("\(viewModel.completedLessonsCount) of \(viewModel.totalLessonsCount) lessons completed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Progress ring
                    ZStack {
                        Circle()
                            .stroke(.gray.opacity(0.2), lineWidth: 6)
                        Circle()
                            .trim(from: 0, to: viewModel.overallProgress)
                            .stroke(.teal, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))

                        Text("\(Int(viewModel.overallProgress * 100))%")
                            .font(.caption.weight(.bold))
                    }
                    .frame(width: 50, height: 50)
                }

                ProgressView(value: viewModel.overallProgress)
                    .tint(.teal)
            }
        }
    }

    private func phaseSection(_ phase: CurriculumPhase) -> some View {
        let completedInPhase = phase.lessons.filter { viewModel.isLessonCompleted($0.id) }.count
        let isPreviousPhaseComplete = isPreviousPhaseCompleted(before: phase)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Week \(phase.week)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.teal)

                    HStack(spacing: 8) {
                        Text(phase.title)
                            .font(.title3.weight(.bold))

                        if !isPreviousPhaseComplete && phase.week > 1 {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                Text("\(completedInPhase)/\(phase.lessons.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(phase.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(phase.lessons) { lesson in
                let isAccessible = viewModel.isLessonAccessible(lesson, in: phase)

                if isAccessible {
                    NavigationLink {
                        LessonDetailView(lesson: lesson, viewModel: viewModel)
                    } label: {
                        lessonCard(lesson, isLocked: false)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        Haptics.warning()
                    } label: {
                        lessonCard(lesson, isLocked: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func lessonCard(_ lesson: CurriculumLesson, isLocked: Bool) -> some View {
        let isCompleted = viewModel.isLessonCompleted(lesson.id)
        let isCurrent = viewModel.currentLesson?.id == lesson.id && !isCompleted && !isLocked

        return GlassCard(padding: 16, accentBorder: isCurrent ? AppColors.primary : nil) {
            HStack(spacing: 14) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : (isLocked ? "lock.fill" : "circle"))
                    .font(.title2)
                    .foregroundStyle(isCompleted ? .green : .secondary)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(lesson.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(isLocked ? .secondary : .primary)

                        if isCurrent {
                            Text("Continue")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(AppColors.primary))
                        }
                    }

                    Text(lesson.objective)
                        .font(.subheadline)
                        .foregroundStyle(isLocked ? .tertiary : .secondary)
                        .lineLimit(2)

                    Text("\(lesson.activities.count) activities")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Image(systemName: isLocked ? "lock.fill" : "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(minHeight: 60)
        }
        .opacity(isLocked ? 0.6 : 1.0)
    }

    // MARK: - Helpers

    private func isPreviousPhaseCompleted(before phase: CurriculumPhase) -> Bool {
        guard let index = viewModel.phases.firstIndex(where: { $0.id == phase.id }),
              index > 0 else { return true }
        let previousPhase = viewModel.phases[index - 1]
        return previousPhase.lessons.allSatisfy { viewModel.isLessonCompleted($0.id) }
    }
}
