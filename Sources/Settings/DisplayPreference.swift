import AppKit

/// Whether the notch follows keyboard focus or stays on one physical display.
enum DisplayPreference: Hashable {
    case followActiveWindow
    case display(String)
}

/// A connected display as it appears in Settings.
struct DisplayOption: Identifiable, Equatable {
    let id: String
    let name: String

    @MainActor
    static var connected: [DisplayOption] {
        NSScreen.screens.enumerated().compactMap { index, screen in
            screen.displayIdentifier.map {
                DisplayOption(id: $0, name: "\(index + 1) · \(screen.localizedName) · \(screen.frame.height > screen.frame.width ? "vertical" : "horizontal")")
            }
        }
    }
}
