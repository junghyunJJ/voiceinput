import Foundation
import SwiftUI
import UIKit

struct IOSQALaunchConfiguration: Equatable {
    let route: IOSQALaunchRoute
    let readiness: IOSQAReadinessRequest?

    static func resolve(arguments: [String]) -> IOSQALaunchConfiguration {
        let route = IOSQALaunchRoute.resolve(arguments: arguments)
        let readiness = IOSQAReadinessRequest.resolve(arguments: arguments, route: route)
        return IOSQALaunchConfiguration(route: route, readiness: readiness)
    }
}

struct IOSQAReadinessRequest: Equatable {
    let token: String
    let screenIdentifier: String

    static func resolve(arguments: [String], route: IOSQALaunchRoute) -> IOSQAReadinessRequest? {
        guard let configuration = IOSQAReadySignalConfiguration.resolve(arguments: arguments),
              let screenIdentifier = route.screenIdentifier
        else {
            return nil
        }

        return IOSQAReadinessRequest(token: configuration.token, screenIdentifier: screenIdentifier)
    }
}

struct IOSQAReadySignalConfiguration: Equatable {
    static let launchArgument = "--qa-ready-token"
    static let markerFilename = "voiceinput-qa-ready.txt"

    let token: String

    static func resolve(arguments: [String]) -> IOSQAReadySignalConfiguration? {
        guard let tokenIndex = arguments.firstIndex(of: launchArgument),
              arguments.indices.contains(tokenIndex + 1)
        else {
            return nil
        }

        let token = arguments[tokenIndex + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            return nil
        }

        return IOSQAReadySignalConfiguration(token: token)
    }

    func markerURL(cachesDirectory: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first) -> URL? {
        cachesDirectory?.appendingPathComponent(Self.markerFilename)
    }

    func writeReadyMarker(
        route: String,
        cachesDirectory: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    ) throws {
        guard let markerURL = markerURL(cachesDirectory: cachesDirectory) else {
            return
        }

        try FileManager.default.createDirectory(
            at: markerURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let payload = "\(token)\t\(route)\n"
        try payload.write(to: markerURL, atomically: true, encoding: .utf8)
    }
}

enum IOSQAReadySignal {
    static func markReady(route: String, arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard let configuration = IOSQAReadySignalConfiguration.resolve(arguments: arguments) else {
            return
        }

        try? configuration.writeReadyMarker(route: route)
    }
}

private struct IOSQAReadinessModifier: ViewModifier {
    let request: IOSQAReadinessRequest?

    func body(content: Content) -> some View {
        content.overlay {
            IOSQAReadinessProbe(request: request)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private enum IOSQAReadinessReporter {
    static func report(_ request: IOSQAReadinessRequest) {
        IOSQAReadySignal.markReady(
            route: request.screenIdentifier,
            arguments: [
                "VoiceInputiOS",
                IOSQAReadySignalConfiguration.launchArgument,
                request.token,
            ]
        )
    }
}

extension View {
    func iosQAReadiness(_ request: IOSQAReadinessRequest?) -> some View {
        modifier(IOSQAReadinessModifier(request: request))
    }
}

extension IOSQALaunchRoute {
    var screenIdentifier: String? {
        switch self {
        case .none:
            return nil
        case .gallery:
            return "gallery-home"
        case .host(let state):
            return "host-\(state.rawValue)"
        case .keyboardGallery:
            return "keyboard-gallery"
        }
    }
}

private struct IOSQAReadinessProbe: UIViewRepresentable {
    let request: IOSQAReadinessRequest?

    func makeUIView(context: Context) -> IOSQAReadinessUIView {
        let view = IOSQAReadinessUIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.request = request
        return view
    }

    func updateUIView(_ uiView: IOSQAReadinessUIView, context: Context) {
        uiView.request = request
        uiView.reportIfReady()
    }
}

private final class IOSQAReadinessUIView: UIView {
    var request: IOSQAReadinessRequest? {
        didSet {
            if request?.token != oldValue?.token || request?.screenIdentifier != oldValue?.screenIdentifier {
                hasReported = false
                pendingFrameCount = Self.requiredDisplayFrames
                earliestReportTime = nil
                invalidateDisplayLink()
            }
        }
    }

    private static let requiredDisplayFrames = 2
    // QA screens need one post-appear stabilization window before simulator capture becomes repeatable.
    private static let minimumReadyDelay: CFTimeInterval = 0.75

    private var hasReported = false
    private var pendingFrameCount = 2
    private var displayLink: CADisplayLink?
    private var earliestReportTime: CFTimeInterval?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        reportIfReady()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        reportIfReady()
    }

    deinit {
        invalidateDisplayLink()
    }

    func reportIfReady() {
        guard !hasReported, window != nil, request != nil else {
            invalidateDisplayLink()
            return
        }

        if displayLink == nil {
            pendingFrameCount = Self.requiredDisplayFrames
            earliestReportTime = CACurrentMediaTime() + Self.minimumReadyDelay
            let displayLink = CADisplayLink(target: self, selector: #selector(handleDisplayLinkTick))
            displayLink.add(to: .main, forMode: .common)
            self.displayLink = displayLink
        }
    }

    @objc
    private func handleDisplayLinkTick() {
        guard !hasReported, window != nil, let request else {
            invalidateDisplayLink()
            return
        }

        if let earliestReportTime, CACurrentMediaTime() < earliestReportTime {
            return
        }

        if pendingFrameCount > 0 {
            pendingFrameCount -= 1
            return
        }

        hasReported = true
        invalidateDisplayLink()
        IOSQAReadinessReporter.report(request)
    }

    private func invalidateDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }
}
