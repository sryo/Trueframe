// Camera lens selector view.

import AVFoundation
import SwiftUI

// MARK: - Zoom Label

/// The telephoto lens's zoom factor relative to the wide lens, from their horizontal fields of view.
func zoomLabel(teleFOV: Double?, wideFOV: Double?) -> String {
    guard let teleFOV, teleFOV > 0 else { return "2x" }
    // Most iPhone wide cameras sit near 77 degrees.
    let wideFOV = wideFOV.flatMap { $0 > 0 ? $0 : nil } ?? 77.0
    let ratio = tan(wideFOV * .pi / 360) / tan(teleFOV * .pi / 360)
    let factor = Int(ratio.rounded())
    return "\(min(max(factor, 2), 10))x"
}

/// Discovery is expensive, so the label is computed once per launch.
private enum TelephotoDiscovery {
    static let label: String = {
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTelephotoCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: .back
        ).devices
        let fov = { (type: AVCaptureDevice.DeviceType) in
            devices.first { $0.deviceType == type }.map { Double($0.activeFormat.videoFieldOfView) }
        }
        return zoomLabel(teleFOV: fov(.builtInTelephotoCamera), wideFOV: fov(.builtInWideAngleCamera))
    }()
}

// MARK: - Lens Style

enum LensStyle {
    static func scale(isSelected: Bool) -> CGFloat {
        isSelected ? 1.0 : 0.86
    }

    static func labelOpacity(isSelected: Bool) -> Double {
        isSelected ? 0.9 : 0.3
    }
}

// MARK: - Camera Toggle View

struct CameraToggleView: View {
    @Bindable var settings: CameraSelectionSettings

    @Namespace private var glassNamespace

    private let circleSize: CGFloat = 52
    private let flashSize: CGFloat = 24
    private let verticalSpacing: CGFloat = 6
    private let horizontalSpacing: CGFloat = 2

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(alignment: .top, spacing: horizontalSpacing) {
                VStack(spacing: verticalSpacing) {
                    FlashButton(
                        isEnabled: settings.flashEnabled,
                        size: flashSize
                    ) {
                        settings.flashEnabled.toggle()
                    }

                    lens(.ultrawide, label: "0.5", accessibilityLabel: "Ultrawide camera")
                }

                VStack(spacing: verticalSpacing) {
                    lens(.telephoto, label: TelephotoDiscovery.label, accessibilityLabel: "Telephoto camera")
                    lens(.wide, label: "1x", accessibilityLabel: "Wide camera")
                }
            }
            .padding(12)
        }
        .sensoryFeedback(.selection, trigger: settings.selectedCamera)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Lens")
    }

    private func lens(_ camera: BackCameraType, label: String, accessibilityLabel: String) -> some View {
        CameraLensButton(
            isSelected: settings.selectedCamera == camera,
            label: label,
            accessibilityLabel: accessibilityLabel,
            size: circleSize
        ) {
            settings.select(camera)
        }
        .glassEffectID(camera, in: glassNamespace)
    }
}

// MARK: - Camera Lens Button

private struct CameraLensButton: View {
    let isSelected: Bool
    let label: String
    let accessibilityLabel: String
    let size: CGFloat
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(LensStyle.labelOpacity(isSelected: isSelected)))
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .strokeBorder(.white.opacity(0.6), lineWidth: 1)
                        .opacity(isSelected ? 1 : 0)
                )
                .contentShape(Circle())
                .glassEffect(.clear.interactive(), in: .circle)
                .scaleEffect(reduceMotion ? 1 : LensStyle.scale(isSelected: isSelected))
                .animation(reduceMotion ? Motion.fade : Motion.glass, value: isSelected)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Flash Button

private struct FlashButton: View {
    let isEnabled: Bool
    let size: CGFloat
    let action: () -> Void

    private let enabledColor = Color.yellow
    private let disabledColor = Color.white.opacity(0.20)

    var body: some View {
        Button(action: action) {
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
        }
        .buttonStyle(PressStyle())
        .sensoryFeedback(.impact(weight: .light), trigger: isEnabled)
        .accessibilityLabel("Flash")
        .accessibilityValue(isEnabled ? "On" : "Off")
        .accessibilityHint("Double tap to toggle")
    }
}

// MARK: - Press Style

private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressedLabel(label: configuration.label, isPressed: configuration.isPressed)
    }
}

private struct PressedLabel<Label: View>: View {
    let label: Label
    let isPressed: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        label
            .scaleEffect(isPressed && !reduceMotion ? 0.92 : 1)
            .opacity(isPressed && reduceMotion ? 0.7 : 1)
            .animation(reduceMotion ? Motion.fade : Motion.press, value: isPressed)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 40) {
            CameraToggleView(settings: CameraSelectionSettings())

            CameraToggleView(settings: {
                let s = CameraSelectionSettings()
                s.select(.telephoto)
                s.flashEnabled = true
                return s
            }())
        }
    }
}
