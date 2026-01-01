//
//  PermissionsService.swift
//  ScreenRecorderPro
//

import Foundation
import AVFoundation
import ScreenCaptureKit
import Combine

/// Permission status for each type
enum PermissionStatus: Equatable {
    case unknown
    case notDetermined
    case denied
    case granted

    var isGranted: Bool {
        self == .granted
    }

    var needsRequest: Bool {
        self == .notDetermined || self == .unknown
    }
}

/// Manages all app permissions
@MainActor
class PermissionsService: ObservableObject {
    static let shared = PermissionsService()

    @Published var screenRecordingStatus: PermissionStatus = .unknown
    @Published var cameraStatus: PermissionStatus = .unknown
    @Published var microphoneStatus: PermissionStatus = .unknown

    /// Whether all required permissions are granted
    var allRequiredPermissionsGranted: Bool {
        screenRecordingStatus.isGranted
    }

    /// Whether all permissions are granted (including optional)
    var allPermissionsGranted: Bool {
        screenRecordingStatus.isGranted && cameraStatus.isGranted && microphoneStatus.isGranted
    }

    private init() {}

    // MARK: - Check All Permissions

    func checkAllPermissions() {
        checkScreenRecordingPermission()
        checkCameraPermission()
        checkMicrophonePermission()
    }

    // MARK: - Screen Recording Permission

    func checkScreenRecordingPermission() {
        // Use CGPreflightScreenCaptureAccess for macOS 11+
        let hasAccess = CGPreflightScreenCaptureAccess()
        screenRecordingStatus = hasAccess ? .granted : .notDetermined
    }

    func requestScreenRecordingPermission() {
        // Request access - this will show the system prompt if needed
        CGRequestScreenCaptureAccess()

        // Open System Preferences for manual granting
        openSystemPreferences(pane: "Privacy_ScreenCapture")

        // Recheck after a delay
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            checkScreenRecordingPermission()
        }
    }

    // MARK: - Camera Permission

    func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            cameraStatus = .notDetermined
        case .restricted, .denied:
            cameraStatus = .denied
        case .authorized:
            cameraStatus = .granted
        @unknown default:
            cameraStatus = .unknown
        }
    }

    func requestCameraPermission() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        await MainActor.run {
            cameraStatus = granted ? .granted : .denied
        }
        return granted
    }

    // MARK: - Microphone Permission

    func checkMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            microphoneStatus = .notDetermined
        case .restricted, .denied:
            microphoneStatus = .denied
        case .authorized:
            microphoneStatus = .granted
        @unknown default:
            microphoneStatus = .unknown
        }
    }

    func requestMicrophonePermission() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        await MainActor.run {
            microphoneStatus = granted ? .granted : .denied
        }
        return granted
    }

    // MARK: - Helpers

    func openSystemPreferences(pane: String) {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    func openScreenRecordingPreferences() {
        openSystemPreferences(pane: "Privacy_ScreenCapture")
    }

    func openCameraPreferences() {
        openSystemPreferences(pane: "Privacy_Camera")
    }

    func openMicrophonePreferences() {
        openSystemPreferences(pane: "Privacy_Microphone")
    }
}
