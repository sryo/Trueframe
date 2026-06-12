// Idle state before capture begins.

import SwiftUI

struct HomeScreen: View {
    @Environment(SessionCoordinator.self) private var coordinator
    @State private var isVisible = false

    // MARK: - Visibility Animation Helpers

    private func hideContent() {
        withAnimation(.easeOut(duration: 0.15)) { isVisible = false }
    }

    private func showContent(delay: Double = 0.2) {
        withAnimation(.easeOut(duration: 0.8).delay(delay)) { isVisible = true }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                Spacer()

                Text("hold to your heart\nto capture life")
                    .font(.system(size: 56, weight: .semibold, design: .default))
                    .lineSpacing(-2)
                    .foregroundStyle(.white.opacity(0.20))
                    .blur(radius: isVisible ? 0 : 8)
                    .opacity(isVisible ? 1 : 0)

                HStack(spacing: 3) {
                    Text("trueframe")
                        .font(.system(size: 15, weight: .light, design: .default))
                        .foregroundStyle(.white.opacity(0.20))

                    HeartbeatSymbol()
                        .offset(y: 1)
                }
                .padding(.bottom, 50)
                .blur(radius: isVisible ? 0 : 6)
                .opacity(isVisible ? 1 : 0)
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
                    .opacity(isVisible ? 0.7 : 0)
                    .blur(radius: isVisible ? 0 : 6)
                    .animation(.easeOut(duration: 0.6).delay(0.4), value: isVisible)
                }
                .padding(.top, 60)
                .padding(.horizontal, 20)
                Spacer()
            }
        }
        .accessibilityLabel("Trueframe home")
        .accessibilityHint("Hold phone to your heart to start capturing photos")
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

private struct HeartbeatSymbol: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var beat = 0

    private static let restingBeatInterval = 60.0 / 52  // a resting heart

    var body: some View {
        // The heart waxes with the moon
        let (dim, bright) = Date.now.isNearFullMoon ? (0.5, 0.9) : (0.30, 0.6)

        PhaseAnimator([false, true], trigger: beat) { isBright in
            Text("♥")
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(isBright ? bright : dim))
        } animation: { phase in
            phase ? .easeIn(duration: 0.05) : .easeOut(duration: 0.85)
        }
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.restingBeatInterval))
                guard !Task.isCancelled else { return }
                // Once in a long while, a real heart skips
                if Int.random(in: 0..<500) == 0 {
                    try? await Task.sleep(for: .seconds(1.2))
                    beat += 1
                    try? await Task.sleep(for: .seconds(0.25))
                }
                beat += 1
            }
        }
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
