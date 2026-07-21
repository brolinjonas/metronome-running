import Foundation

/// Decides whether playback that was stopped by an audio interruption should
/// auto-resume when a usable output route returns. watchOS never delivers
/// interruption `.ended` after a Bluetooth link drop, so a route return is
/// the only resume signal; the window keeps headphones reconnecting much
/// later from surprise-starting playback.
public enum RouteResumePolicy {
    public static let defaultWindow: TimeInterval = 300

    public static func shouldResume(
        stoppedByInterruptionAt: Date?,
        routeReturnedAt: Date,
        window: TimeInterval = defaultWindow
    ) -> Bool {
        guard let stoppedByInterruptionAt else { return false }
        let elapsed = routeReturnedAt.timeIntervalSince(stoppedByInterruptionAt)
        return elapsed >= 0 && elapsed <= window
    }
}
