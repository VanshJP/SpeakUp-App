import Foundation

struct DefaultConfidenceExercises {
    static let all: [ConfidenceExercise] = [
        // Calming
        ConfidenceExercise(
            id: "grounding_54321",
            category: .calming,
            title: "5-4-3-2-1 Grounding",
            description: "Use your senses to ground yourself in the present moment.",
            steps: [
                "Notice 5 things you can see around you",
                "Touch 4 different textures near you",
                "Listen for 3 distinct sounds",
                "Identify 2 things you can smell",
                "Notice 1 thing you can taste"
            ],
            durationMinutes: 3
        ),
        ConfidenceExercise(
            id: "progressive_muscle",
            category: .calming,
            title: "Progressive Muscle Relaxation",
            description: "Systematically tense and release muscle groups to reduce physical tension.",
            steps: [
                "Clench your fists tight for 5 seconds, then release",
                "Shrug your shoulders to your ears for 5 seconds, then drop",
                "Scrunch your face tight for 5 seconds, then relax",
                "Tighten your stomach muscles for 5 seconds, then release",
                "Curl your toes for 5 seconds, then relax",
                "Take three deep breaths and notice how relaxed you feel"
            ],
            durationMinutes: 4
        ),
        // Visualization
        ConfidenceExercise(
            id: "visualize_success",
            category: .visualization,
            title: "Visualize Success",
            description: "Mentally rehearse a successful speaking experience.",
            steps: [
                "Close your eyes and take three deep breaths",
                "Picture yourself walking up to speak, feeling calm",
                "See the audience smiling and engaged",
                "Hear yourself speaking clearly and confidently",
                "Feel the satisfaction of finishing strong",
                "Open your eyes and carry that feeling with you"
            ],
            durationMinutes: 3
        ),
        ConfidenceExercise(
            id: "safe_space",
            category: .visualization,
            title: "Safe Space",
            description: "Create a mental refuge you can visit anytime you feel nervous.",
            steps: [
                "Close your eyes and breathe deeply",
                "Imagine a place where you feel completely safe and relaxed",
                "Notice the colors, sounds, and temperature in this place",
                "Feel yourself becoming more relaxed with each breath",
                "Remember: you can return here anytime before speaking"
            ],
            durationMinutes: 3
        ),
        // Progressive Exposure
        ConfidenceExercise(
            id: "progressive_exposure",
            category: .progressive,
            title: "Progressive Exposure",
            description: "Build confidence step by step through gradually increasing challenges.",
            steps: [
                "Step 1: Record yourself speaking alone (just for you)",
                "Step 2: Listen back to your own recording",
                "Step 3: Record yourself on video",
                "Step 4: Share a recording with a trusted friend"
            ],
            durationMinutes: 5
        ),
        // Affirmation
        ConfidenceExercise(
            id: "power_statements",
            category: .affirmation,
            title: "Power Statements",
            description: "Repeat these affirmations before your next speaking session.",
            steps: [
                "I am a confident speaker",
                "My voice deserves to be heard",
                "I am improving every time I practice",
                "Mistakes are how I learn and grow",
                "I bring unique value to every conversation",
                "My ideas matter and I express them well",
                "I am brave for practicing my voice",
                "Each session makes me stronger",
                "I am proud of my progress",
                "I speak with clarity and purpose"
            ],
            durationMinutes: 3
        ),
    ]
}
