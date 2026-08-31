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
app_directory="$repository_directory/dist/Agent Relay Host.app"
contents_directory="$app_directory/Contents"
macos_directory="$contents_directory/MacOS"
resources_directory="$contents_directory/Resources"

if [[ -d "$app_directory" ]]; then
    /bin/rm -rf "$app_directory"
fi
mkdir -p "$macos_directory" "$resources_directory"
install -m 0755 "$binary_directory/AgentRelayDesktop" "$macos_directory/AgentRelayDesktop"
install -m 0755 "$binary_directory/CoreService" "$resources_directory/CoreService"
install -m 0755 "$binary_directory/CodexRelayWorker" "$resources_directory/CodexRelayWorker"
install -m 0755 "$binary_directory/MCPAdapter" "$resources_directory/MCPAdapter"

icon_source="$repository_directory/Assets/AppIcon-1024.png"
if [[ -f "$icon_source" ]]; then
    icon_work_directory=$(mktemp -d "${TMPDIR:-/tmp}/agent-relay-icon.XXXXXX")
    trap 'rm -rf "$icon_work_directory"' EXIT
    iconset_directory="$icon_work_directory/AgentRelay.iconset"
    mkdir -p "$iconset_directory"

    /usr/bin/sips -z 16 16 "$icon_source" --out "$iconset_directory/icon_16x16.png" >/dev/null
    /usr/bin/sips -z 32 32 "$icon_source" --out "$iconset_directory/icon_16x16@2x.png" >/dev/null
    /usr/bin/sips -z 32 32 "$icon_source" --out "$iconset_directory/icon_32x32.png" >/dev/null
    /usr/bin/sips -z 64 64 "$icon_source" --out "$iconset_directory/icon_32x32@2x.png" >/dev/null
    /usr/bin/sips -z 128 128 "$icon_source" --out "$iconset_directory/icon_128x128.png" >/dev/null
    /usr/bin/sips -z 256 256 "$icon_source" --out "$iconset_directory/icon_128x128@2x.png" >/dev/null
    /usr/bin/sips -z 256 256 "$icon_source" --out "$iconset_directory/icon_256x256.png" >/dev/null
    /usr/bin/sips -z 512 512 "$icon_source" --out "$iconset_directory/icon_256x256@2x.png" >/dev/null
    /usr/bin/sips -z 512 512 "$icon_source" --out "$iconset_directory/icon_512x512.png" >/dev/null
    /usr/bin/sips -z 1024 1024 "$icon_source" --out "$iconset_directory/icon_512x512@2x.png" >/dev/null
    /usr/bin/iconutil -c icns "$iconset_directory" -o "$icon_work_directory/AgentRelay.icns"
    install -m 0644 "$icon_work_directory/AgentRelay.icns" "$resources_directory/AgentRelay.icns"
fi

install -m 0644 "$repository_directory/Packaging/Info.plist" "$contents_directory/Info.plist"

codesign_identity=${AGENT_RELAY_CODESIGN_IDENTITY:--}
provisioning_profile=${AGENT_RELAY_PROVISIONING_PROFILE:-}
if [[ -n "$provisioning_profile" ]]; then
    install -m 0644 "$provisioning_profile" "$contents_directory/embedded.provisionprofile"
fi

for helper in "$resources_directory/CoreService" "$resources_directory/CodexRelayWorker" "$resources_directory/MCPAdapter"; do
    /usr/bin/codesign --force --sign "$codesign_identity" "$helper"
done
/usr/bin/codesign \
    --force \
    --sign "$codesign_identity" \
    --entitlements "$repository_directory/Packaging/Host.entitlements" \
    "$app_directory"

echo "$app_directory"
