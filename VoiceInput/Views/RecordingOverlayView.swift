import AppKit
import SwiftUI

/// Floating overlay window displayed during recording.
/// Shows recording timer and visual feedback.
/// Uses the AppViewModel directly so state changes are reflected live.
struct RecordingOverlayView: View {
    let viewModel: AppViewModel

    @State private var pulseAnimation = false

    var body: some View {
        // TimelineView updates every second so the recording timer ticks
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack(spacing: 12) {
                // Animated recording indicator
                ZStack {
                    Circle()
                        .fill(.red.opacity(0.3))
                        .frame(width: 32, height: 32)
                        .scaleEffect(pulseAnimation ? 1.3 : 1.0)
                        .opacity(pulseAnimation ? 0.5 : 1.0)

                    Circle()
                        .fill(.red)
                        .frame(width: 16, height: 16)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(statusSubtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if viewModel.recordingState.isRecording {
                    Button {
                        Task { await viewModel.toggleRecording() }
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(.red.opacity(0.8))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                } else if viewModel.recordingState.isProcessing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: Constants.UI.overlayWidth)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Constants.UI.overlayCornerRadius))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
        }
    }

    private var statusTitle: String {
        switch viewModel.recordingState {
        case .recording:
            return "Recording..."
        case .transcribing:
            return "Transcribing..."
        case .inserting:
            return "Inserting text..."
        default:
            return ""
        }
    }

    private var statusSubtitle: String {
        switch viewModel.recordingState {
        case .recording(let startTime):
            let duration = Date().timeIntervalSince(startTime)
            return String(format: "%.0fs", duration)
        case .transcribing:
            return "Processing audio"
        case .inserting(let text):
            return String(text.prefix(40)) + (text.count > 40 ? "..." : "")
        default:
            return ""
        }
    }
}

/// NSPanel-based floating window for the recording overlay.
/// Appears above all other windows without stealing focus.
final class OverlayPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Constants.UI.overlayWidth, height: Constants.UI.overlayHeight),
            styleMask: [.nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: true
        )

        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true

        // Position at top-center of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - Constants.UI.overlayWidth / 2
            let y = screenFrame.maxY - Constants.UI.overlayHeight - 20
            setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
}
