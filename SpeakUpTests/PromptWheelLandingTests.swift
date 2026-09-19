import Testing
@testable import SpeakUp

struct PromptWheelLandingTests {

    @Test("A spin lands inside its segment in either direction, never on an edge")
    func landsInsideSegment() {
        for segments in [3, 7, 12] {
            let segmentAngle = 360.0 / Double(segments)
            for rotation in stride(from: -1000.0, through: 1000, by: 37) {
                for amount in [-2160.0, -700, 0, 45, 700, 2160] {
                    for jitter in [-0.3, 0, 0.3] {
                        let landing = PromptWheelViewModel.landing(
                            rotation: rotation,
                            amount: amount,
                            segments: segments,
                            jitter: jitter
                        )
                        let pointer = PromptWheelViewModel.normalized(-(rotation + landing.total))
                        let position = pointer / segmentAngle - Double(landing.index)

                        #expect(landing.index >= 0 && landing.index < segments)
                        #expect(position > 0.19 && position < 0.81)
                        #expect(abs(landing.total - amount) < segmentAngle)
                    }
                }
            }
        }
    }

    @Test("Angle folding")
    func folding() {
        #expect(PromptWheelViewModel.normalized(-90) == 270)
        #expect(PromptWheelViewModel.normalized(725) == 5)
        #expect(PromptWheelViewModel.signedDelta(350) == -10)
        #expect(PromptWheelViewModel.signedDelta(-350) == 10)
        #expect(PromptWheelViewModel.signedDelta(180) == 180)
    }
}
