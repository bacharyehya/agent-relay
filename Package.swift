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
        .target(
            name: "MacAppSupport",
            dependencies: ["AppCore"],
            path: "App/MacApp",
            exclude: ["AgentRelayMacApp.swift"]
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
        .testTarget(
            name: "CoreAPITests",
            dependencies: [
                "AppCore",
                "CoreAPI",
                "CoreStore",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdTesting", package: "hummingbird"),
            ]
        ),
        .testTarget(
            name: "MCPAdapterTests",
            dependencies: [
                "AppCore",
                "MCPAdapter",
            ]
        ),
        .testTarget(
            name: "MacAppTests",
            dependencies: [
                "AppCore",
                "MacAppSupport",
            ]
        ),
        .testTarget(
            name: "IntegrationTests",
            dependencies: [
                "AppCore",
                "CoreAPI",
                "CoreStore",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdTesting", package: "hummingbird"),
            ]
        ),
    ]
)
