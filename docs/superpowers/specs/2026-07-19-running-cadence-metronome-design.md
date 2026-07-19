# Running Cadence Metronome — Design

## Purpose

A watchOS app that plays an audible click track at a runner-chosen tempo (beats per minute) to help them train and hold a target running cadence. This is the first feature built on top of the default Xcode watchOS app template — there is no existing implementation to build on.

## Scope

- Single-screen watchOS app.
- Audio clicks only (no haptics, no HealthKit workout, no networking).
- Must keep clicking when the screen is off or the wrist is lowered mid-run.

## Architecture & Components

Three pieces:

- **`MetronomeEngine`** — owns an `AVAudioEngine` + `AVAudioPlayerNode`, generates the synthesized click tone once at startup, and schedules clicks at sample-accurate intervals for a given BPM. Exposes `start()`, `stop()`, and a settable `bpm` that can change while playing.
- **`MetronomeViewModel`** (`ObservableObject`) — holds `@Published var bpm` and `@Published var isPlaying`, drives `MetronomeEngine`, and persists `bpm` to `UserDefaults` on every change / restores it on launch.
- **`ContentView`** — replaces the current template body. Pure display + button taps, bound to the view model.

The audio session is configured once at launch with category `.playback`, and the watch target adds the "Audio, AirPlay, and Picture in Picture" background mode capability. This makes the app eligible to keep running in the background as long as it's actively playing audio — no HealthKit workout session is used or needed.

## UI Layout

Single screen, top to bottom on the watch face:

```
      160
     BPM

  [ -1 ]  [ +1 ]

    ▶ Play
```

- Large BPM number as the focal point.
- `-1` / `+1` buttons, clamped to the 120–200 range.
- Play/Stop button below; toggles label and starts/stops `MetronomeEngine`. Changing BPM while playing takes effect immediately without requiring Stop first.

## BPM Control

- Range: 120–200 BPM.
- Step: ±1 per tap, for fine-grained cadence tuning.
- Buttons disable/clamp at the range edges.

## Audio Engine Details

- **Click tone**: generated once at startup as a short buffer (~15ms burst of a ~1.5kHz sine wave with a quick fade-out to avoid pop/click artifacts), held in memory as an `AVAudioPCMBuffer`.
- **Scheduling**: the engine keeps a rolling window of upcoming clicks scheduled on the `AVAudioPlayerNode` (e.g. ~4 seconds ahead), computed from `sample rate ÷ (BPM / 60)`. The schedule is topped up before it runs out, driven off the player node's render timeline rather than a wall-clock `Timer`. This gives sample-accurate, drift-free timing over a long run.
- **Changing BPM mid-play**: clears anything scheduled beyond "now" and re-schedules forward at the new interval, so the next click can shift immediately without a restart or audible glitch.
- **Engine lifecycle**: the `AVAudioEngine` starts when Play is tapped and stops when Stop is tapped, releasing the audio session so it doesn't block other apps' audio while idle. While playing, the engine runs continuously — this continuous activity is what keeps watchOS from suspending the app when the screen sleeps or the wrist drops.

## State & Persistence

- `MetronomeViewModel.bpm` defaults to `160` if nothing is stored yet.
- Every change is written immediately to `UserDefaults.standard` under key `"metronome.bpm"` — no debouncing needed at this scale.
- On launch, the stored value is read back before the view renders.
- `isPlaying` is never persisted; the app always opens stopped, since auto-starting audio on launch would be surprising.

## Error Handling

- **Audio session activation fails** (e.g. another app holds exclusive control): `MetronomeEngine.start()` surfaces the failure, the view model catches it, and `isPlaying` stays `false` — the Play button simply stays in its "not playing" state. No user-facing error dialog.
- **Interruption during playback** (phone call, Siri, etc.): the app observes `AVAudioSession.interruptionNotification`.
  - On `.began`: stop the engine and flip `isPlaying` to `false`.
  - On `.ended`: if the interruption options indicate resumption is possible (`.shouldResume`), automatically restart the engine and flip `isPlaying` back to `true`, so a transient interruption doesn't require the runner to fumble with the watch mid-run.

## Testing

- **Unit-testable**: BPM clamping logic (120–200, ±1 step) and the click-interval math (BPM → sample interval), in isolation from `AVAudioEngine`.
- **Manual verification on device/simulator**: Play/Stop toggling, BPM adjustment while playing, persistence across relaunch, and — most importantly — background behavior (start playback, lock the watch or lower the wrist, confirm clicks continue). Background behavior cannot be meaningfully unit tested and needs verification on a real watch.
