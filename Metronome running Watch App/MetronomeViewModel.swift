import Foundation
import Combine
import AVFoundation
import MetronomeCore
import os

@MainActor
final class MetronomeViewModel: ObservableObject {
    private static let log = Logger(
        subsystem: "com.brolinjonas.metronome-running", category: "viewmodel"
    )

    @Published private(set) var bpm: Int
    @Published private(set) var isPlaying = false
    @Published private(set) var isStarting = false

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
        if isPlaying || isStarting {
            // Stopping while a start is still activating the audio session
            // cancels that activation (the engine's generation counter makes
            // the in-flight start throw instead of resuming playback).
            engine.stop()
            isPlaying = false
            isStarting = false
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
        guard !isStarting else { return }
        isStarting = true
        Task {
            do {
                try await engine.start()
                isPlaying = true
            } catch {
                Self.log.error(
                    "engine start failed: \(String(describing: error), privacy: .public)"
                )
                isPlaying = false
            }
            isStarting = false
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
