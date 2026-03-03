import Foundation

struct DefaultFeedbackQuestions {
    static let questions: [FeedbackQuestion] = [
        FeedbackQuestion(
            id: UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")!,
            text: "How do you think the session went?",
            type: .scale
        ),
        FeedbackQuestion(
            id: UUID(uuidString: "B2C3D4E5-F6A7-8901-BCDE-F12345678901")!,
            text: "Did what you said make sense?",
            type: .yesNo
        )
    ]
}
