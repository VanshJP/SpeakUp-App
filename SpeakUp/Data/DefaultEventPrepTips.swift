import Foundation

enum DefaultEventPrepTips {
    static func notificationMessage(phase: EventPrepPhase, daysRemaining: Int, eventTitle: String) -> (title: String, body: String) {
        switch phase {
        case .foundation:
            let bodies = [
                "Your \"\(eventTitle)\" is in \(daysRemaining) days. Time for a quick warm-up!",
                "Start building familiarity with your material — review your script today.",
                "Confidence grows with preparation. Do a quick read-through today.",
                "\(daysRemaining) days until \"\(eventTitle)\". A warm-up exercise will set you up."
            ]
            return ("Prep Time", bodies[daysRemaining % bodies.count])

        case .building:
            let bodies = [
                "\(daysRemaining) days until your talk. Practice your opening section today.",
                "Focus on your weakest section — repetition builds mastery.",
                "Time for a targeted drill. Sharpen your delivery for \"\(eventTitle)\".",
                "Full rehearsal day! Run through your speech start to finish."
            ]
            return ("Keep Building", bodies[daysRemaining % bodies.count])

        case .performance:
            let bodies = [
                "\(daysRemaining) days to go! Full rehearsal time — you've got this.",
                "Almost showtime! Polish your delivery with one more run-through.",
                "Final stretch for \"\(eventTitle)\". You're more prepared than you think.",
                "You're ready. Take 2 minutes for a breathing exercise."
            ]

            if daysRemaining <= 1 {
                return ("You're Ready", "Today is the day! A quick breathing exercise is all you need. You've prepared well.")
            }
            return ("Almost There", bodies[daysRemaining % bodies.count])
        }
    }

    static func coachingTip(phase: EventPrepPhase) -> String {
        switch phase {
        case .foundation:
            let tips = [
                "Read your script aloud at least once — hearing it helps internalize the flow.",
                "Don't memorize word-for-word. Focus on key points and transitions.",
                "Warm up your voice daily, even if you don't practice the full speech.",
                "Visualize yourself delivering the speech confidently in the venue."
            ]
            return tips.randomElement() ?? tips[0]

        case .building:
            let tips = [
                "Practice your weakest section twice as much as your strongest.",
                "Record yourself and listen back — you'll catch things you miss while speaking.",
                "Time yourself to make sure you're within the expected duration.",
                "Practice transitions between sections — these are where most stumbles happen."
            ]
            return tips.randomElement() ?? tips[0]

        case .performance:
            let tips = [
                "Do one full run-through without stopping, even if you stumble.",
                "Focus on your opening and closing — these are what audiences remember most.",
                "Trust your preparation. Confidence comes from repetition.",
                "The night before: review your notes, then rest. Sleep beats last-minute cramming."
            ]
            return tips.randomElement() ?? tips[0]
        }
    }
}
