import SwiftUI

struct LocationPrimingView: View {
    let userId: String
    let onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var alerts = LocationAlertService.shared
    @State private var appear = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 8)

            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 110, height: 110)
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 50, weight: .regular))
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.bounce, value: appear)
            }
            .scaleEffect(appear ? 1 : 0.85)
            .opacity(appear ? 1 : 0)

            VStack(spacing: 12) {
                Text("Nearby Alerts")
                    .font(.title2.bold())
                Text("Optional. When enabled, FieldTrip Pro will alert you when you come within five miles of a location that you or other users have rated.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 6)

            VStack(spacing: 10) {
                Button {
                    Task { await chooseYes() }
                } label: {
                    Text("Yes")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    chooseMaybeLater()
                } label: {
                    Text("Maybe Later")
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.bordered)

                Button {
                    chooseNo()
                } label: {
                    Text("No")
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 12)

            Spacer().frame(height: 8)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { appear = true }
        }
    }

    private func chooseYes() async {
        alerts.recordPrimingChoice(.yes, for: userId)
        alerts.requestLocationPermission()
        _ = await alerts.requestNotificationPermission()
        alerts.startIfPossible()
        finish()
    }

    private func chooseMaybeLater() {
        alerts.recordPrimingChoice(.maybeLater, for: userId)
        finish()
    }

    private func chooseNo() {
        alerts.recordPrimingChoice(.no, for: userId)
        finish()
    }

    private func finish() {
        withAnimation(.easeIn(duration: 0.2)) { appear = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            dismiss()
            onComplete()
        }
    }
}
