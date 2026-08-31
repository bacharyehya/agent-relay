#!/bin/zsh
set -euo pipefail

script_directory=${0:A:h}
repository_directory=${script_directory:h}
configuration=${1:-release}
host_mode=${2:-local-and-cloud}
if [[ "$host_mode" != "local-and-cloud" && "$host_mode" != "cloud-only" ]]; then
    echo "usage: $0 [debug|release] [local-and-cloud|cloud-only]" >&2
    exit 2
fi
app_name="Agent Relay Host.app"
source_app="$repository_directory/dist/$app_name"
installed_app="/Applications/$app_name"
launch_agents_directory="$HOME/Library/LaunchAgents"
launch_agent="$launch_agents_directory/io.agentrelay.host.plist"
launch_agent_template="$repository_directory/Packaging/io.agentrelay.host.plist"
launch_domain="gui/$(id -u)"

"$script_directory/package_app.sh" "$configuration"

/bin/launchctl bootout "$launch_domain/io.agentrelay.host" 2>/dev/null || true
host_pids=$(/usr/bin/pgrep -f '^/Applications/Agent Relay Host\.app/Contents/MacOS/AgentRelayDesktop$' || true)
if [[ -n "$host_pids" ]]; then
    /bin/kill -TERM ${(f)host_pids}
    for attempt in {1..50}; do
        if ! /usr/bin/pgrep -f '^/Applications/Agent Relay Host\.app/Contents/MacOS/AgentRelayDesktop$' >/dev/null; then
            break
        fi
        /bin/sleep 0.1
    done
    lingering_pids=$(/usr/bin/pgrep -f '^/Applications/Agent Relay Host\.app/Contents/MacOS/AgentRelayDesktop$' || true)
    if [[ -n "$lingering_pids" ]]; then
        /bin/kill -KILL ${(f)lingering_pids}
    fi
fi

helper_pids=$(/usr/bin/pgrep -f '^/Applications/Agent Relay Host\.app/Contents/Resources/(CoreService|CodexRelayWorker)$' || true)
if [[ -n "$helper_pids" ]]; then
    /bin/kill -TERM ${(f)helper_pids}
    for attempt in {1..50}; do
        if ! /usr/bin/pgrep -f '^/Applications/Agent Relay Host\.app/Contents/Resources/(CoreService|CodexRelayWorker)$' >/dev/null; then
            break
        fi
        /bin/sleep 0.1
    done
    lingering_helper_pids=$(/usr/bin/pgrep -f '^/Applications/Agent Relay Host\.app/Contents/Resources/(CoreService|CodexRelayWorker)$' || true)
    if [[ -n "$lingering_helper_pids" ]]; then
        /bin/kill -KILL ${(f)lingering_helper_pids}
    fi
fi

if [[ -d "$installed_app" ]]; then
    backup_directory="$HOME/Library/Application Support/Agent Relay/Backups"
    timestamp=$(date -u +%Y%m%dT%H%M%SZ)
    mkdir -p "$backup_directory"
    /bin/mv "$installed_app" "$backup_directory/Agent Relay Host $timestamp.app"
fi

/usr/bin/ditto "$source_app" "$installed_app"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$installed_app"

mkdir -p "$launch_agents_directory"
temporary_launch_agent=$(mktemp "${TMPDIR:-/tmp}/io.agentrelay.host.XXXXXX.plist")
trap '/bin/rm -f "$temporary_launch_agent"' EXIT
/bin/cp "$launch_agent_template" "$temporary_launch_agent"
if [[ "$host_mode" == "cloud-only" ]]; then
    /usr/libexec/PlistBuddy -c "Set :EnvironmentVariables:AGENT_RELAY_ENABLE_LOCAL_AGENTS false" "$temporary_launch_agent"
fi
/usr/bin/plutil -lint "$temporary_launch_agent" >/dev/null
/usr/bin/install -m 0644 "$temporary_launch_agent" "$launch_agent"
/bin/launchctl bootstrap "$launch_domain" "$launch_agent"

echo "$installed_app"
