import Foundation
import SwiftUI
import SwiftData
import UIKit

@Observable
class PromptWheelViewModel {
    var categories: [String] = []
    var prompts: [Prompt] = []
    var selectedPrompt: Prompt?
    var selectedCategory: String?

    var rotation: Double = 0
    var isSpinning = false

    private var modelContext: ModelContext?
    
    let categoryColors: [Color] = [
        .blue,      // Professional Development
        .purple,    // Communication Skills
        .green,     // Personal Growth
        .orange,    // Problem Solving
        .teal,      // Current Events
        .yellow,    // Quick Fire
        .red,       // Debate & Persuasion
        .pink       // Extra (if needed)
    ]
    
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
            print("Error loading prompts: \(error)")
        }
    }
    
    // MARK: - Spin Logic

    @MainActor
    func spin() {
        guard !isSpinning else { return }

        isSpinning = true
        selectedPrompt = nil
        selectedCategory = nil

        // Random spin amount (3-6 full rotations plus random angle)
        let baseRotations = Double.random(in: 3...6) * 360
        let extraAngle = Double.random(in: 0..<360)
        let totalRotation = baseRotations + extraAngle

        // Calculate which segment the pointer lands on
        // The pointer is at the top (12 o'clock). When the wheel rotates clockwise
        // by finalAngle degrees, the segment originally at (360 - finalAngle) is
        // now under the pointer.
        let numberOfSegments = Double(categories.count)
        let segmentAngle = 360.0 / numberOfSegments
        let finalAngle = (rotation + totalRotation).truncatingRemainder(dividingBy: 360)
        let pointerAngle = (360 - finalAngle).truncatingRemainder(dividingBy: 360)
        let selectedIndex = Int(pointerAngle / segmentAngle) % categories.count

        // Dynamic animation duration based on rotation amount (2.5-4.5 seconds)
        let normalizedRotation = totalRotation / (6 * 360) // 0-1 range
        let animationDuration = 2.5 + (normalizedRotation * 2.0)

        // Animate the spin with dynamic timing
        withAnimation(.timingCurve(0.2, 1, 0.3, 1, duration: animationDuration)) {
            rotation += totalRotation
        }

        // Set selection after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) { [weak self] in
            guard let self else { return }
            self.isSpinning = false
            self.selectCategory(at: selectedIndex)

            // Haptic feedback when landing
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
    }
    
    private func selectCategory(at index: Int) {
        guard index < categories.count else { return }
        
        selectedCategory = categories[index]
        
        // Pick a random prompt from this category
        let categoryPrompts = prompts.filter { $0.category == selectedCategory }
        selectedPrompt = categoryPrompts.randomElement()
    }
    
    // MARK: - Helpers
    
    func colorForCategory(_ category: String) -> Color {
        guard let index = categories.firstIndex(of: category) else {
            return .gray
        }
        return categoryColors[index % categoryColors.count]
    }
    
}
