// Photo quality settings - simple mode selection.

import SwiftUI

struct PhotoQualitySettingsView: View {
    @Bindable var settings: PhotoQualitySettings
    @Environment(\.dismiss) private var dismiss
    @State private var availableStorage: Int64 = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // Mode selector
                HStack(spacing: 16) {
                    ForEach(PhotoQualityMode.allCases) { mode in
                        QualityModeButton(
                            mode: mode,
                            isSelected: settings.mode == mode
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                settings.mode = mode
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }
                }
                .padding(.horizontal)

                // Storage info
                VStack(spacing: 8) {
                    Text(settings.estimatedFileSizeFormatted)
                        .font(.system(size: 32, weight: .semibold, design: .rounded))

                    let capacity = settings.estimatedPhotosForStorage(availableBytes: availableStorage)
                    Text("\(capacity) photos fit in storage")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .navigationTitle("Photo Quality")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .onAppear { updateAvailableStorage() }
    }

    private func updateAvailableStorage() {
        if let attributes = try? FileManager.default.attributesOfFileSystem(
            forPath: NSHomeDirectory()
        ),
           let freeSpace = attributes[.systemFreeSize] as? Int64 {
            availableStorage = freeSpace
        }
    }
}

// MARK: - Quality Mode Button

private struct QualityModeButton: View {
    let mode: PhotoQualityMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.white : Color.white.opacity(0.1))
                        .frame(width: 64, height: 64)

                    Image(systemName: mode.iconName)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(isSelected ? .black : .white.opacity(0.6))
                }

                VStack(spacing: 4) {
                    Text(mode.rawValue)
                        .font(.subheadline.bold())
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.6))

                    Text(mode.subtitle)
                        .font(.caption2)
                        .foregroundStyle(isSelected ? .white.opacity(0.7) : .white.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PhotoQualitySettingsView(settings: PhotoQualitySettings())
        .preferredColorScheme(.dark)
}
