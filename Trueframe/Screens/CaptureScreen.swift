import SwiftUI

/// Black but for the wordmark heart, which glows once for every photo kept.
struct CaptureScreen: View {
    /// The home heart's frame; nil before home has laid out.
    let heartFrame: CGRect?
    let captures: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        ZStack {
            // Swallows touches meant for the hidden home controls
            Color.clear.contentShape(Rectangle())

            if let heartFrame {
                KeyframeAnimator(initialValue: SessionHeart.afterglowResting, trigger: captures) { glow in
                    HeartGlyph()
                        .foregroundStyle(.white)
                        .opacity(dimmed ? (reduceMotion ? SessionHeart.afterglowResting : glow) : 0)
                } keyframes: { _ in
                    KeyframeTrack {
                        for step in SessionHeart.afterglowPulse {
                            LinearKeyframe(step.opacity, duration: step.duration, timingCurve: step.easesOut ? .easeOut : .linear)
                        }
                    }
                }
                .placedOnHeart(heartFrame)
                .accessibilityHidden(true)
            }
        }
        .onAppear {
            withAnimation(Motion.dismiss) { dimmed = true }
        }
    }
}

#Preview {
    CaptureScreen(heartFrame: CGRect(x: 180, y: 400, width: 8, height: 10), captures: 0)
        .background(.black)
}
