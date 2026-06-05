import Foundation
import Testing
@testable import VoiceInput

@Suite("Model Variant Tests")
struct ModelVariantTests {

    @Test func canonicalizesLegacyLargeV3TurboVariant() {
        #expect(
            Constants.Transcription.canonicalModelVariant("large-v3-turbo")
                == Constants.Transcription.largeV3TurboModelVariant
        )
    }

    @Test func canonicalTurboVariantMatchesWhisperKitFolderSuffix() {
        let variant = Constants.Transcription.largeV3TurboModelVariant

        #expect(variant == "large-v3-v20240930_turbo_632MB")
        #expect(!variant.contains("large-v3-turbo"))
        #expect("openai_whisper-\(variant)".hasSuffix("-\(variant)"))
    }

    @MainActor
    @Test func modelCatalogUsesCanonicalTurboVariant() {
        let manager = ModelManager()
        let variants = manager.availableModels.map(\.variant)
        let turbo = manager.availableModels.first { $0.displayName == "Large v3 Turbo" }

        #expect(turbo?.variant == Constants.Transcription.largeV3TurboModelVariant)
        #expect(turbo?.sizeDescription == "~632 MB")
        #expect(!variants.contains("large-v3-turbo"))
    }

    @MainActor
    @Test func appSettingsResolvesLegacyTurboSelection() {
        let suiteName = "VoiceInputTests.ModelVariant.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("large-v3-turbo", forKey: "selectedModel")

        #expect(
            AppSettings.resolveSelectedModel(from: defaults)
                == Constants.Transcription.largeV3TurboModelVariant
        )
    }
}
