//
//  ExportSettings.swift
//  ScreenRecorderPro
//

import Foundation
import AVFoundation

/// Export format options
enum ExportFormat: String, CaseIterable, Identifiable {
    case mp4 = "MP4"
    case mov = "MOV"
    case gif = "GIF"

    var id: String { rawValue }

    var fileType: AVFileType {
        switch self {
        case .mp4: return .mp4
        case .mov: return .mov
        case .gif: return .mov // GIF export handled separately
        }
    }

    var fileExtension: String {
        rawValue.lowercased()
    }
}

/// Export quality presets
enum ExportQuality: String, CaseIterable, Identifiable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case original = "Original"

    var id: String { rawValue }

    var exportPreset: String {
        switch self {
        case .low: return AVAssetExportPresetMediumQuality
        case .medium: return AVAssetExportPresetHighestQuality
        case .high: return AVAssetExportPresetHighestQuality
        case .original: return AVAssetExportPresetPassthrough
        }
    }
}

/// Export settings configuration
struct ExportSettings: Equatable {
    var format: ExportFormat = .mp4
    var codec: VideoCodec = .h264
    var quality: ExportQuality = .high
    var includeSystemAudio: Bool = true
    var includeMicrophoneAudio: Bool = true
    var trimStart: TimeInterval = 0
    var trimEnd: TimeInterval?
    var outputURL: URL?

    /// Resolution scaling (1.0 = original, 0.5 = half)
    var resolutionScale: Double = 1.0

    static var `default`: ExportSettings {
        ExportSettings()
    }
}

/// Represents a trim range for video editing
struct TrimRange: Equatable {
    var start: TimeInterval
    var end: TimeInterval

    var duration: TimeInterval {
        end - start
    }

    init(start: TimeInterval = 0, end: TimeInterval) {
        self.start = start
        self.end = end
    }

    func contains(_ time: TimeInterval) -> Bool {
        time >= start && time <= end
    }
}

/// Recording file metadata
struct RecordingMetadata: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let duration: TimeInterval
    let fileURL: URL
    let fileSize: Int64
    let resolution: CGSize
    let frameRate: Int
    let hasSystemAudio: Bool
    let hasMicrophoneAudio: Bool
    let hasWebcam: Bool

    var fileName: String {
        fileURL.lastPathComponent
    }

    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    var formattedResolution: String {
        "\(Int(resolution.width))x\(Int(resolution.height))"
    }
}
