import Foundation
import SwiftUI
import MapKit
import CoreSpotlight
import UniformTypeIdentifiers
import WidgetKit
import AppIntents
#if canImport(ActivityKit)
import ActivityKit
#endif
#if canImport(GroupActivities)
import GroupActivities
#endif

@MainActor
final class FoddAppleExperienceManager: ObservableObject {
    static let shared = FoddAppleExperienceManager()
    @Published private(set) var liveActivityPlanId: String?
    @Published private(set) var lastSpotlightSync: Date?

    private init() {
        #if canImport(ActivityKit)
        liveActivityPlanId = Activity<FoddDiningActivityAttributes>.activities.first?.attributes.planId
        #endif
    }

    func sync(account: Account?, smartDashboard: SmartFoodDashboard?, restaurants: [Restaurant], moments: [Moment], members: [Member], diningPlans: [DiningPlan]) {
        saveWidgetSnapshot(account: account, smartDashboard: smartDashboard, diningPlans: diningPlans)
        indexSpotlight(restaurants: restaurants, moments: moments, members: members, diningPlans: diningPlans)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func saveWidgetSnapshot(account: Account?, smartDashboard: SmartFoodDashboard?, diningPlans: [DiningPlan]) {
        let best = smartDashboard?.forYou.first ?? smartDashboard?.becauseYouLiked.first
        let nextPlan = diningPlans
            .filter { $0.status == "planned" }
            .sorted { Self.date($0.scheduledAt) ?? .distantFuture < Self.date($1.scheduledAt) ?? .distantFuture }
            .first
        let strongestTrait = smartDashboard?.taste.traits.first

        let snapshot = FoddWidgetSnapshot(
            displayName: account?.name ?? "Foodie",
            tasteHeadline: strongestTrait?.name ?? "Taste DNA",
            tasteScore: strongestTrait?.score ?? 0,
            restaurantName: best?.restaurant.name ?? "Temukan tempat baru",
            restaurantCategory: best?.restaurant.category ?? "Smart Food",
            restaurantMatch: best?.matchScore ?? 0,
            restaurantId: best?.restaurant.id ?? "",
            planTitle: nextPlan?.title ?? "Belum ada Makan Bareng",
            planId: nextPlan?.id ?? "",
            planRestaurant: nextPlan?.selectedRestaurant?.name ?? nextPlan?.candidates.first?.restaurant.name ?? "",
            planScheduledAt: nextPlan.flatMap { Self.date($0.scheduledAt) }
        )
        FoddSharedContainer.saveWidgetSnapshot(snapshot)
    }

    private func indexSpotlight(restaurants: [Restaurant], moments: [Moment], members: [Member], diningPlans: [DiningPlan]) {
        var items: [CSSearchableItem] = []
        for restaurant in restaurants.prefix(80) {
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = restaurant.name
            attributes.contentDescription = [restaurant.category, restaurant.address].filter { !$0.isEmpty }.joined(separator: " • ")
            attributes.keywords = ["Fodd", "restaurant", restaurant.category, restaurant.name]
            attributes.contentURL = URL(string: "fodd://restaurant/\(restaurant.id)")
            items.append(CSSearchableItem(uniqueIdentifier: "restaurant-\(restaurant.id)", domainIdentifier: "com.fodd.restaurant", attributeSet: attributes))
        }
        for moment in moments.prefix(50) {
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = moment.locationName.isEmpty ? "Food Moment • \(moment.name)" : moment.locationName
            attributes.contentDescription = moment.caption
            attributes.keywords = ["Fodd", "Food Moment", moment.name, moment.locationName]
            attributes.contentURL = URL(string: "fodd://moment/\(moment.id)")
            items.append(CSSearchableItem(uniqueIdentifier: "moment-\(moment.id)", domainIdentifier: "com.fodd.moment", attributeSet: attributes))
        }
        for member in members.filter({ $0.isFollowing || $0.isCloseFoodie }).prefix(40) {
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = member.name
            attributes.contentDescription = "@\(member.username) • Fodd foodie"
            attributes.keywords = ["Fodd", "foodie", member.name, member.username]
            attributes.contentURL = URL(string: "fodd://profile/\(member.id)")
            items.append(CSSearchableItem(uniqueIdentifier: "member-\(member.id)", domainIdentifier: "com.fodd.member", attributeSet: attributes))
        }
        for plan in diningPlans.filter({ $0.status == "planned" }).prefix(20) {
            let attributes = CSSearchableItemAttributeSet(contentType: .event)
            attributes.title = plan.title
            let venue = plan.selectedRestaurant?.name ?? plan.candidates.first?.restaurant.name ?? "Pilih restoran"
            attributes.contentDescription = "Makan Bareng • \(venue)"
            attributes.startDate = Self.date(plan.scheduledAt)
            attributes.contentURL = URL(string: "fodd://together/\(plan.id)")
            items.append(CSSearchableItem(uniqueIdentifier: "plan-\(plan.id)", domainIdentifier: "com.fodd.together", attributeSet: attributes))
        }
        CSSearchableIndex.default().indexSearchableItems(items) { _ in }
        lastSpotlightSync = Date()
    }

    #if canImport(ActivityKit)
    func startLiveActivity(for plan: DiningPlan, onPushToken: ((String) async -> Void)? = nil) async -> Bool {
        #if FODD_PERSONAL_TEAM
        return false
        #else
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return false }
        let scheduled = Self.date(plan.scheduledAt) ?? Date().addingTimeInterval(3600)
        let attributes = FoddDiningActivityAttributes(planId: plan.id, title: plan.title, hostName: plan.host.name)
        let state = FoddDiningActivityAttributes.ContentState(
            status: plan.status,
            restaurantName: plan.selectedRestaurant?.name ?? plan.candidates.first?.restaurant.name ?? "Voting restoran",
            goingCount: plan.goingCount,
            messageCount: plan.messageCount,
            scheduledAt: scheduled.timeIntervalSince1970
        )
        do {
            for existing in Activity<FoddDiningActivityAttributes>.activities where existing.attributes.planId == plan.id {
                await existing.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
            }
            let activity = try Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: scheduled.addingTimeInterval(900)), pushType: .token)
            liveActivityPlanId = activity.attributes.planId
            if let onPushToken {
                Task {
                    for await tokenData in activity.pushTokenUpdates {
                        let token = tokenData.map { String(format: "%02x", $0) }.joined()
                        await onPushToken(token)
                    }
                }
            }
            return true
        } catch { return false }
        #endif
    }

    func refreshLiveActivity(for plan: DiningPlan) async {
        let scheduled = Self.date(plan.scheduledAt) ?? Date().addingTimeInterval(3600)
        let state = FoddDiningActivityAttributes.ContentState(
            status: plan.status,
            restaurantName: plan.selectedRestaurant?.name ?? plan.candidates.first?.restaurant.name ?? "Voting restoran",
            goingCount: plan.goingCount,
            messageCount: plan.messageCount,
            scheduledAt: scheduled.timeIntervalSince1970
        )
        for activity in Activity<FoddDiningActivityAttributes>.activities where activity.attributes.planId == plan.id {
            if plan.status == "completed" || plan.status == "cancelled" {
                await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .default)
                if liveActivityPlanId == plan.id { liveActivityPlanId = nil }
            } else {
                await activity.update(ActivityContent(state: state, staleDate: scheduled.addingTimeInterval(900)))
                liveActivityPlanId = plan.id
            }
        }
    }

    func stopLiveActivity(planId: String) async {
        for activity in Activity<FoddDiningActivityAttributes>.activities where activity.attributes.planId == planId {
            let state = activity.content.state
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
        }
        if liveActivityPlanId == planId { liveActivityPlanId = nil }
    }
    #endif

    static func date(_ text: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: text) { return date }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: text)
    }
}

#if canImport(GroupActivities)
struct FoddTogetherShareActivity: GroupActivity, Codable {
    let planId: String
    let title: String
    let restaurantName: String

    var metadata: GroupActivityMetadata {
        var value = GroupActivityMetadata()
        value.title = "Makan Bareng • \(title)"
        value.subtitle = restaurantName.isEmpty ? "Rencanakan kuliner bersama di Fodd" : restaurantName
        value.type = .generic
        return value
    }
}

enum FoddSharePlay {
    static func start(plan: DiningPlan) async -> Bool {
        #if FODD_PERSONAL_TEAM
        return false
        #else
        let activity = FoddTogetherShareActivity(planId: plan.id, title: plan.title, restaurantName: plan.selectedRestaurant?.name ?? "")
        switch await activity.prepareForActivation() {
        case .activationPreferred:
            return (try? await activity.activate()) ?? false
        case .activationDisabled, .cancelled:
            return false
        @unknown default:
            return false
        }
        #endif
    }
}
#else
enum FoddSharePlay { static func start(plan: DiningPlan) async -> Bool { false } }
#endif

struct FoddLookAroundCard: View {
    let restaurant: Restaurant
    @State private var scene: MKLookAroundScene?
    @State private var viewer = false
    @State private var checked = false

    var body: some View {
        Group {
            if let scene {
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Label("Look Around", systemImage: "binoculars.fill").font(.headline); Spacer(); Button("Jelajahi") { viewer = true }.font(.caption.bold()) }
                    LookAroundPreview(initialScene: scene)
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .allowsHitTesting(false)
                }
                .padding(14)
                .premiumCard()
                .lookAroundViewer(isPresented: $viewer, initialScene: scene)
            }
        }
        .task {
            guard !checked else { return }; checked = true
            guard let latitude = restaurant.latitude, let longitude = restaurant.longitude else { return }
            let request = MKLookAroundSceneRequest(coordinate: .init(latitude: latitude, longitude: longitude))
            scene = try? await request.scene
        }
    }
}

struct AppleExperienceSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var manager = FoddAppleExperienceManager.shared

    var body: some View {
        NavigationStack {
            List {
                if FoddBuildMode.personalTeam {
                    Section("Personal Team Mode") {
                        Label("Siap dipasang dengan Apple Personal Team", systemImage: "checkmark.shield.fill")
                        Text("Push remote, SharePlay, App Group Widget, dan Dynamic Island remote dinonaktifkan pada build ini. Semua source fitur 7.0 tetap disimpan.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Label("Widget: Taste DNA, rekomendasi, Makan Bareng", systemImage: "rectangle.grid.2x2.fill")
                    Label("Siri & Shortcuts: Explore, Diary, Together", systemImage: "mic.badge.plus")
                    Label("Spotlight: restoran, moment, foodie, plan", systemImage: "magnifyingglass.circle.fill")
                    Label("Live Activity & Dynamic Island untuk Makan Bareng", systemImage: "dynamic.island")
                    Label("SharePlay untuk membuka rencana bersama", systemImage: "shareplay")
                    Label("Look Around pada restoran yang didukung Apple Maps", systemImage: "binoculars.fill")
                } header: { Text("Apple Experience") }
                Section("Status") {
                    HStack { Text("Widget data"); Spacer(); Text(FoddSharedContainer.loadWidgetSnapshot().displayName).foregroundStyle(.secondary) }
                    HStack { Text("Live Activity"); Spacer(); Text(manager.liveActivityPlanId == nil ? "Tidak aktif" : "Aktif").foregroundStyle(manager.liveActivityPlanId == nil ? .secondary : foddOrange) }
                    HStack { Text("Spotlight"); Spacer(); Text(manager.lastSpotlightSync == nil ? "Belum sinkron" : "Siap").foregroundStyle(.secondary) }
                }
                Section {
                    Button { manager.sync(account: store.account, smartDashboard: store.smartDashboard, restaurants: store.restaurants, moments: store.moments, members: store.members, diningPlans: store.diningPlans); FoddFeedbackManager.shared.success() } label: { Label("Refresh Widget & Spotlight", systemImage: "arrow.clockwise") }
                }
            }
            .navigationTitle("Apple Experience")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Tutup") { dismiss() } } }
        }
    }
}

struct OpenFoddExploreIntent: AppIntent {
    static var title: LocalizedStringResource = "Explore Food in Fodd"
    static var description = IntentDescription("Buka Fodd Explore untuk menemukan restoran dan rekomendasi Smart Food.")
    static var openAppWhenRun: Bool = true
    func perform() async throws -> some IntentResult {
        FoddSharedContainer.setPendingRoute("explore")
        return .result()
    }
}

struct OpenFoddDiaryIntent: AppIntent {
    static var title: LocalizedStringResource = "Open My Food Diary"
    static var description = IntentDescription("Buka Food Diary dan Taste DNA di profil Fodd.")
    static var openAppWhenRun: Bool = true
    func perform() async throws -> some IntentResult {
        FoddSharedContainer.setPendingRoute("profile")
        return .result()
    }
}

struct OpenFoddTogetherIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Makan Bareng"
    static var description = IntentDescription("Buka rencana Makan Bareng di Fodd.")
    static var openAppWhenRun: Bool = true
    func perform() async throws -> some IntentResult {
        FoddSharedContainer.setPendingRoute("together")
        return .result()
    }
}

struct FoddAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenFoddExploreIntent(), phrases: ["Explore food with \(.applicationName)", "Cari tempat makan di \(.applicationName)"], shortTitle: "Explore Food", systemImageName: "fork.knife.circle")
        AppShortcut(intent: OpenFoddDiaryIntent(), phrases: ["Open my food diary in \(.applicationName)", "Buka Food Diary di \(.applicationName)"], shortTitle: "Food Diary", systemImageName: "book.closed.fill")
        AppShortcut(intent: OpenFoddTogetherIntent(), phrases: ["Open makan bareng in \(.applicationName)", "Buka Makan Bareng di \(.applicationName)"], shortTitle: "Makan Bareng", systemImageName: "person.3.fill")
    }
}
