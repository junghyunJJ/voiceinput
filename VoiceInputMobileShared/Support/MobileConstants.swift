import Foundation
import VoiceInputCore

public enum MobileConstants {
    public static let appGroupIdentifier = SharedContainerKeys.appGroupIdentifier
    public static let lastTranscriptionKey = SharedContainerKeys.lastTranscriptionKey
    public static let quickNoteHistoryKey = SharedContainerKeys.quickNoteHistoryKey

    public enum Audio {
        public static let sampleRate: Double = 16_000
    }

    public enum Transcription {
        public static let defaultModel = "small"
        public static let modelRepository = "argmaxinc/whisperkit-coreml"
        public static let modelVariants = ["tiny", "base", "small", "large-v3"]
    }
}
