import AppCore
import Foundation
import Hummingbird

struct CreateHandoffRequest: Codable {
    let threadID: String
    let title: String
    let summary: String
    let ask: String
    let priority: HandoffPriority
    let createdBy: String
    let assignedTo: String
    let sourceRefs: [String]
}

struct UpdateHandoffRequest: Codable {
    let status: HandoffStatus
    let resolution: String?
}

public enum HandoffRoutes {
    public static func register(
        on router: Router<BasicRequestContext>,
        environment: AppEnvironment
    ) {
        router.get("threads/:threadID/handoffs") { request, context -> [Handoff] in
            try environment.requireAuthorization(for: request)
            let threadID = try context.parameters.require("threadID")
            return try environment.handoffRepository.list(threadID: threadID)
        }

        router.get("handoffs/:id") { request, context -> Handoff in
            try environment.requireAuthorization(for: request)
            let id = try context.parameters.require("id")
            guard let handoff = try environment.handoffRepository.get(id: id) else {
                throw HTTPError(.notFound, message: "Handoff not found")
            }
            return handoff
        }

        router.post("handoffs") { request, context -> Handoff in
            try environment.requireAuthorization(for: request)
            guard let payload = try? await request.decode(as: CreateHandoffRequest.self, context: context) else {
                throw HTTPError(.badRequest, message: "Invalid handoff payload")
            }
            guard let thread = try environment.threadRepository.get(id: payload.threadID) else {
                throw HTTPError(.notFound, message: "Thread not found")
            }

            let handoff = Handoff(
                id: UUID().uuidString.lowercased(),
                threadID: payload.threadID,
                title: payload.title,
                summary: payload.summary,
                ask: payload.ask,
                status: .open,
                priority: payload.priority,
                createdBy: payload.createdBy,
                assignedTo: payload.assignedTo,
                sourceRefs: payload.sourceRefs
            )

            try environment.handoffRepository.create(handoff)
            try environment.eventRepository.record(
                Event(
                    id: UUID().uuidString.lowercased(),
                    type: .handoffCreated,
                    projectID: thread.projectID,
                    threadID: thread.id,
                    handoffID: handoff.id,
                    actorID: payload.createdBy,
                    body: "Created handoff \(handoff.title)",
                    createdAt: Date()
                )
            )
            return handoff
        }

        router.put("handoffs/:id") { request, context -> Handoff in
            try environment.requireAuthorization(for: request)
            let id = try context.parameters.require("id")
            guard let payload = try? await request.decode(as: UpdateHandoffRequest.self, context: context) else {
                throw HTTPError(.badRequest, message: "Invalid handoff update payload")
            }
            guard var handoff = try environment.handoffRepository.get(id: id) else {
                throw HTTPError(.notFound, message: "Handoff not found")
            }

            try handoff.transition(to: payload.status)
            handoff.resolution = payload.resolution ?? handoff.resolution
            try environment.handoffRepository.update(handoff)

            let eventType: EventType
            switch payload.status {
            case .accepted:
                eventType = .handoffAccepted
            case .blocked:
                eventType = .handoffBlocked
            case .responded:
                eventType = .handoffResponded
            case .resolved:
                eventType = .handoffResolved
            case .open, .canceled:
                eventType = .messageAdded
            }

            let thread = try environment.threadRepository.get(id: handoff.threadID)
            try environment.eventRepository.record(
                Event(
                    id: UUID().uuidString.lowercased(),
                    type: eventType,
                    projectID: thread?.projectID,
                    threadID: handoff.threadID,
                    handoffID: handoff.id,
                    actorID: handoff.assignedTo,
                    body: "Updated handoff \(handoff.title) to \(handoff.status.rawValue)",
                    createdAt: Date()
                )
            )
            return handoff
        }
    }
}
