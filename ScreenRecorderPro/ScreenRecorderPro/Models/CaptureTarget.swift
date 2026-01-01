//
//  CaptureTarget.swift
//  ScreenRecorderPro
//

import Foundation
import ScreenCaptureKit

/// Represents what content to capture
enum CaptureTarget: Equatable, Hashable {
    case display(displayID: CGDirectDisplayID)
    case window(windowID: CGWindowID)
    case area(rect: CGRect, displayID: CGDirectDisplayID)

    var displayID: CGDirectDisplayID? {
        switch self {
        case .display(let id):
            return id
        case .area(_, let id):
            return id
        case .window:
            return nil
        }
    }

    var windowID: CGWindowID? {
        if case .window(let id) = self {
            return id
        }
        return nil
    }

    var description: String {
        switch self {
        case .display:
            return "Full Screen"
        case .window:
            return "Window"
        case .area:
            return "Custom Area"
        }
    }
}

/// Wrapper for SCDisplay with Identifiable conformance
struct DisplayInfo: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let display: SCDisplay
    let name: String
    let frame: CGRect
    let isMain: Bool

    init(display: SCDisplay) {
        self.id = display.displayID
        self.display = display
        self.frame = CGRect(x: 0, y: 0, width: display.width, height: display.height)
        self.isMain = display.displayID == CGMainDisplayID()

        // Get display name
        if let name = Self.getDisplayName(for: display.displayID) {
            self.name = name
        } else {
            self.name = isMain ? "Main Display" : "Display \(display.displayID)"
        }
    }

    private static func getDisplayName(for displayID: CGDirectDisplayID) -> String? {
        // Try to get display name from IOKit
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IODisplayConnect")

        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == kIOReturnSuccess else {
            return nil
        }

        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let info = IODisplayCreateInfoDictionary(service, IOOptionBits(kIODisplayOnlyPreferredName)).takeRetainedValue() as? [String: Any],
               let names = info[kDisplayProductName] as? [String: String],
               let name = names.values.first {
                IOObjectRelease(service)
                return name
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }

        return nil
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: DisplayInfo, rhs: DisplayInfo) -> Bool {
        lhs.id == rhs.id
    }
}

/// Wrapper for SCWindow with Identifiable conformance
struct WindowInfo: Identifiable, Hashable {
    let id: CGWindowID
    let window: SCWindow
    let title: String
    let appName: String
    let bundleID: String?
    let frame: CGRect
    let isOnScreen: Bool

    init(window: SCWindow) {
        self.id = window.windowID
        self.window = window
        self.title = window.title ?? "Untitled"
        self.appName = window.owningApplication?.applicationName ?? "Unknown"
        self.bundleID = window.owningApplication?.bundleIdentifier
        self.frame = window.frame
        self.isOnScreen = window.isOnScreen
    }

    var displayName: String {
        if title.isEmpty {
            return appName
        }
        return "\(appName) - \(title)"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: WindowInfo, rhs: WindowInfo) -> Bool {
        lhs.id == rhs.id
    }
}
