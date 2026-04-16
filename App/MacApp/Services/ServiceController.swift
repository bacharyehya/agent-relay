import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class ServiceController {
    enum Storage {
        case inMemory
        case userDefaults(UserDefaults)

        static var standard: Storage {
            .userDefaults(.standard)
        }
    }

    var agentAccessPaused = false
    var launchAtLoginEnabled = false

    private let pauseStore: any PauseStateStoring
    private let appService: any LaunchServiceControlling

    init(
        storage: Storage = .standard,
        appService: any LaunchServiceControlling = MainAppLaunchService()
    ) {
        self.pauseStore = switch storage {
        case .inMemory:
            InMemoryPauseStateStore()
        case let .userDefaults(userDefaults):
            UserDefaultsPauseStateStore(userDefaults: userDefaults)
        }
        self.appService = appService
        self.agentAccessPaused = pauseStore.isPaused()
        self.launchAtLoginEnabled = appService.status == .enabled
    }

    func refresh() async {
        agentAccessPaused = pauseStore.isPaused()
        launchAtLoginEnabled = appService.status == .enabled
    }

    func setAgentAccessPaused(_ paused: Bool) async throws {
        pauseStore.setPaused(paused)
        agentAccessPaused = paused
    }

    func isAgentAccessPaused() async throws -> Bool {
        let paused = pauseStore.isPaused()
        agentAccessPaused = paused
        return paused
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) async throws {
        if enabled {
            try appService.register()
        } else {
            try appService.unregister()
        }
        launchAtLoginEnabled = appService.status == .enabled
    }
}

private protocol PauseStateStoring {
    func isPaused() -> Bool
    func setPaused(_ paused: Bool)
}

private final class InMemoryPauseStateStore: PauseStateStoring {
    private var paused = false

    func isPaused() -> Bool {
        paused
    }

    func setPaused(_ paused: Bool) {
        self.paused = paused
    }
}

private struct UserDefaultsPauseStateStore: PauseStateStoring {
    private let userDefaults: UserDefaults
    private let key = "agentAccessPaused"

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    func isPaused() -> Bool {
        userDefaults.bool(forKey: key)
    }

    func setPaused(_ paused: Bool) {
        userDefaults.set(paused, forKey: key)
    }
}

protocol LaunchServiceControlling {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

struct MainAppLaunchService: LaunchServiceControlling {
    private let service = SMAppService.mainApp

    var status: SMAppService.Status {
        service.status
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }
}
