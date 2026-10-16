import Foundation

public enum SpeechFailure {
    public static func dictationDisabled(_ error: Error) -> Bool {
        var current: NSError? = error as NSError
        for _ in 0..<8 {
            guard let value = current else { break }
            let message = value.localizedDescription.lowercased()
            if message.contains("siri and dictation are disabled") || message.contains("dictation is disabled") { return true }
            current = value.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }
}

public enum InsertionPolicy {
    /// A deliberate switch to another application must never receive the pending dictation.
    public static func mayReturnToTarget(frontmost: Int32?, target: Int32, own: Int32) -> Bool {
        target != own && (frontmost == target || frontmost == own)
    }
}
