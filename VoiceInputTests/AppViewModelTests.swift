import Foundation
import Testing
import VoiceInputCore
@testable import VoiceInput

@MainActor
@Suite("AppViewModel Tests")
struct AppViewModelTests {
    private final class Harness {
        var micGranted = true
        var requestedMicPermission = true
        var accessibilityGranted = false
        var captureResult = AudioCaptureResult(
            samples: [0.1, 0.2],
            rawBufferCount: 1,
            totalFrames: 2,
            didReceiveTap: true,
            sourceSampleRate: 16_000,
            stopReason: .ok
        )
        var transcriptionResult = TranscriptionResult(
            text: "hello world",
            language: "en",
            segments: [],
            duration: 0.1
        )
        var insertSuccess = true
        var insertResult = TextInsertionManager.InsertionResult(success: true, method: .keyboard)
        var repairResult = TextInsertionManager.InsertionResult(success: false, method: .accessibility)
        var resetCount = 0
        var insertCalls: [(text: String, accessibility: Bool)] = []
        var repairCalls: [(text: String, accessibility: Bool)] = []
        var copiedTexts: [String] = []
        var loadedModels: [String] = []
        var unloadedModelCount = 0
        var requestedPermissionCount = 0
        var refreshedPermissionsCount = 0
        var processTranscription: (String) -> PostTranscriptionProcessingResult = { text in
            PostTranscriptionProcessingResult(originalText: text, processedText: text)
        }
    }

    @Test func noAudioCaptureResetsCycleWithoutError() async {
        let harness = Harness()
        harness.captureResult = AudioCaptureResult(
            samples: [],
            rawBufferCount: 0,
            totalFrames: 0,
            didReceiveTap: false,
            sourceSampleRate: nil,
            stopReason: .noRawBuffersCaptured
        )
        let viewModel = makeViewModel(harness: harness)

        await viewModel.startRecording()
        #expect(viewModel.recordingState.isRecording)

        await viewModel.stopRecording()

        #expect(viewModel.recordingState == .idle)
        #expect(viewModel.showError == false)
        #expect(harness.resetCount == 1)
        #expect(viewModel.lastTranscription.isEmpty)
    }

    @Test func repeatedConfigurationChangeNoAudioShowsActionableError() async {
        let harness = Harness()
        harness.captureResult = AudioCaptureResult(
            samples: [],
            rawBufferCount: 0,
            totalFrames: 0,
            didReceiveTap: false,
            sourceSampleRate: nil,
            stopReason: .engineConfigurationChanged
        )
        let viewModel = makeViewModel(harness: harness)

        for _ in 0..<3 {
            await viewModel.startRecording()
            await viewModel.stopRecording()
        }

        let expected = "Microphone capture stopped before any audio reached Voice Input. Check System Settings > Sound > Input, switch to the microphone you want to use, then retry."
        #expect(viewModel.showError)
        #expect(viewModel.errorMessage == expected)
        #expect(viewModel.recordingState == .error(message: expected))
        #expect(harness.resetCount == 3)
    }

    @Test func emptyTranscriptionSkipsInsertionAndResets() async {
        let harness = Harness()
        harness.transcriptionResult = TranscriptionResult(
            text: "",
            language: "auto",
            segments: [],
            duration: 0.1
        )
        let viewModel = makeViewModel(harness: harness)

        await viewModel.startRecording()
        await viewModel.stopRecording()

        #expect(viewModel.recordingState == .idle)
        #expect(viewModel.lastTranscription.isEmpty)
        #expect(harness.insertCalls.isEmpty)
        #expect(harness.copiedTexts.isEmpty)
        #expect(harness.resetCount == 1)
    }

    @Test func autoInsertOffStoresTranscriptionWithoutInsertion() async {
        let harness = Harness()
        let settings = makeSettings()
        settings.autoInsertText = false
        let viewModel = makeViewModel(harness: harness, settings: settings)

        await viewModel.startRecording()
        await viewModel.stopRecording()

        #expect(viewModel.recordingState == .idle)
        #expect(viewModel.lastTranscription == "hello world")
        #expect(harness.insertCalls.isEmpty)
        #expect(harness.copiedTexts.isEmpty)
        #expect(harness.resetCount == 1)
    }

    @Test func failedInsertionFallsBackToClipboardCopy() async {
        let harness = Harness()
        harness.insertSuccess = false
        harness.accessibilityGranted = true
        let viewModel = makeViewModel(harness: harness)

        await viewModel.startRecording()
        await viewModel.stopRecording()

        #expect(viewModel.recordingState == .idle)
        #expect(viewModel.lastTranscription == "hello world")
        #expect(harness.insertCalls.count == 1)
        #expect(harness.insertCalls.first?.text == "hello world")
        #expect(harness.insertCalls.first?.accessibility == true)
        #expect(harness.copiedTexts == ["hello world"])
        #expect(harness.resetCount == 1)
    }

    @Test func microphonePermissionDeniedSetsErrorAndResetsHotkey() async {
        let harness = Harness()
        harness.micGranted = false
        harness.requestedMicPermission = false
        let viewModel = makeViewModel(harness: harness)

        await viewModel.startRecording()

        #expect(harness.requestedPermissionCount == 1)
        #expect(harness.resetCount == 1)
        #expect(viewModel.showError)
        #expect(viewModel.recordingState == .error(message: "Microphone permission is required."))
    }

    @Test func stopRecordingPublishesSuppressedCandidateSuggestions() async {
        let harness = Harness()
        harness.transcriptionResult = TranscriptionResult(
            text: "챗 지피티에서 확인",
            language: "ko",
            segments: [],
            duration: 0.1
        )
        harness.processTranscription = { text in
            let sourceText = "챗 지피티에서"
            let sourceRange = (text as NSString).range(of: sourceText)
            return PostTranscriptionProcessingResult(
                originalText: text,
                processedText: text,
                suppressedCandidates: [
                    TranscriptionCandidateCorrection(
                        sourceText: sourceText,
                        replacement: "ChatGPT",
                        resolvedReplacement: "ChatGPT에서",
                        sourceRangeLocation: sourceRange.location,
                        sourceRangeLength: sourceRange.length,
                        confidence: 0.62,
                        evidence: TranscriptionCorrectionEvidence(
                            kind: .candidateRule,
                            detail: "mixed-language alias heuristic"
                        ),
                        autoApplyPolicy: .ifConfidenceAtLeast(0.9)
                    )
                ]
            )
        }
        let viewModel = makeViewModel(harness: harness)

        await viewModel.startRecording()
        await viewModel.stopRecording()

        #expect(viewModel.lastTranscription == "챗 지피티에서 확인")
        #expect(viewModel.suppressedCandidateSuggestions.count == 1)
        #expect(viewModel.suppressedCandidateSuggestions.first?.resolvedReplacement == "ChatGPT에서")
    }

    @Test func stopRecordingUsesDedupedSuppressedCandidateSuggestionsFromSharedCore() async {
        let harness = Harness()
        harness.transcriptionResult = TranscriptionResult(
            text: "챗 지피티에서 확인",
            language: "ko",
            segments: [],
            duration: 0.1
        )
        harness.processTranscription = { text in
            PostTranscriptionProcessor(
                configuration: PostTranscriptionProcessingConfiguration(
                    candidateCorrections: [
                        TranscriptionCandidateCorrectionRule(
                            source: "chat gp t",
                            aliases: ["챗 지피티"],
                            replacement: "ChatGPT",
                            confidence: 0.61,
                            evidence: TranscriptionCorrectionEvidence(
                                kind: .candidateRule,
                                detail: "alias heuristic"
                            ),
                            autoApplyPolicy: .ifConfidenceAtLeast(0.9)
                        ),
                        TranscriptionCandidateCorrectionRule(
                            source: "chat g p t",
                            aliases: ["챗 지피티"],
                            replacement: "ChatGPT",
                            confidence: 0.74,
                            evidence: TranscriptionCorrectionEvidence(
                                kind: .candidateRule,
                                detail: "higher confidence overlap"
                            ),
                            autoApplyPolicy: .ifConfidenceAtLeast(0.9)
                        )
                    ],
                    formatting: .preserveExactOutput,
                    outputPreset: .verbatim
                )
            )
            .process(text)
        }
        let viewModel = makeViewModel(harness: harness)

        await viewModel.startRecording()
        await viewModel.stopRecording()

        #expect(viewModel.suppressedCandidateSuggestions.count == 1)
        #expect(viewModel.suppressedCandidateSuggestions.first?.confidence == 0.74)
        #expect(viewModel.suppressedCandidateSuggestions.first?.canonicalSource == nil)
    }

    @Test func stopRecordingRecomputesSuppressedCandidateSpansAgainstProcessedText() async {
        let harness = Harness()
        harness.accessibilityGranted = true
        harness.insertResult = TextInsertionManager.InsertionResult(
            success: true,
            method: .accessibility,
            repairContext: TextInsertionManager.RepairContext()
        )
        harness.repairResult = TextInsertionManager.InsertionResult(
            success: true,
            method: .accessibility,
            repairContext: TextInsertionManager.RepairContext()
        )
        harness.transcriptionResult = TranscriptionResult(
            text: "  ping chat gp t after lunch  ",
            language: "en",
            segments: [],
            duration: 0.1
        )
        harness.processTranscription = { text in
            let rawText = "  ping chat gp t after lunch  "
            let finalText = "Ping chat gp t after lunch."
            let visibleText = text == rawText ? finalText : text
            let sourceRangeBase = text == rawText ? text : visibleText
            let sourceRange = (sourceRangeBase as NSString).range(of: "chat gp t")
            return PostTranscriptionProcessingResult(
                originalText: text,
                processedText: visibleText,
                suppressedCandidates: [
                    TranscriptionCandidateCorrection(
                        sourceText: "chat gp t",
                        replacement: "ChatGPT",
                        resolvedReplacement: "ChatGPT",
                        sourceRangeLocation: sourceRange.location,
                        sourceRangeLength: sourceRange.length,
                        confidence: 0.62,
                        evidence: TranscriptionCorrectionEvidence(
                            kind: .candidateRule,
                            detail: "polished-message span alignment"
                        ),
                        autoApplyPolicy: .ifConfidenceAtLeast(0.9)
                    )
                ]
            )
        }
        let viewModel = makeViewModel(harness: harness)

        await viewModel.startRecording()
        await viewModel.stopRecording()

        #expect(viewModel.lastTranscription == "Ping chat gp t after lunch.")
        #expect(viewModel.suppressedCandidateSuggestions.count == 1)
        #expect(viewModel.suppressedCandidateSuggestions.first?.sourceRangeLocation == 5)
        #expect(viewModel.applySuppressedCandidateSuggestion(at: 0))
        #expect(harness.repairCalls.count == 1)
        #expect(viewModel.lastTranscription == "Ping ChatGPT after lunch.")
    }

    @Test func applySuppressedCandidateSuggestionFailsClosedWithoutRecentInsertionSession() async {
        let harness = Harness()
        harness.processTranscription = { text in
            let suggestions: [TranscriptionCandidateCorrection]
            if text.contains("챗 지피티에서") {
                let sourceText = "챗 지피티에서"
                let sourceRange = (text as NSString).range(of: sourceText)
                suggestions = [
                    TranscriptionCandidateCorrection(
                        sourceText: sourceText,
                        replacement: "ChatGPT",
                        resolvedReplacement: "ChatGPT에서",
                        sourceRangeLocation: sourceRange.location,
                        sourceRangeLength: sourceRange.length,
                        confidence: 0.62,
                        evidence: TranscriptionCorrectionEvidence(
                            kind: .candidateRule,
                            detail: "mixed-language alias heuristic"
                        ),
                        autoApplyPolicy: .ifConfidenceAtLeast(0.9)
                    )
                ]
            } else {
                suggestions = []
            }

            return PostTranscriptionProcessingResult(
                originalText: text,
                processedText: text,
                suppressedCandidates: suggestions
            )
        }
        let viewModel = makeViewModel(harness: harness)
        viewModel.lastTranscription = "챗 지피티에서 확인"
        viewModel.suppressedCandidateSuggestions = harness.processTranscription("챗 지피티에서 확인").suppressedCandidates

        let applied = viewModel.applySuppressedCandidateSuggestion(at: 0)
        let copied = viewModel.copySuppressedCandidateSuggestion(at: 0)

        #expect(!applied)
        #expect(copied)
        #expect(harness.copiedTexts == ["ChatGPT에서 확인"])
        #expect(viewModel.lastTranscription == "챗 지피티에서 확인")
        #expect(viewModel.suppressedCandidateSuggestions.count == 1)
    }

    @Test func applySuppressedCandidateSuggestionRepairsRecentAccessibilityInsertion() async {
        let harness = Harness()
        harness.accessibilityGranted = true
        harness.transcriptionResult = TranscriptionResult(
            text: "챗 지피티에서 확인",
            language: "ko",
            segments: [],
            duration: 0.1
        )
        harness.insertResult = TextInsertionManager.InsertionResult(
            success: true,
            method: .accessibility,
            repairContext: TextInsertionManager.RepairContext()
        )
        harness.repairResult = TextInsertionManager.InsertionResult(
            success: true,
            method: .accessibility,
            repairContext: TextInsertionManager.RepairContext()
        )
        harness.processTranscription = { text in
            let suggestions: [TranscriptionCandidateCorrection]
            if text.contains("챗 지피티에서") {
                let sourceText = "챗 지피티에서"
                let sourceRange = (text as NSString).range(of: sourceText)
                suggestions = [
                    TranscriptionCandidateCorrection(
                        sourceText: sourceText,
                        replacement: "ChatGPT",
                        resolvedReplacement: "ChatGPT에서",
                        sourceRangeLocation: sourceRange.location,
                        sourceRangeLength: sourceRange.length,
                        confidence: 0.62,
                        evidence: TranscriptionCorrectionEvidence(
                            kind: .candidateRule,
                            detail: "mixed-language alias heuristic"
                        ),
                        autoApplyPolicy: .ifConfidenceAtLeast(0.9)
                    )
                ]
            } else {
                suggestions = []
            }

            return PostTranscriptionProcessingResult(
                originalText: text,
                processedText: text,
                suppressedCandidates: suggestions
            )
        }
        let viewModel = makeViewModel(harness: harness)

        await viewModel.startRecording()
        await viewModel.stopRecording()

        let applied = viewModel.applySuppressedCandidateSuggestion(at: 0)
        let copied = viewModel.copySuppressedCandidateSuggestion(at: 0)

        #expect(applied)
        #expect(!copied)
        #expect(harness.repairCalls.count == 1)
        #expect(harness.repairCalls.first?.text == "ChatGPT에서 확인")
        #expect(viewModel.lastTranscription == "ChatGPT에서 확인")
        #expect(viewModel.suppressedCandidateSuggestions.isEmpty)
    }

    @Test func applySuppressedCandidateSuggestionFailsClosedForNonRepairableRecentInsertion() async {
        let harness = Harness()
        harness.accessibilityGranted = true
        harness.transcriptionResult = TranscriptionResult(
            text: "챗 지피티에서 확인",
            language: "ko",
            segments: [],
            duration: 0.1
        )
        harness.insertResult = TextInsertionManager.InsertionResult(
            success: true,
            method: .keyboard
        )
        harness.processTranscription = { text in
            let sourceText = "챗 지피티에서"
            let sourceRange = (text as NSString).range(of: sourceText)
            return PostTranscriptionProcessingResult(
                originalText: text,
                processedText: text,
                suppressedCandidates: [
                    TranscriptionCandidateCorrection(
                        sourceText: sourceText,
                        replacement: "ChatGPT",
                        resolvedReplacement: "ChatGPT에서",
                        sourceRangeLocation: sourceRange.location,
                        sourceRangeLength: sourceRange.length,
                        confidence: 0.62,
                        evidence: TranscriptionCorrectionEvidence(
                            kind: .candidateRule,
                            detail: "mixed-language alias heuristic"
                        ),
                        autoApplyPolicy: .ifConfidenceAtLeast(0.9)
                    )
                ]
            )
        }
        let viewModel = makeViewModel(harness: harness)

        await viewModel.startRecording()
        await viewModel.stopRecording()

        let applied = viewModel.applySuppressedCandidateSuggestion(at: 0)
        let copied = viewModel.copySuppressedCandidateSuggestion(at: 0)

        #expect(!applied)
        #expect(copied)
        #expect(harness.copiedTexts == ["ChatGPT에서 확인"])
        #expect(harness.repairCalls.isEmpty)
        #expect(viewModel.lastTranscription == "챗 지피티에서 확인")
        #expect(viewModel.suppressedCandidateSuggestions.count == 1)
    }

    @Test func applySuppressedCandidateSuggestionFailsClosedAfterClipboardFallback() async {
        let harness = Harness()
        harness.accessibilityGranted = true
        harness.insertSuccess = false
        harness.insertResult = TextInsertionManager.InsertionResult(
            success: false,
            method: .clipboard
        )
        harness.transcriptionResult = TranscriptionResult(
            text: "챗 지피티에서 확인",
            language: "ko",
            segments: [],
            duration: 0.1
        )
        harness.processTranscription = { text in
            let sourceText = "챗 지피티에서"
            let sourceRange = (text as NSString).range(of: sourceText)
            return PostTranscriptionProcessingResult(
                originalText: text,
                processedText: text,
                suppressedCandidates: [
                    TranscriptionCandidateCorrection(
                        sourceText: sourceText,
                        replacement: "ChatGPT",
                        resolvedReplacement: "ChatGPT에서",
                        sourceRangeLocation: sourceRange.location,
                        sourceRangeLength: sourceRange.length,
                        confidence: 0.62,
                        evidence: TranscriptionCorrectionEvidence(
                            kind: .candidateRule,
                            detail: "mixed-language alias heuristic"
                        ),
                        autoApplyPolicy: .ifConfidenceAtLeast(0.9)
                    )
                ]
            )
        }
        let viewModel = makeViewModel(harness: harness)

        await viewModel.startRecording()
        await viewModel.stopRecording()

        let applied = viewModel.applySuppressedCandidateSuggestion(at: 0)
        let copied = viewModel.copySuppressedCandidateSuggestion(at: 0)

        #expect(!applied)
        #expect(copied)
        #expect(harness.copiedTexts == ["챗 지피티에서 확인", "ChatGPT에서 확인"])
        #expect(harness.repairCalls.isEmpty)
        #expect(viewModel.lastTranscription == "챗 지피티에서 확인")
        #expect(viewModel.suppressedCandidateSuggestions.count == 1)
    }

    @Test func applySuppressedCandidateSuggestionFailsWhenRecordedSpanNoLongerMatches() {
        let harness = Harness()
        let currentText = "ChatGPT에서 확인 그리고 챗 지피티에서 확인"
        let sourceText = "챗 지피티에서"
        let originalRange = (sourceText as NSString).range(of: sourceText)
        let viewModel = makeViewModel(harness: harness)
        viewModel.lastTranscription = currentText
        viewModel.suppressedCandidateSuggestions = [
            TranscriptionCandidateCorrection(
                sourceText: sourceText,
                replacement: "ChatGPT",
                resolvedReplacement: "ChatGPT에서",
                sourceRangeLocation: originalRange.location,
                sourceRangeLength: originalRange.length,
                confidence: 0.62,
                evidence: TranscriptionCorrectionEvidence(
                    kind: .candidateRule,
                    detail: "mixed-language alias heuristic"
                ),
                autoApplyPolicy: .ifConfidenceAtLeast(0.9)
            )
        ]

        let applied = viewModel.applySuppressedCandidateSuggestion(at: 0)
        let copied = viewModel.copySuppressedCandidateSuggestion(at: 0)

        #expect(!applied)
        #expect(!copied)
        #expect(harness.copiedTexts.isEmpty)
        #expect(viewModel.lastTranscription == currentText)
        #expect(viewModel.suppressedCandidateSuggestions.count == 1)
    }

    @Test func saveSuppressedCandidateSuggestionAsRuleUpgradesStoredRuleForFutureProcessing() {
        let harness = Harness()
        let settings = makeSettings()
        settings.transcriptionCandidateCorrections = [
            TranscriptionCandidateCorrectionRule(
                source: "chat gp t",
                aliases: ["chat g p t"],
                replacement: "ChatGPT",
                confidence: 0.62,
                evidence: TranscriptionCorrectionEvidence(
                    kind: .candidateRule,
                    detail: "existing heuristic"
                ),
                autoApplyPolicy: .ifConfidenceAtLeast(0.9)
            ),
            TranscriptionCandidateCorrectionRule(
                source: "claud",
                aliases: [],
                replacement: "",
                confidence: 0.62,
                evidence: TranscriptionCorrectionEvidence(kind: .candidateRule),
                autoApplyPolicy: .ifConfidenceAtLeast(0.9)
            )
        ]
        let sourceText = "챗 지피티에서"
        let sourceRange = (sourceText as NSString).range(of: sourceText)
        let viewModel = makeViewModel(harness: harness, settings: settings)
        viewModel.suppressedCandidateSuggestions = [
            TranscriptionCandidateCorrection(
                sourceText: sourceText,
                canonicalSource: "chat gp t",
                replacement: "ChatGPT",
                resolvedReplacement: "ChatGPT에서",
                sourceRangeLocation: sourceRange.location,
                sourceRangeLength: sourceRange.length,
                confidence: 0.62,
                evidence: TranscriptionCorrectionEvidence(
                    kind: .candidateRule,
                    detail: "mixed-language alias heuristic"
                ),
                autoApplyPolicy: .ifConfidenceAtLeast(0.9)
            )
        ]

        let saved = viewModel.saveSuppressedCandidateSuggestionAsRule(at: 0)

        #expect(saved)
        #expect(viewModel.settings.transcriptionCandidateCorrections == [
            TranscriptionCandidateCorrectionRule(
                source: "chat gp t",
                aliases: ["chat g p t", "챗 지피티"],
                replacement: "ChatGPT",
                confidence: 1,
                evidence: TranscriptionCorrectionEvidence(
                    kind: .candidateRule,
                    detail: "existing heuristic"
                ),
                autoApplyPolicy: .always
            ),
            TranscriptionCandidateCorrectionRule(
                source: "claud",
                aliases: [],
                replacement: "",
                confidence: 0.62,
                evidence: TranscriptionCorrectionEvidence(kind: .candidateRule),
                autoApplyPolicy: .ifConfidenceAtLeast(0.9)
            )
        ])

        let result = PostTranscriptionProcessor(
            configuration: viewModel.settings.postTranscriptionProcessingConfiguration
        )
        .process("챗 지피티에서 확인")

        #expect(result.processedText == "ChatGPT에서 확인")
        #expect(result.appliedCorrections.count == 1)
        #expect(result.suppressedCandidates.isEmpty)
    }

    private func makeViewModel(
        harness: Harness,
        settings: AppSettings? = nil
    ) -> AppViewModel {
        let effectiveSettings = settings ?? makeSettings()
        effectiveSettings.showOverlay = false

        let dependencies = AppViewModelDependencies(
            isMicrophoneGranted: { harness.micGranted },
            requestMicrophonePermission: {
                harness.requestedPermissionCount += 1
                return harness.requestedMicPermission
            },
            isAccessibilityGranted: { harness.accessibilityGranted },
            refreshPermissions: {
                harness.refreshedPermissionsCount += 1
            },
            requestAccessibilityPermission: {},
            loadModel: { variant in
                harness.loadedModels.append(variant)
            },
            unloadModel: {
                harness.unloadedModelCount += 1
            },
            startCapture: {},
            stopCapture: {
                harness.captureResult
            },
            transcribe: { _, _ in
                harness.transcriptionResult
            },
            processTranscription: { text in
                harness.processTranscription(text)
            },
            insertText: { text, accessibilityAvailable in
                harness.insertCalls.append((text, accessibilityAvailable))
                return TextInsertionManager.InsertionResult(
                    success: harness.insertResult.success && harness.insertSuccess,
                    method: harness.insertResult.method,
                    repairContext: harness.insertResult.repairContext
                )
            },
            repairInsertedText: { text, _, accessibilityAvailable in
                harness.repairCalls.append((text, accessibilityAvailable))
                return harness.repairResult
            },
            resetHotkeyState: {
                harness.resetCount += 1
            },
            registerHotkeys: { _, _ in },
            updateCopyShortcut: { _ in },
            copyToClipboard: { text in
                harness.copiedTexts.append(text)
            }
        )

        return AppViewModel(
            settings: effectiveSettings,
            permissions: PermissionsManager(),
            modelManager: ModelManager(),
            hotkeyManager: HotkeyManager(),
            audioService: AudioService(),
            transcriptionEngine: WhisperKitEngine(),
            textInsertionManager: TextInsertionManager(),
            postTranscriptionProcessor: PostTranscriptionProcessor(),
            dependencies: dependencies,
            autoSetup: false,
            promptForAccessibilityIfNeeded: false
        )
    }

    private func makeSettings() -> AppSettings {
        let suiteName = "VoiceInputTests.AppViewModel.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return AppSettings(defaults: defaults)
    }
}
