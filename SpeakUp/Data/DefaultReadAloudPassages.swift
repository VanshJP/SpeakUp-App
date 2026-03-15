import Foundation

struct DefaultReadAloudPassages {
    static let all: [ReadAloudPassage] = [
        // MARK: - Easy

        ReadAloudPassage(
            id: "easy_intro_1",
            title: "A Simple Introduction",
            text: "Hello everyone. My name is Alex and I am here today to talk about something I care about deeply. I believe that every person has the ability to become a great speaker. All it takes is practice and a little bit of courage.",
            difficulty: .easy,
            category: .news
        ),
        ReadAloudPassage(
            id: "easy_weather",
            title: "The Weather Report",
            text: "Good morning. Today we can expect clear skies throughout the afternoon with temperatures reaching a comfortable seventy-two degrees. A light breeze will come from the west. Tomorrow brings a chance of rain in the evening hours so plan accordingly.",
            difficulty: .easy,
            category: .news
        ),
        ReadAloudPassage(
            id: "easy_story",
            title: "The Friendly Dog",
            text: "There once was a golden retriever named Max who loved to greet every person he met. He would wag his tail so hard that his whole body would wiggle. Everyone in the neighborhood knew Max and would stop to give him a pat on the head.",
            difficulty: .easy,
            category: .literature
        ),
        ReadAloudPassage(
            id: "easy_twister_1",
            title: "Red Lorry Yellow Lorry",
            text: "Red lorry yellow lorry. Red lorry yellow lorry. Red lorry yellow lorry. A proper copper coffee pot. A proper copper coffee pot. A proper copper coffee pot.",
            difficulty: .easy,
            category: .tongueTwister
        ),

        // MARK: - Medium

        ReadAloudPassage(
            id: "medium_leadership",
            title: "Leadership and Communication",
            text: "Effective leadership requires clear and consistent communication. The best leaders understand that listening is just as important as speaking. They create environments where team members feel comfortable sharing their ideas and concerns. By fostering open dialogue a leader builds trust and drives collaboration across the entire organization.",
            difficulty: .medium,
            category: .news
        ),
        ReadAloudPassage(
            id: "medium_technology",
            title: "The Digital Revolution",
            text: "Technology continues to reshape how we interact with the world around us. Smartphones have become extensions of ourselves carrying our schedules contacts and memories. Artificial intelligence is beginning to automate tasks that once required significant human effort. The challenge now is ensuring that these powerful tools serve humanity rather than diminish our capacity for genuine connection.",
            difficulty: .medium,
            category: .technical
        ),
        ReadAloudPassage(
            id: "medium_persuasion",
            title: "The Art of Persuasion",
            text: "Persuasion is not about manipulation. It is about understanding your audience and presenting your ideas in a way that resonates with their values and experiences. The most persuasive speakers combine logical arguments with emotional appeals and personal credibility. They acknowledge opposing viewpoints before presenting a compelling alternative that inspires action.",
            difficulty: .medium,
            category: .literature
        ),
        ReadAloudPassage(
            id: "medium_twister",
            title: "Woodchuck Challenge",
            text: "How much wood would a woodchuck chuck if a woodchuck could chuck wood. A woodchuck would chuck as much wood as a woodchuck could chuck if a woodchuck could chuck wood. She sells seashells by the seashore and the shells she sells are seashells I am sure.",
            difficulty: .medium,
            category: .tongueTwister
        ),

        // MARK: - Hard

        ReadAloudPassage(
            id: "hard_philosophy",
            title: "The Paradox of Knowledge",
            text: "The acquisition of knowledge simultaneously illuminates and complicates our understanding of the world. Each discovery reveals previously unforeseen complexities demanding an ever more nuanced intellectual framework. Epistemological humility becomes paramount as we recognize that the boundaries of our comprehension are perpetually expanding yet never approaching completeness. The truly wise individual acknowledges that expertise in one domain frequently exposes vast territories of ignorance in adjacent disciplines.",
            difficulty: .hard,
            category: .literature
        ),
        ReadAloudPassage(
            id: "hard_science",
            title: "Quantum Entanglement Explained",
            text: "Quantum entanglement represents one of the most counterintuitive phenomena in modern physics. When two particles become entangled their quantum states are fundamentally interconnected regardless of the spatial separation between them. Measuring the property of one particle instantaneously determines the corresponding property of its entangled partner. This phenomenon which Einstein famously characterized as spooky action at a distance challenges our classical intuitions about locality and information transfer.",
            difficulty: .hard,
            category: .technical
        ),
        ReadAloudPassage(
            id: "hard_economics",
            title: "Global Economic Interdependence",
            text: "Contemporary macroeconomic analysis reveals an extraordinarily interconnected global financial architecture wherein localized disruptions propagate through international supply chains with unprecedented velocity. Central banks navigate the delicate equilibrium between inflationary pressures and recessionary risks while simultaneously monitoring geopolitical developments that can fundamentally restructure commodity markets and currency valuations within hours. The sophisticated interplay between monetary policy fiscal stimulus and regulatory frameworks demands continuous recalibration by policymakers across sovereign jurisdictions.",
            difficulty: .hard,
            category: .news
        ),
        ReadAloudPassage(
            id: "hard_twister",
            title: "The Ultimate Tongue Twister",
            text: "The sixth sick sheik's sixth sheep's sick. Pad kid poured curd pulled cod. Toy boat toy boat toy boat. Irish wristwatch Swiss wristwatch. Unique New York unique New York you know you need unique New York. The thirty-three thieves thought that they thrilled the throne throughout Thursday.",
            difficulty: .hard,
            category: .tongueTwister
        ),
    ]
}
