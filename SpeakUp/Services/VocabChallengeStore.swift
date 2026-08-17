import Foundation

/// Persists the day's word-workout pick and any skips. UserDefaults so a
/// mid-day recording does not reshuffle the words already on Today.
nonisolated struct VocabChallengeStore: @unchecked Sendable {
    static let standard = VocabChallengeStore(defaults: .standard)

    private let defaults: UserDefaults
    private let cacheKey = "vocabChallenge.cachedDay.v1"
    private let skipPrefix = "vocabChallenge.skipped."

    struct CachedDay: Codable, Sendable, Equatable {
        var dayStamp: String
        var fingerprint: String
        var words: [VocabChallengeWord]
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func cached() -> CachedDay? {
        guard let data = defaults.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(CachedDay.self, from: data)
    }

    func save(_ cache: CachedDay) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        defaults.set(data, forKey: cacheKey)
    }

    func skipped(on dayStamp: String) -> Set<String> {
        let values = defaults.stringArray(forKey: skipKey(dayStamp)) ?? []
        return Set(values.map { $0.lowercased() })
    }

    func skip(_ word: String, on dayStamp: String) {
        let key = skipKey(dayStamp)
        var values = defaults.stringArray(forKey: key) ?? []
        let lowered = word.lowercased()
        if !values.contains(where: { $0.lowercased() == lowered }) {
            values.append(word)
            defaults.set(values, forKey: key)
        }
    }

    func clearSkips(on dayStamp: String) {
        defaults.removeObject(forKey: skipKey(dayStamp))
    }

    private func skipKey(_ dayStamp: String) -> String {
        skipPrefix + dayStamp
    }
}
