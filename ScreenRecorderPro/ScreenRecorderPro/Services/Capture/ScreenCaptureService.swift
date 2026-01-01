//
//  ScreenCaptureService.swift
//  ScreenRecorderPro
//

import Foundation
import ScreenCaptureKit
import Combine
import CoreMedia
import AVFoundation

/// Errors that can occur during screen capture
enum CaptureError: LocalizedError {
    case displayNotFound
    case windowNotFound
    case streamCreationFailed
    case notAuthorized
    case alreadyRecording
    case notRecording

    var errorDescription: String? {
        switch self {
        case .displayNotFound:
            return "The selected display could not be found"
        case .windowNotFound:
            return "The selected window could not be found"
        case .streamCreationFailed:
            return "Failed to create capture stream"
        case .notAuthorized:
            return "Screen recording permission not granted"
        case .alreadyRecording:
            return "Recording is already in progress"
        case .notRecording:
            return "No recording in progress"
        }
    }
}

/// Service that wraps ScreenCaptureKit for screen/window/area capture
class ScreenCaptureService: NSObject, ObservableObject {
    // Publishers for frame output
    private let videoFrameSubject = PassthroughSubject<CMSampleBuffer, Never>()
    private let audioSampleSubject = PassthroughSubject<CMSampleBuffer, Never>()
    private let errorSubject = PassthroughSubject<Error, Never>()

    var videoFramePublisher: AnyPublisher<CMSampleBuffer, Never> {
        videoFrameSubject.eraseToAnyPublisher()
    }

    var audioSamplePublisher: AnyPublisher<CMSampleBuffer, Never> {
        audioSampleSubject.eraseToAnyPublisher()
    }

    var errorPublisher: AnyPublisher<Error, Never> {
        errorSubject.eraseToAnyPublisher()
    }

    // Stream management
    private var stream: SCStream?
    private var isCapturing = false

    // Separate queues for video and audio processing
    private let videoQueue = DispatchQueue(label: "com.screenrecorderpro.video", qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "com.screenrecorderpro.audio", qos: .userInteractive)

    // MARK: - Public API

    /// Fetches all available shareable content (displays and windows)
    func getShareableContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    /// Starts capturing with the specified target and configuration
    func startCapture(
        target: CaptureTarget,
        configuration: RecordingConfiguration
    ) async throws {
        guard !isCapturing else {
            throw CaptureError.alreadyRecording
        }

        // Build content filter based on target
        let filter = try await buildContentFilter(for: target)

        // Build stream configuration
        let streamConfig = buildStreamConfiguration(configuration, target: target)

        // Create stream
        stream = SCStream(filter: filter, configuration: streamConfig, delegate: self)

        guard let stream = stream else {
            throw CaptureError.streamCreationFailed
        }

        // Add video output
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)

        // Add audio output if enabled
        if configuration.captureSystemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        }

        // Start capture
        try await stream.startCapture()
        isCapturing = true
    }

    /// Stops the current capture
    func stopCapture() async {
        guard isCapturing, let stream = stream else { return }

        do {
            try await stream.stopCapture()
        } catch {
            print("Error stopping capture: \(error)")
        }

        self.stream = nil
        isCapturing = false
    }

    /// Updates the stream configuration (e.g., for resolution changes)
    func updateConfiguration(_ configuration: RecordingConfiguration, target: CaptureTarget) async throws {
        guard let stream = stream else { return }
        let streamConfig = buildStreamConfiguration(configuration, target: target)
        try await stream.updateConfiguration(streamConfig)
    }

    // MARK: - Private Methods

    private func buildContentFilter(for target: CaptureTarget) async throws -> SCContentFilter {
        let content = try await getShareableContent()

        switch target {
        case .display(let displayID):
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                throw CaptureError.displayNotFound
            }
            // Capture full display, excluding nothing
            return SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

        case .window(let windowID):
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                throw CaptureError.windowNotFound
            }
            // Capture single window
            return SCContentFilter(desktopIndependentWindow: window)

        case .area(_, let displayID):
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                throw CaptureError.displayNotFound
            }
            // For area capture, we capture the whole display and crop in configuration
            return SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        }
    }

    private func buildStreamConfiguration(_ config: RecordingConfiguration, target: CaptureTarget) -> SCStreamConfiguration {
        let streamConfig = SCStreamConfiguration()

        // Video dimensions
        streamConfig.width = config.outputWidth
        streamConfig.height = config.outputHeight

        // Frame rate
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(config.frameRate))

        // Pixel format - BGRA for Core Image processing compatibility
        streamConfig.pixelFormat = kCVPixelFormatType_32BGRA

        // Queue depth for buffering
        streamConfig.queueDepth = 5

        // For area capture, set the source rect
        if case .area(let rect, _) = target {
            streamConfig.sourceRect = rect
            streamConfig.scalesToFit = false
        }

        // Cursor visibility
        streamConfig.showsCursor = config.captureCursor

        // Audio settings
        streamConfig.capturesAudio = config.captureSystemAudio
        if config.captureSystemAudio {
            streamConfig.sampleRate = 48000
            streamConfig.channelCount = 2
        }

        // Color settings for best quality
        streamConfig.colorSpaceName = CGColorSpace.sRGB

        return streamConfig
    }
}

// MARK: - SCStreamOutput

extension ScreenCaptureService: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // Validate sample buffer
        guard sampleBuffer.isValid else { return }

        switch type {
        case .screen:
            videoFrameSubject.send(sampleBuffer)
        case .audio:
            audioSampleSubject.send(sampleBuffer)
        case .microphone:
            // Handled by AudioCaptureService
            break
        @unknown default:
            break
        }
    }
}

// MARK: - SCStreamDelegate

extension ScreenCaptureService: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        isCapturing = false
        errorSubject.send(error)

        // Post notification for error handling
        NotificationCenter.default.post(
            name: .captureStreamError,
            object: nil,
            userInfo: ["error": error]
        )
    }
}
