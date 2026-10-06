// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MeToDo",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "MeToDoCore"),
        .testTarget(name: "MeToDoCoreTests", dependencies: ["MeToDoCore"]),
    ],
    // ponytail: Swift 5 mode skips strict-concurrency ceremony around AppKit/UserNotifications delegates; move to .v6 if the app ever does real background work.
    swiftLanguageModes: [.v5]
)
