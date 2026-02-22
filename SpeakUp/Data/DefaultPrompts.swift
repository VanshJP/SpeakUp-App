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

        // ============================================
        // Professional Development (Expanded)
        // ============================================
        PromptData(
            id: "prof-11",
            text: "How do you handle imposter syndrome in your career?",
            category: "Professional Development",
            difficulty: .medium
        ),
        PromptData(
            id: "prof-12",
            text: "Describe a time you had to lead without formal authority.",
            category: "Professional Development",
            difficulty: .hard
        ),
        PromptData(
            id: "prof-13",
            text: "What is the most difficult decision you have made in your career?",
            category: "Professional Development",
            difficulty: .hard
        ),
        PromptData(
            id: "prof-14",
            text: "How do you approach networking and building professional relationships?",
            category: "Professional Development",
            difficulty: .medium
        ),
        PromptData(
            id: "prof-15",
            text: "Describe a time you had to deliver results under extreme pressure.",
            category: "Professional Development",
            difficulty: .hard
        ),
        PromptData(
            id: "prof-16",
            text: "What role does creativity play in your professional life?",
            category: "Professional Development",
            difficulty: .medium
        ),
        PromptData(
            id: "prof-17",
            text: "How do you keep yourself accountable for your professional goals?",
            category: "Professional Development",
            difficulty: .easy
        ),
        PromptData(
            id: "prof-18",
            text: "Tell me about a time you took a risk in your career. Was it worth it?",
            category: "Professional Development",
            difficulty: .hard
        ),
        PromptData(
            id: "prof-19",
            text: "How do you deal with workplace politics without compromising your values?",
            category: "Professional Development",
            difficulty: .hard
        ),
        PromptData(
            id: "prof-20",
            text: "What is one professional skill you wish you had developed earlier?",
            category: "Professional Development",
            difficulty: .easy
        ),
        PromptData(
            id: "prof-21",
            text: "Describe how you onboard yourself when starting a new role or project.",
            category: "Professional Development",
            difficulty: .medium
        ),
        PromptData(
            id: "prof-22",
            text: "How do you manage up — keeping your manager informed and aligned?",
            category: "Professional Development",
            difficulty: .medium
        ),
        PromptData(
            id: "prof-23",
            text: "What does ethical leadership look like to you?",
            category: "Professional Development",
            difficulty: .hard
        ),
        PromptData(
            id: "prof-24",
            text: "How do you stay productive during periods of low motivation?",
            category: "Professional Development",
            difficulty: .medium
        ),
        PromptData(
            id: "prof-25",
            text: "Describe a time you had to say no to an opportunity. Why did you turn it down?",
            category: "Professional Development",
            difficulty: .medium
        ),

        // ============================================
        // Communication Skills (Expanded)
        // ============================================
        PromptData(
            id: "comm-11",
            text: "How do you give feedback that is honest but still encouraging?",
            category: "Communication Skills",
            difficulty: .hard
        ),
        PromptData(
            id: "comm-12",
            text: "Describe a time you had to simplify a technical topic for a non-technical audience.",
            category: "Communication Skills",
            difficulty: .hard
        ),
        PromptData(
            id: "comm-13",
            text: "What is your approach to having difficult or uncomfortable conversations?",
            category: "Communication Skills",
            difficulty: .hard
        ),
        PromptData(
            id: "comm-14",
            text: "How do you make sure everyone in a meeting gets a chance to speak?",
            category: "Communication Skills",
            difficulty: .medium
        ),
        PromptData(
            id: "comm-15",
            text: "Describe a time you had to apologize professionally. How did you handle it?",
            category: "Communication Skills",
            difficulty: .medium
        ),
        PromptData(
            id: "comm-16",
            text: "How do you communicate urgency without creating panic?",
            category: "Communication Skills",
            difficulty: .hard
        ),
        PromptData(
            id: "comm-17",
            text: "What strategies do you use to keep an audience engaged during a long presentation?",
            category: "Communication Skills",
            difficulty: .hard
        ),
        PromptData(
            id: "comm-18",
            text: "How do you approach writing an email about a sensitive topic?",
            category: "Communication Skills",
            difficulty: .medium
        ),
        PromptData(
            id: "comm-19",
            text: "Describe a time you used humor effectively to make a point.",
            category: "Communication Skills",
            difficulty: .medium
        ),
        PromptData(
            id: "comm-20",
            text: "How do you build rapport with someone you have just met?",
            category: "Communication Skills",
            difficulty: .easy
        ),
        PromptData(
            id: "comm-21",
            text: "What is the difference between hearing and listening? Give an example.",
            category: "Communication Skills",
            difficulty: .medium
        ),
        PromptData(
            id: "comm-22",
            text: "How do you recover when you lose your train of thought mid-sentence?",
            category: "Communication Skills",
            difficulty: .medium
        ),
        PromptData(
            id: "comm-23",
            text: "Describe how you would mediate a disagreement between two colleagues.",
            category: "Communication Skills",
            difficulty: .hard
        ),
        PromptData(
            id: "comm-24",
            text: "How do you ask questions that encourage deeper conversation?",
            category: "Communication Skills",
            difficulty: .medium
        ),
        PromptData(
            id: "comm-25",
            text: "What body language cues do you pay attention to when speaking with someone?",
            category: "Communication Skills",
            difficulty: .easy
        ),

        // ============================================
        // Personal Growth (Expanded)
        // ============================================
        PromptData(
            id: "pers-11",
            text: "What is a belief you held strongly but later changed your mind about?",
            category: "Personal Growth",
            difficulty: .hard
        ),
        PromptData(
            id: "pers-12",
            text: "How do you deal with loneliness or isolation?",
            category: "Personal Growth",
            difficulty: .medium
        ),
        PromptData(
            id: "pers-13",
            text: "What daily routine or ritual keeps you grounded?",
            category: "Personal Growth",
            difficulty: .easy
        ),
        PromptData(
            id: "pers-14",
            text: "Describe a time you stepped outside your comfort zone. What happened?",
            category: "Personal Growth",
            difficulty: .medium
        ),
        PromptData(
            id: "pers-15",
            text: "How do you forgive yourself after making a mistake?",
            category: "Personal Growth",
            difficulty: .hard
        ),
        PromptData(
            id: "pers-16",
            text: "What role does gratitude play in your life?",
            category: "Personal Growth",
            difficulty: .easy
        ),
        PromptData(
            id: "pers-17",
            text: "How do you set boundaries with people you care about?",
            category: "Personal Growth",
            difficulty: .hard
        ),
        PromptData(
            id: "pers-18",
            text: "What is something you are currently working on improving about yourself?",
            category: "Personal Growth",
            difficulty: .easy
        ),
        PromptData(
            id: "pers-19",
            text: "Describe a relationship that taught you something important about yourself.",
            category: "Personal Growth",
            difficulty: .medium
        ),
        PromptData(
            id: "pers-20",
            text: "How do you define happiness, and has your definition changed over time?",
            category: "Personal Growth",
            difficulty: .hard
        ),
        PromptData(
            id: "pers-21",
            text: "What is the hardest truth you have had to accept?",
            category: "Personal Growth",
            difficulty: .hard
        ),
        PromptData(
            id: "pers-22",
            text: "How do you recharge after a mentally exhausting week?",
            category: "Personal Growth",
            difficulty: .easy
        ),
        PromptData(
            id: "pers-23",
            text: "What values guide your decision-making in life?",
            category: "Personal Growth",
            difficulty: .medium
        ),
        PromptData(
            id: "pers-24",
            text: "Describe a time you chose the harder right over the easier wrong.",
            category: "Personal Growth",
            difficulty: .hard
        ),
        PromptData(
            id: "pers-25",
            text: "How do you celebrate small wins in your life?",
            category: "Personal Growth",
            difficulty: .easy
        ),

        // ============================================
        // Problem Solving (Expanded)
        // ============================================
        PromptData(
            id: "prob-11",
            text: "Describe a time you had to convince others to change their approach to a problem.",
            category: "Problem Solving",
            difficulty: .hard
        ),
        PromptData(
            id: "prob-12",
            text: "How do you break down an overwhelming task into manageable steps?",
            category: "Problem Solving",
            difficulty: .medium
        ),
        PromptData(
            id: "prob-13",
            text: "Tell me about a time you failed to solve a problem. What did you learn?",
            category: "Problem Solving",
            difficulty: .hard
        ),
        PromptData(
            id: "prob-14",
            text: "How do you involve others in the problem-solving process?",
            category: "Problem Solving",
            difficulty: .medium
        ),
        PromptData(
            id: "prob-15",
            text: "Describe a situation where the obvious solution turned out to be wrong.",
            category: "Problem Solving",
            difficulty: .hard
        ),
        PromptData(
            id: "prob-16",
            text: "How do you distinguish between symptoms and root causes of a problem?",
            category: "Problem Solving",
            difficulty: .hard
        ),
        PromptData(
            id: "prob-17",
            text: "Tell me about a time you automated or streamlined a repetitive process.",
            category: "Problem Solving",
            difficulty: .medium
        ),
        PromptData(
            id: "prob-18",
            text: "How do you handle conflicting priorities from different stakeholders?",
            category: "Problem Solving",
            difficulty: .hard
        ),
        PromptData(
            id: "prob-19",
            text: "Describe a problem you solved by looking at it from a completely different angle.",
            category: "Problem Solving",
            difficulty: .hard
        ),
        PromptData(
            id: "prob-20",
            text: "What frameworks or mental models do you use to make better decisions?",
            category: "Problem Solving",
            difficulty: .medium
        ),
        PromptData(
            id: "prob-21",
            text: "How do you know when to stop researching and start acting?",
            category: "Problem Solving",
            difficulty: .medium
        ),
        PromptData(
            id: "prob-22",
            text: "Describe a time you turned a constraint into an advantage.",
            category: "Problem Solving",
            difficulty: .hard
        ),
        PromptData(
            id: "prob-23",
            text: "How do you handle a situation where two good options conflict with each other?",
            category: "Problem Solving",
            difficulty: .hard
        ),
        PromptData(
            id: "prob-24",
            text: "Tell me about a time you had to fix someone else's mistake diplomatically.",
            category: "Problem Solving",
            difficulty: .medium
        ),
        PromptData(
            id: "prob-25",
            text: "What is your process for learning from post-mortems or retrospectives?",
            category: "Problem Solving",
            difficulty: .medium
        ),

        // ============================================
        // Current Events & Opinions (Expanded)
        // ============================================
        PromptData(
            id: "curr-11",
            text: "How do you think climate change should be addressed at the individual level?",
            category: "Current Events & Opinions",
            difficulty: .hard
        ),
        PromptData(
            id: "curr-12",
            text: "What is a recent news story that surprised you and why?",
            category: "Current Events & Opinions",
            difficulty: .medium
        ),
        PromptData(
            id: "curr-13",
            text: "Do you think social media platforms should be regulated? Explain your position.",
            category: "Current Events & Opinions",
            difficulty: .hard
        ),
        PromptData(
            id: "curr-14",
            text: "How has the gig economy changed the way people think about work?",
            category: "Current Events & Opinions",
            difficulty: .medium
        ),
        PromptData(
            id: "curr-15",
            text: "What is one global issue you think deserves more attention?",
            category: "Current Events & Opinions",
            difficulty: .medium
        ),
        PromptData(
            id: "curr-16",
            text: "How do you think automation will affect jobs in your industry?",
            category: "Current Events & Opinions",
            difficulty: .hard
        ),
        PromptData(
            id: "curr-17",
            text: "Should companies take public stances on social and political issues? Why or why not?",
            category: "Current Events & Opinions",
            difficulty: .hard
        ),
        PromptData(
            id: "curr-18",
            text: "What is one thing you would change about the education system?",
            category: "Current Events & Opinions",
            difficulty: .medium
        ),
        PromptData(
            id: "curr-19",
            text: "How do you think the rise of streaming has changed entertainment and culture?",
            category: "Current Events & Opinions",
            difficulty: .easy
        ),
        PromptData(
            id: "curr-20",
            text: "What responsibility do tech companies have to protect user privacy?",
            category: "Current Events & Opinions",
            difficulty: .hard
        ),
        PromptData(
            id: "curr-21",
            text: "How has your generation's experience been different from your parents' generation?",
            category: "Current Events & Opinions",
            difficulty: .medium
        ),
        PromptData(
            id: "curr-22",
            text: "What does ethical consumption mean to you in today's economy?",
            category: "Current Events & Opinions",
            difficulty: .hard
        ),
        PromptData(
            id: "curr-23",
            text: "How do you think cities should adapt to be more livable in the future?",
            category: "Current Events & Opinions",
            difficulty: .medium
        ),
        PromptData(
            id: "curr-24",
            text: "What is the most important quality in a leader today?",
            category: "Current Events & Opinions",
            difficulty: .medium
        ),
        PromptData(
            id: "curr-25",
            text: "How do you think mental health awareness has changed in recent years?",
            category: "Current Events & Opinions",
            difficulty: .easy
        ),

        // ============================================
        // Quick Fire (Expanded)
        // ============================================
        PromptData(
            id: "quick-11",
            text: "What song always puts you in a good mood?",
            category: "Quick Fire",
            difficulty: .easy
        ),
        PromptData(
            id: "quick-12",
            text: "If you could live anywhere in the world for a year, where would you go?",
            category: "Quick Fire",
            difficulty: .easy
        ),
        PromptData(
            id: "quick-13",
            text: "What is a skill you have always wanted to learn but never started?",
            category: "Quick Fire",
            difficulty: .easy
        ),
        PromptData(
            id: "quick-14",
            text: "Describe your morning routine in 30 seconds.",
            category: "Quick Fire",
            difficulty: .easy
        ),
        PromptData(
            id: "quick-15",
            text: "If you had an extra hour every day, how would you spend it?",
            category: "Quick Fire",
            difficulty: .easy
        ),
        PromptData(
            id: "quick-16",
            text: "What is the most interesting thing you have learned recently?",
            category: "Quick Fire",
            difficulty: .easy
        ),
        PromptData(
            id: "quick-17",
            text: "What is your go-to comfort food and why?",
            category: "Quick Fire",
            difficulty: .easy
        ),
        PromptData(
            id: "quick-18",
            text: "If you could master any musical instrument overnight, which would you choose?",
            category: "Quick Fire",
            difficulty: .easy
        ),
        PromptData(
            id: "quick-19",
            text: "What is one thing on your bucket list you plan to do this year?",
            category: "Quick Fire",
            difficulty: .easy
        ),
        PromptData(
            id: "quick-20",
            text: "Describe your personality in three words and explain each one.",
            category: "Quick Fire",
            difficulty: .easy
        ),
        PromptData(
            id: "quick-21",
            text: "What is the best gift you have ever received?",
            category: "Quick Fire",
            difficulty: .easy
        ),
        PromptData(
            id: "quick-22",
            text: "If you could relive one day from your past, which day would it be?",
            category: "Quick Fire",
            difficulty: .easy
        ),
        PromptData(
            id: "quick-23",
            text: "What is your favorite season and what do you love about it?",
            category: "Quick Fire",
            difficulty: .easy
        ),
        PromptData(
            id: "quick-24",
            text: "What is something most people do not know about you?",
            category: "Quick Fire",
            difficulty: .easy
        ),
        PromptData(
            id: "quick-25",
            text: "If you could swap jobs with anyone for a week, who would it be?",
            category: "Quick Fire",
            difficulty: .easy
        ),

        // ============================================
        // Debate & Persuasion (Expanded)
        // ============================================
        PromptData(
            id: "debate-11",
            text: "Argue for or against: Privacy is more important than security.",
            category: "Debate & Persuasion",
            difficulty: .hard
        ),
        PromptData(
            id: "debate-12",
            text: "Make the case that reading fiction makes you a better leader.",
            category: "Debate & Persuasion",
            difficulty: .hard
        ),
        PromptData(
            id: "debate-13",
            text: "Argue for or against: Grades are an accurate measure of intelligence.",
            category: "Debate & Persuasion",
            difficulty: .hard
        ),
        PromptData(
            id: "debate-14",
            text: "Convince someone to volunteer their time for a cause.",
            category: "Debate & Persuasion",
            difficulty: .medium
        ),
        PromptData(
            id: "debate-15",
            text: "Argue for or against: Money can buy happiness.",
            category: "Debate & Persuasion",
            difficulty: .hard
        ),
        PromptData(
            id: "debate-16",
            text: "Make the case that travel is the best form of education.",
            category: "Debate & Persuasion",
            difficulty: .medium
        ),
        PromptData(
            id: "debate-17",
            text: "Argue for or against: It is better to be a generalist than a specialist.",
            category: "Debate & Persuasion",
            difficulty: .hard
        ),
        PromptData(
            id: "debate-18",
            text: "Convince a skeptic that public speaking is a skill worth developing.",
            category: "Debate & Persuasion",
            difficulty: .medium
        ),
        PromptData(
            id: "debate-19",
            text: "Argue for or against: Artificial intelligence will create more jobs than it destroys.",
            category: "Debate & Persuasion",
            difficulty: .hard
        ),
        PromptData(
            id: "debate-20",
            text: "Make the case that physical books are better than e-books.",
            category: "Debate & Persuasion",
            difficulty: .medium
        ),
        PromptData(
            id: "debate-21",
            text: "Argue for or against: Everyone should take a gap year before college.",
            category: "Debate & Persuasion",
            difficulty: .hard
        ),
        PromptData(
            id: "debate-22",
            text: "Convince someone to delete their social media accounts for a month.",
            category: "Debate & Persuasion",
            difficulty: .medium
        ),
        PromptData(
            id: "debate-23",
            text: "Argue for or against: Homework should be abolished in schools.",
            category: "Debate & Persuasion",
            difficulty: .hard
        ),
        PromptData(
            id: "debate-24",
            text: "Make the case that cooking at home is always better than eating out.",
            category: "Debate & Persuasion",
            difficulty: .medium
        ),
        PromptData(
            id: "debate-25",
            text: "Argue for or against: History is the most important school subject.",
            category: "Debate & Persuasion",
            difficulty: .hard
        ),

        // ============================================
        // Interview Prep (Expanded)
        // ============================================
        PromptData(
            id: "intv-11",
            text: "What would your previous manager say is your biggest area for improvement?",
            category: "Interview Prep",
            difficulty: .hard
        ),
        PromptData(
            id: "intv-12",
            text: "Tell me about a time you went above and beyond what was expected.",
            category: "Interview Prep",
            difficulty: .medium
        ),
        PromptData(
            id: "intv-13",
            text: "How do you handle a situation where you disagree with a company policy?",
            category: "Interview Prep",
            difficulty: .hard
        ),
        PromptData(
            id: "intv-14",
            text: "What motivates you to do your best work every day?",
            category: "Interview Prep",
            difficulty: .easy
        ),
        PromptData(
            id: "intv-15",
            text: "Describe a time you had to learn something completely new in a short period.",
            category: "Interview Prep",
            difficulty: .medium
        ),
        PromptData(
            id: "intv-16",
            text: "How do you handle working with someone whose style is very different from yours?",
            category: "Interview Prep",
            difficulty: .medium
        ),
        PromptData(
            id: "intv-17",
            text: "Tell me about a time you had to manage competing stakeholder expectations.",
            category: "Interview Prep",
            difficulty: .hard
        ),
        PromptData(
            id: "intv-18",
            text: "What is your approach to setting and tracking goals?",
            category: "Interview Prep",
            difficulty: .easy
        ),
        PromptData(
            id: "intv-19",
            text: "Describe a situation where you had to work with ambiguous requirements.",
            category: "Interview Prep",
            difficulty: .hard
        ),
        PromptData(
            id: "intv-20",
            text: "How do you ensure quality in your work when under time pressure?",
            category: "Interview Prep",
            difficulty: .medium
        ),
        PromptData(
            id: "intv-21",
            text: "Tell me about a cross-functional project you contributed to.",
            category: "Interview Prep",
            difficulty: .medium
        ),
        PromptData(
            id: "intv-22",
            text: "What makes you unique compared to other candidates for this role?",
            category: "Interview Prep",
            difficulty: .hard
        ),
        PromptData(
            id: "intv-23",
            text: "Describe how you handled a situation where a project was falling behind schedule.",
            category: "Interview Prep",
            difficulty: .hard
        ),
        PromptData(
            id: "intv-24",
            text: "What type of manager brings out the best in you?",
            category: "Interview Prep",
            difficulty: .easy
        ),
        PromptData(
            id: "intv-25",
            text: "Tell me about a time you mentored or coached someone.",
            category: "Interview Prep",
            difficulty: .medium
        ),

        // ============================================
        // Storytelling (Expanded)
        // ============================================
        PromptData(
            id: "story-9",
            text: "Tell a story about the strangest coincidence you have ever experienced.",
            category: "Storytelling",
            difficulty: .medium
        ),
        PromptData(
            id: "story-10",
            text: "Narrate the story of how you ended up in your current career or field.",
            category: "Storytelling",
            difficulty: .medium
        ),
        PromptData(
            id: "story-11",
            text: "Tell a story about a time you helped a stranger.",
            category: "Storytelling",
            difficulty: .easy
        ),
        PromptData(
            id: "story-12",
            text: "Describe a moment when you felt truly proud of someone else.",
            category: "Storytelling",
            difficulty: .easy
        ),
        PromptData(
            id: "story-13",
            text: "Tell the story of your most embarrassing moment and how you handled it.",
            category: "Storytelling",
            difficulty: .medium
        ),
        PromptData(
            id: "story-14",
            text: "Narrate a time when a small act of kindness had a big impact on you.",
            category: "Storytelling",
            difficulty: .easy
        ),
        PromptData(
            id: "story-15",
            text: "Tell a story about a tradition in your family or culture that means a lot to you.",
            category: "Storytelling",
            difficulty: .medium
        ),
        PromptData(
            id: "story-16",
            text: "Describe a time you witnessed something beautiful or awe-inspiring.",
            category: "Storytelling",
            difficulty: .easy
        ),
        PromptData(
            id: "story-17",
            text: "Tell the story of the best day of your life so far.",
            category: "Storytelling",
            difficulty: .medium
        ),
        PromptData(
            id: "story-18",
            text: "Narrate an experience that taught you something about a different culture.",
            category: "Storytelling",
            difficulty: .medium
        ),
        PromptData(
            id: "story-19",
            text: "Tell a story about a time technology failed you at the worst possible moment.",
            category: "Storytelling",
            difficulty: .easy
        ),
        PromptData(
            id: "story-20",
            text: "Describe a conversation that completely changed the way you see the world.",
            category: "Storytelling",
            difficulty: .hard
        ),
        PromptData(
            id: "story-21",
            text: "Tell the story of a pet or animal that left a lasting impression on you.",
            category: "Storytelling",
            difficulty: .easy
        ),
        PromptData(
            id: "story-22",
            text: "Narrate a time you had to start over from scratch.",
            category: "Storytelling",
            difficulty: .hard
        ),
        PromptData(
            id: "story-23",
            text: "Tell a story about a promise you made and how you kept it.",
            category: "Storytelling",
            difficulty: .medium
        ),

        // ============================================
        // Elevator Pitch (Expanded)
        // ============================================
        PromptData(
            id: "pitch-8",
            text: "Pitch a business idea that would improve your local community.",
            category: "Elevator Pitch",
            difficulty: .hard
        ),
        PromptData(
            id: "pitch-9",
            text: "Pitch your favorite book as if it were a movie to a Hollywood producer.",
            category: "Elevator Pitch",
            difficulty: .medium
        ),
        PromptData(
            id: "pitch-10",
            text: "Sell a mundane everyday object as if it were revolutionary.",
            category: "Elevator Pitch",
            difficulty: .hard
        ),
        PromptData(
            id: "pitch-11",
            text: "Pitch a new holiday and explain why it should be celebrated.",
            category: "Elevator Pitch",
            difficulty: .medium
        ),
        PromptData(
            id: "pitch-12",
            text: "Pitch a subscription service for something that does not currently have one.",
            category: "Elevator Pitch",
            difficulty: .hard
        ),
        PromptData(
            id: "pitch-13",
            text: "Pitch your city or town to someone thinking of moving there.",
            category: "Elevator Pitch",
            difficulty: .easy
        ),
        PromptData(
            id: "pitch-14",
            text: "Pitch a new school subject that you think every student should take.",
            category: "Elevator Pitch",
            difficulty: .medium
        ),
        PromptData(
            id: "pitch-15",
            text: "Pitch yourself as the ideal candidate for your dream job in 60 seconds.",
            category: "Elevator Pitch",
            difficulty: .hard
        ),
        PromptData(
            id: "pitch-16",
            text: "Pitch a restaurant concept to a panel of investors.",
            category: "Elevator Pitch",
            difficulty: .hard
        ),
        PromptData(
            id: "pitch-17",
            text: "Pitch a volunteer program that would attract young professionals.",
            category: "Elevator Pitch",
            difficulty: .medium
        ),
        PromptData(
            id: "pitch-18",
            text: "Pitch a solution to reduce food waste in your city.",
            category: "Elevator Pitch",
            difficulty: .hard
        ),
        PromptData(
            id: "pitch-19",
            text: "Pitch a wellness habit to a friend who is always busy.",
            category: "Elevator Pitch",
            difficulty: .easy
        ),
        PromptData(
            id: "pitch-20",
            text: "Pitch a creative team-building activity for a remote company.",
            category: "Elevator Pitch",
            difficulty: .medium
        ),
        PromptData(
            id: "pitch-21",
            text: "Pitch an idea for a podcast and explain who would listen.",
            category: "Elevator Pitch",
            difficulty: .medium
        ),
        PromptData(
            id: "pitch-22",
            text: "Pitch a mobile app that helps people build better habits.",
            category: "Elevator Pitch",
            difficulty: .hard
        ),

        // ============================================
        // Professional Development (More)
        // ============================================
        PromptData(
            id: "prof-26",
            text: "How do you navigate the balance between perfectionism and getting things done?",
            category: "Professional Development",
            difficulty: .hard
        ),
        PromptData(
            id: "prof-27",
            text: "Describe a time you inherited a messy project. How did you turn it around?",
            category: "Professional Development",
            difficulty: .hard
        ),
        PromptData(
            id: "prof-28",
            text: "What is the most underrated skill in your profession?",
            category: "Professional Development",
            difficulty: .medium
        ),
        PromptData(
            id: "prof-29",
            text: "How do you decide when it is time to leave a job or opportunity?",
            category: "Professional Development",
            difficulty: .hard
        ),
        PromptData(
            id: "prof-30",
            text: "Tell me about a time you championed an idea that others initially rejected.",
            category: "Professional Development",
            difficulty: .hard
        ),
        PromptData(
            id: "prof-31",
            text: "How do you build a personal brand without coming across as self-promotional?",
            category: "Professional Development",
            difficulty: .medium
        ),
        PromptData(
            id: "prof-32",
            text: "Describe your approach to delegating tasks effectively.",
            category: "Professional Development",
            difficulty: .medium
        ),
        PromptData(
            id: "prof-33",
            text: "What would you do differently if you could restart your career from scratch?",
            category: "Professional Development",
            difficulty: .medium
        ),
        PromptData(
            id: "prof-34",
            text: "How do you maintain high standards without burning out your team?",
            category: "Professional Development",
            difficulty: .hard
        ),
        PromptData(
            id: "prof-35",
            text: "Tell me about a time you had to unlearn something to grow professionally.",
            category: "Professional Development",
            difficulty: .hard
        ),
        PromptData(
            id: "prof-36",
            text: "What does work-life integration mean to you versus work-life balance?",
            category: "Professional Development",
            difficulty: .medium
        ),
        PromptData(
            id: "prof-37",
            text: "How do you handle a boss who micromanages you?",
            category: "Professional Development",
            difficulty: .medium
        ),
        PromptData(
            id: "prof-38",
            text: "Describe how you prepare for high-stakes presentations or meetings.",
            category: "Professional Development",
            difficulty: .medium
        ),
        PromptData(
            id: "prof-39",
            text: "What professional achievement are you working toward right now?",
            category: "Professional Development",
            difficulty: .easy
        ),
        PromptData(
            id: "prof-40",
            text: "How do you recover professionally after a public mistake or failure?",
            category: "Professional Development",
            difficulty: .hard
        ),

        // ============================================
        // Communication Skills (More)
        // ============================================
        PromptData(
            id: "comm-26",
            text: "Explain the concept of infinity to a five-year-old.",
            category: "Communication Skills",
            difficulty: .hard
        ),
        PromptData(
            id: "comm-27",
            text: "How do you deliver a message that you know the audience does not want to hear?",
            category: "Communication Skills",
            difficulty: .hard
        ),
        PromptData(
            id: "comm-28",
            text: "Describe a time you changed someone's mind through a conversation, not an argument.",
            category: "Communication Skills",
            difficulty: .hard
        ),
        PromptData(
            id: "comm-29",
            text: "How do you communicate boundaries without damaging a relationship?",
            category: "Communication Skills",
            difficulty: .hard
        ),
        PromptData(
            id: "comm-30",
            text: "Explain your favorite hobby using only analogies.",
            category: "Communication Skills",
            difficulty: .medium
        ),
        PromptData(
            id: "comm-31",
            text: "How do you adjust your tone when switching between a casual and formal setting?",
            category: "Communication Skills",
            difficulty: .medium
        ),
        PromptData(
            id: "comm-32",
            text: "Describe a time you had to communicate across a language or cultural barrier.",
            category: "Communication Skills",
            difficulty: .hard
        ),
        PromptData(
            id: "comm-33",
            text: "How do you politely interrupt someone who has been talking for too long?",
            category: "Communication Skills",
            difficulty: .medium
        ),
        PromptData(
            id: "comm-34",
            text: "What is the most effective compliment you have ever given or received?",
            category: "Communication Skills",
            difficulty: .easy
        ),
        PromptData(
            id: "comm-35",
            text: "How do you handle silence in a conversation without making it awkward?",
            category: "Communication Skills",
            difficulty: .medium
        ),
        PromptData(
            id: "comm-36",
            text: "Explain a controversial topic from both sides without revealing your opinion.",
            category: "Communication Skills",
            difficulty: .hard
        ),
        PromptData(
            id: "comm-37",
            text: "How do you tell a story that keeps people leaning in?",
            category: "Communication Skills",
            difficulty: .medium
        ),
        PromptData(
            id: "comm-38",
            text: "Describe how you would explain your job to a child.",
            category: "Communication Skills",
            difficulty: .easy
        ),
        PromptData(
            id: "comm-39",
            text: "How do you communicate appreciation in a way that feels genuine, not performative?",
            category: "Communication Skills",
            difficulty: .medium
        ),
        PromptData(
            id: "comm-40",
            text: "What is the hardest thing about communicating over text versus in person?",
            category: "Communication Skills",
            difficulty: .easy
        ),

        // ============================================
        // Personal Growth (More)
        // ============================================
        PromptData(
            id: "pers-26",
            text: "Tell me about a time you realized you were the villain in someone else's story.",
            category: "Personal Growth",
            difficulty: .hard
        ),
        PromptData(
            id: "pers-27",
            text: "What is a fear you have conquered, and how did you do it?",
            category: "Personal Growth",
            difficulty: .medium
        ),
        PromptData(
            id: "pers-28",
            text: "Describe a piece of art — a movie, book, or painting — that profoundly shifted your worldview.",
            category: "Personal Growth",
            difficulty: .medium
        ),
        PromptData(
            id: "pers-29",
            text: "How do you handle the pressure of other people's expectations?",
            category: "Personal Growth",
            difficulty: .hard
        ),
        PromptData(
            id: "pers-30",
            text: "What is the most important conversation you have ever had with yourself?",
            category: "Personal Growth",
            difficulty: .hard
        ),
        PromptData(
            id: "pers-31",
            text: "How has your relationship with money changed as you have gotten older?",
            category: "Personal Growth",
            difficulty: .medium
        ),
        PromptData(
            id: "pers-32",
            text: "Describe a time you chose to be vulnerable and what came from it.",
            category: "Personal Growth",
            difficulty: .hard
        ),
        PromptData(
            id: "pers-33",
            text: "What does integrity look like when nobody is watching?",
            category: "Personal Growth",
            difficulty: .hard
        ),
        PromptData(
            id: "pers-34",
            text: "How do you deal with comparison in the age of social media?",
            category: "Personal Growth",
            difficulty: .medium
        ),
        PromptData(
            id: "pers-35",
            text: "What is one thing you have stopped apologizing for?",
            category: "Personal Growth",
            difficulty: .medium
        ),
        PromptData(
            id: "pers-36",
            text: "How do you know the difference between quitting and letting go?",
            category: "Personal Growth",
            difficulty: .hard
        ),
        PromptData(
            id: "pers-37",
            text: "Describe a moment of silence or solitude that changed you.",
            category: "Personal Growth",
            difficulty: .medium
        ),
        PromptData(
            id: "pers-38",
            text: "What is a compliment you received years ago that still stays with you?",
            category: "Personal Growth",
            difficulty: .easy
        ),
        PromptData(
            id: "pers-39",
            text: "How do you stay true to yourself when you feel pressure to conform?",
            category: "Personal Growth",
            difficulty: .hard
        ),
        PromptData(
            id: "pers-40",
            text: "What would your life look like if you were not afraid of judgment?",
            category: "Personal Growth",
            difficulty: .hard
        ),

        // ============================================
        // Problem Solving (More)
        // ============================================
        PromptData(
            id: "prob-26",
            text: "Describe a complex problem you solved using an incredibly simple solution.",
            category: "Problem Solving",
            difficulty: .hard
        ),
        PromptData(
            id: "prob-27",
            text: "How do you approach a problem you have never seen before in any context?",
            category: "Problem Solving",
            difficulty: .hard
        ),
        PromptData(
            id: "prob-28",
            text: "Tell me about a time you solved a problem by asking a better question.",
            category: "Problem Solving",
            difficulty: .hard
        ),
        PromptData(
            id: "prob-29",
            text: "How do you decide when a problem is worth solving versus when to work around it?",
            category: "Problem Solving",
            difficulty: .medium
        ),
        PromptData(
            id: "prob-30",
            text: "Describe a time you had to make a high-stakes decision in under five minutes.",
            category: "Problem Solving",
            difficulty: .hard
        ),
        PromptData(
            id: "prob-31",
            text: "How do you avoid analysis paralysis when you have too many options?",
            category: "Problem Solving",
            difficulty: .medium
        ),
        PromptData(
            id: "prob-32",
            text: "Tell me about a problem you solved by collaborating with someone from a completely different field.",
            category: "Problem Solving",
            difficulty: .medium
        ),
        PromptData(
            id: "prob-33",
            text: "How do you test whether your solution to a problem actually works?",
            category: "Problem Solving",
            difficulty: .medium
        ),
        PromptData(
            id: "prob-34",
            text: "Describe a time you had to choose between two equally bad options.",
            category: "Problem Solving",
            difficulty: .hard
        ),
        PromptData(
            id: "prob-35",
            text: "What is the most creative workaround you have ever come up with?",
            category: "Problem Solving",
            difficulty: .medium
        ),
        PromptData(
            id: "prob-36",
            text: "How do you prevent the same problem from happening again?",
            category: "Problem Solving",
            difficulty: .medium
        ),
        PromptData(
            id: "prob-37",
            text: "Tell me about a time you had to solve a problem under public scrutiny.",
            category: "Problem Solving",
            difficulty: .hard
        ),
        PromptData(
            id: "prob-38",
            text: "How do you balance speed and quality when solving urgent problems?",
            category: "Problem Solving",
            difficulty: .medium
        ),
        PromptData(
            id: "prob-39",
            text: "Describe a problem you initially thought was someone else's responsibility but ended up solving yourself.",
            category: "Problem Solving",
            difficulty: .medium
        ),
        PromptData(
            id: "prob-40",
            text: "What is a problem in the world you wish you could solve, and how would you start?",
            category: "Problem Solving",
            difficulty: .hard
        ),

        // ============================================
        // Current Events & Opinions (More)
        // ============================================
        PromptData(
            id: "curr-26",
            text: "What is a trend from the past you wish would make a comeback?",
            category: "Current Events & Opinions",
            difficulty: .easy
        ),
        PromptData(
            id: "curr-27",
            text: "How do you think the concept of ownership is changing in a digital world?",
            category: "Current Events & Opinions",
            difficulty: .hard
        ),
        PromptData(
            id: "curr-28",
            text: "What is the biggest misconception people have about your generation?",
            category: "Current Events & Opinions",
            difficulty: .medium
        ),
        PromptData(
            id: "curr-29",
            text: "How should society handle the growing loneliness epidemic?",
            category: "Current Events & Opinions",
            difficulty: .hard
        ),
        PromptData(
            id: "curr-30",
            text: "What does sustainable living actually look like in practice?",
            category: "Current Events & Opinions",
            difficulty: .medium
        ),
        PromptData(
            id: "curr-31",
            text: "How do you feel about the blurring line between news and entertainment?",
            category: "Current Events & Opinions",
            difficulty: .hard
        ),
        PromptData(
            id: "curr-32",
            text: "What is one policy change that would improve quality of life in your country?",
            category: "Current Events & Opinions",
            difficulty: .hard
        ),
        PromptData(
            id: "curr-33",
            text: "How has the pandemic permanently changed the way you think about health?",
            category: "Current Events & Opinions",
            difficulty: .medium
        ),
        PromptData(
            id: "curr-34",
            text: "Do you think people are more or less connected than they were twenty years ago?",
            category: "Current Events & Opinions",
            difficulty: .medium
        ),
        PromptData(
            id: "curr-35",
            text: "What is the role of art and creativity in a technology-driven world?",
            category: "Current Events & Opinions",
            difficulty: .medium
        ),
        PromptData(
            id: "curr-36",
            text: "How do you think space exploration will change in our lifetime?",
            category: "Current Events & Opinions",
            difficulty: .medium
        ),
        PromptData(
            id: "curr-37",
            text: "What is the most important thing the next generation needs to learn?",
            category: "Current Events & Opinions",
            difficulty: .medium
        ),
        PromptData(
            id: "curr-38",
            text: "How should we rethink the relationship between work and identity?",
            category: "Current Events & Opinions",
            difficulty: .hard
        ),
        PromptData(
            id: "curr-39",
            text: "What does a healthy relationship with technology look like?",
            category: "Current Events & Opinions",
            difficulty: .medium
        ),
        PromptData(
            id: "curr-40",
            text: "How do you think history will judge this decade?",
            category: "Current Events & Opinions",
            difficulty: .hard
        ),

        // ============================================
        // Quick Fire (More)
        // ============================================
        PromptData(
            id: "quick-26",
            text: "If you could instantly become an expert in any obscure subject, what would it be and why?",
            category: "Quick Fire",
            difficulty: .easy
        ),
        PromptData(
            id: "quick-27",
            text: "What is the weirdest food combination you secretly enjoy?",
            category: "Quick Fire",
            difficulty: .easy
        ),
        PromptData(
            id: "quick-28",
            text: "If your life had a theme song, what would it be?",
            category: "Quick Fire",
            difficulty: .easy
        ),
        PromptData(
            id: "quick-29",
            text: "What is the most useless talent you have?",
            category: "Quick Fire",
            difficulty: .easy
        ),
        PromptData(
            id: "quick-30",
            text: "If you could only eat one cuisine for the rest of your life, which would you pick?",
            category: "Quick Fire",
            difficulty: .easy
        ),
        PromptData(
            id: "quick-31",
            text: "What is one app on your phone you could not live without?",
            category: "Quick Fire",
            difficulty: .easy
        ),
        PromptData(
            id: "quick-32",
            text: "Describe your dream house in 30 seconds.",
            category: "Quick Fire",
            difficulty: .easy
        ),
        PromptData(
            id: "quick-33",
            text: "If you could witness any historical event firsthand, which would you choose?",
            category: "Quick Fire",
            difficulty: .easy
        ),
        PromptData(
            id: "quick-34",
            text: "What is a smell that instantly takes you back to a specific memory?",
            category: "Quick Fire",
            difficulty: .easy
        ),
        PromptData(
            id: "quick-35",
            text: "If you won the lottery tomorrow, what is the first thing you would do?",
            category: "Quick Fire",
            difficulty: .easy
        ),
        PromptData(
            id: "quick-36",
            text: "What is the best spontaneous decision you have ever made?",
            category: "Quick Fire",
            difficulty: .easy
        ),
        PromptData(
            id: "quick-37",
            text: "If you could have any superpower for just one day, what would you pick?",
            category: "Quick Fire",
            difficulty: .easy
        ),
        PromptData(
            id: "quick-38",
            text: "What is the funniest thing that happened to you this week?",
            category: "Quick Fire",
            difficulty: .easy
        ),
        PromptData(
            id: "quick-39",
            text: "If you could teleport anywhere right now, where would you go?",
            category: "Quick Fire",
            difficulty: .easy
        ),
        PromptData(
            id: "quick-40",
            text: "What fictional world would you most want to live in?",
            category: "Quick Fire",
            difficulty: .easy
        ),

        // ============================================
        // Debate & Persuasion (More)
        // ============================================
        PromptData(
            id: "debate-26",
            text: "Argue for or against: Humans should colonize other planets.",
            category: "Debate & Persuasion",
            difficulty: .hard
        ),
        PromptData(
            id: "debate-27",
            text: "Make the case that boredom is essential for creativity.",
            category: "Debate & Persuasion",
            difficulty: .hard
        ),
        PromptData(
            id: "debate-28",
            text: "Argue for or against: All education should be free.",
            category: "Debate & Persuasion",
            difficulty: .hard
        ),
        PromptData(
            id: "debate-29",
            text: "Convince someone that learning a second language is worth the effort.",
            category: "Debate & Persuasion",
            difficulty: .medium
        ),
        PromptData(
            id: "debate-30",
            text: "Argue for or against: We should have a universal basic income.",
            category: "Debate & Persuasion",
            difficulty: .hard
        ),
        PromptData(
            id: "debate-31",
            text: "Make the case that silence is more powerful than words.",
            category: "Debate & Persuasion",
            difficulty: .hard
        ),
        PromptData(
            id: "debate-32",
            text: "Argue for or against: Children should be allowed unrestricted internet access.",
            category: "Debate & Persuasion",
            difficulty: .hard
        ),
        PromptData(
            id: "debate-33",
            text: "Convince someone to start journaling every day.",
            category: "Debate & Persuasion",
            difficulty: .medium
        ),
        PromptData(
            id: "debate-34",
            text: "Argue for or against: Success is more about luck than hard work.",
            category: "Debate & Persuasion",
            difficulty: .hard
        ),
        PromptData(
            id: "debate-35",
            text: "Make the case that every person should spend a year living abroad.",
            category: "Debate & Persuasion",
            difficulty: .medium
        ),
        PromptData(
            id: "debate-36",
            text: "Argue for or against: Social media has made us better communicators.",
            category: "Debate & Persuasion",
            difficulty: .hard
        ),
        PromptData(
            id: "debate-37",
            text: "Convince a friend to try a 30-day digital detox.",
            category: "Debate & Persuasion",
            difficulty: .medium
        ),
        PromptData(
            id: "debate-38",
            text: "Argue for or against: Professional athletes are overpaid.",
            category: "Debate & Persuasion",
            difficulty: .hard
        ),
        PromptData(
            id: "debate-39",
            text: "Make the case that small talk is actually an important social skill.",
            category: "Debate & Persuasion",
            difficulty: .medium
        ),
        PromptData(
            id: "debate-40",
            text: "Argue for or against: The voting age should be lowered to sixteen.",
            category: "Debate & Persuasion",
            difficulty: .hard
        ),

        // ============================================
        // Interview Prep (More)
        // ============================================
        PromptData(
            id: "intv-26",
            text: "How do you stay current with trends and developments in your field?",
            category: "Interview Prep",
            difficulty: .easy
        ),
        PromptData(
            id: "intv-27",
            text: "Tell me about a time you had to give a presentation with very little preparation.",
            category: "Interview Prep",
            difficulty: .hard
        ),
        PromptData(
            id: "intv-28",
            text: "How would your best friend describe you versus how a coworker would describe you?",
            category: "Interview Prep",
            difficulty: .medium
        ),
        PromptData(
            id: "intv-29",
            text: "Describe a time you had to admit you were wrong to your team.",
            category: "Interview Prep",
            difficulty: .hard
        ),
        PromptData(
            id: "intv-30",
            text: "What is a professional failure that ultimately made you better at your job?",
            category: "Interview Prep",
            difficulty: .hard
        ),
        PromptData(
            id: "intv-31",
            text: "How do you approach building relationships with new team members?",
            category: "Interview Prep",
            difficulty: .easy
        ),
        PromptData(
            id: "intv-32",
            text: "Tell me about a time you had to push back on a request from a senior leader.",
            category: "Interview Prep",
            difficulty: .hard
        ),
        PromptData(
            id: "intv-33",
            text: "What do you do when you realize you have made a commitment you cannot keep?",
            category: "Interview Prep",
            difficulty: .medium
        ),
        PromptData(
            id: "intv-34",
            text: "How do you handle a project where the requirements keep changing?",
            category: "Interview Prep",
            difficulty: .medium
        ),
        PromptData(
            id: "intv-35",
            text: "Describe a time you improved a process or workflow at your company.",
            category: "Interview Prep",
            difficulty: .medium
        ),
        PromptData(
            id: "intv-36",
            text: "What is the toughest piece of feedback you have received, and what did you do about it?",
            category: "Interview Prep",
            difficulty: .hard
        ),
        PromptData(
            id: "intv-37",
            text: "How do you make decisions when your team cannot reach consensus?",
            category: "Interview Prep",
            difficulty: .hard
        ),
        PromptData(
            id: "intv-38",
            text: "Tell me about a time you had to deliver results with a very small budget.",
            category: "Interview Prep",
            difficulty: .hard
        ),
        PromptData(
            id: "intv-39",
            text: "What is the first thing you do when starting a new job?",
            category: "Interview Prep",
            difficulty: .easy
        ),
        PromptData(
            id: "intv-40",
            text: "How do you handle a coworker who is not pulling their weight on a team project?",
            category: "Interview Prep",
            difficulty: .medium
        ),

        // ============================================
        // Storytelling (More)
        // ============================================
        PromptData(
            id: "story-24",
            text: "Tell a story about a time you got completely lost and how you found your way back.",
            category: "Storytelling",
            difficulty: .medium
        ),
        PromptData(
            id: "story-25",
            text: "Narrate the moment you realized you had grown up.",
            category: "Storytelling",
            difficulty: .medium
        ),
        PromptData(
            id: "story-26",
            text: "Tell a story about a meal that brought people together.",
            category: "Storytelling",
            difficulty: .easy
        ),
        PromptData(
            id: "story-27",
            text: "Describe the scariest moment of your life and what happened next.",
            category: "Storytelling",
            difficulty: .hard
        ),
        PromptData(
            id: "story-28",
            text: "Tell a story about a teacher or coach who changed the trajectory of your life.",
            category: "Storytelling",
            difficulty: .medium
        ),
        PromptData(
            id: "story-29",
            text: "Narrate a time you stood up for someone who could not stand up for themselves.",
            category: "Storytelling",
            difficulty: .hard
        ),
        PromptData(
            id: "story-30",
            text: "Tell the story of a gift you gave that meant more than you expected.",
            category: "Storytelling",
            difficulty: .easy
        ),
        PromptData(
            id: "story-31",
            text: "Describe a night that did not go as planned but became unforgettable.",
            category: "Storytelling",
            difficulty: .medium
        ),
        PromptData(
            id: "story-32",
            text: "Tell a story about a time you said yes when you usually would have said no.",
            category: "Storytelling",
            difficulty: .medium
        ),
        PromptData(
            id: "story-33",
            text: "Narrate an experience that made you appreciate something you used to take for granted.",
            category: "Storytelling",
            difficulty: .medium
        ),
        PromptData(
            id: "story-34",
            text: "Tell the story of how you met your closest friend.",
            category: "Storytelling",
            difficulty: .easy
        ),
        PromptData(
            id: "story-35",
            text: "Describe a time you had to make a split-second decision that changed everything.",
            category: "Storytelling",
            difficulty: .hard
        ),
        PromptData(
            id: "story-36",
            text: "Tell a story about a place that no longer exists but lives on in your memory.",
            category: "Storytelling",
            difficulty: .medium
        ),
        PromptData(
            id: "story-37",
            text: "Narrate a time you received help from the most unexpected source.",
            category: "Storytelling",
            difficulty: .medium
        ),
        PromptData(
            id: "story-38",
            text: "Tell the story of a mistake that led to one of the best things in your life.",
            category: "Storytelling",
            difficulty: .hard
        ),

        // ============================================
        // Elevator Pitch (More)
        // ============================================
        PromptData(
            id: "pitch-23",
            text: "Pitch a reality TV show concept based on your workplace or daily life.",
            category: "Elevator Pitch",
            difficulty: .medium
        ),
        PromptData(
            id: "pitch-24",
            text: "Pitch a charity event that would go viral on social media.",
            category: "Elevator Pitch",
            difficulty: .hard
        ),
        PromptData(
            id: "pitch-25",
            text: "Pitch a brand-new sport and explain the rules in 60 seconds.",
            category: "Elevator Pitch",
            difficulty: .hard
        ),
        PromptData(
            id: "pitch-26",
            text: "Pitch your morning routine as a productivity course.",
            category: "Elevator Pitch",
            difficulty: .medium
        ),
        PromptData(
            id: "pitch-27",
            text: "Pitch a museum exhibit based on your life experiences.",
            category: "Elevator Pitch",
            difficulty: .hard
        ),
        PromptData(
            id: "pitch-28",
            text: "Pitch a new feature for your favorite app.",
            category: "Elevator Pitch",
            difficulty: .medium
        ),
        PromptData(
            id: "pitch-29",
            text: "Pitch a children's book concept and explain the moral of the story.",
            category: "Elevator Pitch",
            difficulty: .medium
        ),
        PromptData(
            id: "pitch-30",
            text: "Pitch your neighborhood as a tourist destination.",
            category: "Elevator Pitch",
            difficulty: .easy
        ),
        PromptData(
            id: "pitch-31",
            text: "Pitch a technology solution that would help elderly people live independently.",
            category: "Elevator Pitch",
            difficulty: .hard
        ),
        PromptData(
            id: "pitch-32",
            text: "Pitch a conference talk on a topic you are passionate about.",
            category: "Elevator Pitch",
            difficulty: .hard
        ),
        PromptData(
            id: "pitch-33",
            text: "Pitch a dating app with a unique twist.",
            category: "Elevator Pitch",
            difficulty: .medium
        ),
        PromptData(
            id: "pitch-34",
            text: "Pitch a community garden project to your local council.",
            category: "Elevator Pitch",
            difficulty: .medium
        ),
        PromptData(
            id: "pitch-35",
            text: "Pitch yourself as a guest on a podcast. What would you talk about?",
            category: "Elevator Pitch",
            difficulty: .medium
        ),
        PromptData(
            id: "pitch-36",
            text: "Pitch a documentary about an untold story that deserves attention.",
            category: "Elevator Pitch",
            difficulty: .hard
        ),
        PromptData(
            id: "pitch-37",
            text: "Pitch a board game based on real-life challenges people face.",
            category: "Elevator Pitch",
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
