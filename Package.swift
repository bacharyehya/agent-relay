// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentRelay",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "AppCore", targets: ["AppCore"]),
        .library(name: "CodexAppServer", targets: ["CodexAppServer"]),
        .library(name: "RelayCloudClient", targets: ["RelayCloudClient"]),
        .library(name: "RelayCloudKit", targets: ["RelayCloudKit"]),
        .library(name: "RelayCloudUI", targets: ["RelayCloudUI"]),
        .executable(name: "CoreService", targets: ["CoreService"]),
        .executable(name: "MCPAdapter", targets: ["MCPAdapter"]),
        .executable(name: "CodexRelayWorker", targets: ["CodexRelayWorker"]),
        .executable(name: "AgentRelayDesktop", targets: ["AgentRelayDesktop"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.29.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.7.0"),
    ],
    targets: [
        .target(name: "AppCore"),
        .target(name: "CodexAppServer"),
        .target(
            name: "RelayCloudClient",
            dependencies: ["AppCore"]
        ),
        .target(
            name: "RelayCloudKit",
            dependencies: ["AppCore", "RelayCloudClient"]
        ),
        .target(
            name: "RelayCloudUI",
            dependencies: ["AppCore", "RelayCloudClient", "RelayCloudKit"],
            path: "App/CloudUI"
        ),
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
            dependencies: ["AppCore", "RelayCloudClient", "RelayCloudUI"],
            path: "App/MacApp",
            exclude: ["AgentRelayMacApp.swift"]
        ),
        .executableTarget(name: "CoreService", dependencies: ["CoreAPI"]),
        .executableTarget(name: "MCPAdapter", dependencies: ["AppCore"]),
        .executableTarget(
            name: "CodexRelayWorker",
            dependencies: ["AppCore", "CodexAppServer", "RelayCloudClient", "RelayCloudKit"]
        ),
        .executableTarget(
            name: "AgentRelayDesktop",
            dependencies: ["MacAppSupport", "RelayCloudClient", "RelayCloudKit"]
        ),
        .testTarget(name: "AppCoreTests", dependencies: ["AppCore"]),
        .testTarget(name: "RelayCloudClientTests", dependencies: ["RelayCloudClient"]),
        .testTarget(name: "RelayCloudKitTests", dependencies: ["RelayCloudKit"]),
        .testTarget(name: "RelayCloudUITests", dependencies: ["RelayCloudUI"]),
        .testTarget(name: "CodexAppServerTests", dependencies: ["CodexAppServer"]),
        .testTarget(
            name: "CodexRelayWorkerTests",
            dependencies: ["AppCore", "CodexAppServer", "CodexRelayWorker"]
        ),
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
