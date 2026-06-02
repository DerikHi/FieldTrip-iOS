import SwiftUI

/// Persistent bottom tab bar shown on every screen. Liquid-glass background
/// (.thinMaterial) with green highlight for the active tab.
struct MainTabBar: View {
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases) { tab in
                TabButton(
                    tab: tab,
                    isSelected: router.selectedTab == tab
                ) {
                    router.tapTab(tab)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.55),
                                    Color.white.opacity(0.05),
                                    Color.black.opacity(0.05),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                )
                .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 6)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }
}

private struct TabButton: View {
    let tab: MainTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: tab.icon)
                    .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                Text(tab.label)
                    .font(.caption2)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .foregroundStyle(isSelected ? Color.tabSelected : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension Color {
    /// The green tint used to highlight the active tab.
    static let tabSelected = Color(red: 0.13, green: 0.66, blue: 0.27)
}
