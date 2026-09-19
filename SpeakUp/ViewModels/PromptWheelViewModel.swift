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

    var rotation: Double = 0
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

    /// Slower than this on release is a nudge, not a flick: the wheel just
    /// settles onto the nearest segment. Degrees per second.
    static let flickThreshold: Double = 90

    @MainActor
    func spin() {
        guard !isSpinning else { return }
        // Random spin amount (3-6 full rotations plus random angle)
        let baseRotations = Double.random(in: 3...6) * 360
        let extraAngle = Double.random(in: 0..<360)
        spin(by: baseRotations + extraAngle)
    }

    /// The finger is on the wheel: it follows exactly, no animation, and any
    /// earlier result clears so the card is not naming a category the wheel
    /// has already left.
    @MainActor
    func drag(by degrees: Double) {
        guard !isSpinning else { return }
        selectedPrompt = nil
        selectedCategory = nil
        rotation += degrees
    }

    /// A release after a drag. Velocity is signed degrees per second; the
    /// wheel keeps the finger's direction and spins further the harder the
    /// flick, between one and six turns.
    @MainActor
    func release(angularVelocity: Double) {
        guard !isSpinning else { return }
        let magnitude = abs(angularVelocity)
        guard magnitude >= Self.flickThreshold else {
            spin(by: 0, duration: 0.45)
            return
        }
        let turns = min(6, max(1, magnitude / 400))
        spin(by: turns * 360 * (angularVelocity < 0 ? -1 : 1))
    }

    @MainActor
    private func spin(by amount: Double, duration: Double? = nil) {
        guard !categories.isEmpty else { return }

        isSpinning = true
        selectedPrompt = nil
        selectedCategory = nil

        let landing = Self.landing(rotation: rotation, amount: amount, segments: categories.count)

        // Dynamic animation duration based on rotation amount (2.5-4.5 seconds)
        let normalizedRotation = min(1, abs(landing.total) / (6 * 360))
        let animationDuration = duration ?? (2.5 + normalizedRotation * 2.0)

        // Animate the spin with dynamic timing
        withAnimation(.timingCurve(0.2, 1, 0.3, 1, duration: animationDuration)) {
            rotation += landing.total
        }

        // Set selection after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) { [weak self] in
            guard let self else { return }
            self.isSpinning = false
            self.selectCategory(at: landing.index)

            // Haptic feedback when landing
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
    }

    // MARK: - Landing

    /// Where a spin of `amount` degrees from `rotation` lands, with the amount
    /// adjusted so the pointer rests inside the segment rather than on an edge.
    ///
    /// The pointer is at 12 o'clock. When the wheel has turned clockwise by
    /// `r` degrees, the segment originally at `-r` sits under it, so the
    /// pointer's angle in wheel space is `normalized(-r)`. The returned total
    /// nudges the raw amount by less than one segment, toward a point within
    /// the middle 60% of the segment the raw amount would have reached.
    nonisolated static func landing(
        rotation: Double,
        amount: Double,
        segments: Int,
        jitter: Double = .random(in: -0.3...0.3)
    ) -> (index: Int, total: Double) {
        let segmentAngle = 360.0 / Double(segments)
        let pointerAngle = normalized(-(rotation + amount))
        let index = Int(pointerAngle / segmentAngle) % segments
        let target = (Double(index) + 0.5 + jitter) * segmentAngle
        // Adding δ to the rotation moves the pointer by -δ, so travel the
        // signed difference the other way.
        let total = amount + signedDelta(pointerAngle - target)
        return (index, total)
    }

    nonisolated static func normalized(_ degrees: Double) -> Double {
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        return remainder < 0 ? remainder + 360 : remainder
    }

    /// The same angle folded into (-180, 180].
    nonisolated static func signedDelta(_ degrees: Double) -> Double {
        let folded = normalized(degrees)
        return folded > 180 ? folded - 360 : folded
    }

    private func selectCategory(at index: Int) {
        guard index < categories.count else { return }
        
        selectedCategory = categories[index]
        
        // Pick a random prompt from this category
        let categoryPrompts = prompts.filter { $0.category == selectedCategory }
        selectedPrompt = categoryPrompts.randomElement()
    }
    
}
