// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShellCopy",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "ShellCopy", targets: ["ShellCopy"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(name: "ShellCopyCore"),
        .executableTarget(name: "ShellCopy", dependencies: [
            "ShellCopyCore", .product(name: "Sparkle", package: "Sparkle")
        ], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "ShellCopyCoreTests", dependencies: ["ShellCopyCore"]),
        .testTarget(name: "ShellCopyAppTests", dependencies: ["ShellCopy"])
    ]
)
