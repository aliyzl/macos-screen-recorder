//
//  PreferencesWindowView.swift
//  ScreenRecorderPro
//

import SwiftUI

struct PreferencesWindowView: View {
    var body: some View {
        TabView {
            GeneralPreferencesView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            RecordingPreferencesView()
                .tabItem {
                    Label("Recording", systemImage: "record.circle")
                }

            AudioPreferencesView()
                .tabItem {
                    Label("Audio", systemImage: "waveform")
                }

            ShortcutsPreferencesView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
        }
        .frame(width: 500, height: 400)
    }
}

struct GeneralPreferencesView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showInDock") private var showInDock = true
    @AppStorage("showCountdown") private var showCountdown = true
    @AppStorage("countdownSeconds") private var countdownSeconds = 3

    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                Toggle("Show in Dock", isOn: $showInDock)
            } header: {
                Text("General")
            }

            Section {
                Toggle("Show Countdown Before Recording", isOn: $showCountdown)

                if showCountdown {
                    Picker("Countdown Duration", selection: $countdownSeconds) {
                        Text("1 second").tag(1)
                        Text("2 seconds").tag(2)
                        Text("3 seconds").tag(3)
                        Text("5 seconds").tag(5)
                    }
                }
            } header: {
                Text("Recording")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct RecordingPreferencesView: View {
    @AppStorage("defaultQuality") private var defaultQuality = RecordingQuality.high.rawValue
    @AppStorage("defaultCodec") private var defaultCodec = VideoCodec.h264.rawValue
    @AppStorage("defaultFrameRate") private var defaultFrameRate = 60
    @AppStorage("captureCursor") private var captureCursor = true
    @AppStorage("highlightClicks") private var highlightClicks = true
    @AppStorage("outputDirectory") private var outputDirectoryPath = ""

    @State private var outputDirectory: URL = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]

    var body: some View {
        Form {
            Section {
                Picker("Quality", selection: $defaultQuality) {
                    ForEach(RecordingQuality.allCases) { quality in
                        Text(quality.rawValue).tag(quality.rawValue)
                    }
                }

                Picker("Codec", selection: $defaultCodec) {
                    ForEach(VideoCodec.allCases) { codec in
                        Text(codec.rawValue).tag(codec.rawValue)
                    }
                }

                Picker("Frame Rate", selection: $defaultFrameRate) {
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
            } header: {
                Text("Video")
            }

            Section {
                Toggle("Capture Mouse Cursor", isOn: $captureCursor)
                Toggle("Highlight Mouse Clicks", isOn: $highlightClicks)
                    .disabled(!captureCursor)
            } header: {
                Text("Cursor")
            }

            Section {
                HStack {
                    Text("Save Recordings To:")
                    Spacer()
                    Text(outputDirectory.path)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Button("Choose...") {
                        selectOutputDirectory()
                    }
                }
            } header: {
                Text("Output")
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            if !outputDirectoryPath.isEmpty {
                outputDirectory = URL(fileURLWithPath: outputDirectoryPath)
            }
        }
    }

    private func selectOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder to save recordings"

        if panel.runModal() == .OK, let url = panel.url {
            outputDirectory = url
            outputDirectoryPath = url.path
        }
    }
}

struct AudioPreferencesView: View {
    @AppStorage("captureSystemAudio") private var captureSystemAudio = true
    @AppStorage("captureMicrophone") private var captureMicrophone = true
    @AppStorage("systemAudioVolume") private var systemAudioVolume = 1.0
    @AppStorage("microphoneVolume") private var microphoneVolume = 1.0

    var body: some View {
        Form {
            Section {
                Toggle("Capture System Audio", isOn: $captureSystemAudio)

                if captureSystemAudio {
                    HStack {
                        Text("System Audio Volume")
                        Slider(value: $systemAudioVolume, in: 0...1)
                        Text("\(Int(systemAudioVolume * 100))%")
                            .frame(width: 40)
                    }
                }
            } header: {
                Text("System Audio")
            }

            Section {
                Toggle("Capture Microphone", isOn: $captureMicrophone)

                if captureMicrophone {
                    Picker("Microphone", selection: .constant("Default")) {
                        Text("Default").tag("Default")
                        // TODO: Add available microphones
                    }

                    HStack {
                        Text("Microphone Volume")
                        Slider(value: $microphoneVolume, in: 0...1)
                        Text("\(Int(microphoneVolume * 100))%")
                            .frame(width: 40)
                    }
                }
            } header: {
                Text("Microphone")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct ShortcutsPreferencesView: View {
    var body: some View {
        Form {
            Section {
                ShortcutRow(
                    title: "Start/Stop Recording",
                    shortcut: "⇧⌘R"
                )

                ShortcutRow(
                    title: "Pause/Resume Recording",
                    shortcut: "⇧⌘P"
                )

                ShortcutRow(
                    title: "Refresh Sources",
                    shortcut: "⌥⌘R"
                )
            } header: {
                Text("Recording")
            }

            Section {
                Text("To customize shortcuts, consider using the KeyboardShortcuts package or implementing global hotkeys.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } footer: {
                EmptyView()
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct ShortcutRow: View {
    let title: String
    let shortcut: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(shortcut)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(4)
        }
    }
}

#Preview {
    PreferencesWindowView()
}
