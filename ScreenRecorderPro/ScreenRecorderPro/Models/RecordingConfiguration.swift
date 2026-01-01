//
//  RecordingConfiguration.swift
//  ScreenRecorderPro
//

import Foundation
import AVFoundation

/// Video codec options
enum VideoCodec: String, CaseIterable, Identifiable {
    case h264 = "H.264"
    case hevc = "HEVC"
    case proRes = "ProRes 422"

    var id: String { rawValue }

    var avCodecType: AVVideoCodecType {
        switch self {
        case .h264: return .h264
        case .hevc: return .hevc
        case .proRes: return .proRes422
        }
    }

    var fileExtension: String {
        switch self {
        case .h264, .hevc: return "mp4"
        case .proRes: return "mov"
        }
    }
}

/// Recording quality presets
enum RecordingQuality: String, CaseIterable, Identifiable {
    case low = "Low (720p)"
    case medium = "Medium (1080p)"
    case high = "High (1440p)"
    case ultra = "Ultra (4K)"
    case native = "Native"

    var id: String { rawValue }

    var maxHeight: Int? {
        switch self {
        case .low: return 720
        case .medium: return 1080
        case .high: return 1440
        case .ultra: return 2160
        case .native: return nil
        }
    }

    var bitrateMbps: Double {
        switch self {
        case .low: return 5
        case .medium: return 10
        case .high: return 20
        case .ultra: return 40
        case .native: return 30
        }
    }
}

/// Webcam shape options
enum WebcamShape: String, CaseIterable, Identifiable {
    case circle = "Circle"
    case roundedRect = "Rounded Rectangle"
    case rectangle = "Rectangle"

    var id: String { rawValue }
}

/// Webcam position presets
enum WebcamPosition: String, CaseIterable, Identifiable {
    case bottomLeft = "Bottom Left"
    case bottomRight = "Bottom Right"
    case topLeft = "Top Left"
    case topRight = "Top Right"
    case custom = "Custom"

    var id: String { rawValue }
}

/// Main recording configuration
struct RecordingConfiguration: Codable, Equatable {
    // Video settings
    var frameRate: Int = 60
    var quality: RecordingQuality = .high
    var videoCodec: VideoCodec = .h264

    // Resolution (computed based on target and quality)
    var outputWidth: Int = 1920
    var outputHeight: Int = 1080

    // Audio settings
    var captureSystemAudio: Bool = true
    var captureMicrophone: Bool = true
    var systemAudioVolume: Float = 1.0
    var microphoneVolume: Float = 1.0
    var microphoneDeviceID: String?

    // Cursor settings
    var captureCursor: Bool = true
    var highlightClicks: Bool = true
    var clickHighlightColor: CodableColor = CodableColor(.yellow)
    var clickHighlightRadius: CGFloat = 30

    // Webcam settings
    var webcamEnabled: Bool = false
    var webcamDeviceID: String?
    var webcamShape: WebcamShape = .circle
    var webcamPosition: WebcamPosition = .bottomRight
    var webcamSize: CGFloat = 200
    var webcamCustomPosition: CGPoint = .zero

    // Recording settings
    var countdownSeconds: Int = 3
    var showKeystrokes: Bool = false
    var autoZoomEnabled: Bool = false
    var autoZoomFactor: CGFloat = 2.0

    // Output settings
    var outputDirectory: URL = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
    var fileNamePrefix: String = "Recording"

    // Computed bitrate in bits per second
    var videoBitrate: Int {
        Int(quality.bitrateMbps * 1_000_000)
    }

    static var `default`: RecordingConfiguration {
        RecordingConfiguration()
    }

    // Update resolution based on capture target
    mutating func updateResolution(for targetWidth: Int, targetHeight: Int) {
        if let maxHeight = quality.maxHeight {
            if targetHeight > maxHeight {
                let scale = Double(maxHeight) / Double(targetHeight)
                outputHeight = maxHeight
                outputWidth = Int(Double(targetWidth) * scale)
                // Ensure even dimensions for video encoding
                outputWidth = outputWidth & ~1
            } else {
                outputWidth = targetWidth & ~1
                outputHeight = targetHeight & ~1
            }
        } else {
            outputWidth = targetWidth & ~1
            outputHeight = targetHeight & ~1
        }
    }

    enum CodingKeys: String, CodingKey {
        case frameRate, quality, videoCodec
        case outputWidth, outputHeight
        case captureSystemAudio, captureMicrophone
        case systemAudioVolume, microphoneVolume, microphoneDeviceID
        case captureCursor, highlightClicks, clickHighlightColor, clickHighlightRadius
        case webcamEnabled, webcamDeviceID, webcamShape, webcamPosition, webcamSize, webcamCustomPosition
        case countdownSeconds, showKeystrokes, autoZoomEnabled, autoZoomFactor
        case outputDirectory, fileNamePrefix
    }
}

/// Wrapper for Color to make it Codable
struct CodableColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(_ nsColor: NSColor) {
        let color = nsColor.usingColorSpace(.sRGB) ?? nsColor
        self.red = Double(color.redComponent)
        self.green = Double(color.greenComponent)
        self.blue = Double(color.blueComponent)
        self.alpha = Double(color.alphaComponent)
    }

    var nsColor: NSColor {
        NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

// Make enums Codable
extension RecordingQuality: Codable {}
extension VideoCodec: Codable {}
extension WebcamShape: Codable {}
extension WebcamPosition: Codable {}
