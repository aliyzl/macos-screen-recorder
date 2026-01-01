//
//  AudioCaptureService.swift
//  ScreenRecorderPro
//

import Foundation
import AVFoundation
import Combine

/// Errors that can occur during audio capture
enum AudioCaptureError: LocalizedError {
    case deviceNotFound
    case configurationFailed
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            return "Audio device not found"
        case .configurationFailed:
            return "Failed to configure audio capture"
        case .permissionDenied:
            return "Microphone permission denied"
        }
    }
}

/// Service for capturing microphone audio
class AudioCaptureService: NSObject, ObservableObject {
    // Publishers
    private let microphoneSampleSubject = PassthroughSubject<CMSampleBuffer, Never>()

    var microphonePublisher: AnyPublisher<CMSampleBuffer, Never> {
        microphoneSampleSubject.eraseToAnyPublisher()
    }

    // AVCapture session for microphone
    private var captureSession: AVCaptureSession?
    private var audioOutput: AVCaptureAudioDataOutput?
    private let captureQueue = DispatchQueue(label: "com.screenrecorderpro.microphone", qos: .userInteractive)

    // Audio levels for metering
    @Published var microphoneLevel: Float = 0

    // State
    private(set) var isCapturing = false

    // MARK: - Device Discovery

    /// Gets all available audio input devices
    static func availableDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        ).devices
    }

    /// Gets the default audio input device
    static var defaultDevice: AVCaptureDevice? {
        AVCaptureDevice.default(for: .audio)
    }

    // MARK: - Capture Control

    /// Starts microphone capture with the specified device
    func startCapture(deviceID: String? = nil) throws {
        guard !isCapturing else { return }

        // Get device
        let device: AVCaptureDevice?
        if let deviceID = deviceID {
            device = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInMicrophone, .externalUnknown],
                mediaType: .audio,
                position: .unspecified
            ).devices.first { $0.uniqueID == deviceID }
        } else {
            device = AVCaptureDevice.default(for: .audio)
        }

        guard let audioDevice = device else {
            throw AudioCaptureError.deviceNotFound
        }

        // Create session
        captureSession = AVCaptureSession()
        captureSession?.beginConfiguration()

        // Add input
        do {
            let input = try AVCaptureDeviceInput(device: audioDevice)
            if captureSession?.canAddInput(input) == true {
                captureSession?.addInput(input)
            } else {
                throw AudioCaptureError.configurationFailed
            }
        } catch {
            throw AudioCaptureError.configurationFailed
        }

        // Add output
        audioOutput = AVCaptureAudioDataOutput()
        audioOutput?.setSampleBufferDelegate(self, queue: captureQueue)

        if captureSession?.canAddOutput(audioOutput!) == true {
            captureSession?.addOutput(audioOutput!)
        } else {
            throw AudioCaptureError.configurationFailed
        }

        captureSession?.commitConfiguration()

        // Start session on background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.startRunning()
            DispatchQueue.main.async {
                self?.isCapturing = true
            }
        }
    }

    /// Stops microphone capture
    func stopCapture() {
        guard isCapturing else { return }

        captureSession?.stopRunning()
        captureSession = nil
        audioOutput = nil
        isCapturing = false
        microphoneLevel = 0
    }

    // MARK: - Audio Level Metering

    private func updateAudioLevel(from sampleBuffer: CMSampleBuffer) {
        guard let channelData = getChannelData(from: sampleBuffer) else { return }

        // Calculate RMS for audio level
        var sum: Float = 0
        let count = channelData.count

        for sample in channelData {
            sum += sample * sample
        }

        let rms = sqrt(sum / Float(count))
        let level = 20 * log10(max(rms, 0.0001)) // Convert to dB

        // Normalize to 0-1 range (assuming -60dB to 0dB range)
        let normalizedLevel = max(0, min(1, (level + 60) / 60))

        DispatchQueue.main.async {
            self.microphoneLevel = normalizedLevel
        }
    }

    private func getChannelData(from sampleBuffer: CMSampleBuffer) -> [Float]? {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?

        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        )

        guard status == kCMBlockBufferNoErr, let data = dataPointer else { return nil }

        // Assuming 32-bit float audio
        let floatCount = length / MemoryLayout<Float>.size
        let floatPointer = data.withMemoryRebound(to: Float.self, capacity: floatCount) { $0 }
        return Array(UnsafeBufferPointer(start: floatPointer, count: floatCount))
    }
}

// MARK: - AVCaptureAudioDataOutputSampleBufferDelegate

extension AudioCaptureService: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard sampleBuffer.isValid else { return }

        // Send to subscribers
        microphoneSampleSubject.send(sampleBuffer)

        // Update audio level
        updateAudioLevel(from: sampleBuffer)
    }
}
