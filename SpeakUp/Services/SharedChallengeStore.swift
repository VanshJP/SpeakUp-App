import Foundation
import Observation

@MainActor
@Observable
final class SharedChallengeStore {
    static let shared = SharedChallengeStore()

    private static let pendingKey = "sharedChallenge.pending.v1"

    private(set) var pending: SharedChallenge?

    private init() {
        pending = Self.load()
    }

    func remember(_ challenge: SharedChallenge) {
        pending = challenge
        if let data = try? JSONEncoder().encode(challenge) {
            UserDefaults.standard.set(data, forKey: Self.pendingKey)
        }
    }

    func dismiss() {
        pending = nil
        UserDefaults.standard.removeObject(forKey: Self.pendingKey)
    }

    private static func load() -> SharedChallenge? {
        guard let data = UserDefaults.standard.data(forKey: pendingKey) else { return nil }
        return try? JSONDecoder().decode(SharedChallenge.self, from: data)
    }
}
