import SwiftUI

struct LarkView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case spotAPlate = "Spot A Plate"
        case photoOfTheWeek = "Photo of the Week"
        var id: String { rawValue }
    }

    @State private var selected: Tab = .spotAPlate

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $selected) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            Group {
                switch selected {
                case .spotAPlate:
                    SpotAPlateView()
                case .photoOfTheWeek:
                    PhotoOfTheWeekPlaceholder()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Lark")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PhotoOfTheWeekPlaceholder: View {
    var body: some View {
        ContentUnavailableView(
            "Coming Soon",
            systemImage: "photo.on.rectangle.angled",
            description: Text("Photo of the Week will appear here in a future update.")
        )
    }
}
