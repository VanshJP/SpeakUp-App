import SwiftUI
import Testing
@testable import SpeakUp

struct PromptWheelLandingTests {

    @Test("A spin rests exactly on a stop, and names the stop the dial shows")
    func landsOnAStop() {
        for count in [3, 7, 12] {
            for position in stride(from: -40.0, through: 40, by: 3.7) {
                for amount in [-60.0, -7.4, -0.3, 0, 0.6, 7.4, 60] {
                    let landing = PromptWheelViewModel.landing(position: position, amount: amount, count: count)

                    #expect(landing.index >= 0 && landing.index < count)
                    #expect(landing.target == landing.target.rounded())
                    #expect(abs(landing.target - (position + amount)) <= 0.5)
                    #expect(landing.index == ArcDial<EmptyView, EmptyView>.index(at: landing.target, count: count))
                }
            }
        }
    }

    @Test("Negative positions wrap to the right category")
    func wraps() {
        #expect(PromptWheelViewModel.landing(position: 0, amount: -1, count: 5).index == 4)
        #expect(PromptWheelViewModel.landing(position: 0, amount: -6, count: 5).index == 4)
        #expect(PromptWheelViewModel.landing(position: 2.4, amount: 0, count: 5).index == 2)
    }
}
