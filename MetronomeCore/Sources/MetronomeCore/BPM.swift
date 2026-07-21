public enum BPM {
    public static let range = 120...200
    public static let defaultValue = 160

    public static func clamp(_ value: Int) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
