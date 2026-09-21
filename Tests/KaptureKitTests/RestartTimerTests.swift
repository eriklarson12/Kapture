import Foundation
import Testing
@testable import KaptureKit

@Suite("RestartTimer")
@MainActor
struct RestartTimerTests {
    @Test("a hold is one wait a second, and fires at the end")
    func holdSchedule() async {
        let clock = TestClock()
        let timer = RestartTimer(seconds: 5, clock: clock)

        let outcome = await timer.wait()

        #expect(outcome == .fired)
        #expect(clock.waits == [.seconds(1), .seconds(1), .seconds(1), .seconds(1), .seconds(1)])
    }

    /// The number the guest reads. It has to reach 1 rather than 0, and it has
    /// to go away afterwards, because nil is what the view branches on to know
    /// there is no hold.
    @Test("the countdown runs down to one and clears when it ends")
    func countsDown() async {
        let clock = TestClock()
        let timer = RestartTimer(seconds: 4, clock: clock)
        var seen: [Int?] = []
        clock.onWait = { _ in seen.append(timer.secondsRemaining) }

        await timer.wait()

        #expect(seen == [4, 3, 2, 1])
        #expect(timer.secondsRemaining == nil)
    }

    @Test("stopping mid-hold ends it at that beat")
    func stopEndsTheHold() async {
        let clock = TestClock()
        let timer = RestartTimer(seconds: 10, clock: clock)
        clock.onWait = { count in
            if count == 3 { timer.stop() }
        }

        let outcome = await timer.wait()

        #expect(outcome == .stopped)
        #expect(clock.waits.count == 3)
        #expect(timer.secondsRemaining == nil)
    }

    /// Turning the stepper to its floor is how someone says "immediately", so
    /// it must not be a beat of its own.
    @Test("a hold of zero fires at once and waits for nothing")
    func zeroFiresImmediately() async {
        let clock = TestClock()
        let timer = RestartTimer(seconds: 0, clock: clock)

        let outcome = await timer.wait()

        #expect(outcome == .fired)
        #expect(clock.waits.isEmpty)
    }

    /// A queue stops and starts all evening. A stop that outlived its own hold
    /// would cancel the next one before it began.
    @Test("a stopped timer holds normally the next time")
    func reusableAfterStop() async {
        let clock = TestClock()
        let timer = RestartTimer(seconds: 3, clock: clock)
        clock.onWait = { count in
            if count == 1 { timer.stop() }
        }

        #expect(await timer.wait() == .stopped)

        clock.onWait = nil
        #expect(await timer.wait() == .fired)
        #expect(clock.waits.count == 4)
    }

    @Test("the hold length is read when the hold starts, not when the timer is built")
    func honoursAChangedLength() async {
        let clock = TestClock()
        let timer = RestartTimer(seconds: 20, clock: clock)
        timer.seconds = 2

        await timer.wait()

        #expect(clock.waits.count == 2)
    }
}
