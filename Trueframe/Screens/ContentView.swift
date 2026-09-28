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
                                verdict: {
                                    guard let kept = coordinator.keptPreviews, let scores = coordinator.previewScores else { return nil }
                                    return FanLayout.Verdict(kept: kept, scores: scores)
                                },
                                heartFrame: heartFrame,
                                canvas: proxy.size,
                                onComplete: {
                                    // A new session may have taken over and be celebrating by now
                                    if self.celebration?.id == celebration.id {
                                        coordinator.tumbleAnimationComplete()
                                    }
                                },
                                onFinished: {
                                    if self.celebration?.id == celebration.id { self.celebration = nil }
                                }
                            )
                            .id(celebration.id)
                            .allowsHitTesting(!coordinator.isCapturing)
                            // The photos bring their own entrance; a fade would hide it.
                            // Only a new session animates the removal, so only it fades
                            .transition(.asymmetric(insertion: .identity, removal: .opacity))
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
                    if celebration != nil {
                        withAnimation(Motion.dismiss) { celebration = nil }
                    }
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
