//
//  MenuBarView.swift
//  ScreenRecorderPro
//

import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var recordingVM: RecordingViewModel
    @EnvironmentObject var permissionsVM: PermissionsViewModel

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            // Header
            MenuBarHeaderView()

            Divider()

            // Quick actions
            QuickActionsView()

            Divider()

            // Settings and quit
            VStack(spacing: 4) {
                SettingsLink {
                    HStack {
                        Image(systemName: "gearshape")
                        Text("Preferences...")
                        Spacer()
                        Text("⌘,")
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    HStack {
                        Image(systemName: "power")
                        Text("Quit")
                        Spacer()
                        Text("⌘Q")
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q")
            }
            .padding(.vertical, 8)
        }
        .frame(width: 280)
    }
}

struct MenuBarHeaderView: View {
    @EnvironmentObject var recordingVM: RecordingViewModel

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                // Recording indicator
                if recordingVM.isRecording {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                        .modifier(PulseAnimation())
                }

                Text(recordingVM.state.statusText)
                    .font(.system(.headline, design: .monospaced))

                Spacer()

                // Target info
                if let target = recordingVM.captureTarget {
                    Text(target.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(4)
                }
            }
        }
        .padding()
    }
}

struct QuickActionsView: View {
    @EnvironmentObject var recordingVM: RecordingViewModel
    @EnvironmentObject var permissionsVM: PermissionsViewModel

    var body: some View {
        VStack(spacing: 4) {
            // Main recording button
            Button {
                Task {
                    if recordingVM.isRecording {
                        await recordingVM.stopRecording()
                    } else {
                        await recordingVM.startRecording()
                    }
                }
            } label: {
                HStack {
                    Image(systemName: recordingVM.isRecording ? "stop.circle.fill" : "record.circle")
                        .foregroundColor(recordingVM.isRecording ? .red : .primary)
                    Text(recordingVM.isRecording ? "Stop Recording" : "Start Recording")
                    Spacer()
                    Text("⇧⌘R")
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .disabled(!recordingVM.canStartRecording && !recordingVM.isRecording)

            // Pause/Resume (when recording)
            if recordingVM.isRecording {
                Button {
                    if recordingVM.isPaused {
                        recordingVM.resumeRecording()
                    } else {
                        recordingVM.pauseRecording()
                    }
                } label: {
                    HStack {
                        Image(systemName: recordingVM.isPaused ? "play.circle" : "pause.circle")
                        Text(recordingVM.isPaused ? "Resume" : "Pause")
                        Spacer()
                        Text("⇧⌘P")
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }

            Divider()
                .padding(.vertical, 4)

            // Source selection submenu
            Menu {
                // Displays
                Section("Displays") {
                    ForEach(recordingVM.availableDisplays) { display in
                        Button {
                            recordingVM.selectDisplay(display)
                        } label: {
                            HStack {
                                if case .display(let id) = recordingVM.captureTarget, id == display.id {
                                    Image(systemName: "checkmark")
                                }
                                Text(display.name)
                            }
                        }
                    }
                }

                Divider()

                // Windows
                Section("Windows") {
                    if recordingVM.availableWindows.isEmpty {
                        Text("No windows available")
                    } else {
                        ForEach(recordingVM.availableWindows.prefix(10)) { window in
                            Button {
                                recordingVM.selectWindow(window)
                            } label: {
                                HStack {
                                    if case .window(let id) = recordingVM.captureTarget, id == window.id {
                                        Image(systemName: "checkmark")
                                    }
                                    Text(window.displayName)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "rectangle.on.rectangle")
                    Text("Capture Source")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .disabled(recordingVM.isRecording)

            // Refresh sources
            Button {
                Task {
                    await recordingVM.refreshAvailableContent()
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh Sources")
                    Spacer()
                    Text("⌥⌘R")
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .disabled(recordingVM.isRecording)

            Divider()
                .padding(.vertical, 4)

            // Last recording
            if let lastURL = recordingVM.lastRecordingURL {
                Button {
                    recordingVM.revealLastRecordingInFinder()
                } label: {
                    HStack {
                        Image(systemName: "folder")
                        Text("Show Last Recording")
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)

                Button {
                    recordingVM.openLastRecording()
                } label: {
                    HStack {
                        Image(systemName: "play.rectangle")
                        VStack(alignment: .leading) {
                            Text("Open Last Recording")
                            Text(lastURL.lastPathComponent)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    MenuBarView()
        .environmentObject(RecordingViewModel())
        .environmentObject(PermissionsViewModel())
        .frame(width: 280)
}
