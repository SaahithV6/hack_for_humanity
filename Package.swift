// swift-tools-version: 5.9
import PackageDescription

// The engine is plain Swift with no Apple-framework imports, so it builds and
// tests on Linux as well as in the iOS app. Moth.xcodeproj compiles the exact
// same files directly into the app target -- one source of truth, no linking.
let package = Package(
    name: "MothEngine",
    products: [
        .library(name: "MothEngine", targets: ["MothEngine"]),
        .executable(name: "mothdemo", targets: ["mothdemo"]),
    ],
    targets: [
        .target(name: "MothEngine"),
        .executableTarget(name: "mothdemo", dependencies: ["MothEngine"]),
        .testTarget(name: "MothEngineTests", dependencies: ["MothEngine"]),
    ]
)
