import AppCore
import CoreStore
import Foundation
import Hummingbird

struct CreateThreadRequest: Codable {
    let projectID: String
    let title: String
    let intentType: ThreadIntentType
    let createdBy: String
    let assignedActorIDs: [String]
}

public enum ThreadRoutes {
    public static func register(
        on router: Router<BasicRequestContext>,
        environment: AppEnvironment
    ) {
        router.get("projects/:projectID/threads") { request, context -> [AppCore.Thread] in
            try environment.requireAuthorization(for: request)
            let projectID = try context.parameters.require("projectID")
            return try environment.threadRepository.list(projectID: projectID)
        }

        router.get("threads/:threadID") { request, context -> AppCore.Thread in
            try environment.requireAuthorization(for: request)
            let threadID = try context.parameters.require("threadID")
            guard let thread = try environment.threadRepository.get(id: threadID) else {
                throw HTTPError(.notFound, message: "Thread not found")
            }
            return thread
        }

        router.get("threads/:threadID/context") { request, context -> ThreadContext in
            try environment.requireAuthorization(for: request)
            let threadID = try context.parameters.require("threadID")
            let mode = request.uri.queryParameters["mode"]
                .map { String($0) }
                .flatMap { ThreadContextMode(rawValue: $0) }
                ?? ThreadContextMode.recent
            return try environment.inboxRepository.threadContext(threadID: threadID, mode: mode)
        }

        router.post("threads") { request, context -> AppCore.Thread in
            try environment.requireAuthorization(for: request)
            guard let payload = try? await request.decode(as: CreateThreadRequest.self, context: context) else {
                throw HTTPError(.badRequest, message: "Invalid thread payload")
            }
            guard try environment.projectRepository.get(id: payload.projectID) != nil else {
                throw HTTPError(.notFound, message: "Project not found")
            }

            let thread = AppCore.Thread(
                id: UUID().uuidString.lowercased(),
                projectID: payload.projectID,
                title: payload.title,
                intentType: payload.intentType,
                status: .active,
                createdBy: payload.createdBy,
                assignedActorIDs: payload.assignedActorIDs,
                updatedAt: Date()
            )
            try environment.threadRepository.create(thread)
            return thread
        }
    }
}
