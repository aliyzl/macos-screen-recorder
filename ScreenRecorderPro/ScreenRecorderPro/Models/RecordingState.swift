//
//  RecordingState.swift
//  ScreenRecorderPro
//

import Foundation

/// Represents the current state of the recording
enum RecordingState: Equatable {
    case idle
    case preparing
    case countdown(remaining: Int)
    case recording(duration: TimeInterval)
    case paused(duration: TimeInterval)
    case finishing
    case error(String)

    var isActive: Bool {
        switch self {
        case .recording, .paused:
            return true
        default:
            return false
        }
    }

    var canStart: Bool {
        switch self {
        case .idle, .error:
            return true
        default:
            return false
        }
    }

    var canStop: Bool {
        switch self {
        case .recording, .paused:
            return true
        default:
            return false
        }
    }

    var canPause: Bool {
        if case .recording = self {
            return true
        }
        return false
    }

    var canResume: Bool {
        if case .paused = self {
            return true
        }
        return false
    }

    var statusText: String {
        switch self {
        case .idle:
            return "Ready"
        case .preparing:
            return "Preparing..."
        case .countdown(let remaining):
            return "\(remaining)"
        case .recording(let duration):
            return formatDuration(duration)
        case .paused(let duration):
            return "Paused - \(formatDuration(duration))"
        case .finishing:
            return "Saving..."
        case .error(let message):
            return "Error: \(message)"
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

/// Notification names for recording events
extension Notification.Name {
    static let recordingStarted = Notification.Name("recordingStarted")
    static let recordingStopped = Notification.Name("recordingStopped")
    static let recordingCompleted = Notification.Name("recordingCompleted")
    static let recordingFailed = Notification.Name("recordingFailed")
    static let captureStreamError = Notification.Name("captureStreamError")
}
