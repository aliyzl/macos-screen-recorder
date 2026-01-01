//
//  RecordingCoordinator.swift
//  ScreenRecorderPro
//

import Foundation
import Combine
import CoreMedia
import CoreImage
import AVFoundation

/// Orchestrates all recording services
class RecordingCoordinator: ObservableObject {
    static let shared = RecordingCoordinator()

    // Services
    private let screenCaptureService = ScreenCaptureService()
    private let audioCaptureService = AudioCaptureService()
    private let assetWriterService = AssetWriterService()

    // Frame processing
    private let ciContext: CIContext

    // State
    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var recordingDuration: TimeInterval = 0

    // Error publishing
    private let errorSubject = PassthroughSubject<Error, Never>()
    var errorPublisher: AnyPublisher<Error, Never> {
        errorSubject.eraseToAnyPublisher()
    }

    // Combine
    private var cancellables = Set<AnyCancellable>()
    private var durationTimer: Timer?

    // Recording info
    private var recordingStartTime: Date?
    private var currentConfiguration: RecordingConfiguration?
    private var currentTarget: CaptureTarget?

    private init() {
        // Create Metal-backed CIContext for efficient processing
        if let device = MTLCreateSystemDefaultDevice() {
            ciContext = CIContext(mtlDevice: device, options: [
                .cacheIntermediates: false,
                .priorityRequestLow: false
            ])
        } else {
            ciContext = CIContext(options: [.useSoftwareRenderer: false])
        }

        setupBindings()
    }

    // MARK: - Public API

    /// Starts a new recording
    func startRecording(
        target: CaptureTarget,
        configuration: RecordingConfiguration
    ) async throws {
        guard !isRecording else { return }

        currentTarget = target
        currentConfiguration = configuration

        // Generate output URL
        let outputURL = generateOutputURL(configuration: configuration)

        // Start asset writer
        try assetWriterService.startWriting(to: outputURL, configuration: configuration)

        // Start screen capture
        try await screenCaptureService.startCapture(target: target, configuration: configuration)

        // Start microphone if enabled
        if configuration.captureMicrophone {
            try audioCaptureService.startCapture(deviceID: configuration.microphoneDeviceID)
        }

        // Setup frame pipeline
        setupFramePipeline(configuration: configuration)

        // Update state
        await MainActor.run {
            self.isRecording = true
            self.isPaused = false
            self.recordingStartTime = Date()
            self.startDurationTimer()
        }

        // Post notification
        NotificationCenter.default.post(name: .recordingStarted, object: nil)
    }

    /// Stops the current recording
    func stopRecording() async throws -> URL {
        guard isRecording else {
            throw CaptureError.notRecording
        }

        // Update state
        await MainActor.run {
            self.stopDurationTimer()
        }

        // Stop all captures
        await screenCaptureService.stopCapture()
        audioCaptureService.stopCapture()

        // Cancel subscriptions
        cancellables.removeAll()

        // Finalize recording
        let outputURL = try await assetWriterService.finishWriting()

        // Update state
        await MainActor.run {
            self.isRecording = false
            self.isPaused = false
            self.recordingDuration = 0
            self.recordingStartTime = nil
        }

        // Post notification
        NotificationCenter.default.post(
            name: .recordingCompleted,
            object: nil,
            userInfo: ["url": outputURL]
        )

        return outputURL
    }

    /// Pauses the current recording
    func pauseRecording() {
        guard isRecording, !isPaused else { return }
        isPaused = true
        stopDurationTimer()
    }

    /// Resumes the current recording
    func resumeRecording() {
        guard isRecording, isPaused else { return }
        isPaused = false
        startDurationTimer()
    }

    /// Force stops recording (for cleanup on app termination)
    func forceStop() async {
        guard isRecording else { return }

        await screenCaptureService.stopCapture()
        audioCaptureService.stopCapture()
        assetWriterService.cancel()
        cancellables.removeAll()

        await MainActor.run {
            self.isRecording = false
            self.isPaused = false
            self.recordingDuration = 0
            self.stopDurationTimer()
        }
    }

    // MARK: - Private Methods

    private func setupBindings() {
        // Handle capture errors
        screenCaptureService.errorPublisher
            .sink { [weak self] error in
                self?.errorSubject.send(error)
            }
            .store(in: &cancellables)
    }

    private func setupFramePipeline(configuration: RecordingConfiguration) {
        // Cancel existing subscriptions
        cancellables.removeAll()
        setupBindings()

        // Video frame processing
        screenCaptureService.videoFramePublisher
            .filter { [weak self] _ in
                guard let self = self else { return false }
                return !self.isPaused
            }
            .sink { [weak self] sampleBuffer in
                self?.processVideoFrame(sampleBuffer, configuration: configuration)
            }
            .store(in: &cancellables)

        // System audio
        if configuration.captureSystemAudio {
            screenCaptureService.audioSamplePublisher
                .filter { [weak self] _ in !(self?.isPaused ?? true) }
                .sink { [weak self] sampleBuffer in
                    self?.assetWriterService.appendSystemAudio(sampleBuffer)
                }
                .store(in: &cancellables)
        }

        // Microphone audio
        if configuration.captureMicrophone {
            audioCaptureService.microphonePublisher
                .filter { [weak self] _ in !(self?.isPaused ?? true) }
                .sink { [weak self] sampleBuffer in
                    self?.assetWriterService.appendMicrophoneAudio(sampleBuffer)
                }
                .store(in: &cancellables)
        }
    }

    private func processVideoFrame(_ sampleBuffer: CMSampleBuffer, configuration: RecordingConfiguration) {
        // Simply write the frame - effects processing will be added later
        assetWriterService.appendVideoFrame(sampleBuffer)
    }

    private func generateOutputURL(configuration: RecordingConfiguration) -> URL {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())

        let fileName = "\(configuration.fileNamePrefix)_\(timestamp).\(configuration.videoCodec.fileExtension)"

        // Ensure output directory exists
        let outputDir = configuration.outputDirectory
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        return outputDir.appendingPathComponent(fileName)
    }

    private func startDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = self.recordingStartTime else { return }
            DispatchQueue.main.async {
                self.recordingDuration = Date().timeIntervalSince(startTime)
            }
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }
}
