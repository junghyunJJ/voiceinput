import Foundation
import Testing
@testable import VoiceInputMobileShared

@Suite("Mobile WhisperKit Model Recovery Tests")
struct MobileWhisperKitTranscriberTests {

    @Test func matchesVariantForCommonFolderNames() {
        #expect(MobileWhisperKitTranscriber.matchesModelVariant("openai_whisper-small", variant: "small"))
        #expect(MobileWhisperKitTranscriber.matchesModelVariant("openai_whisper_large-v3", variant: "large-v3"))
        #expect(!MobileWhisperKitTranscriber.matchesModelVariant("openai_whisper-base", variant: "small"))
    }

    @Test func detectsMissingRequiredModelFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("voiceinput-model-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let missingInitially = MobileWhisperKitTranscriber.missingRequiredModelFiles(in: root)
        #expect(missingInitially.count == 2)
        #expect(missingInitially.contains("TextDecoder.mlmodelc/model.mil"))
        #expect(missingInitially.contains("TextDecoder.mlmodelc/weights/weight.bin"))

        let decoderDir = root.appendingPathComponent("TextDecoder.mlmodelc", isDirectory: true)
        let weightsDir = decoderDir.appendingPathComponent("weights", isDirectory: true)
        try FileManager.default.createDirectory(at: weightsDir, withIntermediateDirectories: true)
        _ = FileManager.default.createFile(atPath: decoderDir.appendingPathComponent("model.mil").path, contents: Data())
        _ = FileManager.default.createFile(atPath: weightsDir.appendingPathComponent("weight.bin").path, contents: Data())

        let missingAfterCreate = MobileWhisperKitTranscriber.missingRequiredModelFiles(in: root)
        #expect(missingAfterCreate.isEmpty)
    }
}
