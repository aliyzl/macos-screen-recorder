//
//  PermissionsOnboardingView.swift
//  ScreenRecorderPro
//

import SwiftUI

struct PermissionsOnboardingView: View {
    @EnvironmentObject var permissionsVM: PermissionsViewModel

    var body: some View {
        VStack(spacing: 32) {
            // Header
            VStack(spacing: 16) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 64))
                    .foregroundColor(.accentColor)

                Text("Permissions Required")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Screen Recorder Pro needs your permission to capture screen content, camera, and microphone.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // Permissions list
            VStack(spacing: 16) {
                PermissionRow(
                    icon: "rectangle.dashed.badge.record",
                    title: "Screen Recording",
                    description: "Required to capture your screen",
                    status: permissionsVM.screenRecordingStatus,
                    isRequired: true,
                    action: { permissionsVM.requestScreenRecordingPermission() },
                    openSettings: { permissionsVM.openScreenRecordingPreferences() }
                )

                PermissionRow(
                    icon: "mic",
                    title: "Microphone",
                    description: "Record voice narration",
                    status: permissionsVM.microphoneStatus,
                    isRequired: false,
                    action: { Task { await permissionsVM.requestMicrophonePermission() } },
                    openSettings: { permissionsVM.openMicrophonePreferences() }
                )

                PermissionRow(
                    icon: "camera",
                    title: "Camera",
                    description: "Add webcam overlay to recordings",
                    status: permissionsVM.cameraStatus,
                    isRequired: false,
                    action: { Task { await permissionsVM.requestCameraPermission() } },
                    openSettings: { permissionsVM.openCameraPreferences() }
                )
            }
            .padding(.horizontal, 32)

            // Continue button
            VStack(spacing: 8) {
                Button {
                    permissionsVM.checkPermissions()
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Check Permissions Again")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .buttonStyle(.bordered)

                if permissionsVM.allRequiredPermissionsGranted {
                    Button {
                        permissionsVM.showOnboarding = false
                    } label: {
                        Text("Continue")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .padding(.top, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let status: PermissionStatus
    let isRequired: Bool
    let action: () -> Void
    let openSettings: () -> Void

    var statusColor: Color {
        switch status {
        case .granted:
            return .green
        case .denied:
            return .red
        case .notDetermined, .unknown:
            return .orange
        }
    }

    var statusText: String {
        switch status {
        case .granted:
            return "Granted"
        case .denied:
            return "Denied"
        case .notDetermined:
            return "Not Set"
        case .unknown:
            return "Unknown"
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 32)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.headline)
                    if isRequired {
                        Text("Required")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .cornerRadius(4)
                    }
                }
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Status and action
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if status != .granted {
                    Button {
                        if status == .denied {
                            openSettings()
                        } else {
                            action()
                        }
                    } label: {
                        Text(status == .denied ? "Settings" : "Grant")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

#Preview {
    PermissionsOnboardingView()
        .environmentObject(PermissionsViewModel())
        .frame(width: 600, height: 600)
}
