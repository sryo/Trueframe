// Idle state before capture begins.

import SwiftUI

struct HomeScreen: View {
    @Environment(SessionCoordinator.self) private var coordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reveal: [HomeReveal.Part: HomeReveal.State] = [:]

    // MARK: - Visibility Animation Helpers

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

    // MARK: - Body

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

                HStack(spacing: 3) {
                    Text("trueframe")
                        .font(.system(size: 15, weight: .light, design: .default))
                        .foregroundStyle(.white.opacity(0.20))

                    HeartbeatSymbol()
                        .offset(y: 1)
                }
                .padding(.bottom, 50)
                .revealPose(state(.wordmark), reduceMotion: reduceMotion)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack {
                HStack {
                    Spacer()

                    // Camera selection and interval
                    VStack(spacing: 12) {
                        CameraToggleView(settings: coordinator.cameraSelectionSettings)

                        // Capture interval picker (0.25s = burst-like speed)
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
            if isCapturing { hideContent() }
        }
        .onChange(of: coordinator.showingTumbleAnimation) { _, showing in
            if showing {
                hideContent()
            } else if !coordinator.isCapturing {
                showContent(delay: 0.3)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var beat = 0
    @State private var keyframes = HeartbeatKeyframes(isNearFullMoon: Date.now.isNearFullMoon)

    var body: some View {
        KeyframeAnimator(
            initialValue: HeartPose(opacity: keyframes.restingOpacity, scale: keyframes.restingScale),
            trigger: beat
        ) { pose in
            Text("♥")
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(reduceMotion ? keyframes.restingOpacity : pose.opacity))
                .scaleEffect(reduceMotion ? 1 : pose.scale)
        } keyframes: { _ in
            KeyframeTrack(\.opacity) {
                for step in keyframes.steps {
                    LinearKeyframe(step.opacity, duration: step.duration, timingCurve: step.easesOut ? .easeOut : .linear)
                }
            }
            KeyframeTrack(\.scale) {
                for step in keyframes.steps {
                    SpringKeyframe(step.scale, duration: step.duration, spring: .snappy)
                }
            }
        }
        .accessibilityHidden(true)
        .anchorPreference(key: HeartAnchorKey.self, value: .bounds) { $0 }
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
        beat += 1
    }
}

struct CaptureIntervalPicker: View {
    @Bindable var settings: CaptureSettings
    @State private var dragOffset: CGFloat = 0
    @State private var lastPreviewIndex: Int = -1

    private let options = CaptureSettings.intervalOptions
    private let itemWidth: CGFloat = 32
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    private var currentIndex: Int {
        options.firstIndex(of: settings.captureInterval) ?? 2
    }

    private var previewIndex: Int {
        let offsetInItems = -dragOffset / itemWidth
        let targetIndex = currentIndex + Int(round(offsetInItems))
        return max(0, min(options.count - 1, targetIndex))
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, interval in
                IntervalItem(
                    interval: interval,
                    isSelected: isItemSelected(index: index)
                )
            }
        }
        .offset(x: dragOffset)
        .gesture(dragGesture)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.08))
        )
        .onAppear {
            haptic.prepare()
        }
    }

    private func isItemSelected(index: Int) -> Bool {
        dragOffset == 0 ? (index == currentIndex) : (index == previewIndex)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation.width
                let newPreview = previewIndex
                if newPreview != lastPreviewIndex {
                    haptic.impactOccurred()
                    lastPreviewIndex = newPreview
                }
            }
            .onEnded { _ in
                let newIndex = previewIndex
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    settings.captureInterval = options[newIndex]
                    dragOffset = 0
                }
                lastPreviewIndex = -1
            }
    }
}

private struct IntervalItem: View {
    let interval: Double
    let isSelected: Bool

    var body: some View {
        Text(CaptureSettings.formatInterval(interval))
            .font(.system(size: 10, weight: isSelected ? .bold : .regular))
            .foregroundStyle(isSelected ? .white : .white.opacity(0.3))
            .frame(width: 32, height: 24)
            .background(
                Capsule()
                    .fill(isSelected ? Color.white.opacity(0.15) : Color.clear)
            )
    }
}

#Preview {
    HomeScreen()
        .environment(SessionCoordinator())
}
