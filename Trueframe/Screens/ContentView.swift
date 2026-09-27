import SwiftUI

struct ContentView: View {
    @Environment(SessionCoordinator.self) private var coordinator

    var body: some View {
        HomeScreen()
            .overlayPreferenceValue(HeartAnchorKey.self) { anchor in
                GeometryReader { proxy in
                    let heartFrame = anchor.map { proxy[$0] }
                    ZStack {
                        if coordinator.isCapturing {
                            CaptureScreen(
                                heartFrame: heartFrame,
                                captures: coordinator.capturedCount,
                                handoffOpacity: HeartbeatKeyframes(isNearFullMoon: Date.now.isNearFullMoon).restingOpacity
                            )
                            // Home is already black underneath; only its content needs to leave
                            .transition(.identity)
                        }

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
                }
                .ignoresSafeArea()
            }
            .animation(.easeInOut(duration: 0.3), value: coordinator.showingTumbleAnimation)
            .statusBarHidden(coordinator.isCapturing || coordinator.showingTumbleAnimation)
            .onChange(of: coordinator.isCapturing) { _, capturing in
                if capturing {
                    AccessibilityNotification.Announcement(SessionAnnouncements.capturing).post()
                }
            }
    }
}
