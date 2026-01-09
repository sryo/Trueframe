// Idle state before capture begins.

import SwiftUI

struct HomeScreen: View {
    @Environment(AppState.self) private var appState
    @State private var isVisible = false
    @State private var showingQualitySettings = false

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
                        CameraToggleView(settings: appState.cameraSelectionSettings)

                        // Capture interval picker (0.25s = burst-like speed)
                        if appState.captureMode == .photo {
                            CaptureIntervalPicker(settings: appState.captureSettings)
                        }
                    }
                    .opacity(isVisible ? 0.7 : 0)
                    .blur(radius: isVisible ? 0 : 6)
                    .animation(.easeOut(duration: 0.6).delay(0.4), value: isVisible)
                }
                .padding(.top, 60)
                .padding(.horizontal, 20)
                Spacer()

                // Capture mode selector (centered) with quality button (right)
                ZStack {
                    CaptureModeSelector(appState: appState)

                    HStack {
                        Spacer()
                        // Quality settings button
                        Button {
                            showingQualitySettings = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(width: 40, height: 40)
                                .background(
                                    Circle()
                                        .fill(Color.white.opacity(0.08))
                                )
                        }
                    }
                }
                .padding(.horizontal, 20)
                .opacity(isVisible ? 0.8 : 0)
                .blur(radius: isVisible ? 0 : 6)
                .animation(.easeOut(duration: 0.6).delay(0.5), value: isVisible)
                .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $showingQualitySettings) {
            PhotoQualitySettingsView(settings: appState.photoQualitySettings)
        }
        .accessibilityLabel("Trueframe home")
        .accessibilityHint("Hold phone to your heart to start capturing photos")
        .onChange(of: appState.isCapturing) { _, isCapturing in
            if isCapturing {
                withAnimation(.easeOut(duration: 0.15)) { isVisible = false }
            }
        }
        .onChange(of: appState.showingTumbleAnimation) { _, showing in
            if showing {
                withAnimation(.easeOut(duration: 0.15)) { isVisible = false }
            } else if !appState.isCapturing {
                // Tumble finished, fade back in
                isVisible = false
                withAnimation(.easeOut(duration: 0.8).delay(0.3)) { isVisible = true }
            }
        }
        .onAppear {
            if !appState.isCapturing {
                isVisible = false
                withAnimation(.easeOut(duration: 0.8).delay(0.2)) { isVisible = true }
            }
        }
    }
}

/// Heartbeat animation using PhaseAnimator (iOS 17+)
private struct HeartbeatSymbol: View {
    var body: some View {
        PhaseAnimator([false, true], trigger: true) { isBright in
            Text("♥")
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(isBright ? 0.6 : 0.30))
        } animation: { phase in
            phase ? .easeIn(duration: 0.05) : .easeOut(duration: 0.85)
        }
    }
}

/// Capture mode selector (Photo/Burst/Video)
struct CaptureModeSelector: View {
    @Bindable var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CaptureMode.allCases) { mode in
                CaptureModeButton(
                    mode: mode,
                    isSelected: appState.captureMode == mode
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        appState.captureMode = mode
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.08))
        )
    }
}

private struct CaptureModeButton: View {
    let mode: CaptureMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: mode.icon)
                    .font(.system(size: 12, weight: .medium))

                if isSelected {
                    Text(mode.displayName)
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .foregroundStyle(isSelected ? .black : .white.opacity(0.6))
            .padding(.horizontal, isSelected ? 16 : 12)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isSelected ? mode.accentColor : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Swipeable interval picker showing all options
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
        .environment(AppState())
}
