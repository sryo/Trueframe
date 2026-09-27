import SwiftUI

/// The session's photos fan out so you see what you caught, then gather into the heart.
struct TumbleAnimationView: View {
    let heartFrame: CGRect?
    let canvas: CGSize
    let onComplete: () -> Void

    private enum Stage {
        case waiting
        case fanned
        case gathered
    }

    private let photos: [UIImage]
    private let slots: [FanLayout.Slot]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stages: [Stage]

    init(photos: [UIImage], heartFrame: CGRect?, canvas: CGSize, onComplete: @escaping () -> Void) {
        self.photos = FanLayout.photos(from: photos)
        self.slots = FanLayout.slots(count: self.photos.count)
        self.heartFrame = heartFrame
        self.canvas = canvas
        self.onComplete = onComplete
        _stages = State(initialValue: Array(repeating: .waiting, count: self.photos.count))
    }

    var body: some View {
        ZStack {
            // Swallows touches meant for the hidden home controls
            Color.clear.contentShape(Rectangle())

            ForEach(photos.indices, id: \.self) { index in
                photo(photos[index])
                    .modifier(pose(for: index))
            }
        }
        .accessibilityHidden(true)
        .task { await play() }
    }

    private func photo(_ image: UIImage) -> some View {
        let shape = RoundedRectangle(cornerRadius: FanLayout.cornerRadius, style: .continuous)
        return Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: FanLayout.photoSize, height: FanLayout.photoSize)
            .clipShape(shape)
            .overlay(shape.strokeBorder(.white.opacity(0.15), lineWidth: 1))
    }

    private func pose(for index: Int) -> PhotoPose {
        let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        let slot = slots[index]
        let fanned = PhotoPose(
            position: CGPoint(x: center.x + slot.offset.width, y: center.y + slot.offset.height),
            rotation: slot.rotation,
            scale: 1,
            opacity: 1
        )
        // Reduce Motion keeps the fan still and only fades it in and out
        if reduceMotion {
            return stages[index] == .fanned ? fanned : PhotoPose(position: fanned.position, rotation: fanned.rotation, scale: 1, opacity: 0)
        }
        switch stages[index] {
        case .waiting:
            return PhotoPose(
                position: CGPoint(x: center.x + FanLayout.entryOffset.width, y: center.y + FanLayout.entryOffset.height),
                rotation: .zero,
                scale: FanLayout.entryScale,
                opacity: 0
            )
        case .fanned:
            return fanned
        case .gathered:
            let heart = heartFrame.map { CGPoint(x: $0.midX, y: $0.midY + HeartGlyph.baselineOffset) } ?? center
            return PhotoPose(position: heart, rotation: .zero, scale: FanLayout.landingScale, opacity: 0)
        }
    }

    private func play() async {
        guard !photos.isEmpty else {
            onComplete()
            return
        }
        if reduceMotion {
            await animateAll(to: .fanned, with: Motion.fade, staggered: false)
            try? await Task.sleep(for: FanLayout.hold)
            await animateAll(to: .gathered, with: Motion.fade, staggered: false)
        } else {
            await animateAll(to: .fanned, with: .spring(duration: 0.5, bounce: 0.2), staggered: true)
            try? await Task.sleep(for: FanLayout.hold)
            await animateAll(to: .gathered, with: .spring(duration: 0.6, bounce: 0), staggered: true)
        }
        guard !Task.isCancelled else { return }
        onComplete()
    }

    /// Resumes when the last photo's animation completes, so the stagger and springs set the pace.
    private func animateAll(to stage: Stage, with animation: Animation, staggered: Bool) async {
        await withCheckedContinuation { continuation in
            let last = stages.indices.last
            for index in stages.indices {
                let delay = staggered ? FanLayout.delay(for: index) : 0
                withAnimation(animation.delay(delay)) {
                    stages[index] = stage
                } completion: {
                    if index == last { continuation.resume() }
                }
            }
        }
    }
}

private struct PhotoPose: ViewModifier {
    let position: CGPoint
    let rotation: Angle
    let scale: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .rotationEffect(rotation)
            .opacity(opacity)
            .position(position)
    }
}
