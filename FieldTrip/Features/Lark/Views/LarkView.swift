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
                    PhotoOfTheWeekView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("For A Lark")
        .navigationBarTitleDisplayMode(.inline)
        .withHomeToolbar()
    }
}
