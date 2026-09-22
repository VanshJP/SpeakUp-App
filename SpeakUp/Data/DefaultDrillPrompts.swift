import Foundation

/// What each drill gives you to say.
///
/// Every drill gets something. Filler Elimination, Pace Control and Pause
/// Practice used to open on a bare clock, which spent the first seconds of a
/// fifteen-second round deciding what to talk about - and fillers cluster
/// exactly where a speaker is still deciding. So the habit drills get easy,
/// familiar topics that leave attention free for *how* you speak, and the
/// thinking drills get harder ones on purpose.
struct DefaultDrillPrompts {
    /// Low-planning topics for the habit drills: you already know the answer.
    static let familiarTopics = [
        "Walk through your morning routine, step by step",
        "Describe how you cook a meal you make often",
        "Give directions from your home to a place you go every week",
        "Describe the room you're in right now",
        "Explain how you got into a hobby you enjoy",
        "Describe your favorite place to eat and what you order there",
        "Talk through what you did last weekend",
        "Describe a close friend and how you met",
        "Explain what you do all day to someone who has never seen it",
        "Describe the best trip you've taken",
        "Talk about a show or movie you watched recently",
        "Explain the rules of a game you know well",
    ]

    /// Open topics for Impromptu Sprint, where finding a shape under pressure
    /// is the skill.
    static let impromptuTopics = [
        "Describe your perfect weekend from start to finish",
        "Why is your favorite food the best one out there?",
        "Explain a hobby to someone who's never heard of it",
        "Convince someone to visit your favorite place",
        "Talk about a book or movie that changed your perspective",
        "What would you do with an extra hour each day?",
        "Describe your morning routine and why it works for you",
        "What's the best advice you've ever received?",
        "If you could have dinner with anyone, who and why?",
        "Pitch a brand new app idea in 30 seconds",
        "Talk about a skill you'd love to master and why",
        "Explain something interesting you learned recently",
        "Why should everyone try your favorite activity?",
        "Describe a place that feels like home to you",
        "What's one thing you'd change about how people communicate?",
        "Tell the story of your most memorable travel experience",
        "Explain why a simple everyday object is actually amazing",
        "What's a common misconception people have about your field?",
    ]

    static let vocalVarietyLines = [
        "The storm rolled in, then the sky cracked open with light.",
        "Please lower your voice here, then lift it on the final word: victory.",
        "Start soft and low, then climb until the last phrase rings clear.",
        "Whisper the opening, speak the middle, project the close.",
        "Glide from your lowest comfortable note to your highest on this line.",
    ]

    /// Lines with one capitalized word to stress, and that word.
    static let emphasisPrompts: [(line: String, target: String)] = [
        ("I am absolutely CERTAIN this will work.", "CERTAIN"),
        ("We need this done TODAY, not next week.", "TODAY"),
        ("That was the BEST decision we made all year.", "BEST"),
        ("Never underestimate a simple CLEAR answer.", "CLEAR"),
        ("This matters NOW more than it ever has.", "NOW"),
        ("She was the ONLY person who stayed.", "ONLY"),
    ]

    static let qaQuestions = [
        "What's the biggest challenge in your field right now, and how would you solve it?",
        "Why should someone trust your recommendation?",
        "What would you do differently if you started over tomorrow?",
        "How do you explain your work to someone outside your field?",
        "What's one risk worth taking this year, and why?",
        "Where do most teams waste time, and what would you cut first?",
        "What does success look like for you in six months?",
        "How would you handle a question you don't know the answer to?",
    ]
}
