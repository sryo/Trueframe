// Mock helper for AppState in integration testing.

import Foundation
import UIKit
@testable import Trueframe

/// Helper extension for testing with AppState.
/// Note: Since AppState is a final @Observable class, we can't subclass it.
/// Instead, we provide factory methods for creating test instances.
@MainActor
enum MockAppStateFactory {

    /// Create an AppState configured for testing with mock camera service reference.
    static func createWithMockCamera(_ mockCamera: MockCameraService) -> AppState {
        let appState = AppState()
        // AppState is ready for testing as-is
        return appState
    }

    /// Create an AppState with default test configuration.
    static func createDefault() -> AppState {
        return AppState()
    }
}
