// Photo capture type.

import UIKit

struct CapturedPhoto: Identifiable {
    let id: UUID
    let image: UIImage
    let timestamp: Date

    init(
        id: UUID = UUID(),
        image: UIImage,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.image = image
        self.timestamp = timestamp
    }
}

enum CameraPosition: Equatable, Sendable {
    case front
    case back
    case both
}
