// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShellCopy",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "ShellCopy", targets: ["ShellCopy"])],
    targets: [
        .target(name: "ShellCopyCore"),
        .executableTarget(name: "ShellCopy", dependencies: ["ShellCopyCore"]),
        .testTarget(name: "ShellCopyCoreTests", dependencies: ["ShellCopyCore"]),
        .testTarget(name: "ShellCopyAppTests", dependencies: ["ShellCopy"])
    ]
)
