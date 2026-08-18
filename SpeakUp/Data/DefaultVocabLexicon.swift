import Foundation

/// One speaking-power word the daily workout can introduce.
nonisolated struct VocabLexiconEntry: Sendable, Equatable {
    let word: String
    let gloss: String
    let prompt: String
    /// 0 beginner, 1 intermediate, 2 advanced — matches `SpeakerLevel.rawValue`.
    let level: Int
}

/// Curated, original glosses for daily introduction. Onboarding seeds live here
/// too so bank words get a coach line. Every entry is WordSafety-clean.
nonisolated enum DefaultVocabLexicon {
    static func entry(for word: String) -> VocabLexiconEntry? {
        let key = word.lowercased()
        return byLowercased[key]
    }

    static func entries(matchingLevel raw: Int) -> [VocabLexiconEntry] {
        let level = min(2, max(0, raw))
        let preferred = entries.filter { $0.level == level }
        if !preferred.isEmpty { return preferred }
        return entries
    }

    private static let byLowercased: [String: VocabLexiconEntry] = {
        Dictionary(uniqueKeysWithValues: entries.map { ($0.word.lowercased(), $0) })
    }()

    static let entries: [VocabLexiconEntry] = beginner + intermediate + advanced

    // MARK: - Beginner

    private static let beginner: [VocabLexiconEntry] = [
        .init(word: "Confident", gloss: "Sure of yourself without showing off.", prompt: "Use it about a moment you spoke up.", level: 0),
        .init(word: "Practice", gloss: "Doing the thing again so it gets easier.", prompt: "Use it about how you got better at something.", level: 0),
        .init(word: "Improve", gloss: "Make something better than it was.", prompt: "Use it about a skill you are building.", level: 0),
        .init(word: "Prepare", gloss: "Get ready before you have to perform.", prompt: "Use it about what you did before a hard talk.", level: 0),
        .init(word: "Express", gloss: "Put a feeling or idea into words.", prompt: "Use it about something you found hard to say.", level: 0),
        .init(word: "Focus", gloss: "Give one thing your full attention.", prompt: "Use it about cutting a distraction.", level: 0),
        .init(word: "Listen", gloss: "Hear someone fully before you answer.", prompt: "Use it about a conversation that changed your mind.", level: 0),
        .init(word: "Engage", gloss: "Pull people in so they actually care.", prompt: "Use it about holding a room's attention.", level: 0),
        .init(word: "Straightforward", gloss: "Easy to follow on the first pass.", prompt: "Use it to describe how you want to sound.", level: 0),
        .init(word: "Specific", gloss: "Named and concrete, not vague.", prompt: "Use it when you swap a fuzzy claim for a fact.", level: 0),
        .init(word: "Honest", gloss: "True even when it is uncomfortable.", prompt: "Use it about feedback you gave or got.", level: 0),
        .init(word: "Collected", gloss: "Steady when the stakes rise.", prompt: "Use it about a tense moment you handled.", level: 0),
        .init(word: "Forthright", gloss: "Said straight, without padding.", prompt: "Use it about a request you need to make.", level: 0),
        .init(word: "Curious", gloss: "Wanting to understand, not just reply.", prompt: "Use it about a question you asked.", level: 0),
        .init(word: "Grateful", gloss: "Noticing help and naming it.", prompt: "Use it about someone who backed you.", level: 0),
        .init(word: "Patient", gloss: "Willing to wait without snapping.", prompt: "Use it about a delay you handled well.", level: 0),
        .init(word: "Brave", gloss: "Willing to speak while still nervous.", prompt: "Use it about a first time you tried.", level: 0),
        .init(word: "Accessible", gloss: "Stripped to what actually matters.", prompt: "Use it about explaining a hard idea easily.", level: 0),
        .init(word: "Steady", gloss: "Even pace, no rush and no stall.", prompt: "Use it about how you want to deliver.", level: 0),
        .init(word: "Receptive", gloss: "Ready to hear a view that is not yours.", prompt: "Use it about changing your mind.", level: 0),
        .init(word: "Considerate", gloss: "Firm on the point, gentle on the person.", prompt: "Use it about hard news you had to share.", level: 0),
        .init(word: "Willing", gloss: "Prepared enough to start now.", prompt: "Use it about a moment you stopped stalling.", level: 0),
        .init(word: "Attentive", gloss: "Here, not rehearsing the next line.", prompt: "Use it about staying with the listener.", level: 0),
        .init(word: "Reliable", gloss: "Tied to facts, not spinning.", prompt: "Use it about keeping a story honest.", level: 0),
        .init(word: "Welcoming", gloss: "Friendly without going soft on the point.", prompt: "Use it about how you greet a room.", level: 0),
        .init(word: "Precise", gloss: "The right word, not a nearby one.", prompt: "Use it when you correct a fuzzy phrase.", level: 0),
        .init(word: "Encouraging", gloss: "Leaves people braver than you found them.", prompt: "Use it about a pep talk that actually helped.", level: 0),
        .init(word: "Thoughtful", gloss: "Shows you considered the other side.", prompt: "Use it about a reply you sat with first.", level: 0),
        .init(word: "Supportive", gloss: "Makes the next step obvious.", prompt: "Use it about advice that actually landed.", level: 0),
        .init(word: "Sincere", gloss: "Means it; nothing performed.", prompt: "Use it about praise you actually believed.", level: 0),
    ]

    // MARK: - Intermediate

    private static let intermediate: [VocabLexiconEntry] = [
        .init(word: "Strategic", gloss: "Chosen because it serves a longer aim.", prompt: "Use it about a tradeoff you made on purpose.", level: 1),
        .init(word: "Authentic", gloss: "Sounds like you, not a script.", prompt: "Use it about dropping a fake tone.", level: 1),
        .init(word: "Resilient", gloss: "Bounces back without pretending it was easy.", prompt: "Use it about a setback you recovered from.", level: 1),
        .init(word: "Empathetic", gloss: "Shows you felt the other person's side.", prompt: "Use it about a conflict you de-escalated.", level: 1),
        .init(word: "Decisive", gloss: "Picks a path and owns it.", prompt: "Use it about a call you stopped delaying.", level: 1),
        .init(word: "Adaptable", gloss: "Changes approach when the room changes.", prompt: "Use it about a plan you rewrote live.", level: 1),
        .init(word: "Articulate", gloss: "Puts a messy idea into clean language.", prompt: "Use it about explaining something tangled.", level: 1),
        .init(word: "Visionary", gloss: "Describes a future people can actually see.", prompt: "Use it about a direction you pitched.", level: 1),
        .init(word: "Concise", gloss: "Short because the extras were cut.", prompt: "Use it about trimming a rambling answer.", level: 1),
        .init(word: "Deliberate", gloss: "Done on purpose, not by accident.", prompt: "Use it about a pause you chose.", level: 1),
        .init(word: "Credible", gloss: "Believable because the evidence is there.", prompt: "Use it about why someone should trust a claim.", level: 1),
        .init(word: "Poised", gloss: "Composed while the pressure is on.", prompt: "Use it about staying even in a hard Q&A.", level: 1),
        .init(word: "Pragmatic", gloss: "Useful in the real world, not just clever.", prompt: "Use it about picking the workable option.", level: 1),
        .init(word: "Intentional", gloss: "Every part is there for a reason.", prompt: "Use it about a word you chose carefully.", level: 1),
        .init(word: "Cohesive", gloss: "The pieces belong to one story.", prompt: "Use it about tying two points together.", level: 1),
        .init(word: "Balanced", gloss: "Fair to more than one side.", prompt: "Use it about presenting a tradeoff honestly.", level: 1),
        .init(word: "Candid", gloss: "Frank without being cruel.", prompt: "Use it about news you did not sugarcoat.", level: 1),
        .init(word: "Composed", gloss: "Voice and body stay under your control.", prompt: "Use it about nerves you did not leak.", level: 1),
        .init(word: "Insightful", gloss: "Notices what other people skipped.", prompt: "Use it about a pattern you named.", level: 1),
        .init(word: "Relevant", gloss: "Tied to what this listener needs now.", prompt: "Use it about cutting a tangent.", level: 1),
        .init(word: "Memorable", gloss: "Sticks after the room empties.", prompt: "Use it about a line you want them to repeat.", level: 1),
        .init(word: "Grounded", gloss: "Anchored in what actually happened.", prompt: "Use it about backing a claim with a story.", level: 1),
        .init(word: "Flexible", gloss: "Can change shape without losing the point.", prompt: "Use it about adjusting mid-answer.", level: 1),
        .init(word: "Respectful", gloss: "Disagrees without diminishing the person.", prompt: "Use it about a pushback you delivered well.", level: 1),
        .init(word: "Vivid", gloss: "The listener can picture it.", prompt: "Use it about swapping abstract talk for a scene.", level: 1),
        .init(word: "Measured", gloss: "Volume and pace match the moment.", prompt: "Use it about not overselling a small point.", level: 1),
        .init(word: "Accountable", gloss: "Owns the outcome, including the miss.", prompt: "Use it about a mistake you named first.", level: 1),
        .init(word: "Generous", gloss: "Gives credit and airtime to others.", prompt: "Use it about sharing the floor.", level: 1),
        .init(word: "Disciplined", gloss: "Sticks to the structure you promised.", prompt: "Use it about not wandering off-prompt.", level: 1),
        .init(word: "Lucid", gloss: "The logic is easy to walk through.", prompt: "Use it about a chain of reasons you laid out.", level: 1),
    ]

    // MARK: - Advanced

    private static let advanced: [VocabLexiconEntry] = [
        .init(word: "Compelling", gloss: "Hard to ignore once you have heard it.", prompt: "Use it about an argument that moved someone.", level: 2),
        .init(word: "Nuanced", gloss: "Holds more than one true thing at once.", prompt: "Use it about a take that is not binary.", level: 2),
        .init(word: "Cogent", gloss: "Tight logic, no holes to pick at.", prompt: "Use it about a case you built step by step.", level: 2),
        .init(word: "Eloquent", gloss: "Graceful without getting flowery.", prompt: "Use it about a line that sounded like you at your best.", level: 2),
        .init(word: "Transformative", gloss: "Changes how people see the problem.", prompt: "Use it about a reframe that stuck.", level: 2),
        .init(word: "Substantive", gloss: "Has weight; not just polish.", prompt: "Use it about content that earned the time.", level: 2),
        .init(word: "Incisive", gloss: "Cuts to the real issue fast.", prompt: "Use it about a question that opened the topic.", level: 2),
        .init(word: "Persuasive", gloss: "Moves someone toward a decision.", prompt: "Use it about an ask that got a yes.", level: 2),
        .init(word: "Salient", gloss: "The detail that actually changes the call.", prompt: "Use it about the fact you led with.", level: 2),
        .init(word: "Judicious", gloss: "Careful with emphasis and claims.", prompt: "Use it about hedging only where you must.", level: 2),
        .init(word: "Evocative", gloss: "Calls up a feeling without naming it.", prompt: "Use it about an image you used instead of a label.", level: 2),
        .init(word: "Rigorous", gloss: "Survives a skeptical listener.", prompt: "Use it about how you checked your own argument.", level: 2),
        .init(word: "Trenchant", gloss: "Sharp, brief, and hard to dismiss.", prompt: "Use it about a critique you kept short.", level: 2),
        .init(word: "Discerning", gloss: "Tells signal from noise in the room.", prompt: "Use it about what you chose not to say.", level: 2),
        .init(word: "Catalytic", gloss: "Starts motion in other people.", prompt: "Use it about a meeting you unstuck.", level: 2),
        .init(word: "Unflinching", gloss: "Does not look away from the hard part.", prompt: "Use it about naming a cost out loud.", level: 2),
        .init(word: "Economical", gloss: "Maximum meaning per word.", prompt: "Use it about a sentence you cut in half.", level: 2),
        .init(word: "Resonant", gloss: "Matches what the listener already feels.", prompt: "Use it about a story that landed in the room.", level: 2),
        .init(word: "Forensic", gloss: "Examines the evidence without theatre.", prompt: "Use it about walking through what actually happened.", level: 2),
        .init(word: "Magisterial", gloss: "Commanding because the command is earned.", prompt: "Use it about holding silence after a point.", level: 2),
        .init(word: "Austere", gloss: "Stripped of decoration on purpose.", prompt: "Use it about dropping the adjectives.", level: 2),
        .init(word: "Pivotal", gloss: "The turn the rest of the talk hangs on.", prompt: "Use it about the moment the story changed.", level: 2),
        .init(word: "Socratic", gloss: "Leads people to the point with questions.", prompt: "Use it about teaching without lecturing.", level: 2),
        .init(word: "Lapidary", gloss: "Cut like a stone: dense, finished, small.", prompt: "Use it about a one-line close.", level: 2),
        .init(word: "Irrefutable", gloss: "Leaves no honest way to deny it.", prompt: "Use it about a fact you put down first.", level: 2),
        .init(word: "Expansive", gloss: "Opens the topic without losing the spine.", prompt: "Use it about zooming out, then landing.", level: 2),
        .init(word: "Tactful", gloss: "True, and timed so it can be heard.", prompt: "Use it about a correction you delayed one beat.", level: 2),
        .init(word: "Unambiguous", gloss: "Only one reading is available.", prompt: "Use it about an ask with a clear yes or no.", level: 2),
        .init(word: "Provocative", gloss: "Pushes the room to think, not to flinch.", prompt: "Use it about a claim you meant them to wrestle with.", level: 2),
        .init(word: "Sinewy", gloss: "Lean muscle: no spare language.", prompt: "Use it about a paragraph you tightened.", level: 2),
    ]
}
