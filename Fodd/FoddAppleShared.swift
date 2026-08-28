import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

struct FoddWidgetSnapshot: Codable, Hashable {
    var displayName: String
    var tasteHeadline: String
    var tasteScore: Int
    var restaurantName: String
    var restaurantCategory: String
    var restaurantMatch: Int
    var restaurantId: String
    var planTitle: String
    var planId: String
    var planRestaurant: String
    var planScheduledAt: Date?

    static let empty = FoddWidgetSnapshot(
        displayName: "Foodie",
        tasteHeadline: "Temukan rasa favoritmu",
        tasteScore: 0,
        restaurantName: "Buka Fodd",
        restaurantCategory: "Smart Food",
        restaurantMatch: 0,
        restaurantId: "",
        planTitle: "Belum ada Makan Bareng",
        planId: "",
        planRestaurant: "",
        planScheduledAt: nil
    )
}

enum FoddSharedContainer {
    static let suiteName = "group.com.fodd.app"
    static let widgetSnapshotKey = "fodd.widget.snapshot.v7"
    static let pendingRouteKey = "fodd.pending.route.v7"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    static func saveWidgetSnapshot(_ snapshot: FoddWidgetSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: widgetSnapshotKey)
        }
    }

    static func loadWidgetSnapshot() -> FoddWidgetSnapshot {
        guard let data = defaults.data(forKey: widgetSnapshotKey),
              let value = try? JSONDecoder().decode(FoddWidgetSnapshot.self, from: data) else { return .empty }
        return value
    }

    static func setPendingRoute(_ route: String) {
        defaults.set(route, forKey: pendingRouteKey)
    }

    static func consumePendingRoute() -> String? {
        let value = defaults.string(forKey: pendingRouteKey)
        defaults.removeObject(forKey: pendingRouteKey)
        return value
    }
}

#if canImport(ActivityKit)
struct FoddDiningActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var status: String
        var restaurantName: String
        var goingCount: Int
        var messageCount: Int
        var scheduledAt: Double
    }

    var planId: String
    var title: String
    var hostName: String
}
#endif
