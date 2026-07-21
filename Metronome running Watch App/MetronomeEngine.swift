import AVFoundation
import MetronomeCore

@MainActor
final class MetronomeEngine {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private let clickBuffer: AVAudioPCMBuffer
    private let scheduleAheadSeconds = 4.0
    private var nextClickSampleTime: AVAudioFramePosition = 0
    private var schedulingTimer: Timer?
    private var configurationChangeObserver: NSObjectProtocol?
    private var startGeneration = 0

    var bpm: Int = BPM.defaultValue {
        didSet {
            guard oldValue != bpm, engine.isRunning else { return }
            player.stop()
            player.play()
            nextClickSampleTime = 0
            scheduleClicks(through: aheadHorizon())
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
    }

    deinit {
        if let configurationChangeObserver {
            NotificationCenter.default.removeObserver(configurationChangeObserver)
        }
    }

    func start() async throws {
        guard schedulingTimer == nil else { return }
        startGeneration += 1
        let generation = startGeneration
        let session = AVAudioSession.sharedInstance()
        // watchOS suspends audio sessions that use the default route-sharing
        // policy as soon as the app is backgrounded, even with the "audio"
        // background mode enabled. Background playback requires the long-form
        // policy (routed to Bluetooth output) activated asynchronously, and
        // long-form sessions reject the mixWithOthers option.
        try session.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
        let activated = try await session.activate(options: [])
        // Activation can suspend on a route picker; bail out if the user
        // declined a route or stop() was called while we waited.
        guard activated, generation == startGeneration, schedulingTimer == nil else {
            throw CancellationError()
        }
        try resumePlayback()
        schedulingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.topUpSchedule()
            }
        }
    }

    func stop() {
        startGeneration += 1
        schedulingTimer?.invalidate()
        schedulingTimer = nil
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func resumePlayback() throws {
        if !engine.isRunning {
            try engine.start()
        }
        nextClickSampleTime = 0
        scheduleClicks(through: aheadHorizon())
        player.play()
    }

    private func handleConfigurationChange() {
        guard schedulingTimer != nil else { return }
        try? resumePlayback()
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
        else { return }
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
