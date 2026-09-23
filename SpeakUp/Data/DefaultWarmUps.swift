import Foundation

struct DefaultWarmUps {
    static let all: [WarmUpExercise] = [
        WarmUpExercise(
            id: "box_breathing",
            category: .breathing,
            title: "Box Breathing",
            instructions: "Equal counts in, hold, out, hold. Evens out a racing heartbeat so your first sentence doesn't arrive breathless.",
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
            id: "cyclic_sighing",
            category: .breathing,
            title: "Physiological Sigh",
            instructions: "Two breaths in through the nose, then one long breath out through the mouth. In a Stanford study, a few minutes of this a day lifted mood and slowed breathing more than mindfulness meditation. The long exhale is what brakes a racing heart.",
            steps: [
                ExerciseStep(label: "Breathe In Through the Nose", durationSeconds: 2, animation: .expand),
                ExerciseStep(label: "Top Up with a Second Sniff", durationSeconds: 1, animation: .expand),
                ExerciseStep(label: "Long, Slow Exhale Through the Mouth", durationSeconds: 6, animation: .contract),
                ExerciseStep(label: "Breathe In Through the Nose", durationSeconds: 2, animation: .expand),
                ExerciseStep(label: "Top Up with a Second Sniff", durationSeconds: 1, animation: .expand),
                ExerciseStep(label: "Long, Slow Exhale Through the Mouth", durationSeconds: 6, animation: .contract),
                ExerciseStep(label: "Breathe In Through the Nose", durationSeconds: 2, animation: .expand),
                ExerciseStep(label: "Top Up with a Second Sniff", durationSeconds: 1, animation: .expand),
                ExerciseStep(label: "Long, Slow Exhale Through the Mouth", durationSeconds: 6, animation: .contract),
            ],
            durationSeconds: 27
        ),
        WarmUpExercise(
            id: "478_technique",
            category: .breathing,
            title: "4-7-8 Technique",
            instructions: "A long exhale is the part that settles you. Inhale 4, hold 7, out for 8 - the ratio does the work.",
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
            instructions: "Hand on the belly so you can feel it rise instead of your chest. Low breath is what stops a voice thinning out mid-sentence.",
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
        WarmUpExercise(
            id: "she_sells",
            category: .tonguetwister,
            title: "She Sells Seashells",
            instructions: "Stacked s and sh sounds force your tongue to reset between each one. Start slow and clean, then push the tempo.",
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
            instructions: "Repeated hard p sounds wake up the lips. Say it slowly enough that every p actually pops before speeding up.",
            steps: [
                ExerciseStep(label: "Peter Piper picked a peck of pickled peppers", durationSeconds: 10, animation: .hold),
                ExerciseStep(label: "Rest", durationSeconds: 3, animation: .hold),
                ExerciseStep(label: "Peter Piper picked a peck of pickled peppers (faster)", durationSeconds: 8, animation: .hold),
                ExerciseStep(label: "Rest", durationSeconds: 3, animation: .hold),
                ExerciseStep(label: "Peter Piper picked a peck of pickled peppers (fastest)", durationSeconds: 6, animation: .hold),
            ],
            durationSeconds: 30
        ),
        WarmUpExercise(
            id: "humming",
            category: .vocal,
            title: "Humming Warm-Up",
            instructions: "Humming gets the vocal folds moving gently and finds the buzz in your face - that resonance is what carries a voice across a room.",
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
            instructions: "A loose lip buzz keeps the throat relaxed while you move through your range, so you stretch pitch without straining.",
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
            instructions: "Sliding through your whole range on one breath. Makes the top and bottom of your voice available, so you stop speaking on one flat note.",
            steps: [
                ExerciseStep(label: "Low to high", durationSeconds: 8, animation: .expand),
                ExerciseStep(label: "High to low", durationSeconds: 8, animation: .contract),
                ExerciseStep(label: "Low to high", durationSeconds: 8, animation: .expand),
                ExerciseStep(label: "High to low", durationSeconds: 8, animation: .contract),
            ],
            durationSeconds: 32
        ),
        WarmUpExercise(
            id: "hum_into_speech",
            category: .vocal,
            title: "Hum Into Speech",
            instructions: "Find the buzz of an easy hum on your lips, then carry it straight into words. Speech-language pathologists use this resonant-voice bridge so the forward, carrying tone you warm up is the one you actually speak with.",
            steps: [
                ExerciseStep(label: "Easy hum: mmm, feel the lips buzz", durationSeconds: 6, animation: .hold),
                ExerciseStep(label: "Mm-hmm, like you're agreeing", durationSeconds: 6, animation: .hold),
                ExerciseStep(label: "Mmm-many, mmm-more, mmm-money", durationSeconds: 7, animation: .hold),
                ExerciseStep(label: "Mmm, my name is... (say your name)", durationSeconds: 6, animation: .hold),
                ExerciseStep(label: "Say your first line with that same buzz", durationSeconds: 8, animation: .hold),
            ],
            durationSeconds: 33
        ),
        WarmUpExercise(
            id: "vowel_stretches",
            category: .articulation,
            title: "Vowel Stretches",
            instructions: "Wide, exaggerated vowels open the jaw. Speech that sounds mumbled is usually a mouth that never fully opens.",
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
            instructions: "Rapid consonant pairs train the tongue tip and the back of the mouth to switch cleanly, which is what keeps word endings intact.",
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
            instructions: "Gentle jaw stretches release the clench most people carry. A tight jaw is the most common reason words come out swallowed.",
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
