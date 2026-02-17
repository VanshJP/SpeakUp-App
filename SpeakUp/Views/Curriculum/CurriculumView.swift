import SwiftUI
import SwiftData

struct CurriculumView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = CurriculumViewModel()

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
                .padding()
            }
        }
        .navigationTitle("Learning Path")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Week \(phase.week)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.teal)

                    Text(phase.title)
                        .font(.title3.weight(.bold))
                }

                Spacer()

                let completedInPhase = phase.lessons.filter { viewModel.isLessonCompleted($0.id) }.count
                Text("\(completedInPhase)/\(phase.lessons.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(phase.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(phase.lessons) { lesson in
                NavigationLink {
                    LessonDetailView(lesson: lesson, viewModel: viewModel)
                } label: {
                    GlassCard(padding: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: viewModel.isLessonCompleted(lesson.id) ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(viewModel.isLessonCompleted(lesson.id) ? .green : .secondary)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(lesson.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)

                                Text(lesson.objective)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
