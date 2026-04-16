import Hummingbird

public struct HealthResponse: ResponseCodable {
    public let status: String

    public init(status: String) {
        self.status = status
    }
}

public enum HealthRoutes {
    public static func register(on router: Router<BasicRequestContext>) {
        router.get("health") { _, _ in
            HealthResponse(status: "ok")
        }
    }
}
