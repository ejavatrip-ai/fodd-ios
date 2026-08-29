import Foundation
import CoreLocation
import MapKit
import UIKit
import UserNotifications

extension Notification.Name {
    static let foddDeviceTokenDidChange = Notification.Name("foddDeviceTokenDidChange")
}

final class FoddAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey:Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate=self
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 256 * 1024 * 1024, diskPath: "fodd-image-cache")
        return true
    }

    func application(_ application:UIApplication,didRegisterForRemoteNotificationsWithDeviceToken deviceToken:Data) {
        let token=deviceToken.map{String(format:"%02x",$0)}.joined()
        UserDefaults.standard.set(token,forKey:"fodd.deviceToken")
        NotificationCenter.default.post(name:.foddDeviceTokenDidChange,object:nil)
    }

    func application(_ application:UIApplication,didFailToRegisterForRemoteNotificationsWithError error:Error) {
        print("APNs registration gagal: \(error.localizedDescription)")
    }

    func userNotificationCenter(_ center:UNUserNotificationCenter,willPresent notification:UNNotification,withCompletionHandler completionHandler:@escaping (UNNotificationPresentationOptions)->Void) {
        completionHandler([.banner,.sound,.badge])
    }

    func userNotificationCenter(_ center:UNUserNotificationCenter,didReceive response:UNNotificationResponse,withCompletionHandler completionHandler:@escaping ()->Void) {
        let info=response.notification.request.content.userInfo
        if response.actionIdentifier == "FODD_OPEN_MAPS",
           let lat=info["latitude"] as? Double, let lon=info["longitude"] as? Double {
            let name=(info["restaurantName"] as? String ?? "Tempat Nongkrong").addingPercentEncoding(withAllowedCharacters:.urlQueryAllowed) ?? "Tempat"
            if let url=URL(string:"http://maps.apple.com/?ll=\(lat),\(lon)&q=\(name)&dirflg=d") {
                DispatchQueue.main.async { UIApplication.shared.open(url) }
                completionHandler(); return
            }
        }
        if let deep=info["deepLink"] as? String, let url=URL(string:deep) {
            DispatchQueue.main.async { UIApplication.shared.open(url) }
        } else if let planId=info["planId"] as? String, let url=URL(string:"fodd://together/\(planId)") {
            DispatchQueue.main.async { UIApplication.shared.open(url) }
        }
        completionHandler()
    }
}

@MainActor
final class PushNotificationManager: ObservableObject {
    static let shared=PushNotificationManager()
    @Published var authorizationStatus:UNAuthorizationStatus = .notDetermined
    private init() { refreshStatus() }

    func refreshStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in self.authorizationStatus=settings.authorizationStatus }
        }
    }

    func requestAuthorizationAndRegister() {
        UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.badge,.sound]) { granted,_ in
            Task { @MainActor in
                self.refreshStatus()
                #if FODD_PERSONAL_TEAM
                // Personal Team does not support the Push Notifications entitlement.
                _ = granted
                #else
                if granted { UIApplication.shared.registerForRemoteNotifications() }
                #endif
            }
        }
    }
}

@MainActor
final class LocationManager:NSObject,ObservableObject,CLLocationManagerDelegate {
    private let manager=CLLocationManager()
    @Published var coordinate:CLLocationCoordinate2D?
    @Published var authorizationStatus:CLAuthorizationStatus = .notDetermined
    @Published var errorMessage:String?

    override init() {
        super.init()
        manager.delegate=self
        manager.desiredAccuracy=kCLLocationAccuracyHundredMeters
        authorizationStatus=manager.authorizationStatus
    }

    func request() {
        authorizationStatus=manager.authorizationStatus
        switch authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways,.authorizedWhenInUse: manager.requestLocation()
        case .denied,.restricted: errorMessage="Akses lokasi dimatikan. Aktifkan dari Settings agar Fodd dapat mencari restoran di sekitar Anda."
        @unknown default: break
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let latitude = locations.last?.coordinate.latitude
        let longitude = locations.last?.coordinate.longitude
        Task { @MainActor [weak self] in
            if let latitude, let longitude {
                self?.coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            }
            self?.errorMessage = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            self?.errorMessage = message
        }
    }
}

struct NearbyRestaurant:Identifiable,Hashable {
    let id:String
    let name:String
    let category:String
    let address:String
    let phone:String
    let website:String
    let latitude:Double
    let longitude:Double
    let distanceMeters:Double

    var coordinate:CLLocationCoordinate2D { .init(latitude:latitude,longitude:longitude) }
    var distanceText:String {
        if distanceMeters < 1000 { return "\(Int(distanceMeters)) m" }
        return String(format:"%.1f km",distanceMeters/1000)
    }

    func mapItem() -> MKMapItem {
        let item=MKMapItem(placemark:MKPlacemark(coordinate:coordinate))
        item.name=name
        item.phoneNumber=phone.isEmpty ? nil:phone
        item.url=URL(string:website)
        return item
    }
}

@MainActor
final class NearbyRestaurantService:ObservableObject {
    @Published var items:[NearbyRestaurant]=[]
    @Published var isLoading=false
    @Published var errorMessage:String?

    func search(center:CLLocationCoordinate2D,query:String="restaurant") async {
        isLoading=true; errorMessage=nil; defer{isLoading=false}
        let request=MKLocalSearch.Request()
        request.naturalLanguageQuery=query.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? "restaurant":query
        request.region=MKCoordinateRegion(center:center,latitudinalMeters:12_000,longitudinalMeters:12_000)
        if query.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || query.lowercased()=="restaurant" {
            request.pointOfInterestFilter=MKPointOfInterestFilter(including:[.restaurant,.cafe,.bakery])
        }
        do {
            let response=try await MKLocalSearch(request:request).start()
            let origin=CLLocation(latitude:center.latitude,longitude:center.longitude)
            items=response.mapItems.compactMap { mapItem in
                guard let name=mapItem.name,!name.isEmpty else{return nil}
                let c=mapItem.placemark.coordinate
                let distance=origin.distance(from:CLLocation(latitude:c.latitude,longitude:c.longitude))
                let address=[mapItem.placemark.subThoroughfare,mapItem.placemark.thoroughfare,mapItem.placemark.locality,mapItem.placemark.administrativeArea].compactMap{$0}.joined(separator:", ")
                let category=Self.categoryName(mapItem.pointOfInterestCategory)
                let stable="apple-\(Self.slug(name))-\(String(format:"%.5f",c.latitude))-\(String(format:"%.5f",c.longitude))"
                return NearbyRestaurant(id:stable,name:name,category:category,address:address,phone:mapItem.phoneNumber ?? "",website:mapItem.url?.absoluteString ?? "",latitude:c.latitude,longitude:c.longitude,distanceMeters:distance)
            }.sorted{$0.distanceMeters < $1.distanceMeters}.prefix(30).map{$0}
        } catch { errorMessage=error.localizedDescription }
    }

    private static func categoryName(_ value:MKPointOfInterestCategory?) -> String {
        switch value {
        case .restaurant: "Restoran"
        case .cafe: "Kafe"
        case .bakery: "Toko Roti"
        default: "Kuliner"
        }
    }
    private static func slug(_ value:String)->String {
        value.lowercased().folding(options:.diacriticInsensitive,locale:.current).replacingOccurrences(of:"[^a-z0-9]+",with:"-",options:.regularExpression).trimmingCharacters(in:CharacterSet(charactersIn:"-"))
    }
}

struct OSMPlaceDetails:Hashable {
    let openingHours:String
    let cuisine:String
    let phone:String
    let website:String
}

struct OSMPlaceDetailsService {
    func fetch(for place:NearbyRestaurant) async -> OSMPlaceDetails? {
        let query="""
        [out:json][timeout:8];
        (nwr(around:120,\(place.latitude),\(place.longitude))[\"amenity\"~\"restaurant|cafe|fast_food|food_court\"];);
        out center tags;
        """
        guard var components=URLComponents(string:"https://overpass-api.de/api/interpreter") else{return nil}
        components.queryItems=[URLQueryItem(name:"data",value:query)]
        guard let url=components.url else{return nil}
        do {
            let (data,response)=try await URLSession.shared.data(from:url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else{return nil}
            let decoded=try JSONDecoder().decode(OSMResponse.self,from:data)
            let normalized=normalize(place.name)
            let best=decoded.elements.sorted { score($0.tags?.name ?? "",normalized) > score($1.tags?.name ?? "",normalized) }.first
            guard let tags=best?.tags else{return nil}
            return OSMPlaceDetails(openingHours:tags.openingHours ?? "",cuisine:(tags.cuisine ?? "").replacingOccurrences(of:";",with:", "),phone:tags.phone ?? tags.contactPhone ?? "",website:tags.website ?? tags.contactWebsite ?? "")
        } catch { return nil }
    }

    private func normalize(_ text:String)->String { text.lowercased().folding(options:.diacriticInsensitive,locale:.current) }
    private func score(_ candidate:String,_ target:String)->Int {
        let c=normalize(candidate)
        if c == target { return 100 }
        if c.contains(target) || target.contains(c) { return 70 }
        let a=Set(c.split(separator:" ").map(String.init)); let b=Set(target.split(separator:" ").map(String.init))
        return a.intersection(b).count*10
    }
}

private struct OSMResponse:Decodable { let elements:[OSMElement] }
private struct OSMElement:Decodable { let tags:OSMTags? }
private struct OSMTags:Decodable {
    let name:String?
    let openingHours:String?
    let cuisine:String?
    let phone:String?
    let website:String?
    let contactPhone:String?
    let contactWebsite:String?
    enum CodingKeys:String,CodingKey {
        case name,cuisine,phone,website
        case openingHours="opening_hours"
        case contactPhone="contact:phone"
        case contactWebsite="contact:website"
    }
}

// MARK: - Fodd 7.4 Smart Together Reminders

enum TogetherReminderPreset: String, CaseIterable, Identifiable, Codable {
    case dayBefore, twoHours, thirtyMinutes
    var id: String { rawValue }
    var secondsBefore: TimeInterval {
        switch self {
        case .dayBefore: 86_400
        case .twoHours: 7_200
        case .thirtyMinutes: 1_800
        }
    }
    var title: String {
        switch self {
        case .dayBefore: "H-1"
        case .twoHours: "2 jam"
        case .thirtyMinutes: "30 menit"
        }
    }
    var subtitle: String {
        switch self {
        case .dayBefore: "Sehari sebelum nongkrong"
        case .twoHours: "Waktunya bersiap"
        case .thirtyMinutes: "Sebentar lagi berangkat"
        }
    }
    var icon: String {
        switch self {
        case .dayBefore: "calendar.badge.clock"
        case .twoHours: "clock.fill"
        case .thirtyMinutes: "figure.walk"
        }
    }
}

@MainActor
final class TogetherReminderManager: ObservableObject {
    static let shared = TogetherReminderManager()
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var pendingCount: Int = 0

    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private let selectionPrefix = "fodd.together.reminders."
    private let departurePrefix = "fodd.together.departure."
    private let notificationPrefix = "fodd.together.local."

    private init() {
        refreshAuthorizationStatus()
        registerCategories()
        refreshPendingCount()
    }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            authorizationStatus = granted ? .authorized : .denied
            return granted
        } catch {
            refreshAuthorizationStatus()
            return false
        }
    }

    func refreshAuthorizationStatus() {
        center.getNotificationSettings { settings in
            Task { @MainActor in self.authorizationStatus = settings.authorizationStatus }
        }
    }

    func selectedPresets(for planId: String) -> Set<TogetherReminderPreset> {
        guard let raw = defaults.array(forKey: selectionPrefix + planId) as? [String] else {
            return Set(TogetherReminderPreset.allCases)
        }
        return Set(raw.compactMap(TogetherReminderPreset.init(rawValue:)))
    }

    func setSelectedPresets(_ presets: Set<TogetherReminderPreset>, for plan: DiningPlan) async {
        defaults.set(presets.map(\.rawValue), forKey: selectionPrefix + plan.id)
        await schedule(plan: plan, presets: presets)
    }

    func schedule(plan: DiningPlan, presets: Set<TogetherReminderPreset>? = nil) async {
        guard plan.status == "planned", let date = parseTogetherISODate(plan.scheduledAt), date > Date() else {
            cancel(planId: plan.id)
            return
        }
        let chosen = presets ?? selectedPresets(for: plan.id)
        cancelScheduledRequests(planId: plan.id, keepDeparture: true)
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else { return }

        for preset in chosen {
            let fireDate = date.addingTimeInterval(-preset.secondsBefore)
            guard fireDate > Date().addingTimeInterval(5) else { continue }
            let content = contentFor(plan: plan, preset: preset)
            let trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year,.month,.day,.hour,.minute,.second], from: fireDate), repeats: false)
            let request = UNNotificationRequest(identifier: identifier(planId: plan.id, suffix: preset.rawValue), content: content, trigger: trigger)
            try? await center.add(request)
        }
        refreshPendingCount()
    }

    func scheduleDeparture(plan: DiningPlan, travelTime: TimeInterval, buffer: TimeInterval = 600) async -> Date? {
        guard let date = parseTogetherISODate(plan.scheduledAt), date > Date(), travelTime > 0 else { return nil }
        let fireDate = date.addingTimeInterval(-(travelTime + buffer))
        guard fireDate > Date().addingTimeInterval(10) else { return nil }
        if authorizationStatus == .notDetermined { _ = await requestAuthorization() }
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else { return nil }
        center.removePendingNotificationRequests(withIdentifiers: [identifier(planId: plan.id, suffix: "departure")])
        let content = UNMutableNotificationContent()
        content.title = "Waktunya berangkat 🚗"
        let venue = plan.selectedRestaurant?.name ?? plan.candidates.first?.restaurant.name ?? "tempat nongkrong"
        content.body = "Perjalanan ke \(venue) sekitar \(max(1, Int(round(travelTime / 60)))) menit. Berangkat sekarang agar tidak terlambat."
        content.sound = .default
        content.categoryIdentifier = "FODD_TOGETHER_REMINDER"
        content.userInfo = togetherUserInfo(plan)
        let trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year,.month,.day,.hour,.minute,.second], from: fireDate), repeats: false)
        try? await center.add(UNNotificationRequest(identifier: identifier(planId: plan.id, suffix: "departure"), content: content, trigger: trigger))
        defaults.set(fireDate.timeIntervalSince1970, forKey: departurePrefix + plan.id)
        refreshPendingCount()
        return fireDate
    }

    func departureDate(for planId: String) -> Date? {
        let value = defaults.double(forKey: departurePrefix + planId)
        return value > 0 ? Date(timeIntervalSince1970: value) : nil
    }

    func sync(plans: [DiningPlan]) async {
        let planned = plans.filter { $0.status == "planned" && (parseTogetherISODate($0.scheduledAt) ?? .distantPast) > Date() }
            .sorted { $0.scheduledAt < $1.scheduledAt }
        let activeIds = Set(planned.prefix(18).map(\.id))
        for plan in plans {
            if activeIds.contains(plan.id) { await schedule(plan: plan) }
            else if plan.status != "planned" { cancel(planId: plan.id) }
        }
    }

    func cancel(planId: String) {
        let ids = TogetherReminderPreset.allCases.map { identifier(planId: planId, suffix: $0.rawValue) } + [identifier(planId: planId, suffix: "departure")]
        center.removePendingNotificationRequests(withIdentifiers: ids)
        defaults.removeObject(forKey: departurePrefix + planId)
        refreshPendingCount()
    }

    private func cancelScheduledRequests(planId: String, keepDeparture: Bool) {
        var ids = TogetherReminderPreset.allCases.map { identifier(planId: planId, suffix: $0.rawValue) }
        if !keepDeparture { ids.append(identifier(planId: planId, suffix: "departure")) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    private func contentFor(plan: DiningPlan, preset: TogetherReminderPreset) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let venue = plan.selectedRestaurant?.name ?? plan.candidates.first?.restaurant.name ?? "tempat pilihan kalian"
        switch preset {
        case .dayBefore:
            content.title = "Besok waktunya nongkrong ☕"
            content.body = "\(plan.title) • \(venue). Cek rencana dan pastikan RSVP kamu."
        case .twoHours:
            content.title = "2 jam lagi 🍽️"
            content.body = "\(plan.title) sebentar lagi. Siapkan diri dan cek lokasi \(venue)."
        case .thirtyMinutes:
            content.title = "30 menit lagi! 🔥"
            content.body = "\(plan.title) akan dimulai. Tap untuk buka lokasi dan rencana nongkrong."
        }
        content.sound = .default
        content.categoryIdentifier = "FODD_TOGETHER_REMINDER"
        content.userInfo = togetherUserInfo(plan)
        return content
    }

    private func togetherUserInfo(_ plan: DiningPlan) -> [AnyHashable: Any] {
        var info: [AnyHashable: Any] = ["planId": plan.id, "deepLink": "fodd://together/\(plan.id)"]
        if let restaurant = plan.selectedRestaurant ?? plan.candidates.first?.restaurant,
           let lat = restaurant.latitude, let lon = restaurant.longitude {
            info["latitude"] = lat; info["longitude"] = lon; info["restaurantName"] = restaurant.name
        }
        return info
    }

    private func identifier(planId: String, suffix: String) -> String { notificationPrefix + planId + "." + suffix }

    private func refreshPendingCount() {
        center.getPendingNotificationRequests { requests in
            let count = requests.filter { $0.identifier.hasPrefix(self.notificationPrefix) }.count
            Task { @MainActor in self.pendingCount = count }
        }
    }

    private func registerCategories() {
        let open = UNNotificationAction(identifier: "FODD_OPEN_PLAN", title: "Lihat Rencana", options: [.foreground])
        let maps = UNNotificationAction(identifier: "FODD_OPEN_MAPS", title: "Buka Maps", options: [.foreground])
        let category = UNNotificationCategory(identifier: "FODD_TOGETHER_REMINDER", actions: [open, maps], intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }
}

private func parseTogetherISODate(_ raw: String) -> Date? {
    let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
}

@MainActor
final class TogetherTravelEstimator: ObservableObject {
    @Published var isLoading = false
    @Published var travelTime: TimeInterval?
    @Published var errorMessage: String?

    func calculate(from source: CLLocationCoordinate2D, to restaurant: Restaurant) async {
        guard let lat = restaurant.latitude, let lon = restaurant.longitude else { errorMessage = "Lokasi restoran belum tersedia."; return }
        isLoading = true; errorMessage = nil; defer { isLoading = false }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: source))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)))
        request.transportType = .automobile
        do {
            let response = try await MKDirections(request: request).calculate()
            travelTime = response.routes.first?.expectedTravelTime
            if travelTime == nil { errorMessage = "Estimasi perjalanan belum tersedia." }
        } catch { errorMessage = error.localizedDescription }
    }
}
