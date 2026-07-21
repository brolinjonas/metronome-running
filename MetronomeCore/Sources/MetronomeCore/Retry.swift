public enum Retry {
    /// Runs `operation` up to `attempts` times, returning its first success.
    /// `beforeRetry` runs between attempts (for backoff delays and
    /// cancellation checks); if it throws, the retry loop aborts immediately
    /// with that error. After the final failed attempt, the operation's last
    /// error is thrown.
    public static func run<T>(
        attempts: Int,
        beforeRetry: () async throws -> Void,
        operation: () async throws -> T
    ) async throws -> T {
        precondition(attempts >= 1, "attempts must be at least 1")
        var lastError: Error?
        for attempt in 1...attempts {
            if attempt > 1 {
                try await beforeRetry()
            }
            do {
                return try await operation()
            } catch {
                lastError = error
            }
        }
        throw lastError!
    }
}
