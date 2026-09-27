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
                                heartFrame: heartFrame,
                                canvas: proxy.size,
                                onComplete: {
                                    coordinator.tumbleAnimationComplete()
                                }
                            )
                            // The photos bring their own entrance; a fade would hide it
                            .transition(.identity)
                        }
                    }
                }
                .ignoresSafeArea()
            }
            .statusBarHidden(coordinator.isCapturing || coordinator.showingTumbleAnimation)
            .onChange(of: coordinator.isCapturing) { _, capturing in
                if capturing {
                    AccessibilityNotification.Announcement(SessionAnnouncements.capturing).post()
                }
            }
            .onChange(of: coordinator.keptCount) { _, kept in
                if let kept {
                    AccessibilityNotification.Announcement(SessionAnnouncements.kept(kept)).post()
                }
            }
    }
}
