import Foundation

enum Constants {
    static let appName = "Voice Input"
    static let bundleIdentifier = "com.voiceinput.app"

    enum Audio {
        static let sampleRate: Double = 16_000
        static let bufferDurationSeconds: Double = 30
        static let bufferSize: Int = Int(sampleRate * bufferDurationSeconds) // 480,000 samples (~1.83MB)
        static let captureBufferFrameCount: UInt32 = 1024
    }

    enum Transcription {
        static let defaultModelVariant = "small"
        static let modelRepository = "argmaxinc/whisperkit-coreml"
        static let supportedLanguages = ["en", "ko", "ja", "zh", "es", "fr", "de"]
        static let maxCharactersForKeyboardSimulation = 200
    }

    enum UI {
        static let overlayWidth: CGFloat = 280
        static let overlayHeight: CGFloat = 80
        static let overlayCornerRadius: CGFloat = 16
    }

    enum Storage {
        static let modelDirectoryName = "Models"
        static var applicationSupportURL: URL {
            let fm = FileManager.default
            let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let appDir = appSupport.appendingPathComponent(appName)
            if !fm.fileExists(atPath: appDir.path) {
                try? fm.createDirectory(at: appDir, withIntermediateDirectories: true)
            }
            return appDir
        }
        static var modelDirectoryURL: URL {
            applicationSupportURL.appendingPathComponent(modelDirectoryName)
        }
    }
}
