import SwiftUI

@main
struct TrueframeApp: App {
    @State private var coordinator = Self.makeCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(coordinator)
                .preferredColorScheme(.dark)
                .persistentSystemOverlays(.hidden)
                .task {
                    // The unit test host must never raise permission prompts
                    guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
                    await coordinator.start()
                }
        }
    }

    private static func makeCoordinator() -> SessionCoordinator {
        #if DEBUG
        if DemoSession.isRequested { return DemoSession.makeCoordinator() }
        #endif
        return SessionCoordinator()
    }
}
