import AppCore
import Foundation
import Hummingbird

struct CreateProjectRequest: Codable {
    let title: String
    let summary: String
}

public enum ProjectRoutes {
    public static func register(
        on router: Router<BasicRequestContext>,
        environment: AppEnvironment
    ) {
        router.get("projects") { request, _ -> [Project] in
            try environment.requireAuthorization(for: request)
            return try environment.projectRepository.list()
        }

        router.post("projects") { request, context -> Project in
            try environment.requireAuthorization(for: request)
            guard let payload = try? await request.decode(as: CreateProjectRequest.self, context: context) else {
                throw HTTPError(.badRequest, message: "Invalid project payload")
            }

            let timestamp = Date()
            let project = Project(
                id: UUID().uuidString.lowercased(),
                title: payload.title,
                summary: payload.summary,
                status: .active,
                createdAt: timestamp,
                updatedAt: timestamp
            )
            try environment.projectRepository.create(project)
            return project
        }
    }
}
