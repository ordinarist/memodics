// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Memodics",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "MemodicsCore", targets: ["MemodicsCore"]),
        .executable(name: "Memodics", targets: ["Memodics"]),
    ],
    targets: [
        .target(
            name: "MemodicsCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "Memodics",
            dependencies: ["MemodicsCore"]
        ),
        .testTarget(
            name: "MemodicsCoreTests",
            dependencies: ["MemodicsCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
