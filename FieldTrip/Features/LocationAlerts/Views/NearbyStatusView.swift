import SwiftUI

struct NearbyStatusView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var alerts = LocationAlertService.shared
    @State private var appear = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 4)

            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.12))
                    .frame(width: 90, height: 90)
                Image(systemName: statusIcon)
                    .font(.system(size: 40))
                    .foregroundStyle(statusColor)
            }
            .scaleEffect(appear ? 1 : 0.85)
            .opacity(appear ? 1 : 0)

            VStack(spacing: 12) {
                Text(statusTitle)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                Text(statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 6)

            if showsOpenSettingsButton {
                Button {
                    openSettings()
                } label: {
                    Text("Open Settings")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            }

            Button {
                dismiss()
            } label: {
                Text(showsOpenSettingsButton ? "Not Now" : "Got it")
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)

            if case .enabled = status {
                Button(role: .destructive) {
                    turnOffLocationServices()
                } label: {
                    Text("Turn off location services")
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }

            Spacer().frame(height: 4)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) { appear = true }
            Task { await alerts.refreshNotificationStatus() }
        }
    }

    private var status: Status {
        if alerts.locationPermissionGranted && alerts.primingChoice == .yes {
            return .enabled
        }
        if alerts.primingChoice == .maybeLater {
            return .needsEnabling(reason: "You can enable Nearby Alerts now.")
        }
        if alerts.primingChoice == .no {
            return .needsEnabling(reason: "You can enable Nearby Alerts now.")
        }
        return .needsEnabling(reason: "Enable Nearby Alerts to be notified as you approach rated locations.")
    }

    private enum Status {
        case enabled
        case needsEnabling(reason: String)
    }

    private var statusTitle: String {
        switch status {
        case .enabled: return "Nearby Alerts are On"
        case .needsEnabling: return "Enable Nearby Alerts"
        }
    }

    private var statusMessage: String {
        switch status {
        case .enabled:
            if alerts.primingChoice == .yes && !alerts.locationPermissionGranted {
                return "Open Settings → FieldTrip → Location and choose 'While Using the App'. When done, you'll see notifications as you approach rated locations."
            }
            return "You'll be notified as you approach places rated in FTP."
        case .needsEnabling(let reason):
            return "\(reason)\n\nOpen Settings → FieldTrip → Location and choose 'While Using the App'. When done, we'll send you a notification when you are near a place rated in FTP."
        }
    }

    private var statusIcon: String {
        switch status {
        case .enabled: return "checkmark.circle.fill"
        case .needsEnabling: return "location.circle"
        }
    }

    private var statusColor: Color {
        switch status {
        case .enabled: return .green
        case .needsEnabling: return .accentColor
        }
    }

    private var showsOpenSettingsButton: Bool {
        switch status {
        case .enabled: return !alerts.locationPermissionGranted
        case .needsEnabling: return true
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func turnOffLocationServices() {
        alerts.disableNearbyAlerts()
        dismiss()
    }
}
