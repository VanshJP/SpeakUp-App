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

        // ============================================
        // Interview Prep
        // ============================================
        PromptData(
            id: "intv-1",
            text: "Tell me about yourself and what makes you a great fit for this role.",
            category: "Interview Prep",
            difficulty: .medium
        ),
        PromptData(
            id: "intv-2",
            text: "What is your greatest strength and how has it helped you professionally?",
            category: "Interview Prep",
            difficulty: .easy
        ),
        PromptData(
            id: "intv-3",
            text: "Describe a time when you led a team through a difficult situation.",
            category: "Interview Prep",
            difficulty: .hard
        ),
        PromptData(
            id: "intv-4",
            text: "Where do you see yourself in five years?",
            category: "Interview Prep",
            difficulty: .medium
        ),
        PromptData(
            id: "intv-5",
            text: "Why are you interested in this company and this position?",
            category: "Interview Prep",
            difficulty: .medium
        ),
        PromptData(
            id: "intv-6",
            text: "Tell me about a time you disagreed with your manager and how you handled it.",
            category: "Interview Prep",
            difficulty: .hard
        ),
        PromptData(
            id: "intv-7",
            text: "What is your approach to handling tight deadlines and multiple priorities?",
            category: "Interview Prep",
            difficulty: .medium
        ),
        PromptData(
            id: "intv-8",
            text: "Describe a project you are most proud of and your role in it.",
            category: "Interview Prep",
            difficulty: .medium
        ),
        PromptData(
            id: "intv-9",
            text: "How do you handle receiving negative feedback?",
            category: "Interview Prep",
            difficulty: .medium
        ),
        PromptData(
            id: "intv-10",
            text: "What questions do you have for us about the role or company?",
            category: "Interview Prep",
            difficulty: .easy
        ),

        // ============================================
        // Storytelling
        // ============================================
        PromptData(
            id: "story-1",
            text: "Tell a story about a moment that changed your perspective on life.",
            category: "Storytelling",
            difficulty: .medium
        ),
        PromptData(
            id: "story-2",
            text: "Describe the most memorable trip or adventure you have ever had.",
            category: "Storytelling",
            difficulty: .easy
        ),
        PromptData(
            id: "story-3",
            text: "Tell a story about someone who inspired you and how they changed your path.",
            category: "Storytelling",
            difficulty: .medium
        ),
        PromptData(
            id: "story-4",
            text: "Narrate an experience where you overcame a fear.",
            category: "Storytelling",
            difficulty: .hard
        ),
        PromptData(
            id: "story-5",
            text: "Tell a funny story from your childhood that your family still talks about.",
            category: "Storytelling",
            difficulty: .easy
        ),
        PromptData(
            id: "story-6",
            text: "Describe a time when something went completely wrong but turned out well.",
            category: "Storytelling",
            difficulty: .medium
        ),
        PromptData(
            id: "story-7",
            text: "Tell a story about an unexpected friendship you formed.",
            category: "Storytelling",
            difficulty: .easy
        ),
        PromptData(
            id: "story-8",
            text: "Narrate a lesson you learned the hard way.",
            category: "Storytelling",
            difficulty: .medium
        ),

        // ============================================
        // Elevator Pitch
        // ============================================
        PromptData(
            id: "pitch-1",
            text: "Pitch yourself to a potential employer in 60 seconds.",
            category: "Elevator Pitch",
            difficulty: .hard
        ),
        PromptData(
            id: "pitch-2",
            text: "Pitch an app idea that solves a problem you face every day.",
            category: "Elevator Pitch",
            difficulty: .hard
        ),
        PromptData(
            id: "pitch-3",
            text: "Pitch your favorite hobby as if you were convincing an investor to fund it.",
            category: "Elevator Pitch",
            difficulty: .medium
        ),
        PromptData(
            id: "pitch-4",
            text: "Pitch a new product to an audience of busy executives.",
            category: "Elevator Pitch",
            difficulty: .hard
        ),
        PromptData(
            id: "pitch-5",
            text: "Pitch your dream company: what it does, why it matters, and why now.",
            category: "Elevator Pitch",
            difficulty: .hard
        ),
        PromptData(
            id: "pitch-6",
            text: "Pitch a social cause you care about and what people can do to help.",
            category: "Elevator Pitch",
            difficulty: .medium
        ),
        PromptData(
            id: "pitch-7",
            text: "Summarize the value of your current job to someone who has never heard of your industry.",
            category: "Elevator Pitch",
            difficulty: .medium
        ),

        // ============================================
        // Additional Professional Development
        // ============================================
        PromptData(
            id: "prof-7",
            text: "How would you explain your biggest career achievement to a stranger?",
            category: "Professional Development",
            difficulty: .medium
        ),
        PromptData(
            id: "prof-8",
            text: "What is the most important lesson you have learned from a mentor?",
            category: "Professional Development",
            difficulty: .easy
        ),
        PromptData(
            id: "prof-9",
            text: "How do you build trust with colleagues or clients?",
            category: "Professional Development",
            difficulty: .medium
        ),
        PromptData(
            id: "prof-10",
            text: "Describe your approach to giving constructive criticism.",
            category: "Professional Development",
            difficulty: .hard
        ),

        // ============================================
        // Additional Communication Skills
        // ============================================
        PromptData(
            id: "comm-7",
            text: "How do you make yourself understood when discussing a controversial topic?",
            category: "Communication Skills",
            difficulty: .hard
        ),
        PromptData(
            id: "comm-8",
            text: "Describe a time you had to deliver bad news and how you approached it.",
            category: "Communication Skills",
            difficulty: .hard
        ),
        PromptData(
            id: "comm-9",
            text: "What role does active listening play in effective communication?",
            category: "Communication Skills",
            difficulty: .medium
        ),
        PromptData(
            id: "comm-10",
            text: "How do you handle speaking to a large group versus a small one?",
            category: "Communication Skills",
            difficulty: .medium
        ),

        // ============================================
        // Additional Personal Growth
        // ============================================
        PromptData(
            id: "pers-7",
            text: "What would you tell your younger self about life?",
            category: "Personal Growth",
            difficulty: .easy
        ),
        PromptData(
            id: "pers-8",
            text: "Describe a book or podcast that changed the way you think.",
            category: "Personal Growth",
            difficulty: .easy
        ),
        PromptData(
            id: "pers-9",
            text: "How do you handle uncertainty and ambiguity in your life?",
            category: "Personal Growth",
            difficulty: .hard
        ),
        PromptData(
            id: "pers-10",
            text: "What does being courageous mean to you? Give an example.",
            category: "Personal Growth",
            difficulty: .medium
        ),

        // ============================================
        // Additional Problem Solving
        // ============================================
        PromptData(
            id: "prob-7",
            text: "Describe a time you had to solve a problem with limited resources.",
            category: "Problem Solving",
            difficulty: .hard
        ),
        PromptData(
            id: "prob-8",
            text: "How do you evaluate different options when making a major decision?",
            category: "Problem Solving",
            difficulty: .medium
        ),
        PromptData(
            id: "prob-9",
            text: "Tell me about a time you anticipated a problem before it happened.",
            category: "Problem Solving",
            difficulty: .hard
        ),
        PromptData(
            id: "prob-10",
            text: "How do you stay calm and focused when a plan falls apart?",
            category: "Problem Solving",
            difficulty: .medium
        ),

        // ============================================
        // Additional Current Events
        // ============================================
        PromptData(
            id: "curr-7",
            text: "What role should AI play in everyday life? Where should we draw the line?",
            category: "Current Events & Opinions",
            difficulty: .hard
        ),
        PromptData(
            id: "curr-8",
            text: "What change in education do you think would have the biggest impact on society?",
            category: "Current Events & Opinions",
            difficulty: .medium
        ),
        PromptData(
            id: "curr-9",
            text: "Is it important for professionals to have a personal brand? Why or why not?",
            category: "Current Events & Opinions",
            difficulty: .medium
        ),
        PromptData(
            id: "curr-10",
            text: "How do you think work culture will change in the next decade?",
            category: "Current Events & Opinions",
            difficulty: .medium
        ),

        // ============================================
        // Additional Quick Fire
        // ============================================
        PromptData(
            id: "quick-6",
            text: "If you could have dinner with anyone in history, who and why?",
            category: "Quick Fire",
            difficulty: .easy
        ),
        PromptData(
            id: "quick-7",
            text: "Describe your perfect weekend in one minute.",
            category: "Quick Fire",
            difficulty: .easy
        ),
        PromptData(
            id: "quick-8",
            text: "What is a small thing that always makes your day better?",
            category: "Quick Fire",
            difficulty: .easy
        ),
        PromptData(
            id: "quick-9",
            text: "Name three things you could not live without and explain why.",
            category: "Quick Fire",
            difficulty: .easy
        ),
        PromptData(
            id: "quick-10",
            text: "What is the best piece of advice you have ever received?",
            category: "Quick Fire",
            difficulty: .easy
        ),

        // ============================================
        // Additional Debate & Persuasion
        // ============================================
        PromptData(
            id: "debate-6",
            text: "Argue for or against: Everyone should learn to code.",
            category: "Debate & Persuasion",
            difficulty: .hard
        ),
        PromptData(
            id: "debate-7",
            text: "Make the case that failure is more valuable than success.",
            category: "Debate & Persuasion",
            difficulty: .hard
        ),
        PromptData(
            id: "debate-8",
            text: "Argue for or against: A four-day work week should be the standard.",
            category: "Debate & Persuasion",
            difficulty: .hard
        ),
        PromptData(
            id: "debate-9",
            text: "Convince someone to adopt a healthier lifestyle in 90 seconds.",
            category: "Debate & Persuasion",
            difficulty: .medium
        ),
        PromptData(
            id: "debate-10",
            text: "Argue for or against: University education is overrated.",
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
