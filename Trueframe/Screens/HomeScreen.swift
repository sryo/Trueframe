import SwiftUI

struct HomeScreen: View {
    @Environment(SessionCoordinator.self) private var coordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reveal: [HomeReveal.Part: HomeReveal.State] = [:]
    /// After the first session the heart never leaves its spot; home comes and goes around it.
    @State private var heartStaysPut = false
    @State private var landings = 0

    private var sessionHoldsHeart: Bool {
        coordinator.isCapturing || coordinator.showingTumbleAnimation
    }

    private func hideContent() {
        withAnimation(Motion.dismiss) {
            for part in HomeReveal.Part.all { reveal[part] = .left }
        } completion: {
            // Reset off screen so the next entrance rises from below instead of the sink point.
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) {
                for part in HomeReveal.Part.all where reveal[part] == .left { reveal[part] = .waiting }
            }
        }
    }

    func showContent(delay: Double = 0.2) {
        for part in HomeReveal.Part.all {
            withAnimation(entrance(for: part).delay(HomeReveal.delay(for: part, after: delay))) {
                reveal[part] = .shown
            }
        }
    }

    private func entrance(for part: HomeReveal.Part) -> Animation {
        if reduceMotion { return .easeOut(duration: 0.25) }
        return part == .controls ? .spring(duration: 0.7, bounce: 0) : .spring(duration: 0.9, bounce: 0)
    }

    private func state(_ part: HomeReveal.Part) -> HomeReveal.State {
        reveal[part] ?? .waiting
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                Spacer()

                VStack(alignment: .leading, spacing: -2) {
                    ForEach(HomeReveal.lines.indices, id: \.self) { index in
                        Text(HomeReveal.lines[index])
                            .font(.system(size: 56, weight: .semibold, design: .default))
                            .lineSpacing(-2)
                            .foregroundStyle(.white.opacity(0.20))
                            .revealPose(state(.line(index)), reduceMotion: reduceMotion)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Trueframe home")
                .accessibilityHint("Hold phone to your heart to start capturing photos")

                // Poses apply per item, not to the row, so the heart's anchor never moves
                HStack(spacing: 3) {
                    Text("trueframe")
                        .font(.system(size: 15, weight: .light, design: .default))
                        .foregroundStyle(.white.opacity(0.20))
                        .revealPose(state(.wordmark), reduceMotion: reduceMotion)

                    HeartbeatSymbol(landings: landings)
                        .offset(y: HeartGlyph.baselineOffset)
                        .revealPose(heartStaysPut ? .shown : state(.wordmark), reduceMotion: reduceMotion)
                        .opacity(sessionHoldsHeart ? 0 : 1)
                        // Crossfades with the capture heart so a beat in progress never snaps
                        .animation(sessionHoldsHeart ? Motion.dismiss : nil, value: sessionHoldsHeart)
                }
                .padding(.bottom, 50)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack {
                HStack {
                    Spacer()

                    VStack(spacing: 12) {
                        CameraToggleView(settings: coordinator.cameraSelectionSettings)

                        CaptureIntervalPicker(settings: coordinator.captureSettings)
                    }
                    .opacity(0.7)
                    .revealPose(state(.controls), reduceMotion: reduceMotion, rises: false)
                }
                .padding(.top, 60)
                .padding(.horizontal, 20)
                Spacer()
            }
        }
        .onChange(of: coordinator.isCapturing) { _, isCapturing in
            if isCapturing {
                heartStaysPut = true
                hideContent()
            } else if !coordinator.showingTumbleAnimation {
                showContent(delay: 0)
            }
        }
        .onChange(of: coordinator.showingTumbleAnimation) { _, showing in
            if showing {
                hideContent()
            } else if !coordinator.isCapturing {
                landings += 1
                showContent(delay: 0)
            }
        }
        .onAppear {
            if !coordinator.isCapturing { showContent() }
        }
    }
}

private extension View {
    func revealPose(_ state: HomeReveal.State, reduceMotion: Bool, rises: Bool = true) -> some View {
        let pose = HomeReveal.pose(for: state, reduceMotion: reduceMotion, rises: rises)
        return self
            .blur(radius: pose.blur)
            .opacity(pose.opacity)
            .offset(y: pose.offsetY)
    }
}

private struct HeartPose {
    var opacity: Double
    var scale: Double
}

private struct HeartbeatSymbol: View {
    /// Bumped each time a celebration hands the screen back to home.
    let landings: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var beat = 0
    @State private var beatIsLanding = false
    @State private var keyframes = HeartbeatKeyframes(isNearFullMoon: Date.now.isNearFullMoon)

    var body: some View {
        KeyframeAnimator(
            initialValue: HeartPose(opacity: keyframes.dim, scale: 1),
            trigger: beat
        ) { pose in
            HeartGlyph()
                .foregroundStyle(.white.opacity(reduceMotion ? keyframes.dim : pose.opacity))
                .scaleEffect(reduceMotion ? 1 : pose.scale)
        } keyframes: { _ in
            let steps = beatIsLanding ? SessionHeart.landingBeat(settlingTo: keyframes) : keyframes.steps
            KeyframeTrack(\.opacity) {
                // The builder has no `if`; a landing beat jumps to dark first
                for start in beatIsLanding ? [SessionHeart.landingStart] : [] {
                    MoveKeyframe(start)
                }
                for step in steps {
                    step.opacityKeyframe
                }
            }
            KeyframeTrack(\.scale) {
                for step in steps {
                    SpringKeyframe(step.scale, duration: step.duration, spring: .snappy)
                }
            }
        }
        .accessibilityHidden(true)
        .anchorPreference(key: HeartAnchorKey.self, value: .bounds) { $0 }
        .onChange(of: landings) {
            beatIsLanding = true
            beat += 1
        }
        .task(id: reduceMotion) {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: Motion.restingBeatInterval)
                guard !Task.isCancelled else { return }
                // Once in a long while, a real heart skips
                if Int.random(in: 0..<500) == 0 {
                    try? await Task.sleep(for: .seconds(1.2))
                    pulse()
                    try? await Task.sleep(for: .seconds(0.25))
                }
                pulse()
            }
        }
    }

    // The moon can turn full while the app stays open, so check it each beat.
    private func pulse() {
        let current = HeartbeatKeyframes(isNearFullMoon: Date.now.isNearFullMoon)
        if current != keyframes { keyframes = current }
        beatIsLanding = false
        beat += 1
    }
}

struct CaptureIntervalPicker: View {
    @Bindable var settings: CaptureSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0

    private let options = CaptureSettings.intervalOptions
    /// Shorter than this, a touch counts as a tap on the value under it.
    private let tapSlop: CGFloat = 3

    private var currentIndex: Int {
        IntervalPickerGeometry.nearestIndex(for: settings.captureInterval)
    }

    private var rowOffset: CGFloat {
        ScrubWheelMath.rowOffset(for: currentIndex) + dragOffset
    }

    private var centeredIndex: Int {
        ScrubWheelMath.nearestIndex(forRowOffset: rowOffset, count: options.count)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.white.opacity(0.15))
                .frame(width: ScrubWheelMath.itemWidth, height: 24)
                .offset(x: (ScrubWheelMath.windowWidth - ScrubWheelMath.itemWidth) / 2)

            HStack(spacing: IntervalPickerGeometry.spacing) {
                ForEach(options.indices, id: \.self) { index in
                    let distance = ScrubWheelMath.distance(of: index, rowOffset: rowOffset)
                    IntervalItem(
                        interval: options[index],
                        isCentered: ScrubWheelMath.isCentered(atDistance: distance)
                    )
                    .scaleEffect(ScrubWheelMath.scale(atDistance: distance))
                    .opacity(ScrubWheelMath.opacity(atDistance: distance))
                }
            }
            .offset(x: rowOffset)
        }
        .frame(width: ScrubWheelMath.windowWidth, height: 32, alignment: .leading)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .clipShape(Capsule())
        .frame(height: 44)
        .contentShape(Rectangle())
        .gesture(scrub)
        .sensoryFeedback(.selection, trigger: centeredIndex)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Capture interval")
        .accessibilityValue(ScrubWheelMath.accessibilityValue(for: options[currentIndex]))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: select(ScrubWheelMath.steppedIndex(from: currentIndex, by: 1, count: options.count))
            case .decrement: select(ScrubWheelMath.steppedIndex(from: currentIndex, by: -1, count: options.count))
            @unknown default: break
            }
        }
    }

    private var scrub: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                dragOffset = value.translation.width
            }
            .onEnded { value in
                let index = abs(value.translation.width) < tapSlop
                    ? ScrubWheelMath.tappedIndex(
                        atX: value.location.x,
                        rowOffset: ScrubWheelMath.rowOffset(for: currentIndex),
                        count: options.count
                    )
                    : centeredIndex
                select(index)
            }
    }

    private func select(_ index: Int) {
        withAnimation(reduceMotion ? nil : Motion.snap) {
            settings.captureInterval = options[index]
            dragOffset = 0
        }
    }
}

private struct IntervalItem: View {
    let interval: Double
    let isCentered: Bool

    var body: some View {
        Text(CaptureSettings.formatInterval(interval))
            .font(.system(size: 10, weight: isCentered ? .bold : .regular))
            .foregroundStyle(isCentered ? .white : .white.opacity(0.3))
            .frame(width: ScrubWheelMath.itemWidth, height: 24)
    }
}

#Preview {
    HomeScreen()
        .environment(SessionCoordinator())
}
