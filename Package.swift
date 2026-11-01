// swift-tools-version:5.9
import PackageDescription

// The Co-Stanza feed in a terminal. Foundation only: it reads the public poems from api.jaybulb.com and prints them.
let package = Package(
    name: "costanza-tui",
    platforms: [.macOS(.v13)],
    targets: [.executableTarget(name: "costanza-tui", path: "tui")]
)
