// Bridges UIKit animation to SwiftUI.

import SwiftUI
import UIKit

struct TumbleAnimationView: UIViewControllerRepresentable {
    let photos: [UIImage]
    let onComplete: () -> Void

    func makeUIViewController(context: Context) -> TumbleAnimationViewController {
        let controller = TumbleAnimationViewController(photos: photos)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: TumbleAnimationViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    class Coordinator: NSObject, TumbleAnimationDelegate {
        let onComplete: () -> Void

        init(onComplete: @escaping () -> Void) {
            self.onComplete = onComplete
        }

        func tumbleAnimationDidComplete() {
            onComplete()
        }
    }
}
