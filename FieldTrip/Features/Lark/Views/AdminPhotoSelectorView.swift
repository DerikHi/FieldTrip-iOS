import SwiftUI

struct AdminPhotoSelectorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var photos: [AdminPhoto] = []
    @State private var isLoading = false
    @State private var isSelecting = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var page = 1

    private let apiBaseURL = ProcessInfo.processInfo.environment["API_URL"] ?? "https://backend-nine-kappa-58.vercel.app"
    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if let error = errorMessage {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .padding()
                }
                if let message = successMessage {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.green)
                        .padding()
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(photos, id: \.photoId) { photo in
                        Button {
                            Task { await select(photo: photo) }
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                AsyncImage(url: URL(string: photo.url)) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(height: 140)
                                        .clipped()
                                        .cornerRadius(8)
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(.secondarySystemBackground))
                                        .frame(height: 140)
                                        .overlay(ProgressView())
                                }
                                Text(photo.userName)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                if let locationName = photo.locationName {
                                    Text(locationName)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isSelecting)
                    }
                }
                .padding()

                if !photos.isEmpty && photos.count >= 20 {
                    Button {
                        Task { await loadMore() }
                    } label: {
                        Text("Load More")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            .navigationTitle("Choose Photo of the Week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if isLoading || isSelecting {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    ProgressView(isSelecting ? "Selecting…" : "Loading…")
                        .padding(20)
                        .background(.thickMaterial)
                        .cornerRadius(12)
                }
            }
            .task { if photos.isEmpty { await loadFirstPage() } }
        }
    }

    private func loadFirstPage() async {
        page = 1
        isLoading = true
        defer { isLoading = false }
        await fetchPage(replace: true)
    }

    private func loadMore() async {
        page += 1
        await fetchPage(replace: false)
    }

    private func fetchPage(replace: Bool) async {
        errorMessage = nil
        guard let token = KeychainService.retrieve(for: .authToken),
              let url = URL(string: "\(apiBaseURL)/api/admin/photos?page=\(page)") else {
            errorMessage = "Please sign in again."
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoded = try JSONDecoder.apiDecoder.decode(APIResponse<AdminPhotosResponse>.self, from: data)
            if replace {
                photos = decoded.data.photos
            } else {
                photos += decoded.data.photos
            }
        } catch {
            errorMessage = "Could not load photos."
        }
    }

    private func select(photo: AdminPhoto) async {
        isSelecting = true
        defer { isSelecting = false }
        errorMessage = nil

        guard let token = KeychainService.retrieve(for: .authToken),
              let url = URL(string: "\(apiBaseURL)/api/admin/photo-of-the-week") else {
            errorMessage = "Please sign in again."
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["photoId": photo.photoId])

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                successMessage = "Photo of the Week updated."
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { dismiss() }
            } else {
                errorMessage = "Could not select photo."
            }
        } catch {
            errorMessage = "Could not select photo."
        }
    }
}

struct AdminPhotosResponse: Decodable {
    let photos: [AdminPhoto]
    let page: Int
    let pageSize: Int
}

struct AdminPhoto: Decodable {
    let photoId: String
    let url: String
    let userId: String
    let userName: String
    let locationId: String
    let locationName: String?
    let createdAt: Date
}
