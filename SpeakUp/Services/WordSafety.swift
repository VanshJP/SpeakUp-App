import Foundation

/// Gates words that enter the vocab bank, dictation dictionary, or daily
/// word-workout spotlight. Exact-token matching (not substrings) so "class"
/// and "assessment" stay allowed.
nonisolated enum WordSafety {
    enum Rejection: Equatable, Sendable {
        case empty
        case tooShort
        case blocked
        case filler
    }

    static let minimumLength = 2
    static let challengeMinimumLength = 3

    static func normalized(_ word: String) -> String {
        word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Whether this string may be stored in the word bank or dictation dictionary.
    static func allows(_ word: String) -> Bool {
        rejection(for: word) == nil
    }

    /// Spotlight words need a little more length and must not be fillers.
    static func allowsForChallenge(_ word: String) -> Bool {
        guard allows(word) else { return false }
        let key = normalized(word)
        guard key.count >= challengeMinimumLength else { return false }
        return !isFiller(key)
    }

    static func rejection(for word: String) -> Rejection? {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        guard trimmed.count >= minimumLength else { return .tooShort }
        if isBlocked(trimmed) { return .blocked }
        return nil
    }

    static func isBlocked(_ word: String) -> Bool {
        let key = normalized(word)
        if blocked.contains(key) { return true }

        let lettersOnly = String(key.filter(\.isLetter))
        if lettersOnly.count >= minimumLength, blocked.contains(lettersOnly) { return true }

        let tokens = key.split { !$0.isLetter }.map(String.init)
        if tokens.contains(where: { blocked.contains($0) }) { return true }
        return false
    }

    static func isFiller(_ word: String) -> Bool {
        let key = normalized(word)
        if challengeFillers.contains(key) { return true }
        let collapsed = collapseRepeatedLetters(key)
        return challengeFillers.contains(collapsed)
    }

    static func isUserName(_ word: String, userName: String) -> Bool {
        let parts = userName.split { !$0.isLetter }.map { $0.lowercased() }
        guard !parts.isEmpty else { return false }
        let key = normalized(word)
        return parts.contains(where: { $0 == key })
    }

    // MARK: - Fillers excluded from spotlight

    /// Snapshot of hesitation sounds plus context-dependent fillers. Kept here
    /// so challenge picking stays a pure, nonisolated function.
    private static let challengeFillers: Set<String> = [
        "um", "umm", "ummm", "uh", "uhh", "uhhh", "er", "err", "ah", "ahh",
        "eh", "oh", "ohh", "mm", "mmm", "mhm", "hmm", "hmmm", "huh", "erm",
        "yeah", "yea", "mhmm", "like", "so", "just", "well", "right", "okay",
        "actually", "basically", "literally", "honestly", "seriously"
    ]

    private static func collapseRepeatedLetters(_ word: String) -> String {
        var result = ""
        var previous: Character?
        for char in word {
            if char != previous {
                result.append(char)
                previous = char
            }
        }
        return result
    }

    // MARK: - Blocked tokens

    /// Lowercased whole tokens. Do not substring-match this set.
    private static let blocked: Set<String> = [
        "anal", "anus", "arsehole", "asshole", "ballsack", "bastard", "bitch",
        "blowjob", "bollocks", "boner", "boob", "boobs", "bugger", "clit",
        "clitoris", "cock", "cocks", "coon", "cum", "cunt", "dick",
        "dildo", "dyke", "ejaculate", "fag", "faggot", "fags", "felch",
        "fellate", "fellatio", "felching", "fuck", "fucked", "fucker",
        "fucking", "fucks", "fudgepacker", "goddamn", "homo", "handjob",
        "jizz", "kike", "labia", "muff", "nigga", "nigger", "nutsack",
        "orgasm", "penis", "piss", "pissed", "porn", "porno", "pube", "pubes",
        "pussy", "queef", "rape", "rapist", "rectum", "retard", "retarded",
        "rimjob", "semen", "shit", "shite", "shits", "shitty",
        "slut", "sluts", "smegma", "spunk", "tit", "tits", "titties",
        "twat", "vagina", "wank", "wanker", "whore", "whores",
        "chink", "gook", "spic", "spick", "tranny", "wetback",
        "motherfucker", "motherfuckers", "cocksucker", "cocksuckers"
    ]
}
