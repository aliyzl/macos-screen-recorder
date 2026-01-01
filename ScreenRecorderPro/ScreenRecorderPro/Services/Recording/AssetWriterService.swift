//
//  AssetWriterService.swift
//  ScreenRecorderPro
//

import Foundation
import AVFoundation
import Combine
import CoreMedia

/// Errors that can occur during asset writing
enum WriterError: LocalizedError {
    case failedToStart(Error?)
    case noActiveWriter
    case failedToFinish(Error?)
    case invalidConfiguration
    case unknown

    var errorDescription: String? {
        switch self {
        case .failedToStart(let error):
            return "Failed to start writing: \(error?.localizedDescription ?? "Unknown error")"
        case .noActiveWriter:
            return "No active writer"
        case .failedToFinish(let error):
            return "Failed to finish writing: \(error?.localizedDescription ?? "Unknown error")"
        case .invalidConfiguration:
            return "Invalid configuration"
        case .unknown:
            return "Unknown error"
        }
    }
}

/// Service for writing video and audio to file using AVAssetWriter
class AssetWriterService {
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var micAudioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    private let writingQueue = DispatchQueue(label: "com.screenrecorderpro.writer", qos: .userInteractive)

    private var isWriting = false
    private var sessionStarted = false
    private var firstVideoTimestamp: CMTime?
    private var lastVideoTimestamp: CMTime?

    private var outputURL: URL?

    // MARK: - Public API

    /// Starts writing to the specified URL with the given configuration
    func startWriting(to url: URL, configuration: RecordingConfiguration) throws {
        // Remove existing file if present
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        // Determine file type based on codec
        let fileType: AVFileType = configuration.videoCodec == .proRes ? .mov : .mp4

        // Create asset writer
        assetWriter = try AVAssetWriter(outputURL: url, fileType: fileType)
        outputURL = url

        // Configure video input
        let videoSettings = videoOutputSettings(for: configuration)
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput?.expectsMediaDataInRealTime = true

        // Create pixel buffer adaptor for efficient frame writing
        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: configuration.outputWidth,
            kCVPixelBufferHeightKey as String: configuration.outputHeight,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput!,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )

        if let videoInput = videoInput, assetWriter?.canAdd(videoInput) == true {
            assetWriter?.add(videoInput)
        }

        // Configure system audio input
        if configuration.captureSystemAudio {
            let systemAudioSettings = audioOutputSettings()
            systemAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: systemAudioSettings)
            systemAudioInput?.expectsMediaDataInRealTime = true

            if let input = systemAudioInput, assetWriter?.canAdd(input) == true {
                assetWriter?.add(input)
            }
        }

        // Configure microphone audio input
        if configuration.captureMicrophone {
            let micSettings = audioOutputSettings()
            micAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: micSettings)
            micAudioInput?.expectsMediaDataInRealTime = true

            if let input = micAudioInput, assetWriter?.canAdd(input) == true {
                assetWriter?.add(input)
            }
        }

        // Start writing
        guard assetWriter?.startWriting() == true else {
            throw WriterError.failedToStart(assetWriter?.error)
        }

        isWriting = true
        sessionStarted = false
        firstVideoTimestamp = nil
        lastVideoTimestamp = nil
    }

    /// Appends a video frame
    func appendVideoFrame(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        writingQueue.async { [weak self] in
            guard let self = self, self.isWriting else { return }

            // Start session with first frame timestamp
            if !self.sessionStarted {
                self.assetWriter?.startSession(atSourceTime: timestamp)
                self.firstVideoTimestamp = timestamp
                self.sessionStarted = true
            }

            guard self.videoInput?.isReadyForMoreMediaData == true else {
                return
            }

            self.pixelBufferAdaptor?.append(pixelBuffer, withPresentationTime: timestamp)
            self.lastVideoTimestamp = timestamp
        }
    }

    /// Appends a video frame from sample buffer
    func appendVideoFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        appendVideoFrame(pixelBuffer, timestamp: timestamp)
    }

    /// Appends system audio
    func appendSystemAudio(_ sampleBuffer: CMSampleBuffer) {
        writingQueue.async { [weak self] in
            guard let self = self,
                  self.isWriting,
                  self.sessionStarted,
                  self.systemAudioInput?.isReadyForMoreMediaData == true else { return }

            self.systemAudioInput?.append(sampleBuffer)
        }
    }

    /// Appends microphone audio
    func appendMicrophoneAudio(_ sampleBuffer: CMSampleBuffer) {
        writingQueue.async { [weak self] in
            guard let self = self,
                  self.isWriting,
                  self.sessionStarted,
                  self.micAudioInput?.isReadyForMoreMediaData == true else { return }

            self.micAudioInput?.append(sampleBuffer)
        }
    }

    /// Finishes writing and returns the output URL
    func finishWriting() async throws -> URL {
        guard let writer = assetWriter, let url = outputURL else {
            throw WriterError.noActiveWriter
        }

        isWriting = false

        // Mark inputs as finished
        videoInput?.markAsFinished()
        systemAudioInput?.markAsFinished()
        micAudioInput?.markAsFinished()

        // Wait for writing to complete
        await writer.finishWriting()

        // Check for errors
        if writer.status == .failed {
            throw WriterError.failedToFinish(writer.error)
        }

        // Cleanup
        cleanup()

        return url
    }

    /// Cancels writing and removes the partial file
    func cancel() {
        isWriting = false
        assetWriter?.cancelWriting()

        // Remove partial file
        if let url = outputURL {
            try? FileManager.default.removeItem(at: url)
        }

        cleanup()
    }

    /// Returns the duration of the recording so far
    var recordingDuration: TimeInterval {
        guard let first = firstVideoTimestamp, let last = lastVideoTimestamp else {
            return 0
        }
        return CMTimeGetSeconds(CMTimeSubtract(last, first))
    }

    // MARK: - Private Methods

    private func cleanup() {
        assetWriter = nil
        videoInput = nil
        systemAudioInput = nil
        micAudioInput = nil
        pixelBufferAdaptor = nil
        outputURL = nil
        sessionStarted = false
        firstVideoTimestamp = nil
        lastVideoTimestamp = nil
    }

    private func videoOutputSettings(for config: RecordingConfiguration) -> [String: Any] {
        var settings: [String: Any] = [
            AVVideoWidthKey: config.outputWidth,
            AVVideoHeightKey: config.outputHeight
        ]

        switch config.videoCodec {
        case .h264:
            settings[AVVideoCodecKey] = AVVideoCodecType.h264
            settings[AVVideoCompressionPropertiesKey] = [
                AVVideoAverageBitRateKey: config.videoBitrate,
                AVVideoMaxKeyFrameIntervalKey: config.frameRate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: config.frameRate
            ]

        case .hevc:
            settings[AVVideoCodecKey] = AVVideoCodecType.hevc
            settings[AVVideoCompressionPropertiesKey] = [
                AVVideoAverageBitRateKey: config.videoBitrate,
                AVVideoMaxKeyFrameIntervalKey: config.frameRate,
                AVVideoExpectedSourceFrameRateKey: config.frameRate
            ]

        case .proRes:
            settings[AVVideoCodecKey] = AVVideoCodecType.proRes422
        }

        return settings
    }

    private func audioOutputSettings() -> [String: Any] {
        return [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128000
        ]
    }
}
