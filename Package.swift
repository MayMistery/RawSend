// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RawSend",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/finnvoor/FindFaster.git", exact: "1.1.1"),
    ],
    targets: [
        .executableTarget(
            name: "RawSend",
            dependencies: [
                .product(name: "FindFaster", package: "FindFaster"),
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "RawSendTests",
            dependencies: ["RawSend"],
            path: "Tests/RawSendTests",
            swiftSettings: [
                .unsafeFlags(["-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
                ])
            ]
        )
    ]
)
