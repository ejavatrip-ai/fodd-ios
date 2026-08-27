import Foundation

@MainActor
final class AppStore: ObservableObject {
    @Published var restaurants = fallbackRestaurants
    @Published var isOnline = false
    private let api = APIClient()

    func refresh() async {
        do {
            restaurants = try await api.restaurants()
            isOnline = true
        } catch {
            isOnline = false
        }
    }

    func createMoment(caption: String) async throws {
        try await api.createMoment(.init(author: "Food Explorer", caption: caption, restaurantId: nil, image: "Noodles"))
    }
}
