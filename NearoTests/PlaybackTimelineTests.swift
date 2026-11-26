import Foundation
import Testing
@testable import Nearo

struct PlaybackTimelineTests {
    @Test func playbackAdvancesAtTheReportedRateOnlyWhilePlaying() {
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        let timeline = PlaybackTimeline(length: 60_000, position: 10_000, reportedAt: start, rate: 1.5)
        let later = start.addingTimeInterval(2)
        #expect(timeline.milliseconds(at: later, playing: true) == 13_000)
        #expect(timeline.milliseconds(at: later, playing: false) == 10_000)
        #expect(timeline.milliseconds(at: start.addingTimeInterval(-1), playing: true) == 10_000)
        #expect(timeline.milliseconds(at: start.addingTimeInterval(60), playing: true) == 60_000)
        #expect(PlaybackTimeline().milliseconds(at: later, playing: true) == 0)
    }
}
