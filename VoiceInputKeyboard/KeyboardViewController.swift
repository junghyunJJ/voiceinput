import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController, KeyboardTextDocumentHelping {
    private var hostingController: UIHostingController<KeyboardRootView>?
    private let viewModel = KeyboardDictationViewModel()
    private lazy var helperBridge = KeyboardTextDocumentHelperBridge(helper: self)

    override func viewDidLoad() {
        super.viewDidLoad()
        setupKeyboardView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshKeyboardState()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        refreshKeyboardState()
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        refreshKeyboardState()
    }

    private func setupKeyboardView() {
        let rootView = KeyboardRootView(
            helperBridge: helperBridge,
            hasFullAccess: hasFullAccess,
            viewModel: viewModel
        )

        let hosting = UIHostingController(rootView: rootView)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(hosting)
        view.addSubview(hosting.view)

        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        hosting.didMove(toParent: self)
        self.hostingController = hosting
    }

    func insertTextIntoDocument(_ text: String) {
        textDocumentProxy.insertText(text)
    }

    func deleteBackwardInDocument() {
        textDocumentProxy.deleteBackward()
    }

    func advanceToNextKeyboardInputMode() {
        advanceToNextInputMode()
    }

    func openVoiceInputHostApp() {
        guard let url = URL(string: "voiceinput://open?dictate=1") else {
            return
        }

        guard let extensionContext else {
            viewModel.reportHostAppLaunchFailure(hasFullAccess: hasFullAccess)
            return
        }

        extensionContext.open(url) { [weak self] success in
            guard !success, let self else {
                return
            }

            Task { @MainActor in
                self.viewModel.reportHostAppLaunchFailure(hasFullAccess: self.hasFullAccess)
            }
        }
    }

    func documentContextBeforeInputText() -> String? {
        textDocumentProxy.documentContextBeforeInput
    }

    func replaceTextBeforeCursor(currentText: String, with replacement: String) {
        guard !currentText.isEmpty else {
            insertTextIntoDocument(replacement)
            return
        }

        for _ in currentText {
            textDocumentProxy.deleteBackward()
        }
        textDocumentProxy.insertText(replacement)
    }

    private func refreshKeyboardState() {
        viewModel.refresh(using: helperBridge)
    }
}
