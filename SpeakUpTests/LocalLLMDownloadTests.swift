import Foundation
import Testing
@testable import SpeakUp

/// URLSession reports every chunk of a multi-GB model download. Each report
/// used to reach the main actor and re-render every view reading the model
/// state; these pin the gate that lets through only visible steps.
struct LocalLLMDownloadTests {

    @Test func tickNeedsBothAVisibleStepAndAPause() {
        #expect(LocalLLMService.isProgressStep(from: 0.10, to: 0.106, elapsed: 0.3))
        // Big step, too soon: fast Wi-Fi.
        #expect(!LocalLLMService.isProgressStep(from: 0.10, to: 0.20, elapsed: 0.1))
        // Long wait, invisible step: slow link.
        #expect(!LocalLLMService.isProgressStep(from: 0.10, to: 0.101, elapsed: 5))
    }

    @Test func downloadRestartingFromZeroStillReports() {
        #expect(LocalLLMService.isProgressStep(from: 0.40, to: 0.0, elapsed: 1))
    }
}
