import Foundation

struct APIEnvelope<T: Decodable>: Decodable { let data: T }

struct MomentRequest: Encodable {
    let author: String
    let caption: String
    let restaurantId: String?
    let image: String
}

enum APIError: LocalizedError {
    case invalidURL, invalidResponse
    var errorDescription: String? {
        switch self {
        case .invalidURL: "Alamat server belum benar."
        case .invalidResponse: "Server memberikan respons yang tidak valid."
        }
    }
}

struct APIClient {
    private let session: URLSession = .shared
    private var baseURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String else { return nil }
        return URL(string: raw)
    }

    func restaurants() async throws -> [Restaurant] {
        guard let url = baseURL?.appending(path: "api/restaurants") else { throw APIError.invalidURL }
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw APIError.invalidResponse }
        return try JSONDecoder().decode(APIEnvelope<[Restaurant]>.self, from: data).data
    }

    func createMoment(_ request: MomentRequest) async throws {
        guard let url = baseURL?.appending(path: "api/moments") else { throw APIError.invalidURL }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        let (_, response) = try await session.data(for: urlRequest)
        guard (response as? HTTPURLResponse)?.statusCode == 201 else { throw APIError.invalidResponse }
    }
}
