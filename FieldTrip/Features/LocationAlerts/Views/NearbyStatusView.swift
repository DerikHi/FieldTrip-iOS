import SwiftUI
import CoreLocation

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

            if let action = primaryAction {
                Button {
                    action.run()
                } label: {
                    Text(action.label)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            }

            Button {
                dismiss()
            } label: {
                Text(primaryAction == nil ? "Got it" : "Not Now")
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

    /// Resolves the current state by treating iOS Settings as the source of
    /// truth for permission, and the in-app priming choice as a separate
    /// opt-in for background nearby alerts. This avoids the bug where the
    /// app told the user to open Settings even though Settings was already
    /// set correctly (because they granted permission via the GPS button
    /// in another screen without ever seeing the priming sheet).
    private var status: Status {
        switch alerts.authorizationStatus {
        case .denied, .restricted:
            return .systemDenied
        case .authorizedWhenInUse, .authorizedAlways:
            return alerts.primingChoice == .yes ? .enabled : .needsInAppOptIn
        case .notDetermined:
            return .needsInAppOptIn
        @unknown default:
            return .needsInAppOptIn
        }
    }

    private enum Status {
        case enabled
        case needsInAppOptIn
        case systemDenied
    }

    private var statusTitle: String {
        switch status {
        case .enabled: return "Nearby Alerts are On"
        case .needsInAppOptIn: return "Turn On Nearby Alerts"
        case .systemDenied: return "Location Access is Off"
        }
    }

    private var statusMessage: String {
        switch status {
        case .enabled:
            return "You'll be notified as you approach places rated in FTP."
        case .needsInAppOptIn:
            return "Get a notification when you're near a place rated in FTP."
        case .systemDenied:
            return "FieldTrip Pro doesn't have permission to use your location. Open Settings → FieldTrip Pro → Location and choose 'While Using the App'."
        }
    }

    private var statusIcon: String {
        switch status {
        case .enabled: return "checkmark.circle.fill"
        case .needsInAppOptIn: return "location.circle"
        case .systemDenied: return "location.slash.circle"
        }
    }

    private var statusColor: Color {
        switch status {
        case .enabled: return .green
        case .needsInAppOptIn: return .accentColor
        case .systemDenied: return .orange
        }
    }

    private struct PrimaryAction {
        let label: String
        let run: () -> Void
    }

    private var primaryAction: PrimaryAction? {
        switch status {
        case .enabled:
            return nil
        case .needsInAppOptIn:
            return PrimaryAction(label: "Turn On Nearby Alerts") {
                Task {
                    alerts.enableNearbyAlerts()
                    _ = await alerts.requestNotificationPermission()
                    await alerts.refreshNotificationStatus()
                }
            }
        case .systemDenied:
            return PrimaryAction(label: "Open Settings") { openSettings() }
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
