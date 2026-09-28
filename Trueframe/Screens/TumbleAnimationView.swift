import SwiftUI

/// The session's photos fan out so you see what you caught, then the kept ones
/// fall into the heart, which bursts into sparks in their colors. Dropped ones
/// miss it and are slung away.
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
    /// Which previews curation keeps; nil until it has decided.
    private let verdict: @MainActor () -> [Bool]?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Indices into `previews`, in capture order.
    @State private var shown: [Int]
    @State private var stages: [Stage]
    /// Per shown photo, whether it reaches the heart.
    @State private var kept: [Bool] = []
    @State private var collapsing = false
    @State private var clock = CollapseClock()
    @State private var handedOff = false
    @State private var tints: [Color] = []

    init(
        photos: [UIImage],
        verdict: @escaping @MainActor () -> [Bool]?,
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
        let shown = FanLayout.shownIndices(count: photos.count, kept: verdict())
        _shown = State(initialValue: shown)
        _stages = State(initialValue: Array(repeating: .waiting, count: shown.count))
    }

    private var slots: [FanLayout.Slot] { FanLayout.slots(count: shown.count) }

    private var heart: CGPoint {
        heartFrame.map { CGPoint(x: $0.midX, y: $0.midY + HeartGlyph.baselineOffset) }
            ?? CGPoint(x: canvas.width / 2, y: canvas.height / 2)
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
        let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        let slot = slots[index]
        let fanned = CGPoint(x: center.x + slot.offset.width, y: center.y + slot.offset.height)
        if let since {
            let progress = HeartCollapse.progress(at: since, index: index, count: shown.count)
            let start = CGPoint(x: fanned.x - heart.x, y: fanned.y - heart.y)
            let fall = kept[index]
                ? HeartCollapse.infall(from: start, fanRotation: slot.rotation.radians, progress: progress)
                : HeartCollapse.sling(from: start, fanRotation: slot.rotation.radians, progress: progress)
            return PhotoPose(
                position: CGPoint(x: heart.x + fall.offset.x, y: heart.y + fall.offset.y),
                rotation: .radians(fall.rotation),
                scaleX: fall.scaleX,
                scaleY: fall.scaleY,
                stretchAxis: .radians(fall.direction),
                opacity: fall.opacity,
                grayscale: fall.grayscale,
                brightness: fall.brightness
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
        let absorbed = HeartCollapse.absorbed(at: time, kept: kept)
        let squash = HeartCollapse.wobble(at: time, kept: kept) + HeartCollapse.shiver(at: time)
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
                Path(ellipseIn: CGRect(x: heart.x - r, y: heart.y - r, width: 2 * r, height: 2 * r)),
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
                Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                with: .color(tint.opacity(opacity))
            )
        }

        if let ring = BurstField.ring(at: t, cover: BurstField.cover(from: heart, in: size)) {
            context.stroke(
                Path(ellipseIn: CGRect(x: heart.x - ring.radius, y: heart.y - ring.radius, width: 2 * ring.radius, height: 2 * ring.radius)),
                with: .color(.white.opacity(ring.opacity)),
                lineWidth: ring.lineWidth
            )
        }
    }

    private func play() async {
        guard !previews.isEmpty else {
            handOff()
            onFinished()
            return
        }
        // Only a long session has to choose, and then it's worth a beat to choose
        // keepers; the slots are still invisible, so swapping what fills them can't show
        if previews.count > FanLayout.maxPhotos,
           let early = await FanLayout.awaitVerdict(within: FanLayout.fanVerdictGrace, read: verdict) {
            shown = FanLayout.shownIndices(count: previews.count, kept: early)
        }
        let fanned = shown.map { previews[$0] }
        let sampling = Task.detached(priority: .userInitiated) {
            fanned.map { BurstField.tint(for: $0.averageColor()) }
        }

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
        try? await Task.sleep(for: FanLayout.hold)
        let decided = await FanLayout.awaitVerdict(within: FanLayout.verdictDeadline, read: verdict)
        kept = FanLayout.keptFlags(shown: shown, verdict: decided)
        // Sparks carry only what the heart took in
        tints = zip(await sampling.value, kept).filter(\.1).map { Color(red: $0.0.red, green: $0.0.green, blue: $0.0.blue) }
        guard !Task.isCancelled else { return }

        collapsing = true
        while clock.start == nil, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(8))
        }
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

/// Starts on the first frame the fall is actually drawn, so a slow first
/// frame can't skip the photos partway down.
private final class CollapseClock {
    private(set) var start: Date?

    func elapsed(at date: Date) -> Double {
        if start == nil { start = date }
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
    var grayscale: Double = 0
    var brightness: Double = 1

    init(
        position: CGPoint,
        rotation: Angle,
        scaleX: CGFloat,
        scaleY: CGFloat,
        stretchAxis: Angle,
        opacity: Double,
        grayscale: Double = 0,
        brightness: Double = 1
    ) {
        self.position = position
        self.rotation = rotation
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.stretchAxis = stretchAxis
        self.opacity = opacity
        self.grayscale = grayscale
        self.brightness = brightness
    }

    init(position: CGPoint, rotation: Angle, scale: CGFloat, opacity: Double) {
        self.init(position: position, rotation: rotation, scaleX: scale, scaleY: scale, stretchAxis: .zero, opacity: opacity)
    }

    func body(content: Content) -> some View {
        content
            .grayscale(grayscale)
            .colorMultiply(Color(white: brightness))
            .rotationEffect(rotation - stretchAxis)
            .scaleEffect(x: scaleX, y: scaleY)
            .rotationEffect(stretchAxis)
            .opacity(opacity)
            .position(position)
    }
}
