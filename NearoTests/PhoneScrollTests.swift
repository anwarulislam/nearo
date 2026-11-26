import Foundation
import Testing
@testable import Nearo

struct PhoneScrollTests {
    @Test func trackpadAccumulatesSmallDeltasAndReversesPromptly() {
        var scroll = PhoneScroll()
        #expect(scroll.step(delta: -20, precise: true) == nil)
        #expect(scroll.step(delta: -16, precise: true) == 500)
        #expect(scroll.step(delta: 30, precise: true) == nil)
        #expect(scroll.step(delta: 2, precise: true) == -500)
        #expect(scroll.step(delta: 0, precise: true) == nil)
    }

    @Test func wheelNotchSendsOnePhoneScrollAction() {
        var scroll = PhoneScroll()
        #expect(scroll.step(delta: -1, precise: false) == 500)
        #expect(scroll.step(delta: 1, precise: false) == -500)
    }
}
