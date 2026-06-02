import SwiftUI

/// Persistent bottom tab bar shown on every screen. Liquid-glass background
/// with green highlight, plus a follow-the-finger glass bubble that previews
/// the user's selection while they drag across the bar.
struct MainTabBar: View {
    @EnvironmentObject private var router: AppRouter
    @State private var draggedIndex: Int?
    @State private var hasReleasedDrag = true

    var body: some View {
        GeometryReader { geo in
            let count = MainTab.allCases.count
            let cellWidth = geo.size.width / CGFloat(count)
            let buttons = MainTab.allCases

            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(Array(buttons.enumerated()), id: \.offset) { idx, tab in
                        TabButton(
                            tab: tab,
                            isSelected: router.selectedTab == tab,
                            isHovered: draggedIndex == idx
                        ) {
                            router.tapTab(tab)
                        }
                        .frame(width: cellWidth)
                    }
                }

                // Liquid Glass bubble following the user's finger while they drag.
                if let i = draggedIndex {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.thinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.tabSelected.opacity(0.85),
                                            Color.tabSelected.opacity(0.45),
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                        .shadow(color: Color.tabSelected.opacity(0.35), radius: 10, x: 0, y: 4)
                        .frame(width: cellWidth - 6, height: geo.size.height - 10)
                        .offset(x: CGFloat(i) * cellWidth + 3, y: 5)
                        .animation(.spring(response: 0.22, dampingFraction: 0.85), value: draggedIndex)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        let raw = Int(value.location.x / cellWidth)
                        let clamped = min(max(raw, 0), count - 1)
                        if draggedIndex != clamped {
                            draggedIndex = clamped
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        hasReleasedDrag = false
                    }
                    .onEnded { _ in
                        if let i = draggedIndex {
                            router.tapTab(buttons[i])
                        }
                        draggedIndex = nil
                        hasReleasedDrag = true
                    }
            )
        }
        .frame(height: 64)
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
    let isHovered: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: tab.icon)
                    .font(.system(size: 20, weight: (isSelected || isHovered) ? .semibold : .regular))
                Text(tab.label)
                    .font(.caption2)
                    .fontWeight((isSelected || isHovered) ? .semibold : .regular)
            }
            .foregroundStyle((isSelected || isHovered) ? Color.tabSelected : Color.primary)
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
