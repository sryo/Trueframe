// App entry point.

import SwiftUI

@main
struct TrueframeApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .preferredColorScheme(.dark)
                .persistentSystemOverlays(.hidden)
                .task {
                    await appState.checkAndRequestPermissions()
                }
        }
    }
}

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            HomeScreen()

            if appState.isCapturing {
                captureScreen
                    .transition(.opacity)
            }

            // Tumble animation
            if appState.showingTumbleAnimation {
                TumbleAnimationView(
                    photos: appState.sessionPhotos,
                    onComplete: {
                        appState.tumbleAnimationComplete()
                    }
                )
                .transition(.opacity)
            }

        }
        .animation(.easeInOut(duration: 0.3), value: appState.isCapturing)
        .animation(.easeInOut(duration: 0.3), value: appState.showingTumbleAnimation)
        .statusBarHidden(appState.isCapturing || appState.showingTumbleAnimation)
    }

    @ViewBuilder
    private var captureScreen: some View {
        switch appState.captureMode {
        case .photo:
            CaptureScreen()
        case .video:
            VideoCaptureScreen()
        }
    }
}
