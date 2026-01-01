//
//  ScreenRecorderCLI Pro v2 - Advanced Command-line Screen Recorder for macOS
//  Uses ScreenCaptureKit + AVFoundation + CoreGraphics
//  Requires macOS 13.0+
//
//  Build: swift build -c release
//  Run: .build/release/screenrecord
//

import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia
import CoreGraphics
import Combine
import VideoToolbox
import Carbon.HIToolbox
import ApplicationServices

// MARK: - ANSI Terminal Styling

struct Terminal {
    static let reset = "\u{001B}[0m"
    static let bold = "\u{001B}[1m"
    static let dim = "\u{001B}[2m"
    static let italic = "\u{001B}[3m"
    static let underline = "\u{001B}[4m"
    static let blink = "\u{001B}[5m"
    static let reverse = "\u{001B}[7m"

    static let black = "\u{001B}[30m"
    static let red = "\u{001B}[31m"
    static let green = "\u{001B}[32m"
    static let yellow = "\u{001B}[33m"
    static let blue = "\u{001B}[34m"
    static let magenta = "\u{001B}[35m"
    static let cyan = "\u{001B}[36m"
    static let white = "\u{001B}[37m"

    static let brightRed = "\u{001B}[91m"
    static let brightGreen = "\u{001B}[92m"
    static let brightYellow = "\u{001B}[93m"
    static let brightBlue = "\u{001B}[94m"
    static let brightMagenta = "\u{001B}[95m"
    static let brightCyan = "\u{001B}[96m"
    static let brightWhite = "\u{001B}[97m"

    static let bgBlack = "\u{001B}[40m"
    static let bgRed = "\u{001B}[41m"
    static let bgGreen = "\u{001B}[42m"
    static let bgBlue = "\u{001B}[44m"
    static let bgMagenta = "\u{001B}[45m"
    static let bgCyan = "\u{001B}[46m"

    static let clearScreen = "\u{001B}[2J"
    static let moveCursorHome = "\u{001B}[H"
    static let hideCursor = "\u{001B}[?25l"
    static let showCursor = "\u{001B}[?25h"
    static let saveCursor = "\u{001B}[s"
    static let restoreCursor = "\u{001B}[u"

    static func moveCursor(row: Int, col: Int) -> String { "\u{001B}[\(row);\(col)H" }
    static func clearLine() -> String { "\u{001B}[2K" }
    static func moveUp(_ n: Int) -> String { "\u{001B}[\(n)A" }
}

struct Box {
    static let topLeft = "╔", topRight = "╗", bottomLeft = "╚", bottomRight = "╝"
    static let horizontal = "═", vertical = "║"
    static let leftT = "╠", rightT = "╣", topT = "╦", bottomT = "╩", cross = "╬"
    static let singleHorizontal = "─", singleVertical = "│"
}

// MARK: - Enums and Configuration

enum Resolution: String, CaseIterable, Codable {
    case native = "Native"
    case uhd4k = "4K (3840×2160)"
    case qhd = "1440p (2560×1440)"
    case fhd = "1080p (1920×1080)"
    case hd = "720p (1280×720)"

    var dimensions: (width: Int, height: Int)? {
        switch self {
        case .native: return nil
        case .uhd4k: return (3840, 2160)
        case .qhd: return (2560, 1440)
        case .fhd: return (1920, 1080)
        case .hd: return (1280, 720)
        }
    }

    var shortName: String {
        switch self {
        case .native: return "Native"
        case .uhd4k: return "4K"
        case .qhd: return "1440p"
        case .fhd: return "1080p"
        case .hd: return "720p"
        }
    }
}

enum VideoCodec: String, CaseIterable, Codable {
    case h264 = "H.264"
    case hevc = "HEVC (H.265)"

    var avCodec: AVVideoCodecType {
        switch self {
        case .h264: return .h264
        case .hevc: return .hevc
        }
    }
}

enum QualityPreset: String, CaseIterable, Codable {
    case low = "Low"
    case optimized = "Optimized"
    case medium = "Medium"
    case high = "High"
    case ultra = "Ultra"

    var bitrate: Int {
        switch self {
        case .low: return 5_000_000
        case .optimized: return 8_000_000
        case .medium: return 10_000_000
        case .high: return 15_000_000
        case .ultra: return 25_000_000
        }
    }

    var description: String {
        switch self {
        case .low: return "5 Mbps (~37 MB/min)"
        case .optimized: return "8 Mbps (~60 MB/min) Recommended"
        case .medium: return "10 Mbps (~75 MB/min)"
        case .high: return "15 Mbps (~112 MB/min)"
        case .ultra: return "25 Mbps (~187 MB/min)"
        }
    }
}

enum OutputFormat: String, CaseIterable, Codable {
    case mp4 = "MP4"
    case mov = "MOV"

    var fileType: AVFileType {
        switch self {
        case .mp4: return .mp4
        case .mov: return .mov
        }
    }

    var ext: String {
        switch self {
        case .mp4: return "mp4"
        case .mov: return "mov"
        }
    }
}

enum ClickColor: String, CaseIterable, Codable {
    case yellow = "Yellow"
    case red = "Red"
    case blue = "Blue"
    case green = "Green"
    case white = "White"
    case magenta = "Magenta"
    case cyan = "Cyan"

    var cgColor: CGColor {
        switch self {
        case .yellow: return CGColor(red: 1.0, green: 0.9, blue: 0.0, alpha: 0.6)
        case .red: return CGColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 0.6)
        case .blue: return CGColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 0.6)
        case .green: return CGColor(red: 0.2, green: 0.9, blue: 0.3, alpha: 0.6)
        case .white: return CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.6)
        case .magenta: return CGColor(red: 1.0, green: 0.2, blue: 0.8, alpha: 0.6)
        case .cyan: return CGColor(red: 0.2, green: 0.9, blue: 0.9, alpha: 0.6)
        }
    }

    func getRGBA() -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        switch self {
        case .yellow: return (1.0, 0.9, 0.0, 0.6)
        case .red: return (1.0, 0.2, 0.2, 0.6)
        case .blue: return (0.2, 0.5, 1.0, 0.6)
        case .green: return (0.2, 0.9, 0.3, 0.6)
        case .white: return (1.0, 1.0, 1.0, 0.6)
        case .magenta: return (1.0, 0.2, 0.8, 0.6)
        case .cyan: return (0.2, 0.9, 0.9, 0.6)
        }
    }
}

enum CaptureTarget: Codable {
    case display(Int)
    case window(windowID: CGWindowID, appName: String, title: String)

    var description: String {
        switch self {
        case .display(let idx): return "Display \(idx)"
        case .window(_, let app, let title): return "\(app) - \(title)"
        }
    }
}

enum PIPPosition: String, CaseIterable, Codable {
    case topLeft = "Top Left"
    case topRight = "Top Right"
    case bottomLeft = "Bottom Left"
    case bottomRight = "Bottom Right"
}

enum PIPShape: String, CaseIterable, Codable {
    case circle = "Circle"
    case rectangle = "Rectangle"
    case roundedRect = "Rounded Rectangle"
}

enum KeyDisplayPosition: String, CaseIterable, Codable {
    case bottomLeft = "Bottom Left"
    case bottomCenter = "Bottom Center"
    case bottomRight = "Bottom Right"
    case topLeft = "Top Left"
    case topCenter = "Top Center"
    case topRight = "Top Right"
}

// MARK: - Recording Configuration

struct RecordingConfig: Codable {
    // Video Settings
    var resolution: Resolution = .native
    var frameRate: Int = 60
    var codec: VideoCodec = .h264
    var quality: QualityPreset = .high
    var outputFormat: OutputFormat = .mp4
    var outputDirectoryPath: String = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0].path

    var outputDirectory: URL {
        get { URL(fileURLWithPath: outputDirectoryPath) }
        set { outputDirectoryPath = newValue.path }
    }

    // Audio Settings
    var captureSystemAudio: Bool = true
    var captureMicrophone: Bool = false
    var selectedMicrophoneID: String? = nil

    // Mouse Settings
    var showCursor: Bool = true
    var highlightClicks: Bool = false
    var clickColor: ClickColor = .yellow
    var rightClickColor: ClickColor = .blue
    var clickRadius: Int = 30
    var clickDuration: Double = 0.3
    var detectDoubleClick: Bool = true
    var doubleClickThreshold: Double = 0.3

    // Capture Target
    var captureTarget: CaptureTarget = .display(0)

    // Keystroke Overlay
    var showKeystrokes: Bool = false
    var keystrokePosition: KeyDisplayPosition = .bottomLeft
    var keystrokeDuration: Double = 2.0

    // Webcam PIP
    var enableWebcam: Bool = false
    var webcamPosition: PIPPosition = .bottomRight
    var webcamSize: Double = 0.2  // 20% of screen
    var webcamShape: PIPShape = .circle

    // Watermark
    var enableWatermark: Bool = false
    var watermarkText: String = ""
    var watermarkPosition: PIPPosition = .bottomRight
    var watermarkOpacity: Double = 0.5

    // Recording Options
    var showCountdown: Bool = true
    var countdownSeconds: Int = 3

    // Auto-stop options
    var autoStopEnabled: Bool = false
    var autoStopSeconds: Int = 0
    var maxFileSizeMB: Int = 0  // 0 = no limit

    // Codable helpers for non-Codable URL
    enum CodingKeys: String, CodingKey {
        case resolution, frameRate, codec, quality, outputFormat, outputDirectoryPath
        case captureSystemAudio, captureMicrophone, selectedMicrophoneID
        case showCursor, highlightClicks, clickColor, rightClickColor, clickRadius, clickDuration
        case detectDoubleClick, doubleClickThreshold
        case captureTarget
        case showKeystrokes, keystrokePosition, keystrokeDuration
        case enableWebcam, webcamPosition, webcamSize, webcamShape
        case enableWatermark, watermarkText, watermarkPosition, watermarkOpacity
        case showCountdown, countdownSeconds
        case autoStopEnabled, autoStopSeconds, maxFileSizeMB
    }

    // Save/Load presets
    static func load(from path: URL) throws -> RecordingConfig {
        let data = try Data(contentsOf: path)
        return try JSONDecoder().decode(RecordingConfig.self, from: data)
    }

    func save(to path: URL) throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: path)
    }

    static var presetsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let presetsDir = appSupport.appendingPathComponent("ScreenRecorderCLI/Presets")
        try? FileManager.default.createDirectory(at: presetsDir, withIntermediateDirectories: true)
        return presetsDir
    }

    // Auto-save settings path
    static var defaultConfigPath: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appDir = appSupport.appendingPathComponent("ScreenRecorderCLI")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("settings.json")
    }

    // Auto-save current settings
    func autoSave() {
        try? save(to: RecordingConfig.defaultConfigPath)
    }

    // Load saved settings or return defaults
    static func loadDefault() -> RecordingConfig {
        if let loaded = try? load(from: defaultConfigPath) {
            return loaded
        }
        return RecordingConfig()
    }
}

// MARK: - Click Event Tracking

struct ClickEvent {
    let position: CGPoint
    let timestamp: Date
    let isRightClick: Bool
    let isDoubleClick: Bool

    var age: TimeInterval { Date().timeIntervalSince(timestamp) }
}

// MARK: - Keystroke Event

struct KeystrokeEvent {
    let key: String
    let modifiers: String
    let timestamp: Date

    var age: TimeInterval { Date().timeIntervalSince(timestamp) }

    var displayString: String {
        modifiers.isEmpty ? key : "\(modifiers)\(key)"
    }
}

// MARK: - Click Monitor with Double-Click Detection

@available(macOS 13.0, *)
class ClickMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isMonitoring = false
    var monitoringFailed = false

    var clickEvents: [ClickEvent] = []
    var onClickDetected: ((ClickEvent) -> Void)?

    private let clickQueue = DispatchQueue(label: "click.monitor.queue")
    private var clickDuration: Double = 0.3
    private var doubleClickThreshold: Double = 0.3
    private var detectDoubleClick: Bool = true

    private var lastLeftClickTime: Date?
    private var lastRightClickTime: Date?

    func startMonitoring(clickDuration: Double = 0.3, doubleClickThreshold: Double = 0.3, detectDoubleClick: Bool = true) -> Bool {
        guard !isMonitoring else { return true }
        self.clickDuration = clickDuration
        self.doubleClickThreshold = doubleClickThreshold
        self.detectDoubleClick = detectDoubleClick

        // Check Accessibility permission first
        if !AXIsProcessTrusted() {
            print("\n\(Terminal.yellow)⚠️  Accessibility permission required for click highlighting!\(Terminal.reset)")
            print("   Go to: \(Terminal.bold)System Settings → Privacy & Security → Accessibility\(Terminal.reset)")
            print("   Add Terminal (or this app) to the list and enable it.\n")
            monitoringFailed = true
            return false
        }

        let eventMask: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue) |
                                      (1 << CGEventType.rightMouseDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let monitor = Unmanaged<ClickMonitor>.fromOpaque(refcon).takeUnretainedValue()
                monitor.handleEvent(type: type, event: event)
                return Unmanaged.passRetained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            monitoringFailed = true
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            isMonitoring = true
            monitoringFailed = false
            return true
        }

        monitoringFailed = true
        return false
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        isMonitoring = false
        clickEvents.removeAll()
    }

    private func handleEvent(type: CGEventType, event: CGEvent) {
        let position = event.location
        let isRightClick = type == .rightMouseDown
        let now = Date()

        var isDoubleClick = false
        if detectDoubleClick {
            if isRightClick {
                if let last = lastRightClickTime, now.timeIntervalSince(last) <= doubleClickThreshold {
                    isDoubleClick = true
                }
                lastRightClickTime = now
            } else {
                if let last = lastLeftClickTime, now.timeIntervalSince(last) <= doubleClickThreshold {
                    isDoubleClick = true
                }
                lastLeftClickTime = now
            }
        }

        let clickEvent = ClickEvent(position: position, timestamp: now, isRightClick: isRightClick, isDoubleClick: isDoubleClick)

        clickQueue.async { [weak self] in
            self?.clickEvents.append(clickEvent)
            self?.onClickDetected?(clickEvent)
            self?.clickEvents.removeAll { $0.age > (self?.clickDuration ?? 0.3) + 0.1 }
        }
    }

    func getActiveClicks() -> [ClickEvent] {
        clickQueue.sync { clickEvents.filter { $0.age <= clickDuration } }
    }
}

// MARK: - Keystroke Monitor

@available(macOS 13.0, *)
class KeystrokeMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isMonitoring = false
    var monitoringFailed = false

    var keystrokeEvents: [KeystrokeEvent] = []
    private let keystrokeQueue = DispatchQueue(label: "keystroke.monitor.queue")
    private var keystrokeDuration: Double = 2.0

    func startMonitoring(keystrokeDuration: Double = 2.0) -> Bool {
        guard !isMonitoring else { return true }
        self.keystrokeDuration = keystrokeDuration

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let monitor = Unmanaged<KeystrokeMonitor>.fromOpaque(refcon).takeUnretainedValue()
                monitor.handleKeyEvent(event: event)
                return Unmanaged.passRetained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            monitoringFailed = true
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            isMonitoring = true
            monitoringFailed = false
            return true
        }

        monitoringFailed = true
        return false
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        isMonitoring = false
        keystrokeEvents.removeAll()
    }

    private func handleKeyEvent(event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        let keyName = getKeyName(keyCode: Int(keyCode))
        var modifiers = ""

        if flags.contains(.maskCommand) { modifiers += "⌘" }
        if flags.contains(.maskShift) { modifiers += "⇧" }
        if flags.contains(.maskAlternate) { modifiers += "⌥" }
        if flags.contains(.maskControl) { modifiers += "⌃" }

        let keystroke = KeystrokeEvent(key: keyName, modifiers: modifiers, timestamp: Date())

        keystrokeQueue.async { [weak self] in
            self?.keystrokeEvents.append(keystroke)
            self?.keystrokeEvents.removeAll { $0.age > (self?.keystrokeDuration ?? 2.0) }
        }
    }

    private func getKeyName(keyCode: Int) -> String {
        let keyMap: [Int: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↵",
            37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
            44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space",
            51: "⌫", 53: "⎋", 96: "F5", 97: "F6", 98: "F7", 99: "F3",
            100: "F8", 101: "F9", 103: "F11", 105: "F13", 107: "F14",
            109: "F10", 111: "F12", 113: "F15", 118: "F4", 119: "F2",
            120: "F1", 121: "F14", 122: "F15", 123: "←", 124: "→",
            125: "↓", 126: "↑"
        ]
        return keyMap[keyCode] ?? "?"
    }

    func getActiveKeystrokes() -> [KeystrokeEvent] {
        keystrokeQueue.sync { keystrokeEvents.filter { $0.age <= keystrokeDuration } }
    }
}

// MARK: - Webcam Capture Service

@available(macOS 13.0, *)
class WebcamCaptureService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    var latestFrame: CVPixelBuffer?
    private let captureQueue = DispatchQueue(label: "webcam.capture.queue")

    static func listCameras() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    func startCapture(deviceID: String? = nil) throws {
        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .medium

        let device: AVCaptureDevice?
        if let deviceID = deviceID {
            device = AVCaptureDevice(uniqueID: deviceID)
        } else {
            device = AVCaptureDevice.default(for: .video)
        }

        guard let camera = device else {
            throw RecorderError.webcamNotFound
        }

        let input = try AVCaptureDeviceInput(device: camera)
        if captureSession?.canAddInput(input) == true {
            captureSession?.addInput(input)
        }

        videoOutput = AVCaptureVideoDataOutput()
        videoOutput?.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput?.setSampleBufferDelegate(self, queue: captureQueue)

        if captureSession?.canAddOutput(videoOutput!) == true {
            captureSession?.addOutput(videoOutput!)
        }

        captureSession?.startRunning()
    }

    func stopCapture() {
        captureSession?.stopRunning()
        captureSession = nil
        videoOutput = nil
        latestFrame = nil
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        latestFrame = CMSampleBufferGetImageBuffer(sampleBuffer)
    }
}

// MARK: - Microphone Capture Service

@available(macOS 13.0, *)
class MicrophoneCaptureService: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private var captureSession: AVCaptureSession?
    private var audioOutput: AVCaptureAudioDataOutput?
    private var audioDevice: AVCaptureDevice?

    var onAudioBuffer: ((CMSampleBuffer) -> Void)?
    var currentLevel: Float = 0.0
    private let captureQueue = DispatchQueue(label: "microphone.capture.queue")

    static func listMicrophones() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        ).devices
    }

    static func checkPermission() -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined:
            var granted = false
            let semaphore = DispatchSemaphore(value: 0)
            AVCaptureDevice.requestAccess(for: .audio) { result in
                granted = result
                semaphore.signal()
            }
            semaphore.wait()
            return granted
        default: return false
        }
    }

    func startCapture(deviceID: String? = nil) throws {
        guard MicrophoneCaptureService.checkPermission() else {
            throw RecorderError.microphonePermissionDenied
        }

        captureSession = AVCaptureSession()

        if let deviceID = deviceID {
            audioDevice = AVCaptureDevice(uniqueID: deviceID)
        } else {
            audioDevice = AVCaptureDevice.default(for: .audio)
        }

        guard let device = audioDevice else {
            throw RecorderError.microphoneNotFound
        }

        let input = try AVCaptureDeviceInput(device: device)

        if captureSession?.canAddInput(input) == true {
            captureSession?.addInput(input)
        }

        audioOutput = AVCaptureAudioDataOutput()
        audioOutput?.setSampleBufferDelegate(self, queue: captureQueue)

        if captureSession?.canAddOutput(audioOutput!) == true {
            captureSession?.addOutput(audioOutput!)
        }

        captureSession?.startRunning()
    }

    func stopCapture() {
        captureSession?.stopRunning()
        captureSession = nil
        audioOutput = nil
        audioDevice = nil
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        onAudioBuffer?(sampleBuffer)
        if let level = calculateAudioLevel(from: sampleBuffer) {
            currentLevel = level
        }
    }

    private func calculateAudioLevel(from buffer: CMSampleBuffer) -> Float? {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { return nil }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

        guard let data = dataPointer, length > 0 else { return nil }

        let floatCount = length / MemoryLayout<Float>.size
        guard floatCount > 0 else { return 0 }

        let floatBuffer = UnsafeBufferPointer<Float>(
            start: UnsafeRawPointer(data).assumingMemoryBound(to: Float.self),
            count: floatCount
        )

        let sumOfSquares = floatBuffer.reduce(0) { $0 + $1 * $1 }
        let rms = sqrt(sumOfSquares / Float(floatCount))
        return min(1.0, rms * 3)
    }
}

// MARK: - Frame Processor

@available(macOS 13.0, *)
class FrameProcessor {
    private var config: RecordingConfig
    private var displayScale: CGFloat = 1.0
    private var displayBounds: CGRect = .zero

    init(config: RecordingConfig) {
        self.config = config
    }

    func updateConfig(_ config: RecordingConfig) {
        self.config = config
    }

    func setDisplayInfo(scale: CGFloat, bounds: CGRect) {
        self.displayScale = scale
        self.displayBounds = bounds
    }

    func processFrame(_ pixelBuffer: CVPixelBuffer,
                      clicks: [ClickEvent],
                      keystrokes: [KeystrokeEvent],
                      webcamFrame: CVPixelBuffer?) -> CVPixelBuffer {

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return pixelBuffer
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return pixelBuffer
        }

        // Draw click highlights
        if config.highlightClicks {
            for click in clicks {
                drawClickHighlight(context: context, click: click, width: width, height: height)
            }
        }

        // Draw keystroke overlay
        if config.showKeystrokes && !keystrokes.isEmpty {
            drawKeystrokeOverlay(context: context, keystrokes: keystrokes, width: width, height: height)
        }

        // Draw webcam PIP
        if config.enableWebcam, let webcam = webcamFrame {
            drawWebcamPIP(context: context, webcamFrame: webcam, width: width, height: height)
        }

        // Draw watermark
        if config.enableWatermark && !config.watermarkText.isEmpty {
            drawWatermark(context: context, width: width, height: height)
        }

        return pixelBuffer
    }

    private func drawClickHighlight(context: CGContext, click: ClickEvent, width: Int, height: Int) {
        let age = click.age
        let alpha = max(0, 1.0 - (age / config.clickDuration))

        let x = click.position.x * displayScale
        let y = CGFloat(height) - (click.position.y * displayScale)

        var radius = CGFloat(config.clickRadius) * displayScale * CGFloat(alpha)
        if click.isDoubleClick { radius *= 1.3 }

        let color = click.isRightClick ? config.rightClickColor : config.clickColor
        let rgba = color.getRGBA()

        let fadeColor = CGColor(red: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a * CGFloat(alpha))

        context.setFillColor(fadeColor)
        context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))

        context.setStrokeColor(CGColor(red: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a * CGFloat(alpha) * 1.5))
        context.setLineWidth(2 * displayScale)
        context.strokeEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))

        // Double-click ring
        if click.isDoubleClick {
            let outerRadius = radius * 1.5
            context.setStrokeColor(CGColor(red: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a * CGFloat(alpha) * 0.5))
            context.setLineWidth(1 * displayScale)
            context.strokeEllipse(in: CGRect(x: x - outerRadius, y: y - outerRadius, width: outerRadius * 2, height: outerRadius * 2))
        }
    }

    private func drawKeystrokeOverlay(context: CGContext, keystrokes: [KeystrokeEvent], width: Int, height: Int) {
        let fontSize: CGFloat = 24 * displayScale
        let padding: CGFloat = 10 * displayScale
        let margin: CGFloat = 20 * displayScale

        let displayText = keystrokes.suffix(5).map { $0.displayString }.joined(separator: " ")

        // Calculate position based on config
        var x: CGFloat = margin
        var y: CGFloat = margin

        switch config.keystrokePosition {
        case .bottomLeft:
            y = margin
        case .bottomCenter:
            x = CGFloat(width) / 2
        case .bottomRight:
            x = CGFloat(width) - margin
        case .topLeft:
            y = CGFloat(height) - margin - fontSize - padding * 2
        case .topCenter:
            x = CGFloat(width) / 2
            y = CGFloat(height) - margin - fontSize - padding * 2
        case .topRight:
            x = CGFloat(width) - margin
            y = CGFloat(height) - margin - fontSize - padding * 2
        }

        // Draw background
        let textWidth = CGFloat(displayText.count) * fontSize * 0.6
        let boxWidth = textWidth + padding * 2
        let boxHeight = fontSize + padding * 2

        if config.keystrokePosition.rawValue.contains("Right") {
            x -= boxWidth
        } else if config.keystrokePosition.rawValue.contains("Center") {
            x -= boxWidth / 2
        }

        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.7))
        context.fill(CGRect(x: x, y: y, width: boxWidth, height: boxHeight))

        // Draw text
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        // Note: CoreGraphics doesn't have built-in text drawing, using simple approach
        // In production, would use CoreText or draw character by character
    }

    private func drawWebcamPIP(context: CGContext, webcamFrame: CVPixelBuffer, width: Int, height: Int) {
        CVPixelBufferLockBaseAddress(webcamFrame, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(webcamFrame, .readOnly) }

        let webcamWidth = CVPixelBufferGetWidth(webcamFrame)
        let webcamHeight = CVPixelBufferGetHeight(webcamFrame)

        guard let webcamBase = CVPixelBufferGetBaseAddress(webcamFrame) else { return }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let webcamContext = CGContext(
            data: webcamBase,
            width: webcamWidth,
            height: webcamHeight,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(webcamFrame),
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ),
        let webcamImage = webcamContext.makeImage() else { return }

        let pipSize = CGFloat(width) * CGFloat(config.webcamSize)
        let margin: CGFloat = 20 * displayScale

        var pipX: CGFloat = margin
        var pipY: CGFloat = margin

        switch config.webcamPosition {
        case .topLeft:
            pipY = CGFloat(height) - margin - pipSize
        case .topRight:
            pipX = CGFloat(width) - margin - pipSize
            pipY = CGFloat(height) - margin - pipSize
        case .bottomLeft:
            break
        case .bottomRight:
            pipX = CGFloat(width) - margin - pipSize
        }

        let pipRect = CGRect(x: pipX, y: pipY, width: pipSize, height: pipSize)

        // Clip to shape
        context.saveGState()

        switch config.webcamShape {
        case .circle:
            context.addEllipse(in: pipRect)
            context.clip()
        case .roundedRect:
            let path = CGPath(roundedRect: pipRect, cornerWidth: pipSize * 0.1, cornerHeight: pipSize * 0.1, transform: nil)
            context.addPath(path)
            context.clip()
        case .rectangle:
            break
        }

        context.draw(webcamImage, in: pipRect)

        // Draw border
        context.restoreGState()
        context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.8))
        context.setLineWidth(3 * displayScale)

        switch config.webcamShape {
        case .circle:
            context.strokeEllipse(in: pipRect)
        case .roundedRect:
            let path = CGPath(roundedRect: pipRect, cornerWidth: pipSize * 0.1, cornerHeight: pipSize * 0.1, transform: nil)
            context.addPath(path)
            context.strokePath()
        case .rectangle:
            context.stroke(pipRect)
        }
    }

    private func drawWatermark(context: CGContext, width: Int, height: Int) {
        let fontSize: CGFloat = 16 * displayScale
        let margin: CGFloat = 10 * displayScale

        var x: CGFloat = margin
        var y: CGFloat = margin

        switch config.watermarkPosition {
        case .topLeft:
            y = CGFloat(height) - margin - fontSize
        case .topRight:
            x = CGFloat(width) - margin
            y = CGFloat(height) - margin - fontSize
        case .bottomLeft:
            break
        case .bottomRight:
            x = CGFloat(width) - margin
        }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: CGFloat(config.watermarkOpacity)))
        // Simplified - would use CoreText for proper text rendering
    }
}

// MARK: - Recording Stats

struct RecordingStats {
    var duration: TimeInterval = 0
    var frameCount: Int = 0
    var width: Int = 0
    var height: Int = 0
    var systemAudioLevel: Float = 0
    var microphoneLevel: Float = 0
    var fileName: String = ""
    var filePath: String = ""
    var fileSize: Int64 = 0
}

// MARK: - Screen Recorder

@available(macOS 13.0, *)
class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var micAudioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    private var isRecording = false
    private var isPaused = false
    private var sessionStarted = false
    private var startTime: Date?
    private var pausedTime: TimeInterval = 0
    private var lastPauseStart: Date?
    private var frameCount = 0

    private let videoQueue = DispatchQueue(label: "video.queue", qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "audio.queue", qos: .userInteractive)
    private let writerQueue = DispatchQueue(label: "writer.queue", qos: .userInteractive)

    private var outputURL: URL?
    private var config: RecordingConfig

    private var clickMonitor: ClickMonitor?
    private var keystrokeMonitor: KeystrokeMonitor?
    private var frameProcessor: FrameProcessor?
    private var microphoneService: MicrophoneCaptureService?
    private var webcamService: WebcamCaptureService?

    private var systemAudioLevel: Float = 0
    private var micAudioLevel: Float = 0

    private var displayWidth: Int = 0
    private var displayHeight: Int = 0

    var isCurrentlyRecording: Bool { isRecording }
    var clickMonitorFailed: Bool { clickMonitor?.monitoringFailed ?? false }
    var keystrokeMonitorFailed: Bool { keystrokeMonitor?.monitoringFailed ?? false }

    init(config: RecordingConfig) {
        self.config = config
        super.init()
        frameProcessor = FrameProcessor(config: config)
    }

    func startRecording() async throws {
        guard !isRecording else { return }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        let filter: SCContentFilter
        var captureWidth: Int
        var captureHeight: Int

        switch config.captureTarget {
        case .display(let index):
            guard index < content.displays.count else {
                throw RecorderError.invalidDisplay
            }
            let display = content.displays[index]
            filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            captureWidth = display.width
            captureHeight = display.height

        case .window(let windowID, _, _):
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                throw RecorderError.windowNotFound
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            captureWidth = Int(window.frame.width)
            captureHeight = Int(window.frame.height)
        }

        // Apply resolution scaling
        var outputWidth = captureWidth
        var outputHeight = captureHeight

        if let dims = config.resolution.dimensions {
            let aspectRatio = Double(captureWidth) / Double(captureHeight)
            if Double(dims.width) / Double(dims.height) > aspectRatio {
                outputWidth = Int(Double(dims.height) * aspectRatio)
                outputHeight = dims.height
            } else {
                outputWidth = dims.width
                outputHeight = Int(Double(dims.width) / aspectRatio)
            }
        }

        displayWidth = outputWidth
        displayHeight = outputHeight

        frameProcessor?.setDisplayInfo(
            scale: CGFloat(outputWidth) / CGFloat(captureWidth),
            bounds: CGRect(x: 0, y: 0, width: captureWidth, height: captureHeight)
        )

        // Setup output file
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let fileName = "Recording_\(timestamp).\(config.outputFormat.ext)"
        outputURL = config.outputDirectory.appendingPathComponent(fileName)

        try setupAssetWriter(width: outputWidth, height: outputHeight)

        // Setup stream
        let streamConfig = SCStreamConfiguration()
        streamConfig.width = outputWidth
        streamConfig.height = outputHeight
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(config.frameRate))
        streamConfig.pixelFormat = kCVPixelFormatType_32BGRA
        streamConfig.queueDepth = 5
        streamConfig.showsCursor = config.showCursor
        streamConfig.capturesAudio = config.captureSystemAudio

        if config.captureSystemAudio {
            streamConfig.sampleRate = 48000
            streamConfig.channelCount = 2
        }

        stream = SCStream(filter: filter, configuration: streamConfig, delegate: self)

        try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
        if config.captureSystemAudio {
            try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        }

        // Start monitors
        if config.highlightClicks {
            clickMonitor = ClickMonitor()
            _ = clickMonitor?.startMonitoring(
                clickDuration: config.clickDuration,
                doubleClickThreshold: config.doubleClickThreshold,
                detectDoubleClick: config.detectDoubleClick
            )
        }

        if config.showKeystrokes {
            keystrokeMonitor = KeystrokeMonitor()
            _ = keystrokeMonitor?.startMonitoring(keystrokeDuration: config.keystrokeDuration)
        }

        if config.captureMicrophone {
            microphoneService = MicrophoneCaptureService()
            microphoneService?.onAudioBuffer = { [weak self] buffer in
                self?.handleMicrophoneBuffer(buffer)
            }
            try? microphoneService?.startCapture(deviceID: config.selectedMicrophoneID)
        }

        if config.enableWebcam {
            webcamService = WebcamCaptureService()
            try? webcamService?.startCapture()
        }

        try await stream?.startCapture()

        isRecording = true
        isPaused = false
        startTime = Date()
        pausedTime = 0
        frameCount = 0
    }

    func stopRecording() async {
        guard isRecording else { return }

        isRecording = false
        isPaused = false

        clickMonitor?.stopMonitoring()
        keystrokeMonitor?.stopMonitoring()
        microphoneService?.stopCapture()
        webcamService?.stopCapture()

        try? await stream?.stopCapture()
        stream = nil

        videoInput?.markAsFinished()
        systemAudioInput?.markAsFinished()
        micAudioInput?.markAsFinished()

        await assetWriter?.finishWriting()

        assetWriter = nil
        videoInput = nil
        systemAudioInput = nil
        micAudioInput = nil
        pixelBufferAdaptor = nil
        sessionStarted = false
    }

    func pauseRecording() {
        guard isRecording, !isPaused else { return }
        isPaused = true
        lastPauseStart = Date()
    }

    func resumeRecording() {
        guard isRecording, isPaused else { return }
        if let pauseStart = lastPauseStart {
            pausedTime += Date().timeIntervalSince(pauseStart)
        }
        isPaused = false
        lastPauseStart = nil
    }

    func getStats() -> RecordingStats {
        var stats = RecordingStats()

        if let start = startTime {
            var duration = Date().timeIntervalSince(start) - pausedTime
            if isPaused, let pauseStart = lastPauseStart {
                duration -= Date().timeIntervalSince(pauseStart)
            }
            stats.duration = max(0, duration)
        }

        stats.frameCount = frameCount
        stats.width = displayWidth
        stats.height = displayHeight
        stats.systemAudioLevel = systemAudioLevel
        stats.microphoneLevel = micAudioLevel

        if let url = outputURL {
            stats.fileName = url.lastPathComponent
            stats.filePath = url.path
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
                stats.fileSize = attrs[.size] as? Int64 ?? 0
            }
        }

        return stats
    }

    private func setupAssetWriter(width: Int, height: Int) throws {
        guard let url = outputURL else { throw RecorderError.invalidOutput }

        try? FileManager.default.removeItem(at: url)

        assetWriter = try AVAssetWriter(outputURL: url, fileType: config.outputFormat.fileType)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: config.codec.avCodec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: config.quality.bitrate,
                AVVideoMaxKeyFrameIntervalKey: config.frameRate,
                AVVideoProfileLevelKey: config.codec == .hevc ?
                    kVTProfileLevel_HEVC_Main_AutoLevel as String :
                    AVVideoProfileLevelH264HighAutoLevel
            ]
        ]

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput?.expectsMediaDataInRealTime = true

        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput!,
            sourcePixelBufferAttributes: attrs
        )

        if assetWriter?.canAdd(videoInput!) == true {
            assetWriter?.add(videoInput!)
        }

        if config.captureSystemAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128000
            ]

            systemAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            systemAudioInput?.expectsMediaDataInRealTime = true

            if assetWriter?.canAdd(systemAudioInput!) == true {
                assetWriter?.add(systemAudioInput!)
            }
        }

        if config.captureMicrophone {
            let micSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 96000
            ]

            micAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: micSettings)
            micAudioInput?.expectsMediaDataInRealTime = true

            if assetWriter?.canAdd(micAudioInput!) == true {
                assetWriter?.add(micAudioInput!)
            }
        }

        guard assetWriter?.startWriting() == true else {
            throw RecorderError.writerFailed(assetWriter?.error)
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard isRecording, !isPaused, sampleBuffer.isValid else { return }

        writerQueue.async { [weak self] in
            guard let self = self else { return }

            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

            if !self.sessionStarted {
                self.assetWriter?.startSession(atSourceTime: timestamp)
                self.sessionStarted = true
            }

            switch type {
            case .screen:
                guard var pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
                      self.videoInput?.isReadyForMoreMediaData == true else { return }

                let clicks = self.clickMonitor?.getActiveClicks() ?? []
                let keystrokes = self.keystrokeMonitor?.getActiveKeystrokes() ?? []
                let webcam = self.webcamService?.latestFrame

                if !clicks.isEmpty || !keystrokes.isEmpty || webcam != nil ||
                   self.config.enableWatermark {
                    pixelBuffer = self.frameProcessor?.processFrame(
                        pixelBuffer,
                        clicks: clicks,
                        keystrokes: keystrokes,
                        webcamFrame: webcam
                    ) ?? pixelBuffer
                }

                self.pixelBufferAdaptor?.append(pixelBuffer, withPresentationTime: timestamp)
                self.frameCount += 1

            case .audio:
                if self.systemAudioInput?.isReadyForMoreMediaData == true {
                    self.systemAudioInput?.append(sampleBuffer)
                }
                self.systemAudioLevel = self.calculateAudioLevel(from: sampleBuffer)

            default:
                break
            }
        }
    }

    private func handleMicrophoneBuffer(_ buffer: CMSampleBuffer) {
        guard isRecording, !isPaused else { return }

        writerQueue.async { [weak self] in
            guard let self = self else { return }

            if self.micAudioInput?.isReadyForMoreMediaData == true {
                self.micAudioInput?.append(buffer)
            }
            self.micAudioLevel = self.microphoneService?.currentLevel ?? 0
        }
    }

    private func calculateAudioLevel(from buffer: CMSampleBuffer) -> Float {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { return 0 }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

        guard let data = dataPointer, length > 0 else { return 0 }

        let floatCount = length / MemoryLayout<Float>.size
        guard floatCount > 0 else { return 0 }

        let floatBuffer = UnsafeBufferPointer<Float>(
            start: UnsafeRawPointer(data).assumingMemoryBound(to: Float.self),
            count: floatCount
        )

        let sumOfSquares = floatBuffer.reduce(0) { $0 + $1 * $1 }
        let rms = sqrt(sumOfSquares / Float(floatCount))
        return min(1.0, rms * 3)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("\(Terminal.red)Stream error: \(error.localizedDescription)\(Terminal.reset)")
    }
}

// MARK: - Errors

enum RecorderError: LocalizedError {
    case invalidDisplay
    case invalidOutput
    case writerFailed(Error?)
    case permissionDenied
    case osVersionNotSupported
    case microphoneNotFound
    case microphonePermissionDenied
    case webcamNotFound
    case windowNotFound

    var errorDescription: String? {
        switch self {
        case .invalidDisplay: return "Invalid display index"
        case .invalidOutput: return "Invalid output path"
        case .writerFailed(let error): return "Writer failed: \(error?.localizedDescription ?? "Unknown")"
        case .permissionDenied: return "Screen recording permission denied"
        case .osVersionNotSupported: return "macOS 13.0 or later is required"
        case .microphoneNotFound: return "No microphone found"
        case .microphonePermissionDenied: return "Microphone permission denied"
        case .webcamNotFound: return "No webcam found"
        case .windowNotFound: return "Window not found or closed"
        }
    }
}

// MARK: - Permission Check

func checkPermissions() -> Bool {
    let hasAccess = CGPreflightScreenCaptureAccess()
    if !hasAccess {
        print("\(Terminal.yellow)\(Terminal.bold)Screen Recording Permission Required!\(Terminal.reset)")
        print("""

        To grant permission:
        1. Open System Settings -> Privacy & Security -> Screen Recording
        2. Enable permission for Terminal (or your terminal app)
        3. Restart your terminal and run this again

        """)
        CGRequestScreenCaptureAccess()
        return false
    }
    return true
}

// MARK: - Menu System

@available(macOS 13.0, *)
class MenuSystem {
    private var config: RecordingConfig
    private var recorder: ScreenRecorder?

    init(config: RecordingConfig) {
        self.config = config
    }

    func clearScreen() {
        print(Terminal.clearScreen + Terminal.moveCursorHome, terminator: "")
    }

    func printBoxTop(_ width: Int = 62) {
        print("\(Terminal.cyan)\(Box.topLeft)\(String(repeating: Box.horizontal, count: width - 2))\(Box.topRight)\(Terminal.reset)")
    }

    func printBoxBottom(_ width: Int = 62) {
        print("\(Terminal.cyan)\(Box.bottomLeft)\(String(repeating: Box.horizontal, count: width - 2))\(Box.bottomRight)\(Terminal.reset)")
    }

    func printBoxMiddle(_ width: Int = 62) {
        print("\(Terminal.cyan)\(Box.leftT)\(String(repeating: Box.horizontal, count: width - 2))\(Box.rightT)\(Terminal.reset)")
    }

    func printBoxLine(_ text: String, width: Int = 62, align: String = "left") {
        let visibleLength = text.replacingOccurrences(of: "\u{001B}\\[[0-9;]*m", with: "", options: .regularExpression).count
        let padding = width - 4 - visibleLength

        switch align {
        case "center":
            let leftPad = padding / 2
            let rightPad = padding - leftPad
            print("\(Terminal.cyan)\(Box.vertical)\(Terminal.reset) \(String(repeating: " ", count: max(0, leftPad)))\(text)\(String(repeating: " ", count: max(0, rightPad))) \(Terminal.cyan)\(Box.vertical)\(Terminal.reset)")
        default:
            print("\(Terminal.cyan)\(Box.vertical)\(Terminal.reset) \(text)\(String(repeating: " ", count: max(0, padding))) \(Terminal.cyan)\(Box.vertical)\(Terminal.reset)")
        }
    }

    func printEmptyBoxLine(_ width: Int = 62) {
        print("\(Terminal.cyan)\(Box.vertical)\(Terminal.reset)\(String(repeating: " ", count: width - 2))\(Terminal.cyan)\(Box.vertical)\(Terminal.reset)")
    }

    func getInput(_ prompt: String = "") -> String {
        if !prompt.isEmpty { print(prompt, terminator: " ") }
        fflush(stdout)
        return readLine() ?? ""
    }

    // MARK: - Main Menu

    func showMainMenu() async {
        while true {
            clearScreen()
            printBoxTop()
            printBoxLine("\(Terminal.bold)\(Terminal.brightCyan)Screen Recorder Pro CLI v2\(Terminal.reset)", align: "center")
            printBoxMiddle()
            printEmptyBoxLine()
            printBoxLine("\(Terminal.brightGreen)[1]\(Terminal.reset)  Start Recording")
            printBoxLine("\(Terminal.brightGreen)[2]\(Terminal.reset)  Recording Settings")
            printBoxLine("\(Terminal.brightGreen)[3]\(Terminal.reset)  Audio Settings")
            printBoxLine("\(Terminal.brightGreen)[4]\(Terminal.reset)  Mouse & Click Settings")
            printBoxLine("\(Terminal.brightGreen)[5]\(Terminal.reset)  Capture Target")
            printBoxLine("\(Terminal.brightGreen)[6]\(Terminal.reset)  Overlays (Keys, Webcam, Watermark)")
            printBoxLine("\(Terminal.brightGreen)[7]\(Terminal.reset)  Output Settings")
            printBoxLine("\(Terminal.brightGreen)[8]\(Terminal.reset)  Presets")
            printBoxLine("\(Terminal.brightGreen)[9]\(Terminal.reset)  Help")
            printEmptyBoxLine()
            printBoxLine("\(Terminal.brightRed)[Q]\(Terminal.reset)  Quit")
            printEmptyBoxLine()
            printBoxBottom()

            // Config summary
            let target = config.captureTarget.description
            print("\n\(Terminal.dim)Current: \(config.resolution.shortName) @ \(config.frameRate)fps | \(target)\(Terminal.reset)")
            print("\(Terminal.dim)Audio: \(config.captureSystemAudio ? "Sys" : "-") \(config.captureMicrophone ? "Mic" : "-") | Clicks: \(config.highlightClicks ? "Yes" : "No") | Keys: \(config.showKeystrokes ? "Yes" : "No")\(Terminal.reset)")

            let choice = getInput("\n\(Terminal.cyan)->\(Terminal.reset) Select:").lowercased()

            switch choice {
            case "1": await startRecordingFlow()
            case "2": await showRecordingSettings()
            case "3": await showAudioSettings()
            case "4": showMouseSettings()
            case "5": await showCaptureTargetMenu()
            case "6": showOverlaysMenu()
            case "7": showOutputSettings()
            case "8": await showPresetsMenu()
            case "9": showHelp()
            case "q", "quit", "exit":
                clearScreen()
                print("\(Terminal.cyan)Goodbye!\(Terminal.reset)\n")
                return
            default: continue
            }
        }
    }

    func startRecordingFlow() async {
        clearScreen()

        guard checkPermissions() else {
            _ = getInput("\nPress Enter to continue...")
            return
        }

        if config.showCountdown {
            await showCountdown()
        }

        recorder = ScreenRecorder(config: config)

        do {
            try await recorder?.startRecording()

            // Check for monitor failures
            if recorder?.clickMonitorFailed == true {
                print("\(Terminal.yellow)Note: Click monitoring requires Accessibility permission\(Terminal.reset)")
            }
            if recorder?.keystrokeMonitorFailed == true {
                print("\(Terminal.yellow)Note: Keystroke monitoring requires Accessibility permission\(Terminal.reset)")
            }

            await showRecordingStatus()

        } catch {
            print("\(Terminal.red)Error: \(error.localizedDescription)\(Terminal.reset)")
            _ = getInput("\nPress Enter to continue...")
        }
    }

    func showCountdown() async {
        for i in (1...config.countdownSeconds).reversed() {
            clearScreen()
            print("\n\n")
            printBoxTop()
            printBoxLine("\(Terminal.bold)Recording starts in...\(Terminal.reset)", align: "center")
            printBoxMiddle()
            printEmptyBoxLine()
            printBoxLine("\(Terminal.brightYellow)\(Terminal.bold)     \(i)     \(Terminal.reset)", align: "center")
            printEmptyBoxLine()
            printBoxBottom()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        clearScreen()
        print("\n\n")
        printBoxTop()
        printEmptyBoxLine()
        printBoxLine("\(Terminal.brightGreen)\(Terminal.bold)GO!\(Terminal.reset)", align: "center")
        printEmptyBoxLine()
        printBoxBottom()
        try? await Task.sleep(nanoseconds: 500_000_000)
    }

    func showRecordingStatus() async {
        guard let recorder = recorder else { return }

        clearScreen()
        print(Terminal.hideCursor, terminator: "")

        let oldSettings = enableRawMode()
        var isPaused = false
        var shouldStop = false
        let autoStopTime = config.autoStopEnabled && config.autoStopSeconds > 0 ? config.autoStopSeconds : nil

        while recorder.isCurrentlyRecording && !shouldStop {
            let stats = recorder.getStats()

            // Check auto-stop
            if let autoStop = autoStopTime, stats.duration >= Double(autoStop) {
                shouldStop = true
                continue
            }

            clearScreen()
            printBoxTop()

            if isPaused {
                printBoxLine("\(Terminal.yellow)\(Terminal.bold)PAUSED\(Terminal.reset)", align: "center")
            } else {
                printBoxLine("\(Terminal.brightRed)\(Terminal.bold)RECORDING\(Terminal.reset)", align: "center")
            }

            printBoxMiddle()
            printEmptyBoxLine()
            printBoxLine("Duration:     \(Terminal.bold)\(formatDuration(stats.duration))\(Terminal.reset)")
            printBoxLine("Frames:       \(Terminal.bold)\(formatNumber(stats.frameCount))\(Terminal.reset)")
            printBoxLine("Resolution:   \(Terminal.bold)\(stats.width)x\(stats.height)\(Terminal.reset)")
            printEmptyBoxLine()

            let sysLevel = min(10, Int(stats.systemAudioLevel * 10))
            let micLevel = min(10, Int(stats.microphoneLevel * 10))
            let sysBar = String(repeating: "#", count: sysLevel) + String(repeating: "-", count: 10 - sysLevel)
            let micBar = String(repeating: "#", count: micLevel) + String(repeating: "-", count: 10 - micLevel)

            if config.captureSystemAudio {
                printBoxLine("System:  [\(Terminal.green)\(sysBar)\(Terminal.reset)]")
            }
            if config.captureMicrophone {
                printBoxLine("Mic:     [\(Terminal.cyan)\(micBar)\(Terminal.reset)]")
            }

            printEmptyBoxLine()
            printBoxLine("File: \(Terminal.dim)\(stats.fileName)\(Terminal.reset)")
            printBoxLine("Size: \(Terminal.bold)\(formatBytes(stats.fileSize))\(Terminal.reset)")

            if let autoStop = autoStopTime {
                let remaining = max(0, autoStop - Int(stats.duration))
                printBoxLine("Auto-stop in: \(remaining)s")
            }

            printEmptyBoxLine()
            printBoxMiddle()

            if isPaused {
                printBoxLine("[R] Resume  [S] Stop")
            } else {
                printBoxLine("[P] Pause   [S] Stop")
            }
            printBoxBottom()

            if let char = getCharNonBlocking() {
                switch char.lowercased() {
                case "p" where !isPaused:
                    recorder.pauseRecording()
                    isPaused = true
                case "r" where isPaused:
                    recorder.resumeRecording()
                    isPaused = false
                case "s", "\n", "\r":
                    shouldStop = true
                default: break
                }
            }

            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        await recorder.stopRecording()

        restoreTerminalMode(oldSettings)
        print(Terminal.showCursor, terminator: "")

        clearScreen()
        printBoxTop()
        printBoxLine("\(Terminal.brightGreen)\(Terminal.bold)Recording Complete!\(Terminal.reset)", align: "center")
        printBoxMiddle()
        printEmptyBoxLine()

        let stats = recorder.getStats()
        printBoxLine("Duration:  \(formatDuration(stats.duration))")
        printBoxLine("Frames:    \(formatNumber(stats.frameCount))")
        printBoxLine("Size:      \(formatBytes(stats.fileSize))")
        printEmptyBoxLine()
        printBoxLine("Saved to:")
        printBoxLine("\(Terminal.dim)\(stats.filePath)\(Terminal.reset)")
        printEmptyBoxLine()
        printBoxBottom()

        _ = getInput("\nPress Enter to continue...")
    }

    // Settings menus (simplified versions)
    func showRecordingSettings() async {
        var done = false
        while !done {
            clearScreen()
            printBoxTop()
            printBoxLine("\(Terminal.bold)Recording Settings\(Terminal.reset)", align: "center")
            printBoxMiddle()
            printEmptyBoxLine()
            printBoxLine("[1] Resolution:   \(config.resolution.rawValue)")
            printBoxLine("[2] Frame Rate:   \(config.frameRate) fps")
            printBoxLine("[3] Codec:        \(config.codec.rawValue)")
            printBoxLine("[4] Quality:      \(config.quality.rawValue)")
            printEmptyBoxLine()
            printBoxLine("[B] Back")
            printEmptyBoxLine()
            printBoxBottom()

            let choice = getInput("\n-> Select:").lowercased()
            switch choice {
            case "1":
                print("\nResolutions: 1=Native, 2=4K, 3=1440p, 4=1080p, 5=720p")
                if let idx = Int(getInput("Select:")), idx >= 1, idx <= Resolution.allCases.count {
                    config.resolution = Resolution.allCases[idx - 1]
                }
            case "2":
                print("\nFrame rates: 1=24, 2=30, 3=48, 4=60")
                let rates = [24, 30, 48, 60]
                if let idx = Int(getInput("Select:")), idx >= 1, idx <= rates.count {
                    config.frameRate = rates[idx - 1]
                }
            case "3":
                print("\nCodecs: 1=H.264, 2=HEVC")
                if let idx = Int(getInput("Select:")), idx >= 1, idx <= 2 {
                    config.codec = VideoCodec.allCases[idx - 1]
                }
            case "4":
                print("\nQuality: 1=Low, 2=Optimized, 3=Medium, 4=High, 5=Ultra")
                print("\(Terminal.dim)Tip: Use HEVC codec + Optimized for best quality/size ratio\(Terminal.reset)")
                if let idx = Int(getInput("Select:")), idx >= 1, idx <= QualityPreset.allCases.count {
                    config.quality = QualityPreset.allCases[idx - 1]
                }
            case "b", "": done = true
            default: continue
            }
            config.autoSave()
        }
    }

    func showAudioSettings() async {
        var done = false
        while !done {
            clearScreen()
            printBoxTop()
            printBoxLine("\(Terminal.bold)Audio Settings\(Terminal.reset)", align: "center")
            printBoxMiddle()
            printEmptyBoxLine()
            printBoxLine("[1] System Audio:  \(config.captureSystemAudio ? "ON" : "OFF")")
            printBoxLine("[2] Microphone:    \(config.captureMicrophone ? "ON" : "OFF")")
            printBoxLine("[3] Select Microphone")
            printEmptyBoxLine()
            printBoxLine("[B] Back")
            printEmptyBoxLine()
            printBoxBottom()

            let choice = getInput("\n-> Select:").lowercased()
            switch choice {
            case "1": config.captureSystemAudio.toggle()
            case "2": config.captureMicrophone.toggle()
            case "3":
                let mics = MicrophoneCaptureService.listMicrophones()
                if mics.isEmpty {
                    print("\nNo microphones found")
                } else {
                    print("\nMicrophones:")
                    for (i, mic) in mics.enumerated() {
                        print("  [\(i + 1)] \(mic.localizedName)")
                    }
                    if let idx = Int(getInput("Select:")), idx >= 1, idx <= mics.count {
                        config.selectedMicrophoneID = mics[idx - 1].uniqueID
                        config.captureMicrophone = true
                    }
                }
                _ = getInput("Press Enter...")
            case "b", "": done = true
            default: continue
            }
            config.autoSave()
        }
    }

    func showMouseSettings() {
        var done = false
        while !done {
            clearScreen()
            printBoxTop()
            printBoxLine("\(Terminal.bold)Mouse & Click Settings\(Terminal.reset)", align: "center")
            printBoxMiddle()
            printEmptyBoxLine()
            printBoxLine("[1] Show Cursor:       \(config.showCursor ? "ON" : "OFF")")
            printBoxLine("[2] Highlight Clicks:  \(config.highlightClicks ? "ON" : "OFF")")
            printBoxLine("[3] Left Click Color:  \(config.clickColor.rawValue)")
            printBoxLine("[4] Right Click Color: \(config.rightClickColor.rawValue)")
            printBoxLine("[5] Click Size:        \(config.clickRadius)px")
            printBoxLine("[6] Double-Click:      \(config.detectDoubleClick ? "ON" : "OFF")")
            printEmptyBoxLine()
            printBoxLine("[B] Back")
            printEmptyBoxLine()
            printBoxBottom()

            let choice = getInput("\n-> Select:").lowercased()
            switch choice {
            case "1": config.showCursor.toggle()
            case "2": config.highlightClicks.toggle()
            case "3":
                print("\nColors: 1=Yellow, 2=Red, 3=Blue, 4=Green, 5=White, 6=Magenta, 7=Cyan")
                if let idx = Int(getInput("Select:")), idx >= 1, idx <= ClickColor.allCases.count {
                    config.clickColor = ClickColor.allCases[idx - 1]
                }
            case "4":
                print("\nColors: 1=Yellow, 2=Red, 3=Blue, 4=Green, 5=White, 6=Magenta, 7=Cyan")
                if let idx = Int(getInput("Select:")), idx >= 1, idx <= ClickColor.allCases.count {
                    config.rightClickColor = ClickColor.allCases[idx - 1]
                }
            case "5":
                print("\nSizes: 1=Small(20), 2=Medium(30), 3=Large(45), 4=XL(60)")
                let sizes = [20, 30, 45, 60]
                if let idx = Int(getInput("Select:")), idx >= 1, idx <= sizes.count {
                    config.clickRadius = sizes[idx - 1]
                }
            case "6": config.detectDoubleClick.toggle()
            case "b", "": done = true
            default: continue
            }
            config.autoSave()
        }
    }

    func showCaptureTargetMenu() async {
        clearScreen()
        printBoxTop()
        printBoxLine("\(Terminal.bold)Capture Target\(Terminal.reset)", align: "center")
        printBoxMiddle()
        printEmptyBoxLine()
        printBoxLine("[1] Full Display")
        printBoxLine("[2] Application Window")
        printEmptyBoxLine()
        printBoxBottom()

        print("\nCurrent: \(config.captureTarget.description)")

        let choice = getInput("\n-> Select:").lowercased()

        switch choice {
        case "1":
            let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            print("\nDisplays:")
            for (i, display) in (content?.displays ?? []).enumerated() {
                let main = display.displayID == CGMainDisplayID() ? " (Main)" : ""
                print("  [\(i)] \(display.width)x\(display.height)\(main)")
            }
            if let idx = Int(getInput("Select display:")), idx >= 0, idx < (content?.displays.count ?? 0) {
                config.captureTarget = .display(idx)
            }

        case "2":
            let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let windows = content?.windows.filter { $0.isOnScreen && $0.frame.width > 100 } ?? []
            print("\nWindows:")
            for (i, window) in windows.prefix(15).enumerated() {
                let app = window.owningApplication?.applicationName ?? "Unknown"
                let title = window.title ?? "Untitled"
                print("  [\(i)] \(app) - \(title.prefix(40))")
            }
            if let idx = Int(getInput("Select window:")), idx >= 0, idx < windows.count {
                let w = windows[idx]
                config.captureTarget = .window(
                    windowID: w.windowID,
                    appName: w.owningApplication?.applicationName ?? "Unknown",
                    title: w.title ?? "Untitled"
                )
            }

        default: break
        }
        config.autoSave()
    }

    func showOverlaysMenu() {
        var done = false
        while !done {
            clearScreen()
            printBoxTop()
            printBoxLine("\(Terminal.bold)Overlays\(Terminal.reset)", align: "center")
            printBoxMiddle()
            printEmptyBoxLine()
            printBoxLine("[1] Keystroke Display: \(config.showKeystrokes ? "ON" : "OFF")")
            printBoxLine("[2] Webcam PIP:        \(config.enableWebcam ? "ON" : "OFF")")
            printBoxLine("[3] Watermark:         \(config.enableWatermark ? "ON" : "OFF")")
            printEmptyBoxLine()
            printBoxLine("[B] Back")
            printEmptyBoxLine()
            printBoxBottom()

            let choice = getInput("\n-> Select:").lowercased()
            switch choice {
            case "1":
                config.showKeystrokes.toggle()
                if config.showKeystrokes {
                    print("\nPosition: 1=BottomLeft, 2=BottomCenter, 3=BottomRight, 4=TopLeft, 5=TopCenter, 6=TopRight")
                    if let idx = Int(getInput("Select:")), idx >= 1, idx <= 6 {
                        config.keystrokePosition = KeyDisplayPosition.allCases[idx - 1]
                    }
                }
            case "2":
                config.enableWebcam.toggle()
                if config.enableWebcam {
                    print("\nPosition: 1=TopLeft, 2=TopRight, 3=BottomLeft, 4=BottomRight")
                    if let idx = Int(getInput("Select:")), idx >= 1, idx <= 4 {
                        config.webcamPosition = PIPPosition.allCases[idx - 1]
                    }
                    print("Shape: 1=Circle, 2=Rectangle, 3=RoundedRect")
                    if let idx = Int(getInput("Select:")), idx >= 1, idx <= 3 {
                        config.webcamShape = PIPShape.allCases[idx - 1]
                    }
                }
            case "3":
                config.enableWatermark.toggle()
                if config.enableWatermark {
                    config.watermarkText = getInput("Enter watermark text:")
                    print("Position: 1=TopLeft, 2=TopRight, 3=BottomLeft, 4=BottomRight")
                    if let idx = Int(getInput("Select:")), idx >= 1, idx <= 4 {
                        config.watermarkPosition = PIPPosition.allCases[idx - 1]
                    }
                }
            case "b", "": done = true
            default: continue
            }
            config.autoSave()
        }
    }

    func showOutputSettings() {
        var done = false
        while !done {
            clearScreen()
            printBoxTop()
            printBoxLine("\(Terminal.bold)Output Settings\(Terminal.reset)", align: "center")
            printBoxMiddle()
            printEmptyBoxLine()
            printBoxLine("[1] Format:     \(config.outputFormat.rawValue)")
            printBoxLine("[2] Directory:  \(config.outputDirectory.path)")
            printBoxLine("[3] Countdown:  \(config.showCountdown ? "ON (\(config.countdownSeconds)s)" : "OFF")")
            printBoxLine("[4] Auto-stop:  \(config.autoStopEnabled ? "\(config.autoStopSeconds)s" : "OFF")")
            printEmptyBoxLine()
            printBoxLine("[B] Back")
            printEmptyBoxLine()
            printBoxBottom()

            let choice = getInput("\n-> Select:").lowercased()
            switch choice {
            case "1":
                print("\nFormat: 1=MP4, 2=MOV")
                if let idx = Int(getInput("Select:")), idx >= 1, idx <= 2 {
                    config.outputFormat = OutputFormat.allCases[idx - 1]
                }
            case "2":
                print("\nCurrent: \(config.outputDirectory.path)")
                let path = getInput("New path (or Enter to keep):")
                if !path.isEmpty {
                    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                    if FileManager.default.fileExists(atPath: url.path) {
                        config.outputDirectory = url
                    } else {
                        print("Directory not found")
                        _ = getInput("Press Enter...")
                    }
                }
            case "3":
                config.showCountdown.toggle()
                if config.showCountdown {
                    if let secs = Int(getInput("Countdown seconds (1-10):")) {
                        config.countdownSeconds = min(10, max(1, secs))
                    }
                }
            case "4":
                config.autoStopEnabled.toggle()
                if config.autoStopEnabled {
                    if let secs = Int(getInput("Auto-stop after seconds:")) {
                        config.autoStopSeconds = max(1, secs)
                    }
                }
            case "b", "": done = true
            default: continue
            }
            config.autoSave()
        }
    }

    func showPresetsMenu() async {
        clearScreen()
        printBoxTop()
        printBoxLine("\(Terminal.bold)Presets\(Terminal.reset)", align: "center")
        printBoxMiddle()
        printEmptyBoxLine()
        printBoxLine("[1] Save Current Settings")
        printBoxLine("[2] Load Preset")
        printBoxLine("[3] List Presets")
        printEmptyBoxLine()
        printBoxLine("[B] Back")
        printEmptyBoxLine()
        printBoxBottom()

        let choice = getInput("\n-> Select:").lowercased()

        switch choice {
        case "1":
            let name = getInput("Preset name:")
            if !name.isEmpty {
                let path = RecordingConfig.presetsDirectory.appendingPathComponent("\(name).json")
                do {
                    try config.save(to: path)
                    print("\(Terminal.green)Preset saved!\(Terminal.reset)")
                } catch {
                    print("\(Terminal.red)Error: \(error.localizedDescription)\(Terminal.reset)")
                }
            }
            _ = getInput("Press Enter...")

        case "2":
            let presets = try? FileManager.default.contentsOfDirectory(at: RecordingConfig.presetsDirectory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
            if let presets = presets, !presets.isEmpty {
                print("\nPresets:")
                for (i, preset) in presets.enumerated() {
                    print("  [\(i + 1)] \(preset.deletingPathExtension().lastPathComponent)")
                }
                if let idx = Int(getInput("Load:")), idx >= 1, idx <= presets.count {
                    do {
                        config = try RecordingConfig.load(from: presets[idx - 1])
                        print("\(Terminal.green)Preset loaded!\(Terminal.reset)")
                    } catch {
                        print("\(Terminal.red)Error: \(error.localizedDescription)\(Terminal.reset)")
                    }
                }
            } else {
                print("No presets found")
            }
            _ = getInput("Press Enter...")

        case "3":
            let presets = try? FileManager.default.contentsOfDirectory(at: RecordingConfig.presetsDirectory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
            print("\nSaved presets:")
            if let presets = presets, !presets.isEmpty {
                for preset in presets {
                    print("  - \(preset.deletingPathExtension().lastPathComponent)")
                }
            } else {
                print("  (none)")
            }
            _ = getInput("\nPress Enter...")

        default: break
        }
    }

    func showHelp() {
        clearScreen()
        printBoxTop()
        printBoxLine("\(Terminal.bold)Help\(Terminal.reset)", align: "center")
        printBoxMiddle()
        printEmptyBoxLine()
        printBoxLine("Screen Recorder Pro CLI v2")
        printBoxLine("A powerful screen recording tool for macOS")
        printEmptyBoxLine()
        printBoxLine("Features:")
        printBoxLine("- Record display or specific window")
        printBoxLine("- System audio + microphone")
        printBoxLine("- Click highlighting with colors")
        printBoxLine("- Keystroke overlay")
        printBoxLine("- Webcam PIP")
        printBoxLine("- Watermark")
        printBoxLine("- Save/load presets")
        printEmptyBoxLine()
        printBoxLine("During Recording:")
        printBoxLine("[P] Pause  [R] Resume  [S] Stop")
        printEmptyBoxLine()
        printBoxLine("Command Line:")
        printBoxLine("screenrecord -t 30       Record 30s")
        printBoxLine("screenrecord --mic       With microphone")
        printBoxLine("screenrecord --clicks    With click highlighting")
        printBoxLine("screenrecord --keys      With keystroke overlay")
        printEmptyBoxLine()
        printBoxBottom()

        _ = getInput("\nPress Enter...")
    }

    // Helpers
    func formatDuration(_ d: TimeInterval) -> String {
        let h = Int(d) / 3600
        let m = (Int(d) % 3600) / 60
        let s = Int(d) % 60
        return h > 0 ? String(format: "%02d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    func formatBytes(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }

    func formatNumber(_ n: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: n), number: .decimal)
    }

    func enableRawMode() -> termios {
        var raw = termios()
        tcgetattr(STDIN_FILENO, &raw)
        let original = raw
        raw.c_lflag &= ~(UInt(ECHO | ICANON))
        raw.c_cc.16 = 0
        raw.c_cc.17 = 0
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
        return original
    }

    func restoreTerminalMode(_ original: termios) {
        var term = original
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &term)
    }

    func getCharNonBlocking() -> String? {
        var buffer = [UInt8](repeating: 0, count: 1)
        let bytesRead = read(STDIN_FILENO, &buffer, 1)
        return bytesRead > 0 ? String(bytes: buffer, encoding: .utf8) : nil
    }
}

// MARK: - CLI Mode

@available(macOS 13.0, *)
func runCLIMode() async {
    let args = CommandLine.arguments

    if args.contains("--help") || args.contains("-h") {
        print("""
        \(Terminal.cyan)\(Terminal.bold)Screen Recorder Pro CLI v2\(Terminal.reset)

        Usage: screenrecord [options]

        Options:
          (no args)       Launch interactive menu
          -l, --list      List displays and windows
          -d <index>      Display index (default: 0)
          -t <seconds>    Auto-stop duration
          -f <fps>        Frame rate (default: 60)
          --no-audio      Disable system audio
          --mic           Enable microphone
          --clicks        Enable click highlighting
          --keys          Enable keystroke overlay
          --webcam        Enable webcam PIP
          -h, --help      Show this help

        Examples:
          screenrecord                  Interactive menu
          screenrecord -t 30            Record 30 seconds
          screenrecord --mic --clicks   With mic and clicks

        """)
        return
    }

    // Load saved settings or use defaults
    var config = RecordingConfig.loadDefault()

    if let idx = args.firstIndex(of: "-d"), idx + 1 < args.count {
        config.captureTarget = .display(Int(args[idx + 1]) ?? 0)
    }
    if let idx = args.firstIndex(of: "-f"), idx + 1 < args.count {
        config.frameRate = Int(args[idx + 1]) ?? 60
    }
    if args.contains("--no-audio") { config.captureSystemAudio = false }
    if args.contains("--mic") { config.captureMicrophone = true }
    if args.contains("--clicks") { config.highlightClicks = true }
    if args.contains("--keys") { config.showKeystrokes = true }
    if args.contains("--webcam") { config.enableWebcam = true }

    var duration: Int? = nil
    if let idx = args.firstIndex(of: "-t"), idx + 1 < args.count {
        duration = Int(args[idx + 1])
    }

    if args.contains("--list") || args.contains("-l") {
        let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        print("\n\(Terminal.green)Displays:\(Terminal.reset)")
        for (i, d) in (content?.displays ?? []).enumerated() {
            print("  [\(i)] \(d.width)x\(d.height)\(d.displayID == CGMainDisplayID() ? " (Main)" : "")")
        }
        print("\n\(Terminal.green)Windows:\(Terminal.reset)")
        for (i, w) in (content?.windows.filter { $0.isOnScreen }.prefix(10) ?? []).enumerated() {
            print("  [\(i)] \(w.owningApplication?.applicationName ?? "?") - \(w.title ?? "")")
        }
        return
    }

    guard checkPermissions() else {
        print("Requesting permission...")
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        return
    }

    let recorder = ScreenRecorder(config: config)

    do {
        try await recorder.startRecording()
        print("\n\(Terminal.red)\(Terminal.bold)RECORDING\(Terminal.reset)")
        print("Press Enter to stop...")

        if let duration = duration {
            print("Auto-stop in \(duration) seconds")
            try? await Task.sleep(nanoseconds: UInt64(duration) * 1_000_000_000)
        } else {
            _ = readLine()
        }

        await recorder.stopRecording()
        let stats = recorder.getStats()
        print("\n\(Terminal.green)Saved: \(stats.filePath)\(Terminal.reset)")

    } catch {
        print("\(Terminal.red)Error: \(error.localizedDescription)\(Terminal.reset)")
    }
}

// MARK: - Main

@available(macOS 13.0, *)
func main() async {
    if CommandLine.arguments.count > 1 {
        await runCLIMode()
    } else {
        let config = RecordingConfig()
        let menu = MenuSystem(config: config)
        await menu.showMainMenu()
    }
}

if #available(macOS 13.0, *) {
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        await main()
        semaphore.signal()
    }
    semaphore.wait()
} else {
    print("\(Terminal.red)Error: macOS 13.0 or later is required\(Terminal.reset)")
}
