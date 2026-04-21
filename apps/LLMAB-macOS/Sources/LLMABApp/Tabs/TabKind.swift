import Foundation
import UIKitOmega

/// The four first-class views of the app. Code sits top-left per the user's
/// design direction and uses the cooler sub-palette.
enum TabKind: String, CaseIterable, Identifiable, Sendable {
    case code   // top-left, CLI-styled, cyan→violet
    case chat   // default on launch
    case agents
    case video

    var id: String { rawValue }

    /// User-facing label.
    var label: String {
        switch self {
        case .code:   return "Code"
        case .chat:   return "Chat"
        case .agents: return "Agents"
        case .video:  return "Video"
        }
    }

    /// SF Symbol name used in the rail.
    var symbol: String {
        switch self {
        case .code:   return "curlybraces"
        case .chat:   return "message"
        case .agents: return "hammer"
        case .video:  return "video"
        }
    }

    /// Which gradient palette drives this tab's chrome.
    var palette: AuroraGradient.Palette {
        switch self {
        case .code:   return .code
        case .chat, .agents, .video: return .full
        }
    }

    /// Launch default.
    static let `default`: TabKind = .chat
}
