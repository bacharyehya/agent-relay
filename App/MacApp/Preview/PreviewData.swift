import Foundation

enum PreviewData {
    @MainActor
    static func makeAppModel() -> AppModel {
        AppModel(client: PreviewAppAPIClient())
    }
}

private struct PreviewAppAPIClient: AppAPIClientProtocol {
    func fetchHealth() async throws -> AppHealth {
        AppHealth(status: "ok")
    }
}
