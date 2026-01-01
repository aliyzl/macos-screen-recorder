//
//  RecordingViewModel.swift
//  ScreenRecorderPro
//

import Foundation
import Combine
import ScreenCaptureKit

/// Main view model for recording functionality
@MainActor
class RecordingViewModel: ObservableObject {
    // Recording state
    @Published var state: RecordingState = .idle
    @Published var captureTarget: CaptureTarget?
    @Published var configuration: RecordingConfiguration = .default

    // Available content
    @Published var availableDisplays: [DisplayInfo] = []
    @Published var availableWindows: [WindowInfo] = []

    // Computed properties
    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    var isPaused: Bool {
        if case .paused = state { return true }
        return false
    }

    var canStartRecording: Bool {
        state.canStart && captureTarget != nil
    }

    // Services
    private let recordingCoordinator: RecordingCoordinator
    private let permissionsService: PermissionsService

    // Combine
    private var cancellables = Set<AnyCancellable>()

    // Recent recordings
    @Published var recentRecordings: [RecordingMetadata] = []
    @Published var lastRecordingURL: URL?

    init(
        recordingCoordinator: RecordingCoordinator = .shared,
        permissionsService: PermissionsService = .shared
    ) {
        self.recordingCoordinator = recordingCoordinator
        self.permissionsService = permissionsService
        setupBindings()
    }

    // MARK: - Setup

    private func setupBindings() {
        // Subscribe to coordinator state
        recordingCoordinator.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRecording in
                guard let self = self else { return }
                if !isRecording && self.state.isActive {
                    self.state = .idle
                }
            }
            .store(in: &cancellables)

        recordingCoordinator.$recordingDuration
            .receive(on: DispatchQueue.main)
            .sink { [weak self] duration in
                guard let self = self else { return }
                if case .recording = self.state {
                    self.state = .recording(duration: duration)
                } else if case .paused = self.state {
                    self.state = .paused(duration: duration)
                }
            }
            .store(in: &cancellables)

        // Subscribe to errors
        recordingCoordinator.errorPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.state = .error(error.localizedDescription)
            }
            .store(in: &cancellables)

        // Listen for recording completed
        NotificationCenter.default.publisher(for: .recordingCompleted)
            .receive(on: DispatchQueue.main)
            .compactMap { $0.userInfo?["url"] as? URL }
            .sink { [weak self] url in
                self?.lastRecordingURL = url
            }
            .store(in: &cancellables)
    }

    // MARK: - Content Discovery

    /// Refreshes available displays and windows
    func refreshAvailableContent() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

            availableDisplays = content.displays.map { DisplayInfo(display: $0) }

            availableWindows = content.windows
                .filter { window in
                    window.isOnScreen &&
                    window.frame.width > 100 &&
                    window.frame.height > 100 &&
                    window.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier
                }
                .map { WindowInfo(window: $0) }

            // Auto-select main display if no target selected
            if captureTarget == nil, let mainDisplay = availableDisplays.first(where: { $0.isMain }) {
                captureTarget = .display(displayID: mainDisplay.id)
            }
        } catch {
            state = .error("Failed to get shareable content: \(error.localizedDescription)")
        }
    }

    // MARK: - Recording Actions

    /// Starts recording with optional countdown
    func startRecording() async {
        guard state.canStart else { return }
        guard let target = captureTarget else {
            state = .error("No capture target selected")
            return
        }

        // Update configuration resolution based on target
        await updateConfigurationForTarget()

        state = .preparing

        // Countdown
        if configuration.countdownSeconds > 0 {
            for remaining in stride(from: configuration.countdownSeconds, through: 1, by: -1) {
                state = .countdown(remaining: remaining)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }

        // Start recording
        do {
            try await recordingCoordinator.startRecording(
                target: target,
                configuration: configuration
            )
            state = .recording(duration: 0)
        } catch {
            state = .error("Failed to start recording: \(error.localizedDescription)")
        }
    }

    /// Stops the current recording
    func stopRecording() async {
        guard state.canStop else { return }

        state = .finishing

        do {
            let outputURL = try await recordingCoordinator.stopRecording()
            lastRecordingURL = outputURL
            state = .idle
        } catch {
            state = .error("Failed to stop recording: \(error.localizedDescription)")
        }
    }

    /// Pauses the current recording
    func pauseRecording() {
        guard state.canPause else { return }
        if case .recording(let duration) = state {
            recordingCoordinator.pauseRecording()
            state = .paused(duration: duration)
        }
    }

    /// Resumes the current recording
    func resumeRecording() {
        guard state.canResume else { return }
        if case .paused(let duration) = state {
            recordingCoordinator.resumeRecording()
            state = .recording(duration: duration)
        }
    }

    // MARK: - Target Selection

    /// Selects a display for capture
    func selectDisplay(_ display: DisplayInfo) {
        captureTarget = .display(displayID: display.id)
    }

    /// Selects a window for capture
    func selectWindow(_ window: WindowInfo) {
        captureTarget = .window(windowID: window.id)
    }

    /// Selects a custom area for capture
    func selectArea(_ rect: CGRect, on displayID: CGDirectDisplayID) {
        captureTarget = .area(rect: rect, displayID: displayID)
    }

    // MARK: - Private Methods

    private func updateConfigurationForTarget() async {
        guard let target = captureTarget else { return }

        switch target {
        case .display(let displayID):
            if let display = availableDisplays.first(where: { $0.id == displayID }) {
                configuration.updateResolution(
                    for: Int(display.frame.width),
                    targetHeight: Int(display.frame.height)
                )
            }
        case .window(let windowID):
            if let window = availableWindows.first(where: { $0.id == windowID }) {
                configuration.updateResolution(
                    for: Int(window.frame.width),
                    targetHeight: Int(window.frame.height)
                )
            }
        case .area(let rect, _):
            configuration.updateResolution(
                for: Int(rect.width),
                targetHeight: Int(rect.height)
            )
        }
    }

    // MARK: - File Operations

    /// Opens the last recording in Finder
    func revealLastRecordingInFinder() {
        guard let url = lastRecordingURL else { return }
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }

    /// Opens the last recording with the default app
    func openLastRecording() {
        guard let url = lastRecordingURL else { return }
        NSWorkspace.shared.open(url)
    }
}
