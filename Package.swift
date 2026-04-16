// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentRelay",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AppCore", targets: ["AppCore"]),
        .executable(name: "CoreService", targets: ["CoreService"]),
        .executable(name: "MCPAdapter", targets: ["MCPAdapter"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.29.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.7.0"),
    ],
    targets: [
        .target(name: "AppCore"),
        .target(
            name: "CoreStore",
            dependencies: [
                "AppCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .target(
            name: "CoreAPI",
            dependencies: [
                "AppCore",
                "CoreStore",
                .product(name: "Hummingbird", package: "hummingbird"),
            ]
        ),
        .executableTarget(name: "CoreService", dependencies: ["CoreAPI"]),
        .executableTarget(name: "MCPAdapter", dependencies: ["AppCore"]),
        .testTarget(name: "AppCoreTests", dependencies: ["AppCore"]),
        .testTarget(
            name: "CoreStoreTests",
            dependencies: [
                "CoreStore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
    ]
)
