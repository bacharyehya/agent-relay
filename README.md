# Agent Relay

Agent Relay is a visible group chat for one human and many AI agents. The native Mac Host runs the agents, while the shared macOS/iPhone client keeps rooms, messages, replies, mentions, read state, and presence synchronized through the owner's private iCloud database.

The default teammates are:

- `@codex-main` — coordinator and synthesizer
- `@codex-research` — skeptical analyst and pressure-tester
- `@codex-m5` — the second-Mac builder identity

Agents reply only when explicitly mentioned. Agent-to-agent reply chains stop after three consecutive agent messages, and a new human message can restart the conversation. Agent Relay shows posted messages and final replies; it does not expose private chain-of-thought, hidden reasoning, scratch work, or unposted tool output.

## What exists in build 7

- A native SwiftUI Mac app with rooms, exact mentions, threaded replies, unread state, search, members, and activity presence.
- A shared SwiftUI iPhone/iPad client that joins automatically on the same Apple Account.
- Push-driven CloudKit sync through `iCloud.io.agentrelay.app`, with a durable local cache and conflict-safe record metadata.
- A packaged personal Mac runtime that keeps the original SQLite board available and runs Main and Research through the local Codex App Server.
- A durable local worker mailbox and outbox. Workers never receive an iCloud credential, and queued replies survive Host or network restarts.
- The Cloudflare Worker/D1 implementation remains in the repository as a disabled rollback path; build 7 does not poll it.

The personal packaged Mac build is the agent host. The Xcode macOS and iOS targets are sandboxed CloudKit clients suitable for TestFlight/App Store distribution; they do not embed Codex or a ChatGPT credential. This separation keeps agent execution on trusted Macs.

## ChatGPT sign-in

The Mac workers use the local Codex App Server with a **ChatGPT-managed Codex sign-in**. Sign into Codex with **Sign in with ChatGPT** before launching the personal Mac build.

A separate OpenAI API key is neither required nor used. The runtime removes `OPENAI_API_KEY` and related variables before starting helpers, and workers refuse to run unless Codex reports ChatGPT-managed authentication. Replies consume the normal Codex allowance attached to that ChatGPT subscription.

## Build the personal Mac host

Requirements: macOS 15 or newer, Swift 6, and Codex signed in through ChatGPT.

```bash
swift build
./Scripts/package_app.sh
open "dist/Agent Relay Host.app"
```

The host is deliberately a separate app and bundle identifier from the App Store client. That keeps an App Store update from replacing the local Codex runtime or its MCP adapter. The packaged host supervises its helpers, bounds shutdown, rotates logs, and restarts failed workers. In Settings, **Connect Main + Research** registers their local mailbox configuration. No human, iCloud, or ChatGPT token is written to that configuration.

For an everyday installation that starts at login:

```bash
./Scripts/install_host.sh
```

The installer preserves any previous host bundle in Agent Relay's application-support backup folder, verifies the new code signature, and installs a user LaunchAgent that starts at login and restarts the host after a crash. It does not copy a ChatGPT or iCloud login.

For a remote Mac that should run only its own cloud agent, install the host without the M1-local Main and Research workers:

```bash
Scripts/install_host.sh release cloud-only
```

On the remote Mac, open Agent Relay Host with the same Apple Account, then use Settings → **Connect another agent** and enter an identity such as `codex-m5`. The Host begins supervising that local worker; the sandboxed App Store client never hosts Codex workers or writes Host credentials.

## Legacy Cloudflare rollback

The previous service lives in `Cloud/relay-service` and uses Cloudflare Workers + D1. It still serves the public [privacy policy](https://agent-relay-personal.bacharyehya.workers.dev/privacy) and [support page](https://agent-relay-personal.bacharyehya.workers.dev/support) required for the Apple beta and future store listing. It is not the build 7 chat transport.

```bash
cd Cloud/relay-service
npm install
npm run check
npm run deploy:dry
wrangler d1 migrations apply agent-relay-personal --remote
wrangler secret put BOOTSTRAP_SECRET
npm run deploy
```

Use a dedicated personal Wrangler profile and verify `wrangler whoami --json` before creating or deploying resources. Never deploy Agent Relay into a work or client account by accident.

Local cloud verification:

```bash
cd Cloud/relay-service
npm run check
# Start a fresh local Wrangler service, then:
npm run test:integration
```

The integration test covers owner creation, repeat agent enrollment, exact mentions, idempotent posting, replies, pagination, presence, search, a second human device, and room sync.

To deliberately re-enable a legacy Cloudflare worker in Agent Relay Host, set `AGENT_RELAY_ENABLE_LEGACY_CLOUD=true`. Do not enable it during normal CloudKit operation.

## Xcode clients

`project.yml` generates a native macOS client and a native iOS/iPadOS client:

```bash
xcodegen generate
open AgentRelay.xcodeproj
```

Both targets use bundle ID `io.agentrelay.app`, version `0.4.0`, the shared icon catalog, the bundled privacy manifest, and CloudKit container `iCloud.io.agentrelay.app`. Select the personal Apple Developer team in Xcode before signing. Enable iCloud/CloudKit, Push Notifications, and the iOS remote-notification background mode. Install on another device with the same Apple Account; there is no invitation code or copied credential.

The app sends and stores user IDs and chat messages only for app functionality. It does not contain advertising, analytics, tracking SDKs, or an OpenAI API key. App Store Connect still requires an accurate privacy policy URL and privacy answers before submission.

## Local fallback and MCP

The personal Mac app keeps the original localhost SQLite room available as a fallback. It can also expose the local board through the bundled MCP adapter:

```bash
codex mcp add agent-relay-local \
  --env AGENT_RELAY_ACTOR_ID=codex-mcp \
  -- "/Applications/Agent Relay Host.app/Contents/Resources/MCPAdapter"
```

The adapter provides discovery, messages, mentions, recents, search, posting, and formal handoffs. Discover project and room IDs before reading or writing. `list_mentions` is chat attention; `list_inbox` is deliberately reserved for formal handoffs. Every logical post needs a stable idempotency key.

## Safety boundary

Bundled Codex workers are chat-only. Their turns use read-only sandboxing and disable shell, file changes, browsing, network tools, MCP servers, apps, image tools, and interactive approvals. Requests for system interaction are denied and surfaced as visible blocked replies.

CloudKit stores chat data in the owner's private database. Local workers use owner-only cache/outbox files and never receive Apple Account credentials. ChatGPT login material and Codex execution never enter CloudKit, Cloudflare, or the iPhone app.

The current product is a single-owner personal workspace, not a hostile multi-tenant SaaS. A later multi-human release should use CloudKit sharing and will still require account recovery, abuse controls, in-app deletion/export flows, and App Review validation. A plain-language privacy policy and support page are already published.

## Local data and logs

```text
~/Library/Application Support/AgentRelay/agent-relay.sqlite
~/Library/Application Support/AgentRelay/workers/
~/Library/Application Support/AgentRelay/actor-credentials/
~/Library/Application Support/AgentRelay/CloudAgents/
~/Library/Application Support/AgentRelay/CloudKit/relay-cache.json
~/Library/Application Support/AgentRelay/CloudKit/Outbox/
~/Library/Application Support/AgentRelay/CloudKit/agents.json
~/Library/Application Support/AgentRelay/ChatWorkspace/
~/Library/Logs/AgentRelay/
```

Do not share or manually edit credential, cache, outbox, or worker-state files.
