//
//  ScreenRecorderProApp.swift
//  ScreenRecorderPro
//
//  Professional screen recording app for macOS
//

import SwiftUI

@main
struct ScreenRecorderProApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var recordingVM = RecordingViewModel()
    @StateObject private var permissionsVM = PermissionsViewModel()

    var body: some Scene {
        // Main window
        WindowGroup {
            MainWindowView()
                .environmentObject(recordingVM)
                .environmentObject(permissionsVM)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
            RecordingCommands(viewModel: recordingVM)
        }

        // Menu bar presence
        MenuBarExtra {
            MenuBarView()
                .environmentObject(recordingVM)
                .environmentObject(permissionsVM)
        } label: {
            Image(systemName: recordingVM.isRecording ? "record.circle.fill" : "record.circle")
                .symbolRenderingMode(.multicolor)
        }
        .menuBarExtraStyle(.window)

        // Preferences window
        Settings {
            PreferencesWindowView()
                .environmentObject(recordingVM)
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check permissions on launch
        PermissionsService.shared.checkAllPermissions()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup if recording is in progress
        Task {
            await RecordingCoordinator.shared.forceStop()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Keep running in menu bar
    }
}

// MARK: - Recording Commands

struct RecordingCommands: Commands {
    @ObservedObject var viewModel: RecordingViewModel

    var body: some Commands {
        CommandMenu("Recording") {
            Button(viewModel.isRecording ? "Stop Recording" : "Start Recording") {
                Task {
                    if viewModel.isRecording {
                        await viewModel.stopRecording()
                    } else {
                        await viewModel.startRecording()
                    }
                }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(viewModel.captureTarget == nil && !viewModel.isRecording)

            if viewModel.isRecording {
                Button(viewModel.isPaused ? "Resume" : "Pause") {
                    if viewModel.isPaused {
                        viewModel.resumeRecording()
                    } else {
                        viewModel.pauseRecording()
                    }
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            }

            Divider()

            Button("Refresh Displays") {
                Task {
                    await viewModel.refreshAvailableContent()
                }
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
        }
    }
}
