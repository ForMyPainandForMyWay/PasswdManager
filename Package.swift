// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PwdSafe",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "PwdSafe",
            path: "PwdSafe"
        ),
        .testTarget(
            name: "PwdSafeTests",
            dependencies: ["PwdSafe"],
            path: "PwdSafeTests"
        )
    ]
)