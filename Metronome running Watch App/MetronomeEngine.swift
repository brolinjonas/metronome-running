import AVFoundation
import MetronomeCore
import os

@MainActor
final class MetronomeEngine {
    private static let log = Logger(
        subsystem: "com.brolinjonas.metronome-running", category: "engine"
    )

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private let clickBuffer: AVAudioPCMBuffer
    private let scheduleAheadSeconds = 4.0
    private var nextClickSampleTime: AVAudioFramePosition = 0
    private var schedulingTimer: Timer?
    private var configurationChangeObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var startGeneration = 0
    private var staleRenderTicks = 0
    private var isRecovering = false

    var bpm: Int = BPM.defaultValue {
        didSet {
            guard oldValue != bpm, engine.isRunning else { return }
            restartClickSchedule()
        }
    }

    init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        self.format = format
        self.clickBuffer = Self.makeClickBuffer(format: format)
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        // Route/hardware changes (e.g. connecting AirPods) reconfigure the
        // engine's I/O and stop rendering; without observing this the engine
        // silently goes quiet while callers still think it's playing.
        configurationChangeObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleConfigurationChange()
            }
        }
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: nil
        ) { notification in
            let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) ?? 0
            Task { @MainActor in
                let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
                    .map(\.portName).joined(separator: ", ")
                Self.log.notice(
                    "route change: reason=\(reason) outputs=\(outputs, privacy: .public)"
                )
            }
        }
    }

    deinit {
        if let configurationChangeObserver {
            NotificationCenter.default.removeObserver(configurationChangeObserver)
        }
        if let routeChangeObserver {
            NotificationCenter.default.removeObserver(routeChangeObserver)
        }
    }

    func start() async throws {
        guard schedulingTimer == nil else {
            Self.log.notice("start ignored: scheduling already active")
            return
        }
        startGeneration += 1
        let generation = startGeneration
        Self.log.notice("start requested (generation \(generation))")
        let session = AVAudioSession.sharedInstance()
        // On a cold launch the audio server may not be ready: setCategory
        // itself can fail with '!res' (OSStatus 561145203, "Resource not
        // available"), and the first long-form activation can transiently
        // fail while the Bluetooth link is re-established. Both must sit
        // inside the retry loop. A `false` activation result means the user
        // declined the route picker, which is a final answer and is not
        // retried.
        var attempt = 0
        let activated = try await Retry.run(
            attempts: 5,
            beforeRetry: {
                try await Task.sleep(for: .milliseconds(400))
                guard generation == self.startGeneration else { throw CancellationError() }
            },
            operation: {
                attempt += 1
                do {
                    // watchOS suspends audio sessions that use the default
                    // route-sharing policy as soon as the app is backgrounded,
                    // even with the "audio" background mode enabled.
                    // Background playback requires the long-form policy
                    // (routed to Bluetooth output) activated asynchronously,
                    // and long-form sessions reject the mixWithOthers option.
                    try session.setCategory(
                        .playback, mode: .default, policy: .longFormAudio, options: []
                    )
                    let result = try await session.activate(options: [])
                    Self.log.notice("session activation attempt \(attempt) returned \(result)")
                    return result
                } catch {
                    Self.log.error(
                        "session setup attempt \(attempt) failed: \(String(describing: error), privacy: .public)"
                    )
                    throw error
                }
            }
        )
        // Activation can suspend on a route picker; bail out if the user
        // declined a route or stop() was called while we waited.
        guard activated, generation == startGeneration, schedulingTimer == nil else {
            Self.log.notice(
                "start abandoned: activated=\(activated) generationChanged=\(generation != self.startGeneration)"
            )
            throw CancellationError()
        }
        try resumePlayback()
        staleRenderTicks = 0
        schedulingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.topUpSchedule()
            }
        }
        Self.log.notice("start complete: engineRunning=\(self.engine.isRunning)")
    }

    func stop() {
        Self.log.notice("stop requested")
        startGeneration += 1
        schedulingTimer?.invalidate()
        schedulingTimer = nil
        staleRenderTicks = 0
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func resumePlayback() throws {
        if !engine.isRunning {
            try engine.start()
        }
        restartClickSchedule()
        let renderTimeValid = player.lastRenderTime?.isSampleTimeValid ?? false
        Self.log.notice(
            "playback (re)started: engineRunning=\(self.engine.isRunning) renderTimeValid=\(renderTimeValid)"
        )
    }

    // Fully resets the player before scheduling: stop() discards any stale
    // buffers (e.g. queued before a configuration change) and rewinds the
    // player's timeline to zero so the freshly scheduled click times are in
    // the future. Scheduling clicks without this reset leaves them at sample
    // times the timeline has already passed, which renders as silence.
    private func restartClickSchedule() {
        player.stop()
        player.play()
        nextClickSampleTime = 0
        scheduleClicks(through: aheadHorizon())
    }

    private func handleConfigurationChange() {
        Self.log.notice(
            "configuration change: engineRunning=\(self.engine.isRunning) schedulingActive=\(self.schedulingTimer != nil)"
        )
        guard schedulingTimer != nil else { return }
        recoverPlayback(reason: "configuration change")
    }

    // Restarting the engine can transiently fail while a route transition is
    // still settling, so recovery is retried instead of dropped — a swallowed
    // failure here leaves the app claiming to play while rendering nothing.
    private func recoverPlayback(reason: String) {
        guard !isRecovering else { return }
        isRecovering = true
        let generation = startGeneration
        Task {
            defer { isRecovering = false }
            do {
                try await Retry.run(
                    attempts: 3,
                    beforeRetry: {
                        try await Task.sleep(for: .milliseconds(200))
                        guard generation == self.startGeneration else { throw CancellationError() }
                    },
                    operation: {
                        guard generation == self.startGeneration, self.schedulingTimer != nil else {
                            throw CancellationError()
                        }
                        try self.resumePlayback()
                    }
                )
                Self.log.notice("recovered playback after \(reason, privacy: .public)")
            } catch {
                Self.log.error(
                    "failed to recover playback after \(reason, privacy: .public): \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    private func aheadHorizon() -> AVAudioFramePosition {
        AVAudioFramePosition(scheduleAheadSeconds * format.sampleRate)
    }

    private func scheduleClicks(through horizon: AVAudioFramePosition) {
        let intervalSamples = AVAudioFramePosition(
            ClickInterval.sampleCount(forBPM: bpm, sampleRate: format.sampleRate)
        )
        while nextClickSampleTime < horizon {
            let when = AVAudioTime(sampleTime: nextClickSampleTime, atRate: format.sampleRate)
            player.scheduleBuffer(clickBuffer, at: when, options: [], completionHandler: nil)
            nextClickSampleTime += intervalSamples
        }
    }

    private func topUpSchedule() {
        guard let renderTime = player.lastRenderTime, renderTime.isSampleTimeValid,
              let playerTime = player.playerTime(forNodeTime: renderTime), playerTime.isSampleTimeValid
        else {
            // The engine believes it's playing but nothing is rendering.
            // One stale tick can be a benign transition; two in a row means
            // playback died (e.g. a configuration change that never fired or
            // whose recovery failed), so restart it.
            staleRenderTicks += 1
            Self.log.notice(
                "top-up skipped: render clock invalid (tick \(self.staleRenderTicks)) engineRunning=\(self.engine.isRunning)"
            )
            if staleRenderTicks >= 2 {
                staleRenderTicks = 0
                recoverPlayback(reason: "stale render clock")
            }
            return
        }
        staleRenderTicks = 0
        let horizon = playerTime.sampleTime + AVAudioFramePosition(scheduleAheadSeconds * format.sampleRate)
        scheduleClicks(through: horizon)
    }

    private static func makeClickBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer {
        let durationSeconds = 0.015
        let toneFrequencyHz = 1500.0
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(sampleRate * durationSeconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let channel = buffer.floatChannelData![0]
        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / sampleRate
            let fadeOut = 1.0 - (time / durationSeconds)
            channel[frame] = Float(sin(2.0 * Double.pi * toneFrequencyHz * time) * fadeOut * 0.8)
        }
        return buffer
    }
}
