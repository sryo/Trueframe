// Capture mode selection for different capture styles.

import SwiftUI

enum CaptureMode: String, CaseIterable, Identifiable {
    case photo = "Photo"
    case video = "Video"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var icon: String {
        switch self {
        case .photo: return "camera.fill"
        case .video: return "video.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .photo: return .white
        case .video: return .red
        }
    }
}
