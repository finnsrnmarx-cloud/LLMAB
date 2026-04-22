import Foundation
import UIKitOmega

/// Five first-class views in the left rail. Code sits top-left per the user's
/// design direction and uses the cooler sub-palette; Settings gets a dedicated
/// tab (instead of only `⌘,` → separate window) so model selection is reachable
/// without a keyboard shortcut.
enum TabKind: String, CaseIterable, Identifiable, Sendable {
    case code      // top-left, CLI-styled, cool palette
    case chat      // default on launch
    case agents
    case video
    case settings  // model picker + runtime status; bottom of the rail

    var id: String { rawValue }

    /// User-facing label.
    var label: String {
        switch self {
        case .code:     return "Code"
        case .chat:     return "Chat"
        case .agents:   return "Agents"
        case .video:    return "Video"
        case .settings: return "Settings"
        }
    }

    /// SF Symbol name used in the rail.
    var symbol: String {
        switch self {
        case .code:     return "curlybraces"
        case .chat:     return "message"
        case .agents:   return "hammer"
        case .video:    return "video"
        case .settings: return "slider.horizontal.3"
        }
    }

    /// Which gradient palette drives this tab's chrome.
    var palette: AuroraGradient.Palette {
        switch self {
        case .code:                              return .code
        case .chat, .agents, .video, .settings:  return .full
        }
    }

    /// Launch default.
    static let `default`: TabKind = .chat
}
