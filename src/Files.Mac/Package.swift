// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacFiles",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MacFiles", targets: ["FilesApp"])],
    targets: [
        .target(name: "CArchive", publicHeadersPath: "include", linkerSettings: [.linkedLibrary("archive")]),
        .target(name: "FilesShared"),
        .target(name: "FilesStorage", dependencies: ["FilesShared", "CArchive"]),
        .executableTarget(name: "FilesApp", dependencies: ["FilesShared", "FilesStorage"],
                          resources: [.process("Resources")]),
        .testTarget(name: "FilesStorageTests", dependencies: ["FilesShared", "FilesStorage", "FilesApp"], resources: [.copy("Fixtures")])
    ],
    swiftLanguageModes: [.v5]
)
