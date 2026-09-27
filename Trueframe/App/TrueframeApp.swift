import SwiftUI

@main
struct TrueframeApp: App {
    @State private var coordinator = SessionCoordinator()

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
}
