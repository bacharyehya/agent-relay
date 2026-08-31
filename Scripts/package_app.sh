#!/bin/zsh
set -euo pipefail

script_directory=${0:A:h}
repository_directory=${script_directory:h}
configuration=${1:-release}

cd "$repository_directory"

for product in AgentRelayDesktop CoreService CodexRelayWorker MCPAdapter; do
    swift build --configuration "$configuration" --product "$product"
done

binary_directory=$(swift build --configuration "$configuration" --show-bin-path)
app_directory="$repository_directory/dist/Agent Relay.app"
contents_directory="$app_directory/Contents"
macos_directory="$contents_directory/MacOS"
resources_directory="$contents_directory/Resources"

mkdir -p "$macos_directory" "$resources_directory"
install -m 0755 "$binary_directory/AgentRelayDesktop" "$macos_directory/AgentRelayDesktop"
install -m 0755 "$binary_directory/CoreService" "$resources_directory/CoreService"
install -m 0755 "$binary_directory/CodexRelayWorker" "$resources_directory/CodexRelayWorker"
install -m 0755 "$binary_directory/MCPAdapter" "$resources_directory/MCPAdapter"
install -m 0644 "$repository_directory/Packaging/Info.plist" "$contents_directory/Info.plist"

/usr/bin/codesign --force --deep --sign - "$app_directory"

echo "$app_directory"
