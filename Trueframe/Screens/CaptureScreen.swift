// Active capture session screen.

import SwiftUI

struct CaptureScreen: View {
    @Environment(AppState.self) private var appState
    @StateObject private var viewModel = CaptureViewModel()

    var body: some View {
        Color.black.ignoresSafeArea()
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
            .onAppear { viewModel.onAppear(appState: appState) }
            .onDisappear { viewModel.onDisappear() }
    }
}

#Preview {
    CaptureScreen()
        .environment(AppState())
}
