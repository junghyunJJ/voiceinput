import AppKit
import AVFoundation
import ApplicationServices
import Foundation

/// Manages microphone and accessibility permission checks and requests.
@MainActor
@Observable
final class PermissionsManager {
    var microphoneGranted = false
    var accessibilityGranted = false

    var allPermissionsGranted: Bool {
        microphoneGranted && accessibilityGranted
    }

    init() {
        refreshPermissions()
    }

    func refreshPermissions() {
        microphoneGranted = checkMicrophonePermission()
        accessibilityGranted = checkAccessibilityPermission()
    }

    // MARK: - Microphone

    func checkMicrophonePermission() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    func requestMicrophonePermission() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        microphoneGranted = granted
        return granted
    }

    // MARK: - Accessibility

    func checkAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    /// Prompt the user to grant accessibility permission.
    /// Opens System Settings to the correct pane.
    func requestAccessibilityPermission() {
        // Show the system prompt that guides users to grant access
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Open System Settings to Accessibility > Privacy pane.
    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Open System Settings to Microphone > Privacy pane.
    func openMicrophoneSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }
}
