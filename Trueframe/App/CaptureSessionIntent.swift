// Opens the app armed for capture, from the Action Button, Shortcuts, or Siri.
// Proximity remains the only capture trigger; this just removes the
// unlock-and-find-icon friction.

import AppIntents

struct CaptureSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture"
    static let description = IntentDescription(
        "Opens Trueframe ready to capture. Hold the phone to your heart to begin."
    )
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct TrueframeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureSessionIntent(),
            phrases: ["Capture with \(.applicationName)"],
            shortTitle: "Capture",
            systemImageName: "heart.fill"
        )
    }
}
