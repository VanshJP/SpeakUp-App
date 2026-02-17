import Foundation

struct DefaultWarmUps {
    static let all: [WarmUpExercise] = [
        // Breathing
        WarmUpExercise(
            id: "box_breathing",
            category: .breathing,
            title: "Box Breathing",
            instructions: "Breathe in a steady 4-4-4-4 pattern to calm your nerves.",
            steps: [
                ExerciseStep(label: "Breathe In", durationSeconds: 4, animation: .expand),
                ExerciseStep(label: "Hold", durationSeconds: 4, animation: .hold),
                ExerciseStep(label: "Breathe Out", durationSeconds: 4, animation: .contract),
                ExerciseStep(label: "Hold", durationSeconds: 4, animation: .hold),
                ExerciseStep(label: "Breathe In", durationSeconds: 4, animation: .expand),
                ExerciseStep(label: "Hold", durationSeconds: 4, animation: .hold),
                ExerciseStep(label: "Breathe Out", durationSeconds: 4, animation: .contract),
                ExerciseStep(label: "Hold", durationSeconds: 4, animation: .hold),
                ExerciseStep(label: "Breathe In", durationSeconds: 4, animation: .expand),
                ExerciseStep(label: "Hold", durationSeconds: 4, animation: .hold),
                ExerciseStep(label: "Breathe Out", durationSeconds: 4, animation: .contract),
                ExerciseStep(label: "Hold", durationSeconds: 4, animation: .hold),
            ],
            durationSeconds: 48
        ),
        WarmUpExercise(
            id: "478_technique",
            category: .breathing,
            title: "4-7-8 Technique",
            instructions: "A calming breath pattern: inhale 4s, hold 7s, exhale 8s.",
            steps: [
                ExerciseStep(label: "Breathe In", durationSeconds: 4, animation: .expand),
                ExerciseStep(label: "Hold", durationSeconds: 7, animation: .hold),
                ExerciseStep(label: "Breathe Out", durationSeconds: 8, animation: .contract),
                ExerciseStep(label: "Breathe In", durationSeconds: 4, animation: .expand),
                ExerciseStep(label: "Hold", durationSeconds: 7, animation: .hold),
                ExerciseStep(label: "Breathe Out", durationSeconds: 8, animation: .contract),
                ExerciseStep(label: "Breathe In", durationSeconds: 4, animation: .expand),
                ExerciseStep(label: "Hold", durationSeconds: 7, animation: .hold),
                ExerciseStep(label: "Breathe Out", durationSeconds: 8, animation: .contract),
            ],
            durationSeconds: 57
        ),
        WarmUpExercise(
            id: "deep_belly",
            category: .breathing,
            title: "Deep Belly Breathing",
            instructions: "Place your hand on your belly. Breathe deeply so your belly rises, not your chest.",
            steps: [
                ExerciseStep(label: "Breathe In Deeply", durationSeconds: 5, animation: .expand),
                ExerciseStep(label: "Breathe Out Slowly", durationSeconds: 5, animation: .contract),
                ExerciseStep(label: "Breathe In Deeply", durationSeconds: 5, animation: .expand),
                ExerciseStep(label: "Breathe Out Slowly", durationSeconds: 5, animation: .contract),
                ExerciseStep(label: "Breathe In Deeply", durationSeconds: 5, animation: .expand),
                ExerciseStep(label: "Breathe Out Slowly", durationSeconds: 5, animation: .contract),
            ],
            durationSeconds: 30
        ),
        // Tongue Twisters
        WarmUpExercise(
            id: "she_sells",
            category: .tonguetwister,
            title: "She Sells Seashells",
            instructions: "Say this tongue twister clearly, then try faster each round.",
            steps: [
                ExerciseStep(label: "She sells seashells by the seashore", durationSeconds: 10, animation: .hold),
                ExerciseStep(label: "Rest", durationSeconds: 3, animation: .hold),
                ExerciseStep(label: "She sells seashells by the seashore (faster)", durationSeconds: 8, animation: .hold),
                ExerciseStep(label: "Rest", durationSeconds: 3, animation: .hold),
                ExerciseStep(label: "She sells seashells by the seashore (fastest)", durationSeconds: 6, animation: .hold),
            ],
            durationSeconds: 30
        ),
        WarmUpExercise(
            id: "peter_piper",
            category: .tonguetwister,
            title: "Peter Piper",
            instructions: "Articulate each word precisely.",
            steps: [
                ExerciseStep(label: "Peter Piper picked a peck of pickled peppers", durationSeconds: 10, animation: .hold),
                ExerciseStep(label: "Rest", durationSeconds: 3, animation: .hold),
                ExerciseStep(label: "Peter Piper picked a peck of pickled peppers (faster)", durationSeconds: 8, animation: .hold),
                ExerciseStep(label: "Rest", durationSeconds: 3, animation: .hold),
                ExerciseStep(label: "Peter Piper picked a peck of pickled peppers (fastest)", durationSeconds: 6, animation: .hold),
            ],
            durationSeconds: 30
        ),
        // Vocal
        WarmUpExercise(
            id: "humming",
            category: .vocal,
            title: "Humming Warm-Up",
            instructions: "Hum at a comfortable pitch, feeling the vibration in your face and chest.",
            steps: [
                ExerciseStep(label: "Hum at low pitch", durationSeconds: 10, animation: .hold),
                ExerciseStep(label: "Hum at medium pitch", durationSeconds: 10, animation: .hold),
                ExerciseStep(label: "Hum at high pitch", durationSeconds: 10, animation: .hold),
            ],
            durationSeconds: 30
        ),
        WarmUpExercise(
            id: "lip_trills",
            category: .vocal,
            title: "Lip Trills",
            instructions: "Blow air through loosely closed lips to create a brrr sound. Vary pitch up and down.",
            steps: [
                ExerciseStep(label: "Lip trill - low to high", durationSeconds: 8, animation: .expand),
                ExerciseStep(label: "Rest", durationSeconds: 3, animation: .hold),
                ExerciseStep(label: "Lip trill - high to low", durationSeconds: 8, animation: .contract),
                ExerciseStep(label: "Rest", durationSeconds: 3, animation: .hold),
                ExerciseStep(label: "Lip trill - sustained", durationSeconds: 8, animation: .hold),
            ],
            durationSeconds: 30
        ),
        WarmUpExercise(
            id: "siren",
            category: .vocal,
            title: "Siren Exercise",
            instructions: "Glide your voice from your lowest comfortable note to your highest and back.",
            steps: [
                ExerciseStep(label: "Low to high", durationSeconds: 8, animation: .expand),
                ExerciseStep(label: "High to low", durationSeconds: 8, animation: .contract),
                ExerciseStep(label: "Low to high", durationSeconds: 8, animation: .expand),
                ExerciseStep(label: "High to low", durationSeconds: 8, animation: .contract),
            ],
            durationSeconds: 32
        ),
        // Articulation
        WarmUpExercise(
            id: "vowel_stretches",
            category: .articulation,
            title: "Vowel Stretches",
            instructions: "Exaggerate each vowel sound, opening your mouth wide.",
            steps: [
                ExerciseStep(label: "AAAA - open wide", durationSeconds: 5, animation: .expand),
                ExerciseStep(label: "EEEE - stretch wide", durationSeconds: 5, animation: .hold),
                ExerciseStep(label: "IIII - smile shape", durationSeconds: 5, animation: .hold),
                ExerciseStep(label: "OOOO - round lips", durationSeconds: 5, animation: .contract),
                ExerciseStep(label: "UUUU - small opening", durationSeconds: 5, animation: .contract),
            ],
            durationSeconds: 25
        ),
        WarmUpExercise(
            id: "consonant_drills",
            category: .articulation,
            title: "Consonant Drills",
            instructions: "Repeat consonant pairs rapidly and clearly.",
            steps: [
                ExerciseStep(label: "BA-BA-BA-BA-BA", durationSeconds: 5, animation: .hold),
                ExerciseStep(label: "DA-DA-DA-DA-DA", durationSeconds: 5, animation: .hold),
                ExerciseStep(label: "GA-GA-GA-GA-GA", durationSeconds: 5, animation: .hold),
                ExerciseStep(label: "PA-TA-KA-PA-TA-KA", durationSeconds: 8, animation: .hold),
                ExerciseStep(label: "LA-RA-LA-RA-LA-RA", durationSeconds: 7, animation: .hold),
            ],
            durationSeconds: 30
        ),
        WarmUpExercise(
            id: "jaw_relaxation",
            category: .articulation,
            title: "Jaw Relaxation",
            instructions: "Release tension in your jaw with gentle stretches.",
            steps: [
                ExerciseStep(label: "Open jaw wide, hold", durationSeconds: 5, animation: .expand),
                ExerciseStep(label: "Close gently", durationSeconds: 3, animation: .contract),
                ExerciseStep(label: "Move jaw left, hold", durationSeconds: 5, animation: .hold),
                ExerciseStep(label: "Move jaw right, hold", durationSeconds: 5, animation: .hold),
                ExerciseStep(label: "Open and close slowly", durationSeconds: 7, animation: .expand),
            ],
            durationSeconds: 25
        ),
    ]
}
