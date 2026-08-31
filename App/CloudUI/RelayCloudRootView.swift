import AppCore
import Observation
import RelayCloudClient
import SwiftUI

public struct RelayCloudRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: RelayCloudModel

    public init(allowsLocalAgentHosting: Bool = false) {
        _model = State(initialValue: RelayCloudModel(allowsLocalAgentHosting: allowsLocalAgentHosting))
    }

    public var body: some View {
        Group {
            switch model.phase {
            case .checking:
                RelayCloudLoadingView()
            case .signedOut:
                RelayCloudOnboardingView(model: model)
            case .signedIn:
                RelayCloudWorkspaceView(model: model)
            }
        }
        .preferredColorScheme(.dark)
        .tint(CloudRelayTheme.ink)
        .task {
            await model.restore()
        }
        .onChange(of: scenePhase) {
            guard scenePhase == .active, model.phase == .signedIn else { return }
            Task { await model.syncOnce() }
        }
    }
}

private struct RelayCloudLoadingView: View {
    var body: some View {
        VStack(spacing: 18) {
            CloudRelayMark(size: 58)
            ProgressView()
                .controlSize(.small)
            Text("Opening your Relay")
                .font(.headline)
                .foregroundStyle(CloudRelayTheme.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CloudRelayTheme.canvas)
    }
}

private struct RelayCloudOnboardingView: View {
    @Bindable var model: RelayCloudModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 14) {
                    CloudRelayMark(size: 54)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AGENT RELAY")
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .tracking(1.4)
                        Text("One human. A room full of agents.")
                            .foregroundStyle(CloudRelayTheme.muted)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    Label("Private iCloud sync", systemImage: "icloud.fill")
                        .font(.headline)
                    Text("Your Mac and iPhone join automatically when they use the same Apple Account. Messages live in your private CloudKit database; Codex and ChatGPT credentials never leave each Mac.")
                        .foregroundStyle(CloudRelayTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Label("No server URL, invitation code, or Cloudflare bill", systemImage: "checkmark.shield.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(CloudRelayTheme.healthy)
                }
                .padding(16)
                .background(CloudRelayTheme.raised, in: RoundedRectangle(cornerRadius: 14))

                if let errorMessage = model.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(CloudRelayTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Task { await model.connectToICloud() }
                } label: {
                    HStack {
                        if model.isWorking { ProgressView().controlSize(.small) }
                        Text("Continue with iCloud")
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isWorking)

                Text("Agent Relay uses the Apple Account already signed in on this device. It cannot see your iCloud password or other iCloud data.")
                    .font(.caption)
                    .foregroundStyle(CloudRelayTheme.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 520)
            .padding(30)
            .background(CloudRelayTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(CloudRelayTheme.line, lineWidth: 1)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .background(CloudRelayTheme.canvas)
    }
}

private struct RelayCloudWorkspaceView: View {
    @Bindable var model: RelayCloudModel
    @State private var showingInvite = false
    @State private var showingSearch = false
    @State private var showingMembers = false
    @State private var showingSettings = false
    @State private var showingNewRoom = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                RelayWorkspaceIdentity(model: model)

                List(selection: $model.selectedRoomID) {
                    Section("Rooms") {
                        ForEach(model.rooms) { room in
                            RelayRoomSidebarRow(room: room, unreadCount: model.unreadCount(roomID: room.id))
                                .tag(room.id)
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)

                RelayConnectionFooter(model: model)
            }
            .background(CloudRelayTheme.sidebar)
            .toolbar {
                ToolbarItem {
                    Button { showingNewRoom = true } label: {
                        Label("New room", systemImage: "plus")
                    }
                }
            }
        } detail: {
            if let roomID = model.selectedRoomID,
               let room = model.rooms.first(where: { $0.id == roomID })
            {
                RelayCloudRoomView(model: model, room: room)
                    .id(roomID)
            } else {
                ContentUnavailableView(
                    "No room selected",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Choose a room to join the conversation.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(CloudRelayTheme.canvas)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup {
                Button { showingSearch = true } label: { Label("Search", systemImage: "magnifyingglass") }
                Button { showingMembers = true } label: { Label("Members", systemImage: "person.2") }
                if model.currentActor?.role == "owner" {
                    Button { showingInvite = true } label: { Label("Invite", systemImage: "person.badge.plus") }
                }
                Button { showingSettings = true } label: { Label("Settings", systemImage: "slider.horizontal.3") }
            }
        }
        .sheet(isPresented: $showingInvite) { RelayInviteView(model: model) }
        .sheet(isPresented: $showingSearch) { RelaySearchView(model: model) }
        .sheet(isPresented: $showingMembers) { RelayMembersView(model: model) }
        .sheet(isPresented: $showingSettings) { RelayCloudSettingsView(model: model) }
        .sheet(isPresented: $showingNewRoom) { RelayNewRoomView(model: model, isPresented: $showingNewRoom) }
    }
}

private struct RelayWorkspaceIdentity: View {
    let model: RelayCloudModel

    var body: some View {
        HStack(spacing: 11) {
            CloudRelayMark(size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.workspace?.name ?? "Agent Relay")
                    .font(.headline.weight(.black))
                    .lineLimit(1)
                Text("ONE HUMAN · MANY AGENTS")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(CloudRelayTheme.faint)
            }
            Spacer()
        }
        .padding(14)
        .overlay(alignment: .bottom) { Rectangle().fill(CloudRelayTheme.line).frame(height: 1) }
    }
}

private struct RelayRoomSidebarRow: View {
    let room: RelayCloudRoom
    let unreadCount: Int

    var body: some View {
        HStack(spacing: 9) {
            Text("#").font(.headline).foregroundStyle(CloudRelayTheme.faint)
            Text(room.title).lineLimit(1)
            Spacer()
            if unreadCount > 0 {
                Text(String(min(unreadCount, 99)))
                    .font(.caption2.monospacedDigit().bold())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .foregroundStyle(CloudRelayTheme.humanInk)
                    .background(CloudRelayTheme.humanBubble, in: Capsule())
            }
        }
    }
}

private struct RelayConnectionFooter: View {
    let model: RelayCloudModel

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.connectionState == .connected ? CloudRelayTheme.healthy : CloudRelayTheme.warning)
                .frame(width: 7, height: 7)
            Text(model.connectionState == .connected ? "Synced · private iCloud" : "Offline · cached")
                .font(.caption2.weight(.medium))
                .foregroundStyle(CloudRelayTheme.muted)
            Spacer()
        }
        .padding(14)
        .overlay(alignment: .top) { Rectangle().fill(CloudRelayTheme.line).frame(height: 1) }
    }
}

private struct RelayCloudRoomView: View {
    @Bindable var model: RelayCloudModel
    let room: RelayCloudRoom
    @State private var draft = ""
    @State private var replyTo: RelayCloudMessage?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("# \(room.title)").font(.headline.weight(.bold))
                    if !room.topic.isEmpty {
                        Text(room.topic).font(.caption).foregroundStyle(CloudRelayTheme.muted).lineLimit(1)
                    }
                }
                Spacer()
                Text("\(model.actors.count) members")
                    .font(.caption)
                    .foregroundStyle(CloudRelayTheme.faint)
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 58)
            .background(CloudRelayTheme.surface)

            Rectangle().fill(CloudRelayTheme.line).frame(height: 1)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(model.messages(in: room.id)) { message in
                            RelayCloudMessageRow(
                                message: message,
                                actor: model.actor(id: message.actorID),
                                replyMessage: model.messages(in: room.id).first { $0.id == message.replyToMessageID },
                                isHuman: message.actorID == model.currentActor?.id,
                                isOnline: model.isOnline(actorID: message.actorID),
                                onReply: { replyTo = message }
                            )
                            .id(message.id)
                        }
                    }
                    .padding(18)
                }
                .background(CloudRelayTheme.canvas)
                .onChange(of: model.messages(in: room.id).count) {
                    if let lastID = model.messages(in: room.id).last?.id {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(lastID, anchor: .bottom) }
                    }
                    Task { await model.markSelectedRoomRead() }
                }
                .task {
                    if let lastID = model.messages(in: room.id).last?.id {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                    await model.markSelectedRoomRead()
                }
            }

            RelayCloudComposer(
                model: model,
                draft: $draft,
                replyTo: $replyTo,
                roomID: room.id
            )
        }
    }
}

private struct RelayCloudMessageRow: View {
    let message: RelayCloudMessage
    let actor: RelayCloudActor?
    let replyMessage: RelayCloudMessage?
    let isHuman: Bool
    let isOnline: Bool
    let onReply: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if isHuman { Spacer(minLength: 44) }
            if !isHuman { RelayActorAvatar(actor: actor, isOnline: isOnline) }
            VStack(alignment: isHuman ? .trailing : .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(actor?.displayName ?? message.actorID)
                        .font(.caption.weight(.bold))
                    Text(message.createdAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(CloudRelayTheme.faint)
                }
                if let replyMessage {
                    Text("Replying to \(replyMessage.actorID): \(replyMessage.body)")
                        .font(.caption)
                        .foregroundStyle(isHuman ? Color.black.opacity(0.55) : CloudRelayTheme.muted)
                        .lineLimit(2)
                        .padding(.horizontal, 10)
                        .padding(.top, 8)
                }
                Text(message.body)
                    .textSelection(.enabled)
                    .font(.body)
                    .foregroundStyle(isHuman ? CloudRelayTheme.humanInk : CloudRelayTheme.ink)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .background(
                        isHuman ? CloudRelayTheme.humanBubble : CloudRelayTheme.raised,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .contextMenu {
                        Button("Reply", systemImage: "arrowshape.turn.up.left") { onReply() }
                    }
            }
            if !isHuman { Spacer(minLength: 44) }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct RelayActorAvatar: View {
    let actor: RelayCloudActor?
    let isOnline: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(actor?.type == .human ? Color.white : CloudRelayTheme.raised)
                .overlay {
                    Text(String((actor?.displayName ?? "A").prefix(1)).uppercased())
                        .font(.caption.bold())
                        .foregroundStyle(actor?.type == .human ? Color.black : Color.white)
                }
            Circle()
                .fill(isOnline ? CloudRelayTheme.healthy : CloudRelayTheme.faint)
                .frame(width: 9, height: 9)
                .overlay { Circle().stroke(CloudRelayTheme.canvas, lineWidth: 2) }
        }
        .frame(width: 34, height: 34)
    }
}

private struct RelayCloudComposer: View {
    @Bindable var model: RelayCloudModel
    @Binding var draft: String
    @Binding var replyTo: RelayCloudMessage?
    let roomID: String

    var body: some View {
        VStack(spacing: 8) {
            if let replyTo {
                HStack {
                    Image(systemName: "arrowshape.turn.up.left")
                    Text("Replying to \(replyTo.actorID)").font(.caption.weight(.semibold))
                    Spacer()
                    Button { self.replyTo = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                }
                .foregroundStyle(CloudRelayTheme.muted)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(model.actors.filter { $0.type == .agent }) { actor in
                        Button("@\(actor.id)") {
                            if !draft.isEmpty && !draft.hasSuffix(" ") { draft += " " }
                            draft += "@\(actor.id) "
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message #room or @mention an agent", text: $draft, axis: .vertical)
                    .lineLimit(1...6)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(CloudRelayTheme.raised, in: RoundedRectangle(cornerRadius: 13))
                    .onSubmit { send() }
                Button(action: send) {
                    if model.isWorking {
                        ProgressView().controlSize(.small).frame(width: 20, height: 20)
                    } else {
                        Image(systemName: "arrow.up").font(.headline.bold()).frame(width: 20, height: 20)
                    }
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .disabled(
                    draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || model.isWorking
                        || !model.canWrite
                )
            }
        }
        .padding(12)
        .background(CloudRelayTheme.surface)
        .overlay(alignment: .top) { Rectangle().fill(CloudRelayTheme.line).frame(height: 1) }
    }

    private func send() {
        let body = draft
        let replyID = replyTo?.id
        Task {
            if await model.send(body: body, roomID: roomID, replyToMessageID: replyID) {
                draft = ""
                replyTo = nil
            }
        }
    }
}

private struct RelayInviteView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: RelayCloudModel
    @State private var actorID = ""
    @State private var displayName = ""
    @State private var didAdd = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Add an agent identity") {
                    TextField("Agent ID, e.g. codex-design", text: $actorID)
                    TextField("Display name", text: $displayName)
                    Text("This makes the agent visible in rooms and @mentions. Open Agent Relay Host on the Mac that will run it to connect the local Codex worker.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Your other devices") {
                    Label("No invitation needed", systemImage: "icloud.and.arrow.down")
                    Text("Install Agent Relay and use the same Apple Account. The private workspace appears automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if didAdd {
                    Label("@\(actorID.lowercased()) added", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(CloudRelayTheme.healthy)
                }
                if let error = model.errorMessage {
                    Text(error).foregroundStyle(CloudRelayTheme.warning)
                }
            }
            .navigationTitle("People & agents")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add agent") {
                        Task {
                            if await model.addAgent(actorID: actorID, displayName: displayName) {
                                didAdd = true
                            }
                        }
                    }
                    .disabled(model.isWorking || actorID.isEmpty || displayName.isEmpty)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 360)
    }
}

private struct RelaySearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: RelayCloudModel
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List(model.searchResults) { message in
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.actor(id: message.actorID)?.displayName ?? message.actorID).font(.caption.bold())
                    Text(message.body).lineLimit(3)
                    Text(message.createdAt, style: .date).font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .searchable(text: $query, prompt: "Search every room")
            .onSubmit(of: .search) { Task { await model.search(query) } }
            .navigationTitle("Search")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
        .frame(minWidth: 500, minHeight: 460)
    }
}

private struct RelayMembersView: View {
    @Environment(\.dismiss) private var dismiss
    let model: RelayCloudModel

    var body: some View {
        NavigationStack {
            List(model.actors) { actor in
                HStack(spacing: 12) {
                    RelayActorAvatar(actor: actor, isOnline: model.isOnline(actorID: actor.id))
                    VStack(alignment: .leading) {
                        Text(actor.displayName).fontWeight(.semibold)
                        Text("@\(actor.id) · \(actor.type.rawValue)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if actor.role == "owner" { Text("OWNER").font(.caption2.bold()).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("People & agents")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
        .frame(minWidth: 420, minHeight: 420)
    }
}

private struct RelayCloudSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: RelayCloudModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    LabeledContent("Signed in as", value: model.currentActor?.displayName ?? "Unknown")
                    LabeledContent("Identity", value: "@\(model.currentActor?.id ?? "unknown")")
                    LabeledContent("Device", value: model.deviceName)
                }
                Section("Private iCloud") {
                    LabeledContent("Container", value: "iCloud.io.agentrelay.app")
                        .font(.caption)
                    Label(
                        model.connectionState == .connected ? "Connected" : "Offline · cached",
                        systemImage: model.connectionState == .connected ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath"
                    )
                    .foregroundStyle(model.connectionState == .connected ? CloudRelayTheme.healthy : CloudRelayTheme.warning)
                    Button("Sync now") { Task { await model.syncOnce() } }
                }
                #if os(macOS)
                if model.allowsLocalAgentHosting {
                    Section("Agents on this Mac") {
                        Button {
                            Task { await model.installLocalMacAgents() }
                        } label: {
                            if model.isWorking {
                                HStack {
                                    ProgressView().controlSize(.small)
                                    Text("Connecting agents…")
                                }
                            } else {
                                Label(
                                    model.localAgentsInstalled
                                        ? "Reconnect Main + Research"
                                        : "Connect Main + Research",
                                    systemImage: "cpu"
                                )
                            }
                        }
                        .disabled(model.isWorking || model.connectionState != .connected)

                        if let message = model.localAgentSetupMessage {
                            Label(message, systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(CloudRelayTheme.healthy)
                        } else {
                            Text("Workers use a durable local mailbox. Your Apple Account and ChatGPT credentials are never copied into agent configuration files.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if !model.localAgentIDs.isEmpty {
                            LabeledContent(
                                "Configured",
                                value: model.localAgentIDs.map { "@\($0)" }.joined(separator: ", ")
                            )
                            .font(.caption)
                        }

                        NavigationLink("Connect another agent") {
                            RelayLocalAgentSetupView(model: model)
                        }
                    }
                }
                #endif
                Section("About sync") {
                    Text("CloudKit sends silent change notifications and Agent Relay keeps a local cache for offline reading. There is no repeating cloud poll timer.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
        .frame(minWidth: 440, minHeight: 420)
    }
}

#if os(macOS)
private struct RelayLocalAgentSetupView: View {
    @Bindable var model: RelayCloudModel
    @State private var actorID = ""
    @State private var displayName = ""

    var body: some View {
        Form {
            TextField("Agent ID, e.g. codex-m5", text: $actorID)
            TextField("Display name", text: $displayName)
            Button("Connect on this Mac") {
                Task {
                    _ = await model.installLocalAgent(actorID: actorID, displayName: displayName)
                }
            }
            .disabled(actorID.isEmpty || displayName.isEmpty || model.isWorking)
            if let message = model.localAgentSetupMessage {
                Label(message, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(CloudRelayTheme.healthy)
            }
            if let error = model.errorMessage {
                Text(error).foregroundStyle(CloudRelayTheme.warning)
            }
        }
        .navigationTitle("Connect agent")
    }
}
#endif

private struct RelayNewRoomView: View {
    @Bindable var model: RelayCloudModel
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var topic = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Room name", text: $name)
                TextField("What belongs here?", text: $topic, axis: .vertical)
            }
            .navigationTitle("New room")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { isPresented = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            if await model.createRoom(name: name, topic: topic) { isPresented = false }
                        }
                    }
                    .disabled(name.isEmpty || model.isWorking)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 260)
    }
}
