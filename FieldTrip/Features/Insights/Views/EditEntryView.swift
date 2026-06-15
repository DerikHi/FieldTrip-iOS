import SwiftUI

/// Lets a user edit the rateable parts of one of their existing insights.
struct EditEntryView: View {
    let entry: MyEntry
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var starRating: Int
    @State private var attributeEntries: [AttributeEntry]
    @State private var comment: String
    @State private var isPublic: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let apiBaseURL = ProcessInfo.processInfo.environment["API_URL"] ?? "https://backend-nine-kappa-58.vercel.app"

    init(entry: MyEntry, onSaved: @escaping () -> Void) {
        self.entry = entry
        self.onSaved = onSaved
        _starRating = State(initialValue: entry.starRating ?? 3)
        _comment = State(initialValue: entry.comment ?? "")
        _isPublic = State(initialValue: true) // assume public; backend will return current
        let attrs = (entry.attributeRatings ?? []).map { attr -> AttributeEntry in
            var e = AttributeEntry(name: attr.attributeName)
            e.rating = AttributeRating.allCases.first { $0.apiValue == attr.rating.lowercased() } ?? .na
            return e
        }
        _attributeEntries = State(initialValue: attrs)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let error = errorMessage {
                        ErrorBanner(message: error)
                    }

                    Toggle("Share publicly with other users", isOn: $isPublic)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Overall Rating").font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            ForEach(1...5, id: \.self) { star in
                                Button(action: { starRating = star }) {
                                    Image(systemName: star <= starRating ? "star.fill" : "star")
                                        .font(.title2)
                                        .foregroundStyle(.yellow)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)

                    if !attributeEntries.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Attributes").font(.caption).foregroundStyle(.secondary)
                            ForEach($attributeEntries) { $entry in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(entry.name).font(.subheadline.weight(.medium))
                                    let options = AttributeRating.options(for: entry.name)
                                    HStack(spacing: 6) {
                                        ForEach(options, id: \.self) { option in
                                            Button(action: { entry.rating = option }) {
                                                Text(option.rawValue)
                                                    .font(.caption.weight(.medium))
                                                    .frame(maxWidth: .infinity, minHeight: 30)
                                                    .background(entry.rating == option ? AttributeRatingDisplay.color(for: option.apiValue).opacity(0.2) : Color(.systemBackground))
                                                    .foregroundStyle(entry.rating == option ? AttributeRatingDisplay.color(for: option.apiValue) : .primary)
                                                    .cornerRadius(6)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 6)
                                                            .stroke(entry.rating == option ? AttributeRatingDisplay.color(for: option.apiValue) : Color.clear, lineWidth: 1)
                                                    )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Comment").font(.caption).foregroundStyle(.secondary)
                        TextField("Comment (optional)", text: $comment, axis: .vertical)
                            .lineLimit(2...6)
                            .font(.subheadline)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                }
                .padding()
            }
            .navigationTitle("Edit Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving)
                }
            }
            .overlay {
                if isSaving {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    ProgressView("Saving…").padding().background(.thickMaterial).cornerRadius(12)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        guard let token = KeychainService.retrieve(for: .authToken),
              let url = URL(string: "\(apiBaseURL)/api/insights/\(entry.id)") else {
            errorMessage = "An error has occurred, please log in again."
            return
        }

        let attrPayload = attributeEntries
            .filter { $0.rating != .na }
            .map { ["attributeName": $0.name, "rating": $0.rating.apiValue] }

        let body: [String: Any] = [
            "comment": comment,
            "isPublic": isPublic,
            "starRating": starRating,
            "attributeRatings": attrPayload,
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                dismiss()
                onSaved()
            } else {
                errorMessage = "An error has occurred, please log in again."
            }
        } catch {
            errorMessage = "An error has occurred, please log in again."
        }
    }
}
