import SwiftUI

struct ContentView: View {
    @Environment(SessionCoordinator.self) private var coordinator
    /// Outlives the celebrating phase, so the sparks can keep flying over home.
    @State private var celebration: Celebration?

    var body: some View {
        HomeScreen()
            .overlayPreferenceValue(HeartAnchorKey.self) { anchor in
                GeometryReader { proxy in
                    let heartFrame = anchor.map { proxy[$0] }
                    ZStack {
                        if coordinator.isCapturing {
                            CaptureScreen(
                                heartFrame: heartFrame,
                                captures: coordinator.capturedCount
                            )
                            // Home is already black underneath; only its content needs to leave
                            .transition(.asymmetric(insertion: .identity, removal: .opacity.animation(Motion.dismiss)))
                        }

                        if let celebration {
                            TumbleAnimationView(
                                photos: celebration.photos,
                                heartFrame: heartFrame,
                                canvas: proxy.size,
                                onComplete: {
                                    coordinator.tumbleAnimationComplete()
                                },
                                onFinished: {
                                    if self.celebration?.id == celebration.id { self.celebration = nil }
                                }
                            )
                            .id(celebration.id)
                            // The photos bring their own entrance; a fade would hide it
                            .transition(.identity)
                        }
                    }
                }
                .ignoresSafeArea()
            }
            .statusBarHidden(coordinator.isCapturing || coordinator.showingTumbleAnimation)
            .onChange(of: coordinator.showingTumbleAnimation) { _, showing in
                if showing { celebration = Celebration(photos: coordinator.sessionPreviews) }
            }
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

private struct Celebration: Identifiable {
    let id = UUID()
    let photos: [UIImage]
}
