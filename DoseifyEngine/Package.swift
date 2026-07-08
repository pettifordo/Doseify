// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DoseifyEngine",
    platforms: [.iOS(.v17), .macOS(.v14), .watchOS(.v10)],
    products: [
        .library(name: "DoseifyEngine", targets: ["DoseifyEngine"]),
    ],
    targets: [
        .target(name: "DoseifyEngine"),
        .testTarget(
            name: "DoseifyEngineTests",
            dependencies: ["DoseifyEngine"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
