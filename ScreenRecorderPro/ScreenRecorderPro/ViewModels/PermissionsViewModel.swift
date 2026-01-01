//
//  PermissionsViewModel.swift
//  ScreenRecorderPro
//

import Foundation
import Combine

/// View model for managing permissions UI
@MainActor
class PermissionsViewModel: ObservableObject {
    @Published var screenRecordingStatus: PermissionStatus = .unknown
    @Published var cameraStatus: PermissionStatus = .unknown
    @Published var microphoneStatus: PermissionStatus = .unknown

    @Published var showOnboarding = false
    @Published var isCheckingPermissions = false

    private let permissionsService: PermissionsService
    private var cancellables = Set<AnyCancellable>()

    var allRequiredPermissionsGranted: Bool {
        screenRecordingStatus.isGranted
    }

    var allPermissionsGranted: Bool {
        screenRecordingStatus.isGranted && cameraStatus.isGranted && microphoneStatus.isGranted
    }

    init(permissionsService: PermissionsService = .shared) {
        self.permissionsService = permissionsService
        setupBindings()
        checkPermissions()
    }

    private func setupBindings() {
        permissionsService.$screenRecordingStatus
            .receive(on: DispatchQueue.main)
            .assign(to: &$screenRecordingStatus)

        permissionsService.$cameraStatus
            .receive(on: DispatchQueue.main)
            .assign(to: &$cameraStatus)

        permissionsService.$microphoneStatus
            .receive(on: DispatchQueue.main)
            .assign(to: &$microphoneStatus)
    }

    func checkPermissions() {
        isCheckingPermissions = true
        permissionsService.checkAllPermissions()

        // Show onboarding if screen recording is not granted
        if !screenRecordingStatus.isGranted {
            showOnboarding = true
        }

        isCheckingPermissions = false
    }

    func requestScreenRecordingPermission() {
        permissionsService.requestScreenRecordingPermission()
    }

    func requestCameraPermission() async {
        _ = await permissionsService.requestCameraPermission()
    }

    func requestMicrophonePermission() async {
        _ = await permissionsService.requestMicrophonePermission()
    }

    func openScreenRecordingPreferences() {
        permissionsService.openScreenRecordingPreferences()
    }

    func openCameraPreferences() {
        permissionsService.openCameraPreferences()
    }

    func openMicrophonePreferences() {
        permissionsService.openMicrophonePreferences()
    }
}
