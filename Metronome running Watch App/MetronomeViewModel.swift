import Foundation
import Combine
import AVFoundation
import MetronomeCore

@MainActor
final class MetronomeViewModel: ObservableObject {
    @Published private(set) var bpm: Int
    @Published private(set) var isPlaying = false

    private let engine: MetronomeEngine
    private let defaults: UserDefaults
    private static let bpmDefaultsKey = "metronome.bpm"
    private var interruptionObserver: NSObjectProtocol?

    init(engine: MetronomeEngine? = nil, defaults: UserDefaults = .standard) {
        self.engine = engine ?? MetronomeEngine()
        self.defaults = defaults
        let storedValue = defaults.integer(forKey: Self.bpmDefaultsKey)
        let initialBPM = storedValue == 0 ? BPM.defaultValue : BPM.clamp(storedValue)
        self.bpm = initialBPM
        self.engine.bpm = initialBPM
        observeInterruptions()
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
    }

    func increment() {
        applyBPM(bpm + 1)
    }

    func decrement() {
        applyBPM(bpm - 1)
    }

    func togglePlayback() {
        if isPlaying {
            engine.stop()
            isPlaying = false
        } else {
            startEngine()
        }
    }

    private func applyBPM(_ newValue: Int) {
        let clamped = BPM.clamp(newValue)
        bpm = clamped
        defaults.set(clamped, forKey: Self.bpmDefaultsKey)
        engine.bpm = clamped
    }

    private func startEngine() {
        Task {
            do {
                try await engine.start()
                isPlaying = true
            } catch {
                isPlaying = false
            }
        }
    }

    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleInterruption(notification)
            }
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            engine.stop()
            isPlaying = false
        case .ended:
            let rawOptions = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            if AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume) {
                startEngine()
            }
        @unknown default:
            break
        }
    }
}
