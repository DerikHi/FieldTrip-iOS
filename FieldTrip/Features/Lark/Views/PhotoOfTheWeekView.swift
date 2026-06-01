import SwiftUI

struct PhotoOfTheWeekView: View {
    @State private var photo: PhotoOfTheWeekModel?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let apiBaseURL = ProcessInfo.processInfo.environment["API_URL"] ?? "https://backend-nine-kappa-58.vercel.app"

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                ContentUnavailableView(
                    "Could Not Load",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if let photo {
                ScrollView {
                    VStack(spacing: 16) {
                        AsyncImage(url: URL(string: photo.photoUrl)) { image in
                            image
                                .resizable()
                                .scaledToFit()
                                .cornerRadius(12)
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.secondarySystemBackground))
                                .frame(height: 280)
                                .overlay(ProgressView())
                        }

                        Text(photo.submittedByUserName)
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "No Photo of the Week",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Check back soon — a new photo is featured each week.")
                )
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let token = KeychainService.retrieve(for: .authToken),
              let url = URL(string: "\(apiBaseURL)/api/photo-of-the-week") else {
            errorMessage = "Please sign in again."
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoded = try JSONDecoder.apiDecoder.decode(APIResponse<PhotoOfTheWeekResponse>.self, from: data)
            photo = decoded.data.photo
        } catch {
            errorMessage = "Could not load Photo of the Week."
        }
    }
}

struct PhotoOfTheWeekResponse: Decodable {
    let photo: PhotoOfTheWeekModel?
}

struct PhotoOfTheWeekModel: Decodable {
    let id: String
    let photoUrl: String
    let submittedByUserName: String
    let locationName: String?
    let selectedAt: Date
}
