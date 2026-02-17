import Foundation

struct DefaultCurriculum {
    static let phases: [CurriculumPhase] = [
        CurriculumPhase(
            id: "week1",
            week: 1,
            title: "Awareness",
            description: "Discover your speaking patterns and set your baseline.",
            lessons: [
                CurriculumLesson(
                    id: "w1_l1",
                    title: "Your Baseline Recording",
                    objective: "Record your first session to establish a starting point.",
                    activities: [
                        CurriculumActivity(id: "w1_l1_a1", type: .lesson, title: "Why baselines matter", description: "Your first recording becomes your comparison point. Don't try to be perfect — just be natural."),
                        CurriculumActivity(id: "w1_l1_a2", type: .practice, title: "Record a 60-second session", description: "Pick any prompt and speak for 60 seconds."),
                    ]
                ),
                CurriculumLesson(
                    id: "w1_l2",
                    title: "Know Your Fillers",
                    objective: "Identify your most common filler words.",
                    activities: [
                        CurriculumActivity(id: "w1_l2_a1", type: .lesson, title: "What are filler words?", description: "Words like 'um', 'uh', 'like', and 'you know' are natural speech patterns. Awareness is the first step."),
                        CurriculumActivity(id: "w1_l2_a2", type: .practice, title: "Record and review fillers", description: "Record a session and review which fillers you use most."),
                    ]
                ),
                CurriculumLesson(
                    id: "w1_l3",
                    title: "Understanding Pace",
                    objective: "Learn about speaking pace and where yours falls.",
                    activities: [
                        CurriculumActivity(id: "w1_l3_a1", type: .lesson, title: "The ideal pace range", description: "130-170 words per minute is considered the optimal range for clear communication."),
                        CurriculumActivity(id: "w1_l3_a2", type: .practice, title: "Record focusing on pace", description: "Record a session and pay attention to your WPM in the analysis."),
                    ]
                ),
                CurriculumLesson(
                    id: "w1_l4",
                    title: "Reading Your Score",
                    objective: "Understand what each score component means.",
                    activities: [
                        CurriculumActivity(id: "w1_l4_a1", type: .lesson, title: "Score breakdown", description: "Your overall score combines clarity, pace, filler usage, and pause quality. Each tells you something different."),
                        CurriculumActivity(id: "w1_l4_a2", type: .review, title: "Review your sessions", description: "Look at your recordings so far and identify your strongest and weakest areas."),
                    ]
                ),
            ]
        ),
        CurriculumPhase(
            id: "week2",
            week: 2,
            title: "Fundamentals",
            description: "Build core skills with targeted exercises.",
            lessons: [
                CurriculumLesson(
                    id: "w2_l1",
                    title: "Breathing for Speaking",
                    objective: "Learn breathing techniques that support clear speech.",
                    activities: [
                        CurriculumActivity(id: "w2_l1_a1", type: .exercise, title: "Box breathing exercise", description: "Complete the box breathing warm-up to calm your nerves.", exerciseId: "box_breathing"),
                        CurriculumActivity(id: "w2_l1_a2", type: .practice, title: "Record after breathing", description: "Do a recording immediately after the breathing exercise and notice the difference."),
                    ]
                ),
                CurriculumLesson(
                    id: "w2_l2",
                    title: "Filler Elimination",
                    objective: "Practice speaking without filler words.",
                    activities: [
                        CurriculumActivity(id: "w2_l2_a1", type: .drill, title: "Filler elimination drill", description: "Complete a 15-second filler elimination drill.", drillMode: "fillerElimination"),
                        CurriculumActivity(id: "w2_l2_a2", type: .practice, title: "30-second clean speech", description: "Record 30 seconds focusing entirely on avoiding fillers."),
                    ]
                ),
                CurriculumLesson(
                    id: "w2_l3",
                    title: "Pace Control",
                    objective: "Practice maintaining a steady, comfortable pace.",
                    activities: [
                        CurriculumActivity(id: "w2_l3_a1", type: .drill, title: "Pace control drill", description: "Complete a 60-second pace control drill.", drillMode: "paceControl"),
                        CurriculumActivity(id: "w2_l3_a2", type: .practice, title: "Controlled pace recording", description: "Record a full session focusing on maintaining 130-170 WPM."),
                    ]
                ),
                CurriculumLesson(
                    id: "w2_l4",
                    title: "Warm-Up Routine",
                    objective: "Establish a pre-speaking warm-up habit.",
                    activities: [
                        CurriculumActivity(id: "w2_l4_a1", type: .exercise, title: "Tongue twister warm-up", description: "Complete a tongue twister exercise to warm up your articulation.", exerciseId: "she_sells"),
                        CurriculumActivity(id: "w2_l4_a2", type: .exercise, title: "Vocal warm-up", description: "Complete the humming warm-up exercise.", exerciseId: "humming"),
                    ]
                ),
            ]
        ),
        CurriculumPhase(
            id: "week3",
            week: 3,
            title: "Structure",
            description: "Organize your thoughts with frameworks and deliberate pausing.",
            lessons: [
                CurriculumLesson(
                    id: "w3_l1",
                    title: "The PREP Framework",
                    objective: "Learn to structure responses using Point-Reason-Example-Point.",
                    activities: [
                        CurriculumActivity(id: "w3_l1_a1", type: .lesson, title: "PREP explained", description: "PREP stands for Point, Reason, Example, Point. It's perfect for answering questions clearly."),
                        CurriculumActivity(id: "w3_l1_a2", type: .practice, title: "Practice with PREP", description: "Record a 60-second response using the PREP framework overlay."),
                    ]
                ),
                CurriculumLesson(
                    id: "w3_l2",
                    title: "The STAR Framework",
                    objective: "Practice the Situation-Task-Action-Result format.",
                    activities: [
                        CurriculumActivity(id: "w3_l2_a1", type: .lesson, title: "STAR explained", description: "STAR is ideal for telling stories: set the Situation, describe the Task, explain your Action, share the Result."),
                        CurriculumActivity(id: "w3_l2_a2", type: .practice, title: "Practice with STAR", description: "Record a response to a personal experience prompt using STAR."),
                    ]
                ),
                CurriculumLesson(
                    id: "w3_l3",
                    title: "The Power of Pauses",
                    objective: "Learn to use deliberate pauses for emphasis and clarity.",
                    activities: [
                        CurriculumActivity(id: "w3_l3_a1", type: .drill, title: "Pause practice drill", description: "Complete the pause practice drill.", drillMode: "pausePractice"),
                        CurriculumActivity(id: "w3_l3_a2", type: .practice, title: "Record with pauses", description: "Record a session and deliberately pause between your main points."),
                    ]
                ),
                CurriculumLesson(
                    id: "w3_l4",
                    title: "Sentence Organization",
                    objective: "Practice completing thoughts before starting new ones.",
                    activities: [
                        CurriculumActivity(id: "w3_l4_a1", type: .lesson, title: "Complete your sentences", description: "A common speech habit is starting a new thought before finishing the current one. Focus on completing each idea."),
                        CurriculumActivity(id: "w3_l4_a2", type: .practice, title: "Organized speech practice", description: "Record a 90-second session focusing on completing each sentence before moving to the next."),
                    ]
                ),
            ]
        ),
        CurriculumPhase(
            id: "week4",
            week: 4,
            title: "Confidence",
            description: "Push your comfort zone and celebrate your growth.",
            lessons: [
                CurriculumLesson(
                    id: "w4_l1",
                    title: "Managing Nerves",
                    objective: "Learn techniques to manage speaking anxiety.",
                    activities: [
                        CurriculumActivity(id: "w4_l1_a1", type: .exercise, title: "Grounding exercise", description: "Complete the 5-4-3-2-1 grounding exercise.", exerciseId: "grounding_54321"),
                        CurriculumActivity(id: "w4_l1_a2", type: .exercise, title: "Power statements", description: "Read through the power affirmation statements.", exerciseId: "power_statements"),
                    ]
                ),
                CurriculumLesson(
                    id: "w4_l2",
                    title: "Impromptu Speaking",
                    objective: "Get comfortable speaking without preparation.",
                    activities: [
                        CurriculumActivity(id: "w4_l2_a1", type: .drill, title: "Impromptu sprint", description: "Complete an impromptu sprint drill — no prep time!", drillMode: "impromptuSprint"),
                        CurriculumActivity(id: "w4_l2_a2", type: .practice, title: "Random prompt challenge", description: "Spin the prompt wheel and start recording immediately."),
                    ]
                ),
                CurriculumLesson(
                    id: "w4_l3",
                    title: "Longer Sessions",
                    objective: "Build stamina with longer speaking sessions.",
                    activities: [
                        CurriculumActivity(id: "w4_l3_a1", type: .practice, title: "3-minute session", description: "Record a full 3-minute session to build your speaking endurance."),
                        CurriculumActivity(id: "w4_l3_a2", type: .review, title: "Review your growth", description: "Compare your latest recording with your very first one."),
                    ]
                ),
                CurriculumLesson(
                    id: "w4_l4",
                    title: "Celebrate Your Progress",
                    objective: "Review how far you've come and set future goals.",
                    activities: [
                        CurriculumActivity(id: "w4_l4_a1", type: .review, title: "Before and after", description: "Listen to your first and latest recordings back-to-back."),
                        CurriculumActivity(id: "w4_l4_a2", type: .lesson, title: "What's next?", description: "You've completed the curriculum! Keep practicing daily, explore new prompts, and challenge yourself with longer sessions."),
                    ]
                ),
            ]
        ),
    ]
}
