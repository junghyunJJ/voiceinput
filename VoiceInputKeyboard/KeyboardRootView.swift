import SwiftUI

struct KeyboardRootView: View {
    let helperBridge: KeyboardTextDocumentHelperBridge
    let hasFullAccess: Bool
    @StateObject private var viewModel: KeyboardDictationViewModel

    @MainActor
    init(
        helperBridge: KeyboardTextDocumentHelperBridge,
        hasFullAccess: Bool,
        viewModel: KeyboardDictationViewModel? = nil
    ) {
        self.helperBridge = helperBridge
        self.hasFullAccess = hasFullAccess
        _viewModel = StateObject(wrappedValue: viewModel ?? KeyboardDictationViewModel())
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.11, blue: 0.18),
                    Color(red: 0.02, green: 0.03, blue: 0.06),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    statusBadge
                    Spacer()
                    languageBadge
                }

                if viewModel.shouldRecommendPasteLast {
                    savedResultSection
                    quickLane
                    proLane
                } else {
                    proLane
                    quickLane
                    savedResultSection
                }

                if let infoMessage = viewModel.infoMessage, !infoMessage.isEmpty {
                    Text(infoMessage)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.62, green: 0.84, blue: 1.00).opacity(0.88))
                        .lineLimit(2)
                }

                if let errorMessage = viewModel.errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 1.00, green: 0.63, blue: 0.63).opacity(0.9))
                        .lineLimit(3)
                }

                if let nextStepMessage {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Next Step")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(nextStepTint.opacity(0.92))
                        Text(nextStepMessage)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(2)
                    }
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(nextStepTint.opacity(0.11))
                    )
                }
            }
            .padding(11)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .onAppear {
            viewModel.refresh(using: helperBridge)
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: viewModel.helperStatusSymbolName)
            Text(viewModel.helperStatusTitle)
        }
        .font(.system(size: 12, weight: .bold, design: .rounded))
        .foregroundStyle(.white.opacity(0.90))
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.09))
        )
    }

    private var languageBadge: some View {
        Text(viewModel.selectedLanguageName)
            .font(.system(size: 11, weight: .bold, design: .rounded))
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.09))
        )
    }

    private var latestPreviewText: String? {
        let trimmed = viewModel.latestTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private var savedResultSectionTitle: String {
        viewModel.shouldRecommendPasteLast ? "Paste Last" : "Saved App Result"
    }

    private var savedResultSectionSubtitle: String {
        viewModel.shouldRecommendPasteLast
            ? "Insert the saved result here without leaving the current app."
            : "Create a saved result in Pro Dictation, then paste it here."
    }

    private var savedResultPreviewTitle: String {
        latestPreviewText == nil ? "No saved result yet" : "Saved result"
    }

    private var savedResultBadgeText: String? {
        latestPreviewText == nil ? "Not ready" : nil
    }

    private var nextStepMessage: String? {
        if !hasFullAccess {
            return "Full Access is required to open the app and paste saved text."
        }

        if latestPreviewText == nil {
            return "Create one saved result in Pro Dictation, then return and tap Paste Last."
        }

        return nil
    }

    private var nextStepTint: Color {
        if !hasFullAccess {
            return Color(red: 1.00, green: 0.76, blue: 0.52)
        }
        return Color(red: 0.62, green: 0.84, blue: 1.00)
    }

    private func laneCard<Content: View>(
        title: String,
        subtitle: String,
        accent: Color,
        badgeText: String? = nil,
        isRecommended: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                if let badgeText {
                    Text(badgeText)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(isRecommended ? accent : .white.opacity(0.68))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill((isRecommended ? accent : .white).opacity(isRecommended ? 0.18 : 0.10))
                        )
                }
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)
            }

            Text(subtitle)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.66))
                .fixedSize(horizontal: false, vertical: true)

            content()
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(isRecommended ? 0.09 : 0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isRecommended ? accent.opacity(0.28) : Color.white.opacity(0.07), lineWidth: 1)
                )
        )
    }

    private func actionButton(title: String, symbol: String, fill: Color, isEnabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isEnabled ? fill : fill.opacity(0.45))
            )
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.75)
        .buttonStyle(.plain)
    }

    private var quickLane: some View {
        laneCard(
            title: "Quick Polish",
            subtitle: "Polish text before the cursor. Recording stays in the app.",
            accent: Color(red: 0.28, green: 0.33, blue: 0.45)
        ) {
            VStack(alignment: .leading, spacing: 8) {
                actionButton(
                    title: viewModel.quickActionTitle,
                    symbol: "wand.and.stars",
                    fill: Color(red: 0.28, green: 0.33, blue: 0.45)
                ) {
                    viewModel.polishCurrentDraft(using: helperBridge)
                }

                HStack(spacing: 6) {
                    Image(systemName: viewModel.hasTextBeforeCursor ? "text.cursor" : "text.cursor")
                    Text(viewModel.quickReadinessTitle)
                    Spacer()
                }
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(viewModel.hasTextBeforeCursor ? Color(red: 0.72, green: 0.88, blue: 1.00) : .white.opacity(0.62))

                Text(viewModel.quickReadinessDetail)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var proLane: some View {
        laneCard(
            title: "Pro Dictation",
            subtitle: viewModel.shouldRecommendProDictation
                ? "Record in the app, then come back for Paste Last."
                : "Use the app when you need a fresh saved result.",
            accent: Color(red: 0.00, green: 0.62, blue: 1.00),
            badgeText: viewModel.shouldRecommendProDictation ? "Recommended now" : nil,
            isRecommended: viewModel.shouldRecommendProDictation
        ) {
            Button {
                viewModel.openAppForProDictation(using: helperBridge, hasFullAccess: hasFullAccess)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.right.square.fill")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text(viewModel.primaryActionTitle)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                    Spacer(minLength: 0)
                    Image(systemName: "iphone.and.arrow.forward")
                        .font(.system(size: 13, weight: .semibold))
                        .opacity(0.8)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.00, green: 0.62, blue: 1.00), Color(red: 0.22, green: 0.40, blue: 1.00)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: Capsule(style: .continuous)
                )
                .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 5)
                .opacity(viewModel.shouldRecommendPasteLast ? 0.88 : 1)
            }
            .buttonStyle(.plain)
        }
    }

    private var savedResultSection: some View {
        laneCard(
            title: savedResultSectionTitle,
            subtitle: savedResultSectionSubtitle,
            accent: Color(red: 0.62, green: 0.84, blue: 1.00),
            badgeText: savedResultBadgeText,
            isRecommended: viewModel.shouldRecommendPasteLast
        ) {
            VStack(alignment: .leading, spacing: 7) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(savedResultPreviewTitle)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(latestPreviewText == nil ? .white.opacity(0.72) : Color(red: 0.62, green: 0.84, blue: 1.00))

                    Text(latestPreviewText ?? "Open the app for Pro Dictation once, then come back here and tap Paste Last.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(latestPreviewText == nil ? 0.62 : 0.88))
                        .lineLimit(2)
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(viewModel.shouldRecommendPasteLast ? 0.10 : 0.07))
                )

                if viewModel.shouldRecommendPasteLast {
                    Button {
                        viewModel.insertLastDictation(using: helperBridge)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.on.clipboard.fill")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                            Text("Paste Last")
                                .font(.system(.headline, design: .rounded).weight(.bold))
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.down.to.line")
                                .font(.system(size: 13, weight: .semibold))
                                .opacity(0.8)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.00, green: 0.62, blue: 1.00), Color(red: 0.26, green: 0.76, blue: 1.00)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: Capsule(style: .continuous)
                        )
                        .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 5)
                    }
                    .buttonStyle(.plain)

                    actionButton(title: "Next Keyboard", symbol: "globe", fill: Color(red: 0.28, green: 0.33, blue: 0.45), action: helperBridge.advanceToNextKeyboard)
                } else {
                    HStack(spacing: 8) {
                        actionButton(title: "Paste Last", symbol: "doc.on.clipboard", fill: Color(red: 0.00, green: 0.62, blue: 1.00), isEnabled: false) {}
                        actionButton(title: "Next Keyboard", symbol: "globe", fill: Color(red: 0.28, green: 0.33, blue: 0.45), action: helperBridge.advanceToNextKeyboard)
                    }
                }
            }
        }
    }
}
