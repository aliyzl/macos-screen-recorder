// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "ScreenRecorderCLI",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "screenrecord",
            path: "Sources"
        )
    ]
)
