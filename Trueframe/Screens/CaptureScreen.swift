// Active capture session screen: intentionally black and empty.
// The session lifecycle is driven by SessionCoordinator, not this view.

import SwiftUI

struct CaptureScreen: View {
    var body: some View {
        Color.black.ignoresSafeArea()
    }
}

#Preview {
    CaptureScreen()
}
