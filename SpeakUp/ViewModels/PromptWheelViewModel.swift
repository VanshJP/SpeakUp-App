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
            let settingsDescriptor = FetchDescriptor<UserSettings>()
            let enabledCategories = try context.fetch(settingsDescriptor).first?.enabledCategories ?? PromptCategory.allCases

            let enabledCategoryNames = Set(enabledCategories.map { $0.rawValue })

            let promptDescriptor = FetchDescriptor<Prompt>()
            let allPrompts = try context.fetch(promptDescriptor)
            prompts = allPrompts.filter { enabledCategoryNames.contains($0.category) }
            categories = Array(Set(prompts.map { $0.category })).sorted()
        } catch {
            logger.error("Error loading prompts: \(error.localizedDescription, privacy: .private(mask: .hash))")
        }
    }
    
    // MARK: - Spin Logic

    @MainActor
    func spin() {
        guard !isSpinning else { return }

        isSpinning = true
        selectedPrompt = nil
        selectedCategory = nil

        let baseRotations = Double.random(in: 3...6) * 360
        let extraAngle = Double.random(in: 0..<360)
        let totalRotation = baseRotations + extraAngle

        let numberOfSegments = Double(categories.count)
        let segmentAngle = 360.0 / numberOfSegments
        let finalAngle = (rotation + totalRotation).truncatingRemainder(dividingBy: 360)
        let pointerAngle = (360 - finalAngle).truncatingRemainder(dividingBy: 360)
        let selectedIndex = Int(pointerAngle / segmentAngle) % categories.count

        let normalizedRotation = totalRotation / (6 * 360) // 0-1 range
        let animationDuration = 2.5 + (normalizedRotation * 2.0)

        withAnimation(.timingCurve(0.2, 1, 0.3, 1, duration: animationDuration)) {
            rotation += totalRotation
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) { [weak self] in
            guard let self else { return }
            self.isSpinning = false
            self.selectCategory(at: selectedIndex)

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
    }
    
    private func selectCategory(at index: Int) {
        guard index < categories.count else { return }
        
        selectedCategory = categories[index]
        
        let categoryPrompts = prompts.filter { $0.category == selectedCategory }
        selectedPrompt = categoryPrompts.randomElement()
    }
    
}
