#!/usr/bin/swift

import Cocoa

// App Icon Generator for ScreenRecorderPro
// Run with: swift generate_icon.swift

let sizes: [(size: Int, scale: Int, name: String)] = [
    (16, 1, "icon_16x16.png"),
    (16, 2, "icon_16x16@2x.png"),
    (32, 1, "icon_32x32.png"),
    (32, 2, "icon_32x32@2x.png"),
    (128, 1, "icon_128x128.png"),
    (128, 2, "icon_128x128@2x.png"),
    (256, 1, "icon_256x256.png"),
    (256, 2, "icon_256x256@2x.png"),
    (512, 1, "icon_512x512.png"),
    (512, 2, "icon_512x512@2x.png")
]

func createIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))

    image.lockFocus()

    // Background - rounded rectangle with gradient
    let bgRect = NSRect(x: size * 0.05, y: size * 0.05, width: size * 0.9, height: size * 0.9)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: size * 0.2, yRadius: size * 0.2)

    // Gradient background (dark blue to purple)
    let gradient = NSGradient(colors: [
        NSColor(red: 0.2, green: 0.1, blue: 0.4, alpha: 1.0),
        NSColor(red: 0.4, green: 0.2, blue: 0.5, alpha: 1.0),
        NSColor(red: 0.3, green: 0.15, blue: 0.45, alpha: 1.0)
    ], atLocations: [0.0, 0.5, 1.0], colorSpace: .deviceRGB)!

    gradient.draw(in: bgPath, angle: -45)

    // Add subtle border
    NSColor(white: 1.0, alpha: 0.1).setStroke()
    bgPath.lineWidth = size * 0.01
    bgPath.stroke()

    // Draw record button (red circle)
    let recordSize = size * 0.35
    let recordX = size * 0.5 - recordSize * 0.5
    let recordY = size * 0.5 - recordSize * 0.5 + size * 0.05
    let recordRect = NSRect(x: recordX, y: recordY, width: recordSize, height: recordSize)
    let recordPath = NSBezierPath(ovalIn: recordRect)

    // Red gradient for record button
    let redGradient = NSGradient(colors: [
        NSColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 1.0),
        NSColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1.0)
    ], atLocations: [0.0, 1.0], colorSpace: .deviceRGB)!

    redGradient.draw(in: recordPath, angle: -45)

    // Add glow effect to record button
    let glowPath = NSBezierPath(ovalIn: recordRect.insetBy(dx: -size * 0.02, dy: -size * 0.02))
    NSColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 0.3).setStroke()
    glowPath.lineWidth = size * 0.02
    glowPath.stroke()

    // Draw screen frame
    let screenWidth = size * 0.6
    let screenHeight = size * 0.4
    let screenX = size * 0.5 - screenWidth * 0.5
    let screenY = size * 0.25
    let screenRect = NSRect(x: screenX, y: screenY, width: screenWidth, height: screenHeight)
    let screenPath = NSBezierPath(roundedRect: screenRect, xRadius: size * 0.03, yRadius: size * 0.03)

    // Screen border
    NSColor(white: 0.9, alpha: 0.8).setStroke()
    screenPath.lineWidth = size * 0.025
    screenPath.stroke()

    // Screen inner glow
    let innerScreenRect = screenRect.insetBy(dx: size * 0.02, dy: size * 0.02)
    let innerScreenPath = NSBezierPath(roundedRect: innerScreenRect, xRadius: size * 0.02, yRadius: size * 0.02)
    NSColor(white: 1.0, alpha: 0.1).setFill()
    innerScreenPath.fill()

    // Draw play triangle inside screen (representing recording)
    let trianglePath = NSBezierPath()
    let triSize = size * 0.1
    let triX = size * 0.5
    let triY = size * 0.45
    trianglePath.move(to: NSPoint(x: triX - triSize * 0.5, y: triY - triSize * 0.6))
    trianglePath.line(to: NSPoint(x: triX - triSize * 0.5, y: triY + triSize * 0.6))
    trianglePath.line(to: NSPoint(x: triX + triSize * 0.6, y: triY))
    trianglePath.close()

    NSColor(white: 1.0, alpha: 0.9).setFill()
    trianglePath.fill()

    image.unlockFocus()

    return image
}

func saveIcon(_ image: NSImage, to path: String, pixelSize: Int) {
    let size = CGFloat(pixelSize)
    let newImage = NSImage(size: NSSize(width: size, height: size))

    newImage.lockFocus()
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
               from: NSRect(origin: .zero, size: image.size),
               operation: .copy,
               fraction: 1.0)
    newImage.unlockFocus()

    guard let tiffData = newImage.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to create PNG for \(path)")
        return
    }

    do {
        try pngData.write(to: URL(fileURLWithPath: path))
        print("Created: \(path)")
    } catch {
        print("Failed to write \(path): \(error)")
    }
}

// Main execution - use absolute path
let iconsetPath = "/Users/lee/ClaudeCode/record screen/ScreenRecorderPro/ScreenRecorderPro/Resources/Assets.xcassets/AppIcon.appiconset"

print("Generating app icons...")
print("Output directory: \(iconsetPath)")

// Create the master icon at high resolution
let masterIcon = createIcon(size: 1024)

// Generate all sizes
for (size, scale, name) in sizes {
    let pixelSize = size * scale
    let outputPath = "\(iconsetPath)/\(name)"
    saveIcon(masterIcon, to: outputPath, pixelSize: pixelSize)
}

print("\nDone! Icons generated successfully.")
