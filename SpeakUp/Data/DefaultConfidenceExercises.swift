import Foundation

struct DefaultConfidenceExercises {
    static let all: [ConfidenceExercise] = [
        ConfidenceExercise(
            id: "grounding_54321",
            category: .calming,
            title: "5-4-3-2-1 Grounding",
            description: "Names five things you can see, four you can hear, and so on - pulls attention out of the spiral and back into the room.",
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
            description: "Tense then release each muscle group in turn. Shows you where you were bracing, and lets it go.",
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
        ConfidenceExercise(
            id: "visualize_success",
            category: .visualization,
            title: "Visualize Success",
            description: "Walk through the talk going well, in detail. Rehearsed calm holds up better than talked-up confidence.",
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
            description: "Build one vivid place you can return to in seconds, so you have somewhere to go when nerves spike.",
            steps: [
                "Close your eyes and breathe deeply",
                "Imagine a place where you feel completely safe and relaxed",
                "Notice the colors, sounds, and temperature in this place",
                "Feel yourself becoming more relaxed with each breath",
                "Remember: you can return here anytime before speaking"
            ],
            durationMinutes: 3
        ),
        ConfidenceExercise(
            id: "progressive_exposure",
            category: .progressive,
            title: "Progressive Exposure",
            description: "Work up through speaking situations in order of difficulty, so the big one isn't your first attempt.",
            steps: [
                "Step 1: Record yourself speaking alone (just for you)",
                "Step 2: Listen back to your own recording",
                "Step 3: Record yourself on video",
                "Step 4: Share a recording with a trusted friend"
            ],
            durationMinutes: 5
        ),
        // Kept under its original id so lesson w4_l1_a2 and anyone's
        // completion record still find it. It used to be ten generic
        // affirmations ("I am a confident speaker"), which is the one version
        // of self-talk with evidence against it: repeating positive
        // self-statements made people with low self-esteem feel worse (Wood,
        // Perunovic & Lee, 2009) - the very people opening a Calm tool before
        // they speak. Reappraising arousal as excitement is the version that
        // held up on stage (Brooks, 2014).
        ConfidenceExercise(
            id: "power_statements",
            category: .affirmation,
            title: "Reframe the Nerves",
            description: "A pounding heart and quick breath are also what excitement feels like. People who said \"I'm excited\" out loud before a speech felt more excited and were rated better than people who tried to calm down.",
            steps: [
                "Notice what your body is doing: heartbeat, breath, hands",
                "Those are the same signals as excitement. Nothing needs fixing",
                "Say it out loud: \"I'm excited\"",
                "Now say what you're excited to share with them",
                "Picture one person in the room getting something from it",
                "Keep the energy. Walk in excited, not calm"
            ],
            durationMinutes: 2
        ),
        // Self-distanced self-talk (Kross et al., 2014): preparing a speech by
        // talking to yourself in the second person and by name cut distress
        // and rumination afterward, and outside raters scored those speeches
        // higher.
        ConfidenceExercise(
            id: "self_distanced_talk",
            category: .affirmation,
            title: "Coach Yourself by Name",
            description: "Talk to yourself the way you'd talk to a friend: by name, as \"you\". People who prepared a speech this way were less anxious, dwelt on it less afterward, and were rated as better speakers.",
            steps: [
                "Picture the first ten seconds of your talk",
                "Using your own name, ask yourself what you're worried about",
                "Answer like a coach would, to \"you\", not \"I\"",
                "Remind yourself, by name, that you've prepared for this",
                "Give yourself one instruction for the opening, like \"Take your time on the first sentence\"",
                "Say that instruction once more, out loud"
            ],
            durationMinutes: 3
        ),
    ]
}
