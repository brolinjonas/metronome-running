# Running Cadence Metronome Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a watchOS app that plays a sample-accurate audio click track at a runner-chosen BPM, keeps clicking when the screen is off or the wrist is lowered, and remembers the last BPM used.

**Architecture:** Pure BPM/tempo math lives in a local Swift package (`MetronomeCore`) so it can be unit tested with plain `swift test`, with no Xcode simulator or AVFoundation involved. The watchOS app itself has three pieces: `MetronomeEngine` (an `AVAudioEngine` wrapper that generates a synthesized click and schedules it sample-accurately), `MetronomeViewModel` (`ObservableObject` holding `bpm`/`isPlaying`, UserDefaults persistence, and interruption handling), and `ContentView` (the display + buttons). `MetronomeEngine`/`MetronomeViewModel` are verified by building the app and by manual on-device testing — the spec explicitly scopes automated tests to the pure math, not to AVAudioEngine or SwiftUI code.

**Tech Stack:** Swift 6, SwiftUI, AVFoundation (`AVAudioEngine`/`AVAudioPlayerNode`), a local Swift Package (SwiftPM) for testable logic, XCTest via `swift test`, watchOS 26.5 deployment target (matches this project's existing build settings).

## Global Constraints

- BPM range: 120–200, adjustable in steps of ±1 per tap.
- Default BPM when nothing is stored: 160.
- Persisted via `UserDefaults.standard` under key `"metronome.bpm"`, written on every change.
- `isPlaying` is never persisted — the app always opens stopped.
- Click tone: synthesized, ~15ms burst of a ~1.5kHz sine wave with a linear fade-out (no bundled audio file).
- Click scheduling must be sample-accurate (via `AVAudioEngine`/`AVAudioPlayerNode` scheduling), not a wall-clock `Timer` driving playback — this is what avoids drift and keeps the app eligible to run with the screen off.
- Background audio: audio session category `.playback` + the watchOS "audio" background mode (`INFOPLIST_KEY_UIBackgroundModes = audio`). No HealthKit, no workout session.
- On `AVAudioSession` interruption: stop playback and flip `isPlaying` to `false` on `.began`; automatically resume playback on `.ended` if `AVAudioSession.InterruptionOptions.shouldResume` is present.
- Automated tests are limited to BPM clamping and BPM→sample-interval math (per spec); everything touching `AVAudioEngine` or SwiftUI is verified by building successfully and by manual on-device/simulator checks.

---

### Task 1: MetronomeCore package — BPM range & clamping

**Files:**
- Create: `MetronomeCore/Package.swift`
- Create: `MetronomeCore/Sources/MetronomeCore/BPM.swift`
- Create: `MetronomeCore/Tests/MetronomeCoreTests/BPMTests.swift`
- Modify: `.gitignore`

**Interfaces:**
- Produces: `enum BPM` with `static let range: ClosedRange<Int>` (120...200), `static let defaultValue: Int` (160), `static func clamp(_ value: Int) -> Int`.

- [ ] **Step 1: Scaffold the package and update `.gitignore`**

Run from the repository root:

```bash
mkdir -p MetronomeCore/Sources/MetronomeCore MetronomeCore/Tests/MetronomeCoreTests
```

Add to `.gitignore` (append to the end of the file):

```
# Swift Package Manager
.build/
.swiftpm/
```

Create `MetronomeCore/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MetronomeCore",
    platforms: [.watchOS(.v10), .iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MetronomeCore", targets: ["MetronomeCore"])
    ],
    targets: [
        .target(name: "MetronomeCore"),
        .testTarget(name: "MetronomeCoreTests", dependencies: ["MetronomeCore"])
    ]
)
```

- [ ] **Step 2: Write the failing test**

Create `MetronomeCore/Tests/MetronomeCoreTests/BPMTests.swift`:

```swift
import XCTest
@testable import MetronomeCore

final class BPMTests: XCTestCase {
    func testClampWithinRangeReturnsSameValue() {
        XCTAssertEqual(BPM.clamp(160), 160)
    }

    func testClampBelowRangeReturnsLowerBound() {
        XCTAssertEqual(BPM.clamp(50), 120)
    }

    func testClampAboveRangeReturnsUpperBound() {
        XCTAssertEqual(BPM.clamp(999), 200)
    }

    func testClampAtLowerBoundaryReturnsLowerBound() {
        XCTAssertEqual(BPM.clamp(120), 120)
    }

    func testClampAtUpperBoundaryReturnsUpperBound() {
        XCTAssertEqual(BPM.clamp(200), 200)
    }

    func testDefaultValueIsWithinRange() {
        XCTAssertTrue(BPM.range.contains(BPM.defaultValue))
    }
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd MetronomeCore && swift test`
Expected: FAIL to build — `error: cannot find 'BPM' in scope`

- [ ] **Step 4: Implement `BPM`**

Create `MetronomeCore/Sources/MetronomeCore/BPM.swift`:

```swift
public enum BPM {
    public static let range = 120...200
    public static let defaultValue = 160

    public static func clamp(_ value: Int) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd MetronomeCore && swift test`
Expected: `Executed 6 tests, with 0 failures`

- [ ] **Step 6: Commit**

```bash
git add MetronomeCore .gitignore
git commit -m "Add MetronomeCore package with BPM range and clamping"
```

---

### Task 2: MetronomeCore package — click interval math

**Files:**
- Create: `MetronomeCore/Sources/MetronomeCore/ClickInterval.swift`
- Create: `MetronomeCore/Tests/MetronomeCoreTests/ClickIntervalTests.swift`

**Interfaces:**
- Consumes: nothing from Task 1 (independent pure math).
- Produces: `enum ClickInterval` with `static func seconds(forBPM bpm: Int) -> Double` and `static func sampleCount(forBPM bpm: Int, sampleRate: Double) -> Double`.

- [ ] **Step 1: Write the failing test**

Create `MetronomeCore/Tests/MetronomeCoreTests/ClickIntervalTests.swift`:

```swift
import XCTest
@testable import MetronomeCore

final class ClickIntervalTests: XCTestCase {
    func testSecondsForBPM60IsOneSecond() {
        XCTAssertEqual(ClickInterval.seconds(forBPM: 60), 1.0, accuracy: 0.0001)
    }

    func testSecondsForBPM120IsHalfSecond() {
        XCTAssertEqual(ClickInterval.seconds(forBPM: 120), 0.5, accuracy: 0.0001)
    }

    func testSampleCountForBPM120At44100Hz() {
        // 120 BPM -> 0.5s per beat; 44100 * 0.5 = 22050 samples
        XCTAssertEqual(ClickInterval.sampleCount(forBPM: 120, sampleRate: 44100), 22050, accuracy: 0.001)
    }

    func testSampleCountForBPM160At48000Hz() {
        // 160 BPM -> 0.375s per beat; 48000 * 0.375 = 18000 samples
        XCTAssertEqual(ClickInterval.sampleCount(forBPM: 160, sampleRate: 48000), 18000, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd MetronomeCore && swift test`
Expected: FAIL to build — `error: cannot find 'ClickInterval' in scope`

- [ ] **Step 3: Implement `ClickInterval`**

Create `MetronomeCore/Sources/MetronomeCore/ClickInterval.swift`:

```swift
public enum ClickInterval {
    public static func seconds(forBPM bpm: Int) -> Double {
        60.0 / Double(bpm)
    }

    public static func sampleCount(forBPM bpm: Int, sampleRate: Double) -> Double {
        sampleRate * seconds(forBPM: bpm)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd MetronomeCore && swift test`
Expected: `Executed 10 tests, with 0 failures` (6 from Task 1 + 4 from this task)

- [ ] **Step 5: Commit**

```bash
git add MetronomeCore
git commit -m "Add BPM-to-sample-interval math to MetronomeCore"
```

---

### Task 3: Wire MetronomeCore into the Xcode project and enable background audio

**Files:**
- Modify: `Metronome running.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: the `MetronomeCore` product (library target) from Tasks 1–2.
- Produces: the "Metronome running Watch App" target can `import MetronomeCore`, and is configured with `INFOPLIST_KEY_UIBackgroundModes = audio` on both Debug and Release.

This project uses Xcode's file-system-synchronized groups, so no per-file pbxproj edits are needed for Swift source files — only this one-time package dependency and background-mode wiring requires editing the project file directly, via the `xcodeproj` Ruby gem (hand-editing `project.pbxproj` for package references is error-prone; this gem generates the correct object graph).

- [ ] **Step 1: Ensure the `xcodeproj` gem is installed**

Run: `gem list -i xcodeproj`
Expected: `true`. If it prints `false`, run `gem install xcodeproj --user-install` first.

- [ ] **Step 2: Write the one-time wiring script**

Create a temporary file `wire_metronome_core.rb` at the repository root:

```ruby
require "xcodeproj"

project_path = "Metronome running.xcodeproj"
project = Xcodeproj::Project.open(project_path)

watch_target = project.native_targets.find { |t| t.name == "Metronome running Watch App" }
raise "Watch App target not found" unless watch_target

package_ref = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
package_ref.relative_path = "MetronomeCore"
project.root_object.package_references << package_ref

product_dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
product_dep.package = package_ref
product_dep.product_name = "MetronomeCore"
watch_target.package_product_dependencies << product_dep

build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
build_file.product_ref = product_dep
watch_target.frameworks_build_phase.files << build_file

watch_target.build_configurations.each do |config|
  config.build_settings["INFOPLIST_KEY_UIBackgroundModes"] = "audio"
end

project.save
puts "MetronomeCore dependency and background audio mode added."
```

- [ ] **Step 3: Run the script**

Run: `ruby wire_metronome_core.rb`
Expected: `MetronomeCore dependency and background audio mode added.`

- [ ] **Step 4: Verify the project builds with the new dependency**

Run: `xcodebuild -project "Metronome running.xcodeproj" -scheme "Metronome running Watch App" -destination 'generic/platform=watchOS Simulator' build`
Expected: last line is `** BUILD SUCCEEDED **`

- [ ] **Step 5: Remove the temporary script**

Run: `rm wire_metronome_core.rb`

- [ ] **Step 6: Commit**

```bash
git add "Metronome running.xcodeproj/project.pbxproj"
git commit -m "Add MetronomeCore package dependency and enable background audio mode"
```

---

### Task 4: MetronomeEngine — synthesized click playback with sample-accurate scheduling

**Files:**
- Create: `Metronome running Watch App/MetronomeEngine.swift`

**Interfaces:**
- Consumes: `BPM.defaultValue` (Task 1), `ClickInterval.sampleCount(forBPM:sampleRate:)` (Task 2).
- Produces: `final class MetronomeEngine` with `var bpm: Int`, `func start() throws`, `func stop()`.

This class has no automated tests (per spec, `AVAudioEngine` behavior is verified manually) — its "test" is a successful build, followed by manual verification in Task 7.

- [ ] **Step 1: Create `MetronomeEngine.swift`**

Create `Metronome running Watch App/MetronomeEngine.swift`:

```swift
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
```

- [ ] **Step 2: Verify the project builds**

Run: `xcodebuild -project "Metronome running.xcodeproj" -scheme "Metronome running Watch App" -destination 'generic/platform=watchOS Simulator' build`
Expected: last line is `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add "Metronome running Watch App/MetronomeEngine.swift"
git commit -m "Add MetronomeEngine with synthesized click and sample-accurate scheduling"
```

---

### Task 5: MetronomeViewModel — state, persistence, and interruption handling

**Files:**
- Create: `Metronome running Watch App/MetronomeViewModel.swift`

**Interfaces:**
- Consumes: `BPM.clamp(_:)`, `BPM.defaultValue` (Task 1); `MetronomeEngine` with `var bpm: Int`, `func start() throws`, `func stop()` (Task 4).
- Produces: `@MainActor final class MetronomeViewModel: ObservableObject` with `@Published private(set) var bpm: Int`, `@Published private(set) var isPlaying: Bool`, `func increment()`, `func decrement()`, `func togglePlayback()`.

No automated tests for this class (per spec) — verified by build success and manual testing in Task 7.

- [ ] **Step 1: Create `MetronomeViewModel.swift`**

Create `Metronome running Watch App/MetronomeViewModel.swift`:

```swift
import Foundation
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

    init(engine: MetronomeEngine = MetronomeEngine(), defaults: UserDefaults = .standard) {
        self.engine = engine
        self.defaults = defaults
        let storedValue = defaults.integer(forKey: Self.bpmDefaultsKey)
        let initialBPM = storedValue == 0 ? BPM.defaultValue : BPM.clamp(storedValue)
        self.bpm = initialBPM
        engine.bpm = initialBPM
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
        do {
            try engine.start()
            isPlaying = true
        } catch {
            isPlaying = false
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
```

- [ ] **Step 2: Verify the project builds**

Run: `xcodebuild -project "Metronome running.xcodeproj" -scheme "Metronome running Watch App" -destination 'generic/platform=watchOS Simulator' build`
Expected: last line is `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add "Metronome running Watch App/MetronomeViewModel.swift"
git commit -m "Add MetronomeViewModel with persistence and interruption handling"
```

---

### Task 6: ContentView — display and controls

**Files:**
- Modify: `Metronome running Watch App/ContentView.swift`

**Interfaces:**
- Consumes: `MetronomeViewModel` with `bpm: Int`, `isPlaying: Bool`, `increment()`, `decrement()`, `togglePlayback()` (Task 5).

- [ ] **Step 1: Replace the template UI**

Replace the full contents of `Metronome running Watch App/ContentView.swift`:

```swift
//
//  ContentView.swift
//  Metronome running Watch App
//
//  Created by Jonas Brolin on 2026-07-19.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = MetronomeViewModel()

    var body: some View {
        VStack(spacing: 8) {
            Text("\(viewModel.bpm)")
                .font(.system(size: 40, weight: .bold))
            Text("BPM")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("-1") { viewModel.decrement() }
                Button("+1") { viewModel.increment() }
            }

            Button(viewModel.isPlaying ? "Stop" : "Play") {
                viewModel.togglePlayback()
            }
            .tint(viewModel.isPlaying ? .red : .green)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
```

- [ ] **Step 2: Verify the project builds**

Run: `xcodebuild -project "Metronome running.xcodeproj" -scheme "Metronome running Watch App" -destination 'generic/platform=watchOS Simulator' build`
Expected: last line is `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add "Metronome running Watch App/ContentView.swift"
git commit -m "Add BPM display and playback controls to ContentView"
```

---

### Task 7: Manual verification on device/simulator

**Files:** none — this task is manual QA, performed by you (not build-verifiable, per spec).

- [ ] **Step 1:** Launch the app on a simulator or physical Apple Watch.
- [ ] **Step 2:** Tap `+1` / `-1` repeatedly; confirm the BPM display updates by 1 each tap and clamps at 120 and 200.
- [ ] **Step 3:** Tap Play; confirm you hear clicks at roughly the displayed tempo, and the button switches to "Stop".
- [ ] **Step 4:** While playing, tap `+1`/`-1`; confirm the click rate changes without the audio stopping or glitching noticeably.
- [ ] **Step 5:** Tap Stop; confirm clicks stop immediately.
- [ ] **Step 6:** Start playback, then lock the watch screen or lower your wrist for at least 30 seconds; confirm clicks continue uninterrupted.
- [ ] **Step 7:** Force-quit and relaunch the app; confirm the displayed BPM matches the last value set before quitting.
- [ ] **Step 8:** During playback, trigger an audio interruption (e.g., an incoming call or "Hey Siri"); confirm clicking stops during the interruption and resumes automatically once it ends.
