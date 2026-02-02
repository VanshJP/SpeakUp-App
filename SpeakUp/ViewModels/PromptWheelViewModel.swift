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
    var spinVelocity: Double = 0

    private var modelContext: ModelContext?
    private var spinTimer: Timer?
    
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
        
        let descriptor = FetchDescriptor<Prompt>()
        
        do {
            prompts = try context.fetch(descriptor)
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

        // Calculate which segment we'll land on
        let numberOfSegments = Double(categories.count)
        let segmentAngle = 360.0 / numberOfSegments
        let finalAngle = (rotation + totalRotation).truncatingRemainder(dividingBy: 360)
        let selectedIndex = Int(finalAngle / segmentAngle) % categories.count

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
    
    // MARK: - Manual Selection
    
    func selectPrompt(_ prompt: Prompt) {
        selectedPrompt = prompt
        selectedCategory = prompt.category
    }
    
    func clearSelection() {
        selectedPrompt = nil
        selectedCategory = nil
    }
    
    // MARK: - Helpers
    
    func colorForCategory(_ category: String) -> Color {
        guard let index = categories.firstIndex(of: category) else {
            return .gray
        }
        return categoryColors[index % categoryColors.count]
    }
    
    func colorForIndex(_ index: Int) -> Color {
        categoryColors[index % categoryColors.count]
    }
    
    var segmentAngle: Double {
        guard !categories.isEmpty else { return 360 }
        return 360.0 / Double(categories.count)
    }
}


