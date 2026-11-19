import Foundation
import Observation

// what the dashboard is showing, shared so the sampler knows what's on screen
@Observable
final class UIState {
    static let shared = UIState()

    var tab: Tab {
        didSet { UserDefaults.standard.set(tab.rawValue, forKey: "lastTab") }
    }
    var settings: SettingsSection?

    init() {
        tab = Tab(rawValue: UserDefaults.standard.integer(forKey: "lastTab")) ?? .overview
    }
}
