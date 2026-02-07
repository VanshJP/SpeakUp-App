import WidgetKit
import SwiftUI

@main
struct SpeakUpWidgetBundle: WidgetBundle {
    var body: some Widget {
        DailyPromptWidget()
        StreakWidget()
    }
}
