#!/bin/zsh
set -euo pipefail

script_directory=${0:A:h}
repository_directory=${script_directory:h}
configuration=${1:-release}
app_name="Agent Relay Host.app"
source_app="$repository_directory/dist/$app_name"
installed_app="/Applications/$app_name"
launch_agents_directory="$HOME/Library/LaunchAgents"
launch_agent="$launch_agents_directory/io.agentrelay.host.plist"
launch_agent_template="$repository_directory/Packaging/io.agentrelay.host.plist"
launch_domain="gui/$(id -u)"

"$script_directory/package_app.sh" "$configuration"

if [[ -d "$installed_app" ]]; then
    backup_directory="$HOME/Library/Application Support/Agent Relay/Backups"
    timestamp=$(date -u +%Y%m%dT%H%M%SZ)
    mkdir -p "$backup_directory"
    /bin/mv "$installed_app" "$backup_directory/Agent Relay Host $timestamp.app"
fi

/usr/bin/ditto "$source_app" "$installed_app"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$installed_app"

mkdir -p "$launch_agents_directory"
/usr/bin/plutil -lint "$launch_agent_template" >/dev/null
/usr/bin/install -m 0644 "$launch_agent_template" "$launch_agent"
/bin/launchctl bootout "$launch_domain/io.agentrelay.host" 2>/dev/null || true
/bin/launchctl bootstrap "$launch_domain" "$launch_agent"

echo "$installed_app"
