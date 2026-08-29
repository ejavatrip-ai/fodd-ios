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
        if let planId=info["planId"] as? String, let url=URL(string:"fodd://together/\(planId)") {
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

    func locationManagerDidChangeAuthorization(_ manager:CLLocationManager) {
        authorizationStatus=manager.authorizationStatus
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways { manager.requestLocation() }
    }
    func locationManager(_ manager:CLLocationManager,didUpdateLocations locations:[CLLocation]) { coordinate=locations.last?.coordinate; errorMessage=nil }
    func locationManager(_ manager:CLLocationManager,didFailWithError error:Error) { errorMessage=error.localizedDescription }
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
