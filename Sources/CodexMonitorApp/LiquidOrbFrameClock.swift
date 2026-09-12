import Foundation

@MainActor
protocol LiquidOrbFrameCancellation: AnyObject {
    func cancel()
}

@MainActor
protocol LiquidOrbFrameClock: AnyObject {
    var nowMilliseconds: Double { get }
    func start(_ tick: @escaping @MainActor () -> Void) -> any LiquidOrbFrameCancellation
}

@MainActor
private final class LiquidOrbTimerCancellation: LiquidOrbFrameCancellation {
    private var timer: Timer?

    init(timer: Timer) {
        self.timer = timer
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        MainActor.assumeIsolated {
            timer?.invalidate()
        }
    }
}

/// A local main-run-loop clock. It runs in common modes while the native
/// panel is tracked, and stops as soon as the liquid body settles.
@MainActor
final class LiquidOrbRunLoopFrameClock: LiquidOrbFrameClock {
    var nowMilliseconds: Double {
        ProcessInfo.processInfo.systemUptime * 1_000
    }

    func start(_ tick: @escaping @MainActor () -> Void) -> any LiquidOrbFrameCancellation {
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { _ in
            MainActor.assumeIsolated {
                tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        return LiquidOrbTimerCancellation(timer: timer)
    }
}
