//
//  MainWindowView.swift
//  ScreenRecorderPro
//

import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject var recordingVM: RecordingViewModel
    @EnvironmentObject var permissionsVM: PermissionsViewModel

    var body: some View {
        Group {
            if permissionsVM.allRequiredPermissionsGranted {
                RecordingDashboardView()
            } else {
                PermissionsOnboardingView()
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            permissionsVM.checkPermissions()
            Task {
                await recordingVM.refreshAvailableContent()
            }
        }
    }
}

struct RecordingDashboardView: View {
    @EnvironmentObject var recordingVM: RecordingViewModel
    @EnvironmentObject var permissionsVM: PermissionsViewModel

    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header with recording status
            RecordingHeaderView()

            Divider()

            // Main content
            HSplitView {
                // Left panel - Source selection
                SourceSelectionPanel()
                    .frame(minWidth: 200, idealWidth: 250, maxWidth: 300)

                // Right panel - Preview and controls
                VStack(spacing: 0) {
                    // Preview area
                    CapturePreviewView()

                    Divider()

                    // Recording controls
                    RecordingControlsView()
                        .padding()
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct RecordingHeaderView: View {
    @EnvironmentObject var recordingVM: RecordingViewModel

    var body: some View {
        HStack {
            // App icon and title
            Image(systemName: "record.circle.fill")
                .font(.title2)
                .foregroundColor(recordingVM.isRecording ? .red : .secondary)

            Text("Screen Recorder Pro")
                .font(.headline)

            Spacer()

            // Recording status
            HStack(spacing: 8) {
                if recordingVM.isRecording {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .modifier(PulseAnimation())
                }

                Text(recordingVM.state.statusText)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(recordingVM.isRecording ? .primary : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .padding()
    }
}

struct SourceSelectionPanel: View {
    @EnvironmentObject var recordingVM: RecordingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Capture Source")
                .font(.headline)

            // Displays section
            DisclosureGroup {
                ForEach(recordingVM.availableDisplays) { display in
                    DisplayRow(display: display)
                }
            } label: {
                Label("Displays", systemImage: "display")
            }

            // Windows section
            DisclosureGroup {
                if recordingVM.availableWindows.isEmpty {
                    Text("No windows available")
                        .foregroundColor(.secondary)
                        .font(.caption)
                } else {
                    ForEach(recordingVM.availableWindows) { window in
                        WindowRow(window: window)
                    }
                }
            } label: {
                Label("Windows", systemImage: "macwindow")
            }

            Spacer()

            // Refresh button
            Button {
                Task {
                    await recordingVM.refreshAvailableContent()
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}

struct DisplayRow: View {
    let display: DisplayInfo
    @EnvironmentObject var recordingVM: RecordingViewModel

    var isSelected: Bool {
        if case .display(let id) = recordingVM.captureTarget {
            return id == display.id
        }
        return false
    }

    var body: some View {
        HStack {
            Image(systemName: display.isMain ? "display" : "rectangle.on.rectangle")
                .foregroundColor(.secondary)

            VStack(alignment: .leading) {
                Text(display.name)
                    .font(.subheadline)
                Text("\(Int(display.frame.width))x\(Int(display.frame.height))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            recordingVM.selectDisplay(display)
        }
    }
}

struct WindowRow: View {
    let window: WindowInfo
    @EnvironmentObject var recordingVM: RecordingViewModel

    var isSelected: Bool {
        if case .window(let id) = recordingVM.captureTarget {
            return id == window.id
        }
        return false
    }

    var body: some View {
        HStack {
            // App icon placeholder
            Image(systemName: "app.dashed")
                .foregroundColor(.secondary)

            VStack(alignment: .leading) {
                Text(window.appName)
                    .font(.subheadline)
                    .lineLimit(1)
                if !window.title.isEmpty && window.title != window.appName {
                    Text(window.title)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            recordingVM.selectWindow(window)
        }
    }
}

struct CapturePreviewView: View {
    @EnvironmentObject var recordingVM: RecordingViewModel

    var body: some View {
        ZStack {
            Color(NSColor.controlBackgroundColor)

            if recordingVM.captureTarget != nil {
                VStack {
                    Image(systemName: "display")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text(recordingVM.captureTarget?.description ?? "No source selected")
                        .foregroundColor(.secondary)

                    if let target = recordingVM.captureTarget {
                        Text(targetDetails(target))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                VStack {
                    Image(systemName: "rectangle.dashed")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("Select a capture source")
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func targetDetails(_ target: CaptureTarget) -> String {
        switch target {
        case .display(let id):
            if let display = recordingVM.availableDisplays.first(where: { $0.id == id }) {
                return "\(Int(display.frame.width))x\(Int(display.frame.height))"
            }
        case .window(let id):
            if let window = recordingVM.availableWindows.first(where: { $0.id == id }) {
                return "\(Int(window.frame.width))x\(Int(window.frame.height))"
            }
        case .area(let rect, _):
            return "\(Int(rect.width))x\(Int(rect.height))"
        }
        return ""
    }
}

struct RecordingControlsView: View {
    @EnvironmentObject var recordingVM: RecordingViewModel

    var body: some View {
        HStack(spacing: 20) {
            // Settings button
            Button {
                // Open settings
            } label: {
                Image(systemName: "gearshape")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(recordingVM.isRecording)

            Spacer()

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
                ZStack {
                    Circle()
                        .fill(recordingVM.isRecording ? Color.red : Color.accentColor)
                        .frame(width: 60, height: 60)

                    if recordingVM.isRecording {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white)
                            .frame(width: 20, height: 20)
                    } else {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 24, height: 24)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!recordingVM.canStartRecording && !recordingVM.isRecording)

            // Pause button (only when recording)
            if recordingVM.isRecording {
                Button {
                    if recordingVM.isPaused {
                        recordingVM.resumeRecording()
                    } else {
                        recordingVM.pauseRecording()
                    }
                } label: {
                    Image(systemName: recordingVM.isPaused ? "play.fill" : "pause.fill")
                        .font(.title2)
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            // Last recording button
            if recordingVM.lastRecordingURL != nil {
                Button {
                    recordingVM.revealLastRecordingInFinder()
                } label: {
                    Image(systemName: "folder")
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Animations

struct PulseAnimation: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.5 : 1.0)
            .animation(
                Animation.easeInOut(duration: 0.8)
                    .repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear {
                isPulsing = true
            }
    }
}

#Preview {
    MainWindowView()
        .environmentObject(RecordingViewModel())
        .environmentObject(PermissionsViewModel())
}
