import SwiftUI

/// The photos curation kept fan out so you see what you caught, then fall into
/// the heart, which bursts into sparks in their colors. Dropped photos never
/// appear: the heart means kept.
///
/// The fall and burst are clock-driven from one start time, so they play out
/// the same however often the view updates.
struct TumbleAnimationView: View {
    let heartFrame: CGRect?
    let canvas: CGSize
    /// Home can come back; the sparks keep flying over it.
    let onComplete: () -> Void
    /// Nothing is left to draw.
    let onFinished: () -> Void

    private enum Stage {
        case waiting
        case fanned
        case faded
    }

    private let previews: [UIImage]
    /// What curation decided about `previews`; nil until it has.
    private let verdict: @MainActor () -> FanLayout.Verdict?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Indices into `previews`, in capture order; empty until the verdict.
    @State private var shown: [Int] = []
    @State private var stages: [Stage] = []
    @State private var fanInserted = ResumeOnce()
    @State private var collapsing = false
    @State private var clock = CollapseClock()
    @State private var handedOff = false
    @State private var tints: [Color] = []

    init(
        photos: [UIImage],
        verdict: @escaping @MainActor () -> FanLayout.Verdict?,
        heartFrame: CGRect?,
        canvas: CGSize,
        onComplete: @escaping () -> Void,
        onFinished: @escaping () -> Void
    ) {
        self.previews = photos
        self.verdict = verdict
        self.heartFrame = heartFrame
        self.canvas = canvas
        self.onComplete = onComplete
        self.onFinished = onFinished
    }

    private var slots: [FanLayout.Slot] { FanLayout.slots(count: shown.count) }

    private var center: CGPoint {
        CGPoint(x: canvas.width / 2, y: canvas.height / 2)
    }

    private var heart: CGPoint {
        heartFrame?.heartCenter ?? center
    }

    var body: some View {
        TimelineView(.animation(paused: !collapsing)) { timeline in
            let since = collapsing ? clock.elapsed(at: timeline.date) : nil
            ZStack {
                // Swallows touches meant for the hidden home controls
                Color.clear.contentShape(Rectangle())

                ForEach(stages.indices, id: \.self) { index in
                    photo(previews[shown[index]])
                        .modifier(pose(for: index, since: since))
                        .onAppear {
                            if index == stages.count - 1 { fanInserted.resume() }
                        }
                }

                if let since {
                    Canvas { context, size in
                        drawCore(in: context, at: since)
                        drawBurst(in: context, at: since - HeartCollapse.burstStart, size: size)
                    }
                }
            }
        }
        .allowsHitTesting(!handedOff)
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

    private func pose(for index: Int, since: Double?) -> PhotoPose {
        let slot = slots[index]
        let fanned = CGPoint(x: center.x + slot.offset.width, y: center.y + slot.offset.height)
        if let since {
            let fall = HeartCollapse.infall(
                from: CGPoint(x: fanned.x - heart.x, y: fanned.y - heart.y),
                fanRotation: slot.rotation.radians,
                progress: HeartCollapse.progress(at: since, index: index, count: shown.count)
            )
            return PhotoPose(
                position: CGPoint(x: heart.x + fall.offset.x, y: heart.y + fall.offset.y),
                rotation: .radians(fall.rotation),
                scaleX: fall.scaleX,
                scaleY: fall.scaleY,
                stretchAxis: .radians(fall.direction),
                opacity: fall.opacity
            )
        }
        switch stages[index] {
        case .waiting where !reduceMotion:
            return PhotoPose(
                position: CGPoint(x: center.x + FanLayout.entryOffset.width, y: center.y + FanLayout.entryOffset.height),
                rotation: .zero,
                scale: FanLayout.entryScale,
                opacity: 0
            )
        case .fanned:
            return PhotoPose(position: fanned, rotation: slot.rotation, scale: 1, opacity: 1)
        // Reduce Motion keeps the fan still and only fades it in and out
        case .waiting, .faded:
            return PhotoPose(position: fanned, rotation: slot.rotation, scale: 1, opacity: 0)
        }
    }

    private func drawCore(in context: GraphicsContext, at time: Double) {
        guard time < HeartCollapse.burstStart else { return }
        let absorbed = HeartCollapse.absorbed(at: time, count: shown.count)
        let squash = HeartCollapse.wobble(at: time, count: shown.count) + HeartCollapse.shiver(at: time)
        var core = context
        core.translateBy(x: heart.x, y: heart.y)
        core.scaleBy(x: 1 + squash, y: 1 - squash)
        core.fill(
            HeartCollapse.heartPath(halfWidth: HeartCollapse.coreRadius(at: time, absorbed: absorbed)),
            with: .color(.white.opacity(HeartCollapse.coreOpacity(at: time, absorbed: absorbed)))
        )
    }

    private func drawBurst(in context: GraphicsContext, at t: Double, size: CGSize) {
        guard t >= 0, t < BurstField.duration else { return }

        let glow = BurstField.glowOpacity(at: t)
        if glow > 0 {
            let r = BurstField.glowRadius
            context.fill(
                circle(at: heart, radius: r),
                with: .radialGradient(
                    Gradient(colors: [.white.opacity(glow), .white.opacity(0)]),
                    center: heart, startRadius: 0, endRadius: r
                )
            )
        }

        for (index, spark) in BurstField.sparks.enumerated() {
            let opacity = BurstField.opacity(of: spark, at: t)
            guard opacity > 0 else { continue }
            let p = BurstField.position(of: spark, at: t, around: heart)
            let r = BurstField.radius(of: spark, at: t)
            let tint = tints.isEmpty ? Color.white : tints[index % tints.count]
            context.fill(
                circle(at: p, radius: r),
                with: .color(tint.opacity(opacity))
            )
        }

        if let ring = BurstField.ring(at: t, cover: BurstField.cover(from: heart, in: size)) {
            context.stroke(
                circle(at: heart, radius: ring.radius),
                with: .color(.white.opacity(ring.opacity)),
                lineWidth: ring.lineWidth
            )
        }
    }

    private func circle(at center: CGPoint, radius r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
    }

    private func play() async {
        let decided = await FanLayout.awaitVerdict(within: FanLayout.verdictDeadline, read: verdict)
        guard !Task.isCancelled else { return }
        guard case .fan(let chosen) = FanLayout.plan(for: decided) else {
            // Better no fan than one that might show a dropped photo; home's
            // heart still takes the landing beat
            handOff()
            onFinished()
            return
        }
        let fanned = chosen.map { previews[$0] }
        let sampling = Task.detached(priority: .userInitiated) {
            fanned.map { BurstField.tint(for: $0.averageColor()) }
        }
        shown = chosen
        stages = Array(repeating: .waiting, count: chosen.count)
        // The fan-in has to start from photos already on screen at .waiting
        await fanInserted.wait()
        guard !Task.isCancelled else { return }

        if reduceMotion {
            await animateAll(to: .fanned, with: Motion.fade, staggered: false)
            try? await Task.sleep(for: FanLayout.hold)
            await animateAll(to: .faded, with: Motion.fade, staggered: false)
            guard !Task.isCancelled else { return }
            handOff()
            onFinished()
            return
        }

        await animateAll(to: .fanned, with: .spring(duration: 0.5, bounce: 0.2), staggered: true)
        guard !Task.isCancelled else { return }
        try? await Task.sleep(for: FanLayout.hold)
        tints = await sampling.value.map { Color(red: $0.red, green: $0.green, blue: $0.blue) }
        guard !Task.isCancelled else { return }

        collapsing = true
        await clock.started.wait()
        guard let start = clock.start else { return }
        try? await Task.sleep(for: .seconds(HeartCollapse.handoff - Date.now.timeIntervalSince(start)))
        guard !Task.isCancelled else { return }
        handOff()
        try? await Task.sleep(for: .seconds(HeartCollapse.finished - Date.now.timeIntervalSince(start)))
        guard !Task.isCancelled else { return }
        onFinished()
    }

    private func handOff() {
        handedOff = true
        onComplete()
    }

    /// Resumes when the last photo's animation completes, so the stagger and springs set the pace.
    private func animateAll(to stage: Stage, with animation: Animation, staggered: Bool) async {
        let lastLanded = ResumeOnce()
        let last = stages.indices.last
        if last == nil { lastLanded.resume() }
        for index in stages.indices {
            let delay = staggered ? FanLayout.delay(for: index) : 0
            withAnimation(animation.delay(delay)) {
                stages[index] = stage
            } completion: {
                if index == last { lastLanded.resume() }
            }
        }
        await lastLanded.wait()
    }
}

/// Starts on the first frame the fall is actually drawn, so a slow first
/// frame can't skip the photos partway down.
private final class CollapseClock {
    private(set) var start: Date?
    let started = ResumeOnce()

    func elapsed(at date: Date) -> Double {
        if start == nil {
            start = date
            started.resume()
        }
        return date.timeIntervalSince(start ?? date)
    }
}

private struct PhotoPose: ViewModifier {
    let position: CGPoint
    let rotation: Angle
    let scaleX: CGFloat
    let scaleY: CGFloat
    /// Scaling happens along this axis, so a falling photo stretches along its path.
    let stretchAxis: Angle
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .rotationEffect(rotation - stretchAxis)
            .scaleEffect(x: scaleX, y: scaleY)
            .rotationEffect(stretchAxis)
            .opacity(opacity)
            .position(position)
    }
}

private extension PhotoPose {
    init(position: CGPoint, rotation: Angle, scale: CGFloat, opacity: Double) {
        self.init(position: position, rotation: rotation, scaleX: scale, scaleY: scale, stretchAxis: .zero, opacity: opacity)
    }
}
