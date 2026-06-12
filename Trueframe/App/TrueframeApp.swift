// App entry point.

import SwiftUI

@main
struct TrueframeApp: App {
    @State private var coordinator = SessionCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(coordinator)
                .preferredColorScheme(.dark)
                .persistentSystemOverlays(.hidden)
                .task {
                    await coordinator.start()
                }
        }
    }
}

struct ContentView: View {
    @Environment(SessionCoordinator.self) private var coordinator

    var body: some View {
        ZStack {
            HomeScreen()

            if coordinator.isCapturing {
                CaptureScreen()
                    .transition(.opacity)
            }

            // Tumble animation
            if coordinator.showingTumbleAnimation {
                TumbleAnimationView(
                    photos: coordinator.sessionPreviews,
                    onComplete: {
                        coordinator.tumbleAnimationComplete()
                    }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: coordinator.isCapturing)
        .animation(.easeInOut(duration: 0.3), value: coordinator.showingTumbleAnimation)
        .statusBarHidden(coordinator.isCapturing || coordinator.showingTumbleAnimation)
    }
}
