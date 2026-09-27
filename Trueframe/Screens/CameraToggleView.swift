// Camera lens selector view.

import AVFoundation
import SwiftUI

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

enum LensStyle {
    static func scale(isSelected: Bool) -> CGFloat {
        isSelected ? 1.0 : 0.86
    }

    static func labelOpacity(isSelected: Bool) -> Double {
        isSelected ? 0.9 : 0.3
    }
}

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
                    .glassEffectID("flash", in: glassNamespace)

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

enum FlashStyle {
    static let minimumHitSize: CGFloat = 44

    static func hitInset(visualSize: CGFloat) -> CGFloat {
        -max(0, (minimumHitSize - visualSize) / 2)
    }

    static func accessibilityValue(isOn: Bool) -> String {
        isOn ? "On" : "Off"
    }

    static func symbol(isOn: Bool) -> String {
        isOn ? "bolt.fill" : "bolt.slash"
    }
}

private struct FlashButton: View {
    let isEnabled: Bool
    let size: CGFloat
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let yellow = Color(red: 1, green: 214 / 255, blue: 10 / 255)
    private let offColor = Color.white.opacity(0.20)

    var body: some View {
        Button(action: action) {
            Image(systemName: FlashStyle.symbol(isOn: isEnabled))
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundStyle(isEnabled ? yellow : offColor)
                .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace.downUp))
                .frame(width: size, height: size)
                .background(Circle().fill(isEnabled ? yellow.opacity(0.16) : .white.opacity(0.03)))
                .overlay(
                    Circle().strokeBorder(isEnabled ? yellow.opacity(0.85) : offColor, lineWidth: 1.5)
                )
                .glassEffect(.clear.interactive(), in: .circle)
                .shadow(color: isEnabled ? yellow.opacity(0.2) : .clear, radius: 3)
                .contentShape(Circle().inset(by: FlashStyle.hitInset(visualSize: size)))
                .animation(reduceMotion ? Motion.fade : Motion.select, value: isEnabled)
        }
        .buttonStyle(PressStyle())
        .sensoryFeedback(.impact(weight: .light), trigger: isEnabled)
        .accessibilityLabel("Flash")
        .accessibilityValue(FlashStyle.accessibilityValue(isOn: isEnabled))
        .accessibilityAddTraits(.isToggle)
    }
}

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
