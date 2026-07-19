public enum ClickInterval {
    public static func seconds(forBPM bpm: Int) -> Double {
        60.0 / Double(bpm)
    }

    public static func sampleCount(forBPM bpm: Int, sampleRate: Double) -> Double {
        sampleRate * seconds(forBPM: bpm)
    }
}
