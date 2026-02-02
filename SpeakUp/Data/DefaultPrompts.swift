import Foundation

struct PromptData {
    let id: String
    let text: String
    let category: String
    let difficulty: PromptDifficulty
}

enum DefaultPrompts {
    static let all: [PromptData] = [
        // ============================================
        // Professional Development
        // ============================================
        PromptData(
            id: "prof-1",
            text: "Describe a challenging project you completed and what you learned from it.",
            category: "Professional Development",
            difficulty: .medium
        ),
        PromptData(
            id: "prof-2",
            text: "Explain how you handle feedback and criticism in the workplace.",
            category: "Professional Development",
            difficulty: .medium
        ),
        PromptData(
            id: "prof-3",
            text: "What strategies do you use to stay organized and manage your time effectively?",
            category: "Professional Development",
            difficulty: .easy
        ),
        PromptData(
            id: "prof-4",
            text: "Tell me about a time when you had to adapt to a significant change at work.",
            category: "Professional Development",
            difficulty: .medium
        ),
        PromptData(
            id: "prof-5",
            text: "How do you approach learning new skills or technologies?",
            category: "Professional Development",
            difficulty: .easy
        ),
        PromptData(
            id: "prof-6",
            text: "Describe your ideal work environment and why it helps you be productive.",
            category: "Professional Development",
            difficulty: .easy
        ),
        
        // ============================================
        // Communication Skills
        // ============================================
        PromptData(
            id: "comm-1",
            text: "Explain a complex topic you know well as if you were teaching it to a beginner.",
            category: "Communication Skills",
            difficulty: .hard
        ),
        PromptData(
            id: "comm-2",
            text: "How do you handle disagreements or conflicts in team settings?",
            category: "Communication Skills",
            difficulty: .medium
        ),
        PromptData(
            id: "comm-3",
            text: "Describe a situation where you had to persuade someone to see your point of view.",
            category: "Communication Skills",
            difficulty: .hard
        ),
        PromptData(
            id: "comm-4",
            text: "What techniques do you use to ensure clear communication in remote or virtual settings?",
            category: "Communication Skills",
            difficulty: .medium
        ),
        PromptData(
            id: "comm-5",
            text: "Tell me about a time when miscommunication caused a problem and how you resolved it.",
            category: "Communication Skills",
            difficulty: .medium
        ),
        PromptData(
            id: "comm-6",
            text: "How do you tailor your communication style for different audiences?",
            category: "Communication Skills",
            difficulty: .hard
        ),
        
        // ============================================
        // Personal Growth
        // ============================================
        PromptData(
            id: "pers-1",
            text: "What is a habit you developed that has had a positive impact on your life?",
            category: "Personal Growth",
            difficulty: .easy
        ),
        PromptData(
            id: "pers-2",
            text: "Describe a goal you set for yourself and the steps you took to achieve it.",
            category: "Personal Growth",
            difficulty: .medium
        ),
        PromptData(
            id: "pers-3",
            text: "How do you maintain work-life balance and prevent burnout?",
            category: "Personal Growth",
            difficulty: .medium
        ),
        PromptData(
            id: "pers-4",
            text: "What does success mean to you, and how do you measure it?",
            category: "Personal Growth",
            difficulty: .hard
        ),
        PromptData(
            id: "pers-5",
            text: "Tell me about a failure or setback and what you learned from the experience.",
            category: "Personal Growth",
            difficulty: .medium
        ),
        PromptData(
            id: "pers-6",
            text: "How do you stay motivated when working on long-term projects?",
            category: "Personal Growth",
            difficulty: .easy
        ),
        
        // ============================================
        // Problem Solving
        // ============================================
        PromptData(
            id: "prob-1",
            text: "Walk me through your process for solving a difficult problem.",
            category: "Problem Solving",
            difficulty: .medium
        ),
        PromptData(
            id: "prob-2",
            text: "Describe a time when you had to make a decision with incomplete information.",
            category: "Problem Solving",
            difficulty: .hard
        ),
        PromptData(
            id: "prob-3",
            text: "How do you prioritize tasks when everything seems urgent?",
            category: "Problem Solving",
            difficulty: .medium
        ),
        PromptData(
            id: "prob-4",
            text: "Tell me about a creative solution you developed to overcome an obstacle.",
            category: "Problem Solving",
            difficulty: .hard
        ),
        PromptData(
            id: "prob-5",
            text: "How do you approach troubleshooting when something isn't working as expected?",
            category: "Problem Solving",
            difficulty: .medium
        ),
        PromptData(
            id: "prob-6",
            text: "Describe how you balance analytical thinking with intuition when making decisions.",
            category: "Problem Solving",
            difficulty: .hard
        ),
        
        // ============================================
        // Current Events & Opinions
        // ============================================
        PromptData(
            id: "curr-1",
            text: "What emerging technology do you think will have the biggest impact in the next five years?",
            category: "Current Events & Opinions",
            difficulty: .medium
        ),
        PromptData(
            id: "curr-2",
            text: "How do you stay informed about developments in your field or industry?",
            category: "Current Events & Opinions",
            difficulty: .easy
        ),
        PromptData(
            id: "curr-3",
            text: "What trend or change in society do you find most interesting right now?",
            category: "Current Events & Opinions",
            difficulty: .medium
        ),
        PromptData(
            id: "curr-4",
            text: "How has technology changed the way you work or communicate in recent years?",
            category: "Current Events & Opinions",
            difficulty: .easy
        ),
        PromptData(
            id: "curr-5",
            text: "What skill do you think will be most valuable for future career success?",
            category: "Current Events & Opinions",
            difficulty: .medium
        ),
        PromptData(
            id: "curr-6",
            text: "How do you evaluate the credibility of information you encounter online?",
            category: "Current Events & Opinions",
            difficulty: .medium
        ),
        
        // ============================================
        // Quick Fire (Easy - great for warm-ups)
        // ============================================
        PromptData(
            id: "quick-1",
            text: "What did you do this morning before coming here?",
            category: "Quick Fire",
            difficulty: .easy
        ),
        PromptData(
            id: "quick-2",
            text: "Describe your favorite meal and why you enjoy it.",
            category: "Quick Fire",
            difficulty: .easy
        ),
        PromptData(
            id: "quick-3",
            text: "What is one thing you are grateful for today?",
            category: "Quick Fire",
            difficulty: .easy
        ),
        PromptData(
            id: "quick-4",
            text: "Tell me about a hobby or interest you have outside of work.",
            category: "Quick Fire",
            difficulty: .easy
        ),
        PromptData(
            id: "quick-5",
            text: "What is the last book, movie, or show you enjoyed and why?",
            category: "Quick Fire",
            difficulty: .easy
        ),
        
        // ============================================
        // Debate & Persuasion (Hard - impromptu arguments)
        // ============================================
        PromptData(
            id: "debate-1",
            text: "Argue for or against: Remote work is better than working in an office.",
            category: "Debate & Persuasion",
            difficulty: .hard
        ),
        PromptData(
            id: "debate-2",
            text: "Make a case for why your favorite city is the best place to live.",
            category: "Debate & Persuasion",
            difficulty: .hard
        ),
        PromptData(
            id: "debate-3",
            text: "Convince me to try something you are passionate about.",
            category: "Debate & Persuasion",
            difficulty: .hard
        ),
        PromptData(
            id: "debate-4",
            text: "Argue for or against: Social media has done more harm than good.",
            category: "Debate & Persuasion",
            difficulty: .hard
        ),
        PromptData(
            id: "debate-5",
            text: "Defend an unpopular opinion you hold (or play devil's advocate).",
            category: "Debate & Persuasion",
            difficulty: .hard
        ),
    ]
    
    // MARK: - Helper Functions
    
    static func getRandomPrompt() -> PromptData {
        all.randomElement()!
    }
    
    static func getPromptsByCategory(_ category: String) -> [PromptData] {
        all.filter { $0.category == category }
    }
    
    static func getPromptsByDifficulty(_ difficulty: PromptDifficulty) -> [PromptData] {
        all.filter { $0.difficulty == difficulty }
    }
    
    static var allCategories: [String] {
        Array(Set(all.map { $0.category })).sorted()
    }
    
    static func getTodaysPrompt() -> PromptData {
        // Use date as seed for consistent daily prompt
        let today = Calendar.current.startOfDay(for: Date())
        let components = Calendar.current.dateComponents([.year, .month, .day], from: today)
        let seed = (components.year ?? 0) + (components.month ?? 0) + (components.day ?? 0)
        let index = seed % all.count
        return all[index]
    }
}
