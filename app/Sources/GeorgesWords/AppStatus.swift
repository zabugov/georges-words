import AppKit
import Combine

/// Sections of the main window's sidebar.
enum MainSection: String, CaseIterable, Identifiable {
    case home
    case history
    case dictionary
    case snippets
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .history: return "History"
        case .dictionary: return "Dictionary"
        case .snippets: return "Snippets"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .history: return "clock.arrow.circlepath"
        case .dictionary: return "character.book.closed"
        case .snippets: return "text.badge.plus"
        case .settings: return "gearshape"
        }
    }
}

/// Live app state published to the main window. The AppDelegate writes,
/// SwiftUI observes; the action closures point back at the AppDelegate.
final class AppStatus: ObservableObject {

    static let shared = AppStatus()

    enum Health {
        case loading
        case ready
        case recording
        case processing
        case error
    }

    @Published var selectedSection: MainSection? = .home
    @Published var health: Health = .loading
    @Published var statusText = "Starting…"
    @Published var engineDescription = ""
    @Published var lastTiming: String?
    @Published var updateProgress: String?

    var checkForUpdates: (() -> Void)?

    private init() {}
}
