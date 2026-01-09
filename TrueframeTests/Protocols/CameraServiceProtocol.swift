// Protocol abstraction for CameraService to enable testing.

import AVFoundation
import Combine
import UIKit
@testable import Trueframe

/// Protocol defining the camera service interface for dependency injection and mocking.
protocol CameraServiceProtocol: AnyObject {
    var capturedPhoto: AnyPublisher<CapturedPhoto, Never> { get }
    var isReady: Bool { get }
    var flashEnabled: Bool { get }

    func preWarm()
    func configure(for position: CameraPosition) async throws
    func capturePhoto() async throws
    func captureReactionShot() async throws
    func updateCameraSettings(wide: Bool, ultrawide: Bool, telephoto: Bool, flash: Bool)
    func tearDown()
}

// MARK: - CameraService Conformance (extend in production code)
// extension CameraService: CameraServiceProtocol {}
