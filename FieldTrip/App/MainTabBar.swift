import SwiftUI

/// Persistent bottom tab bar shown on every screen. Liquid-glass background
/// with green highlight, plus a follow-the-finger glass bubble that previews
/// the user's selection while they drag across the bar.
struct MainTabBar: View {
    @EnvironmentObject private var router: AppRouter
    @State private var draggedIndex: Int?

    private let barHeight: CGFloat = 56

    var body: some View {
        let tabs = MainTab.allCases

        GeometryReader { geo in
            let cellWidth = geo.size.width / CGFloat(tabs.count)

            ZStack(alignment: .leading) {
                // Liquid-Glass bubble that follows the finger while dragging.
                if let i = draggedIndex {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.thinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.tabSelected.opacity(0.9),
                                            Color.tabSelected.opacity(0.4),
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                        .shadow(color: Color.tabSelected.opacity(0.35), radius: 10, x: 0, y: 4)
                        .frame(width: cellWidth - 6, height: barHeight - 10)
                        .offset(x: CGFloat(i) * cellWidth + 3, y: 0)
                        .animation(.spring(response: 0.22, dampingFraction: 0.85), value: draggedIndex)
                }

                HStack(spacing: 0) {
                    ForEach(Array(tabs.enumerated()), id: \.offset) { idx, tab in
                        TabIconView(
                            tab: tab,
                            isSelected: router.selectedTab == tab,
                            isHovered: draggedIndex == idx
                        )
                        .frame(width: cellWidth, height: barHeight)
                    }
                }
            }
            .frame(width: geo.size.width, height: barHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let raw = Int(value.location.x / cellWidth)
                        let clamped = min(max(raw, 0), tabs.count - 1)
                        if draggedIndex != clamped {
                            draggedIndex = clamped
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }
                    .onEnded { _ in
                        if let i = draggedIndex {
                            router.tapTab(tabs[i])
                        }
                        draggedIndex = nil
                    }
            )
        }
        .frame(height: barHeight)
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

/// Static visual cell — not a Button, so the parent DragGesture handles
/// both taps and drags without being intercepted.
private struct TabIconView: View {
    let tab: MainTab
    let isSelected: Bool
    let isHovered: Bool

    private var highlighted: Bool { isSelected || isHovered }

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: tab.icon)
                .font(.system(size: 20, weight: highlighted ? .semibold : .regular))
            Text(tab.label)
                .font(.caption2)
                .fontWeight(highlighted ? .semibold : .regular)
        }
        .foregroundStyle(highlighted ? Color.tabSelected : Color.primary)
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension Color {
    /// The green tint used to highlight the active tab.
    static let tabSelected = Color(red: 0.13, green: 0.66, blue: 0.27)
}
