import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarSelection?
    let serviceState: AppModel.ServiceState
    let mentionCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                RelayAppMark(size: 42)

                VStack(alignment: .leading, spacing: 1) {
                    Text("RELAY")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .tracking(1.4)
                    Text("Your agent room")
                        .font(.caption)
                        .foregroundStyle(RelayPalette.muted)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 24)

            Text("ROOMS")
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(RelayPalette.faint)
                .padding(.horizontal, 16)
                .padding(.bottom, 7)

            RelaySidebarButton(item: .room, selection: $selection)
            RelaySidebarButton(
                item: .mentions,
                selection: $selection,
                badge: mentionCount > 0 ? String(mentionCount) : nil
            )

            Text("TOOLS")
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(RelayPalette.faint)
                .padding(.horizontal, 16)
                .padding(.top, 22)
                .padding(.bottom, 7)

            RelaySidebarButton(item: .recents, selection: $selection)
            RelaySidebarButton(item: .search, selection: $selection)
            RelaySidebarButton(item: .agents, selection: $selection)

            Spacer()

            RelaySidebarButton(item: .settings, selection: $selection)

            HStack(spacing: 8) {
                Circle()
                    .fill(serviceState == .healthy ? RelayPalette.healthy : RelayPalette.danger)
                    .frame(width: 7, height: 7)
                Text(serviceState == .healthy ? "Private · this Mac" : "Relay recovering")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(RelayPalette.muted)
            }
            .padding(.horizontal, 17)
            .padding(.top, 18)
            .padding(.bottom, 15)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RelayPalette.sidebar)
    }
}

private struct RelaySidebarButton: View {
    let item: SidebarSelection
    @Binding var selection: SidebarSelection?
    var badge: String? = nil

    private var isSelected: Bool { selection == item }

    var body: some View {
        Button {
            selection = item
        } label: {
            HStack(spacing: 11) {
                Image(systemName: item.symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 20)
                Text(item.title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                Spacer()
                if item == .room {
                    Circle()
                        .fill(RelayPalette.healthy)
                        .frame(width: 6, height: 6)
                } else if let badge {
                    Text(badge)
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .foregroundStyle(isSelected ? RelayPalette.humanInk : RelayPalette.ink)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(isSelected ? RelayPalette.humanBubble : RelayPalette.surfaceRaised, in: Capsule())
                }
            }
            .foregroundStyle(isSelected ? RelayPalette.ink : RelayPalette.muted)
            .padding(.horizontal, 11)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? RelayPalette.surfaceRaised : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 7)
    }
}

private extension SidebarSelection {
    var title: String {
        switch self {
        case .room:
            return "General"
        case .mentions:
            return "Mentions"
        case .recents:
            return "Recents"
        case .search:
            return "Search"
        case .agents:
            return "Agents"
        case .settings:
            return "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .room:
            return "bubble.left.and.bubble.right.fill"
        case .mentions:
            return "at"
        case .recents:
            return "clock.arrow.circlepath"
        case .search:
            return "magnifyingglass"
        case .agents:
            return "person.2"
        case .settings:
            return "slider.horizontal.3"
        }
    }
}
