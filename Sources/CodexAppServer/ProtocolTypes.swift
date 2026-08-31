import Foundation

public struct AccountSummary: Equatable, Sendable {
    public enum AuthType: Equatable, Sendable {
        case chatGPT
        case apiKey
        case amazonBedrock
        case none
        case other(String)
    }

    public enum PlanType: Equatable, Sendable {
        case free
        case go
        case plus
        case pro
        case proLite
        case team
        case business
        case enterprise
        case education
        case other(String)

        init(rawValue: String) {
            switch rawValue {
            case "free": self = .free
            case "go": self = .go
            case "plus": self = .plus
            case "pro": self = .pro
            case "prolite": self = .proLite
            case "team": self = .team
            case "self_serve_business_prolite", "self_serve_business_usage_based", "business":
                self = .business
            case "ent26", "enterprise_cbp_automation", "enterprise_cbp_usage_based", "enterprise":
                self = .enterprise
            case "edu", "edu_plus", "edu_pro": self = .education
            default: self = .other(rawValue)
            }
        }
    }

    public let authType: AuthType
    public let planType: PlanType?
    public let requiresOpenAIAuthentication: Bool

    public init(
        authType: AuthType,
        planType: PlanType?,
        requiresOpenAIAuthentication: Bool
    ) {
        self.authType = authType
        self.planType = planType
        self.requiresOpenAIAuthentication = requiresOpenAIAuthentication
    }

    public var isChatGPTManaged: Bool {
        authType == .chatGPT
    }

    public var isPro: Bool {
        planType == .pro
    }
}

public struct CodexAppServerInfo: Equatable, Sendable {
    public let userAgent: String
    public let platformFamily: String
    public let platformOS: String

    public init(userAgent: String, platformFamily: String, platformOS: String) {
        self.userAgent = userAgent
        self.platformFamily = platformFamily
        self.platformOS = platformOS
    }
}

public enum CodexApprovalPolicy: String, Equatable, Sendable {
    case untrusted
    case onRequest = "on-request"
    case never
}

public enum CodexSandboxMode: String, Equatable, Sendable {
    case readOnly = "read-only"
    case workspaceWrite = "workspace-write"
    case dangerFullAccess = "danger-full-access"
}

/// Typed thread-level controls accepted by the Codex app-server protocol.
///
/// Callers that need a restricted session should set these explicitly rather
/// than inheriting a user's general Codex defaults.
public struct CodexThreadConfiguration: Equatable, Sendable {
    public let workingDirectory: URL?
    public let model: String?
    public let modelProvider: String?
    public let approvalPolicy: CodexApprovalPolicy?
    public let sandbox: CodexSandboxMode?
    public let developerInstructions: String?
    public let config: [String: JSONValue]?
    public let dynamicTools: [JSONValue]?
    public let environments: [JSONValue]?
    public let serviceName: String
    public let allowProviderModelFallback: Bool?

    public init(
        workingDirectory: URL? = nil,
        model: String? = nil,
        modelProvider: String? = nil,
        approvalPolicy: CodexApprovalPolicy? = nil,
        sandbox: CodexSandboxMode? = nil,
        developerInstructions: String? = nil,
        config: [String: JSONValue]? = nil,
        dynamicTools: [JSONValue]? = nil,
        environments: [JSONValue]? = nil,
        serviceName: String = "agent_relay",
        allowProviderModelFallback: Bool? = nil
    ) {
        self.workingDirectory = workingDirectory
        self.model = model
        self.modelProvider = modelProvider
        self.approvalPolicy = approvalPolicy
        self.sandbox = sandbox
        self.developerInstructions = developerInstructions
        self.config = config
        self.dynamicTools = dynamicTools
        self.environments = environments
        self.serviceName = serviceName
        self.allowProviderModelFallback = allowProviderModelFallback
    }
}

public struct CodexThreadSession: Equatable, Sendable {
    public let id: String
    public let model: String?
    public let workingDirectory: URL?

    public init(id: String, model: String? = nil, workingDirectory: URL? = nil) {
        self.id = id
        self.model = model
        self.workingDirectory = workingDirectory
    }
}

public struct CodexTurnHandle: Equatable, Hashable, Sendable {
    public let threadID: String
    public let turnID: String

    public init(threadID: String, turnID: String) {
        self.threadID = threadID
        self.turnID = turnID
    }
}

public struct CodexAgentMessage: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case commentary
        case finalAnswer
        case other(String)
    }

    public let id: String
    public let text: String
    public let phase: Phase?

    public init(id: String, text: String, phase: Phase? = nil) {
        self.id = id
        self.text = text
        self.phase = phase
    }
}

public enum CodexTurnStatus: String, Equatable, Sendable {
    case completed
    case interrupted
    case failed
    case inProgress
    case unknown
}

public struct CodexTurnResult: Equatable, Sendable {
    public let handle: CodexTurnHandle
    public let status: CodexTurnStatus
    public let agentMessages: [CodexAgentMessage]
    public let errorMessage: String?

    public init(
        handle: CodexTurnHandle,
        status: CodexTurnStatus,
        agentMessages: [CodexAgentMessage],
        errorMessage: String? = nil
    ) {
        self.handle = handle
        self.status = status
        self.agentMessages = agentMessages
        self.errorMessage = errorMessage
    }

    /// The authoritative final-answer message, falling back to all completed
    /// agent messages for older app-server versions that omit message phases.
    public var finalText: String {
        let finalMessages = agentMessages.filter { $0.phase == .finalAnswer }
        let selected = finalMessages.isEmpty ? agentMessages : finalMessages
        return selected.map(\.text).joined(separator: "\n\n")
    }
}

public struct CodexInteractionRequest: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case commandApproval
        case fileChangeApproval
        case permissionsApproval
        case userInput
        case mcpElicitation
        case unsupported(String)
    }

    public let requestID: JSONRPCID
    public let kind: Kind
    public let method: String
    public let threadID: String?
    public let turnID: String?
    public let parameters: JSONValue

    public init(
        requestID: JSONRPCID,
        kind: Kind,
        method: String,
        threadID: String?,
        turnID: String?,
        parameters: JSONValue
    ) {
        self.requestID = requestID
        self.kind = kind
        self.method = method
        self.threadID = threadID
        self.turnID = turnID
        self.parameters = parameters
    }
}

public enum CodexApprovalDecision: String, Equatable, Sendable {
    case accept
    case acceptForSession
    case decline
    case cancel
}

public enum CodexTurnEvent: Equatable, Sendable {
    case started(CodexTurnHandle)
    case agentMessageDelta(itemID: String, delta: String)
    case agentMessageCompleted(CodexAgentMessage)
    case interactionRequired(CodexInteractionRequest)
    case completed(CodexTurnResult)
}

public enum CodexAppServerEvent: Equatable, Sendable {
    case accountUpdated(AccountSummary)
    case interactionRequired(CodexInteractionRequest)
    case notification(method: String, parameters: JSONValue)
    case connectionClosed(message: String)
}

public enum CodexAppServerError: Error, Equatable, Sendable {
    case invalidState(String)
    case invalidResponse(method: String, reason: String)
    case remote(code: Int, message: String, data: JSONValue?)
    case connectionClosed(String)
    case requestTimedOut(String)
    case chatGPTManagedAuthenticationRequired(actual: AccountSummary.AuthType)
    case unknownInteraction(JSONRPCID)
}

extension CodexAppServerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .invalidState(message):
            message
        case let .invalidResponse(method, reason):
            "Invalid \(method) response: \(reason)"
        case let .remote(code, message, _):
            "Codex app-server error \(code): \(message)"
        case let .connectionClosed(message):
            "Codex app-server connection closed: \(message)"
        case let .requestTimedOut(method):
            "Codex app-server request timed out: \(method)"
        case let .chatGPTManagedAuthenticationRequired(actual):
            "ChatGPT-managed Codex authentication is required; current auth is \(actual)."
        case let .unknownInteraction(id):
            "The Codex interaction request is no longer pending: \(id)."
        }
    }
}
