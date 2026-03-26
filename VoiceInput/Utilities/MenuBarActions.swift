import Foundation

enum MenuBarActions {
    static func openSettings(
        open: () -> Void,
        activate: () -> Void
    ) {
        open()
        activate()
    }
}
