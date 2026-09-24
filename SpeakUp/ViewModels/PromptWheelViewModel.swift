import Foundation
import os.log
import SwiftUI
import SwiftData
import UIKit

@Observable
class PromptWheelViewModel {
    private let logger = Logger.app("PromptWheel")
    var categories: [String] = []
    var prompts: [Prompt] = []
    var selectedPrompt: Prompt?
    var selectedCategory: String?

    /// Continuous, in stops, as `ArcDial` reads it: the category under the
    /// marker is `ArcDial.index(at: position, count:)`. Unbounded - the dial
    /// wraps.
    var position: Double = 0
    var isSpinning = false

    private var modelContext: ModelContext?

    func configure(with context: ModelContext) {
        self.modelContext = context
        Task { @MainActor in
            await loadData()
        }
    }
    
    @MainActor
    func loadData() async {
        guard let context = modelContext else { return }

        do {
            // Fetch user settings to get enabled categories
            let settingsDescriptor = FetchDescriptor<UserSettings>()
            let enabledCategories = try context.fetch(settingsDescriptor).first?.enabledCategories ?? PromptCategory.allCases

            let enabledCategoryNames = Set(enabledCategories.map { $0.rawValue })

            // Fetch all prompts and filter by enabled categories
            let promptDescriptor = FetchDescriptor<Prompt>()
            let allPrompts = try context.fetch(promptDescriptor)
            prompts = allPrompts.filter { enabledCategoryNames.contains($0.category) }
            categories = Array(Set(prompts.map { $0.category })).sorted()
        } catch {
            logger.error("Error loading prompts: \(error.localizedDescription, privacy: .private(mask: .hash))")
        }
    }
    
    // MARK: - Spin Logic

    /// A release that would coast less than this many stops is a nudge, not
    /// a flick: the wheel just settles onto the nearest category.
    static let flickThreshold: Double = 1.5

    @MainActor
    func spin() {
        guard !isSpinning, !categories.isEmpty else { return }
        let count = Double(categories.count)
        spin(by: Double.random(in: 3...5) * count + Double.random(in: 0..<count))
    }

    /// The finger is on the wheel: it follows exactly, no animation, and any
    /// earlier result clears so the card is not naming a category the wheel
    /// has already left.
    @MainActor
    func scrub(to newPosition: Double) {
        guard !isSpinning else { return }
        selectedPrompt = nil
        selectedCategory = nil
        position = newPosition
    }

    /// The finger lifted. `projected` is where the drag would coast to; a
    /// real flick keeps its direction and spins further the harder it was
    /// thrown, one to four laps on top of the coast.
    @MainActor
    func release(projected: Double) {
        guard !isSpinning else { return }
        let travel = projected - position
        guard abs(travel) >= Self.flickThreshold else {
            spin(by: travel, duration: 0.45)
            return
        }
        let laps = min(4, max(1, abs(travel) / 4)).rounded()
        spin(by: travel + laps * Double(categories.count) * (travel < 0 ? -1 : 1))
    }

    @MainActor
    private func spin(by amount: Double, duration: Double? = nil) {
        guard !categories.isEmpty else { return }

        isSpinning = true
        selectedPrompt = nil
        selectedCategory = nil

        let landing = Self.landing(position: position, amount: amount, count: categories.count)

        // Longer spins run longer, 2.5-4.5 seconds.
        let laps = abs(landing.target - position) / Double(categories.count)
        let animationDuration = duration ?? (2.5 + min(1, laps / 5) * 2.0)

        withAnimation(.timingCurve(0.2, 1, 0.3, 1, duration: animationDuration)) {
            position = landing.target
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) { [weak self] in
            guard let self else { return }
            self.isSpinning = false
            self.selectCategory(at: landing.index)

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
    }

    // MARK: - Landing

    /// Where a spin of `amount` stops from `position` comes to rest: always
    /// exactly on a stop, so the marker never sits between two categories,
    /// and the category there.
    nonisolated static func landing(position: Double, amount: Double, count: Int) -> (index: Int, target: Double) {
        let target = (position + amount).rounded()
        let raw = Int(target) % count
        return ((raw + count) % count, target)
    }

    private func selectCategory(at index: Int) {
        guard index < categories.count else { return }
        
        selectedCategory = categories[index]
        
        // Pick a random prompt from this category
        let categoryPrompts = prompts.filter { $0.category == selectedCategory }
        selectedPrompt = categoryPrompts.randomElement()
    }
    
}
