import AVFoundation
import MetronomeCore

final class MetronomeEngine {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private let clickBuffer: AVAudioPCMBuffer
    private let scheduleAheadSeconds = 4.0
    private var nextClickSampleTime: AVAudioFramePosition = 0
    private var schedulingTimer: Timer?

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
    }

    func start() throws {
        guard schedulingTimer == nil else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        if !engine.isRunning {
            try engine.start()
        }
        nextClickSampleTime = 0
        scheduleClicks(through: aheadHorizon())
        player.play()
        schedulingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.topUpSchedule()
        }
    }

    func stop() {
        schedulingTimer?.invalidate()
        schedulingTimer = nil
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
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
