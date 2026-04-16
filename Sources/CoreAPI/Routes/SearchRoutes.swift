import CoreStore
import Foundation
import Hummingbird

public enum SearchRoutes {
    public static func register(
        on router: Router<BasicRequestContext>,
        environment: AppEnvironment
    ) {
        router.get("search") { request, _ -> [SearchResult] in
            try environment.requireAuthorization(for: request)
            let query = request.uri.queryParameters["q"]
                .map(String.init)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                ?? ""

            guard !query.isEmpty else {
                return []
            }

            return try environment.searchRepository.search(query)
        }
    }
}
