//
//  SpeakUpWidgetBundle.swift
//  SpeakUpWidget
//
//  Created by Vansh Patel on 3/11/26.
//

import WidgetKit
import SwiftUI

@main
struct SpeakUpWidgetBundle: WidgetBundle {
    var body: some Widget {
        DailyPromptWidget()
        StreakWidget()
        QuickPracticeWidget()
        WeeklyProgressWidget()
        StatsRingWidget()
        DailyChallengeWidget()
        EventCountdownWidget()
    }
}
