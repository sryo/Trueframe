// Camera lens selector view.

import AVFoundation
import SwiftUI

// MARK: - Shared Helpers

/// Triggers a light haptic feedback. Shared across button components.
private func triggerHaptic() {
    let generator = UIImpactFeedbackGenerator(style: .light)
    generator.impactOccurred()
}

// MARK: - Cached Device Discovery

/// Computes the telephoto zoom label once; discovery is expensive per render.
private enum TelephotoDiscovery {
    static let label: String = {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTelephotoCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: .back
        )
        let devices = session.devices
        let telephoto = devices.first(where: { $0.deviceType == .builtInTelephotoCamera })
        let wide = devices.first(where: { $0.deviceType == .builtInWideAngleCamera })

        // Try to get FOV from both cameras
        if let tele = telephoto, let w = wide {
            let teleFOV = Double(tele.activeFormat.videoFieldOfView)
            let wideFOV = Double(w.activeFormat.videoFieldOfView)

            if teleFOV > 0, wideFOV > 0 {
                // FOV ratio approximates zoom factor
                let teleRadians = teleFOV * .pi / 360.0
                let wideRadians = wideFOV * .pi / 360.0
                let ratio = tan(wideRadians) / tan(teleRadians)
                let zoomFactor = Int(round(ratio))
                return "\(max(2, min(zoomFactor, 10)))x"
            }
        }

        // Fallback: estimate from telephoto FOV alone (typical wide is ~77° FOV)
        if let tele = telephoto {
            let teleFOV = Double(tele.activeFormat.videoFieldOfView)
            if teleFOV > 0 {
                let typicalWideFOV = 77.0  // Typical iPhone wide camera FOV
                let teleRadians = teleFOV * .pi / 360.0
                let wideRadians = typicalWideFOV * .pi / 360.0
                let ratio = tan(wideRadians) / tan(teleRadians)
                let zoomFactor = Int(round(ratio))
                return "\(max(2, min(zoomFactor, 10)))x"
            }
        }

        // No telephoto camera available
        return "2x"
    }()
}

// MARK: - Camera Toggle View

struct CameraToggleView: View {
    @Bindable var settings: CameraSelectionSettings

    // Layout constants
    private let circleSize: CGFloat = 52
    private let flashSize: CGFloat = 24
    private let verticalSpacing: CGFloat = 6
    private let horizontalSpacing: CGFloat = 2

    var body: some View {
        HStack(alignment: .top, spacing: horizontalSpacing) {
            // Left column: Flash (top) and Ultrawide below it
            VStack(spacing: verticalSpacing) {
                FlashButton(
                    isEnabled: settings.flashEnabled,
                    size: flashSize
                ) {
                    settings.flashEnabled.toggle()
                }

                CameraLensButton(
                    isEnabled: settings.selectedCamera == .ultrawide,
                    label: "0.5",
                    accessibilityLabel: "Ultrawide camera",
                    size: circleSize
                ) {
                    settings.select(.ultrawide)
                }
            }

            // Right column: Telephoto (top) and Wide (bottom), vertically stacked
            VStack(spacing: verticalSpacing) {
                CameraLensButton(
                    isEnabled: settings.selectedCamera == .telephoto,
                    label: TelephotoDiscovery.label,
                    accessibilityLabel: "Telephoto camera",
                    size: circleSize
                ) {
                    settings.select(.telephoto)
                }

                CameraLensButton(
                    isEnabled: settings.selectedCamera == .wide,
                    label: "1x",
                    accessibilityLabel: "Wide camera",
                    size: circleSize
                ) {
                    settings.select(.wide)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
    }
}

// MARK: - Camera Lens Button

private struct CameraLensButton: View {
    let isEnabled: Bool
    let label: String
    let accessibilityLabel: String
    let size: CGFloat
    let action: () -> Void

    @State private var isPressed = false

    // Visual constants
    private let enabledRingColor = Color.white
    private let disabledRingColor = Color.white.opacity(0.20)
    private let enabledFillColor = Color.white.opacity(0.15)
    private let disabledFillColor = Color.white.opacity(0.08)
    private let ringWidth: CGFloat = 1.5

    var body: some View {
        Button(action: {
            triggerHaptic()
            action()
        }) {
            ZStack {
                // Outer lens ring
                Circle()
                    .fill(isEnabled ? enabledFillColor : disabledFillColor)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                isEnabled ? enabledRingColor : disabledRingColor,
                                lineWidth: ringWidth
                            )
                    )
                    .shadow(
                        color: isEnabled ? Color.white.opacity(0.08) : Color.clear,
                        radius: 4,
                        x: 0,
                        y: 0
                    )

                // Inner lens element (darker center)
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                Color.black.opacity(0.6),
                                Color.black.opacity(0.3)
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.35
                        )
                    )
                    .frame(width: size * 0.55, height: size * 0.55)

                // Focal length label
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .default))
                    .foregroundStyle(isEnabled ? Color.white.opacity(0.9) : Color.white.opacity(0.20))
            }
            .frame(width: size, height: size)
            .scaleEffect(isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isPressed)
            .scaleEffect(isEnabled ? 1.0 : 0.95)
            .animation(.easeOut(duration: 0.2), value: isEnabled)
        }
        .buttonStyle(LensPressStyle(isPressed: $isPressed))
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isEnabled ? "Enabled" : "Disabled")
        .accessibilityHint("Double tap to toggle")
    }
}

// MARK: - Flash Button

private struct FlashButton: View {
    let isEnabled: Bool
    let size: CGFloat
    let action: () -> Void

    @State private var isPressed = false

    private let enabledColor = Color.yellow
    private let disabledColor = Color.white.opacity(0.20)

    var body: some View {
        Button(action: {
            triggerHaptic()
            action()
        }) {
            ZStack {
                Circle()
                    .fill(isEnabled ? enabledColor.opacity(0.2) : Color.white.opacity(0.03))
                    .overlay(
                        Circle()
                            .strokeBorder(
                                isEnabled ? enabledColor : disabledColor,
                                lineWidth: 1.5
                            )
                    )
                    .shadow(
                        color: isEnabled ? enabledColor.opacity(0.3) : Color.clear,
                        radius: 4,
                        x: 0,
                        y: 0
                    )

                Image(systemName: isEnabled ? "bolt.fill" : "bolt.slash")
                    .font(.system(size: size * 0.4, weight: .medium))
                    .foregroundStyle(isEnabled ? enabledColor : disabledColor)
            }
            .frame(width: size, height: size)
            .scaleEffect(isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isPressed)
        }
        .buttonStyle(LensPressStyle(isPressed: $isPressed))
        .accessibilityLabel("Flash")
        .accessibilityValue(isEnabled ? "On" : "Off")
        .accessibilityHint("Double tap to toggle")
    }
}

// MARK: - Custom Button Style

private struct LensPressStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in
                isPressed = pressed
            }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 40) {
            CameraToggleView(settings: CameraSelectionSettings())

            // Preview with different states
            CameraToggleView(settings: {
                let s = CameraSelectionSettings()
                s.select(.telephoto)
                return s
            }())
        }
    }
}
