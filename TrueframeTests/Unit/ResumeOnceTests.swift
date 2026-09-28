import XCTest
@testable import Trueframe

final class ResumeOnceTests: XCTestCase {

    func testResume_afterWaiting_resumesTheWaiter() async {
        let once = ResumeOnce()
        let waiter = Task { await once.wait() }
        try? await Task.sleep(for: .milliseconds(20))
        once.resume()
        await waiter.value
    }

    func testResume_beforeWaiting_letsTheWaitReturnAtOnce() async {
        let once = ResumeOnce()
        once.resume()
        await once.wait()
    }

    func testResume_twice_isHarmless() async {
        let once = ResumeOnce()
        let waiter = Task { await once.wait() }
        try? await Task.sleep(for: .milliseconds(20))
        once.resume()
        once.resume()
        await waiter.value
    }

    func testCancellingTheWaiter_endsTheWait() async {
        let once = ResumeOnce()
        let waiter = Task { await once.wait() }
        try? await Task.sleep(for: .milliseconds(20))
        waiter.cancel()
        await waiter.value
    }

    func testCancelledBeforeWaiting_stillReturns() async {
        let once = ResumeOnce()
        let waiter = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await once.wait()
        }
        await waiter.value
    }
}
