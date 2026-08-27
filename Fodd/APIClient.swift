import Foundation

struct Envelope<T: Decodable>: Decodable { let data: T }
struct AuthResponse: Decodable { let token: String; let user: Account }
struct Account: Identifiable, Codable, Hashable { let id, name, username, email, bio: String }
struct Member: Identifiable, Codable, Hashable {
    let id, name, username, bio: String
    let followersCount, followingCount: Int
    var isFollowing: Bool
}
struct Moment: Identifiable, Codable {
    let id, caption, image, createdAt, userId, name, username: String
    let likes: Int
}
struct ChatMessage: Identifiable, Codable {
    let id, senderId, receiverId, body, createdAt: String
}
struct Restaurant: Identifiable, Codable, Hashable {
    let id, name, category, image: String
    let rating: Double
    let distance, price: String
}

enum APIError: LocalizedError {
    case invalidURL, invalidResponse, server(String)
    var errorDescription: String? {
        switch self {
        case .invalidURL: "Alamat server tidak valid."
        case .invalidResponse: "Respons server tidak valid."
        case .server(let message): message
        }
    }
}

struct APIClient {
    private let session = URLSession.shared
    private var baseURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String else { return nil }
        return URL(string: raw)
    }

    func register(name: String, username: String, email: String, password: String) async throws -> AuthResponse {
        try await request("api/auth/register", method: "POST", body: ["name":name,"username":username,"email":email,"password":password])
    }
    func login(email: String, password: String) async throws -> AuthResponse {
        try await request("api/auth/login", method: "POST", body: ["email":email,"password":password])
    }
    func me(token: String) async throws -> Account { try await request("api/me", token: token) }
    func updateMe(name: String, bio: String, token: String) async throws -> Account { try await request("api/me", method:"PATCH", token:token, body:["name":name,"bio":bio]) }
    func members(search: String, token: String) async throws -> [Member] { try await request("api/users?search=\(search.addingPercentEncoding(withAllowedCharacters:.urlQueryAllowed) ?? "")", token:token) }
    func follow(id: String, enabled: Bool, token: String) async throws { let _: EmptyResponse = try await request("api/users/\(id)/follow", method:enabled ? "PUT":"DELETE", token:token) }
    func restaurants() async throws -> [Restaurant] { try await request("api/restaurants") }
    func moments(token: String) async throws -> [Moment] { try await request("api/moments", token:token) }
    func createMoment(caption: String, image: String, token: String) async throws { let _: Moment = try await request("api/moments",method:"POST",token:token,body:["caption":caption,"image":image]) }
    func messages(with id: String, token: String) async throws -> [ChatMessage] { try await request("api/messages/\(id)",token:token) }
    func sendMessage(to id: String, body: String, token: String) async throws -> ChatMessage { try await request("api/messages/\(id)",method:"POST",token:token,body:["body":body]) }

    private func request<T: Decodable>(_ path: String, method: String = "GET", token: String? = nil, body: [String:String]? = nil) async throws -> T {
        guard let baseURL, let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else { throw APIError.invalidURL }
        var request = URLRequest(url:url); request.httpMethod=method
        if let token { request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization") }
        if let body { request.setValue("application/json",forHTTPHeaderField:"Content-Type"); request.httpBody=try JSONEncoder().encode(body) }
        let (data,response)=try await session.data(for:request)
        guard let http=response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 204 { return EmptyResponse() as! T }
        guard (200..<300).contains(http.statusCode) else {
            let message=(try? JSONDecoder().decode(ServerError.self,from:data).error) ?? "Server error \(http.statusCode)"
            throw APIError.server(message)
        }
        return try JSONDecoder().decode(Envelope<T>.self,from:data).data
    }
}
private struct ServerError: Decodable { let error: String }
private struct EmptyResponse: Codable { init() {} }
