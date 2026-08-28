import Foundation

struct Envelope<T: Decodable>: Decodable { let data: T }

struct AuthResponse: Decodable {
    let token: String
    let user: Account
}

struct Account: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let username: String
    let email: String
    let bio: String
    let avatar: String
    let isEmailVerified: Bool
    var isPrivate: Bool
    var isCreator: Bool
    var creatorVerified: Bool
    var creatorCategory: String
    var creatorWebsite: String

    enum CodingKeys: String, CodingKey { case id, name, username, email, bio, avatar, isEmailVerified, isPrivate, isCreator, creatorVerified, creatorCategory, creatorWebsite }
    init(id:String,name:String,username:String,email:String,bio:String,avatar:String,isEmailVerified:Bool=false,isPrivate:Bool=false,isCreator:Bool=false,creatorVerified:Bool=false,creatorCategory:String="",creatorWebsite:String="") {
        self.id=id; self.name=name; self.username=username; self.email=email; self.bio=bio; self.avatar=avatar; self.isEmailVerified=isEmailVerified; self.isPrivate=isPrivate; self.isCreator=isCreator; self.creatorVerified=creatorVerified; self.creatorCategory=creatorCategory; self.creatorWebsite=creatorWebsite
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey:.id)
        name = try c.decode(String.self, forKey:.name)
        username = try c.decode(String.self, forKey:.username)
        email = try c.decode(String.self, forKey:.email)
        bio = try c.decodeIfPresent(String.self, forKey:.bio) ?? ""
        avatar = try c.decodeIfPresent(String.self, forKey:.avatar) ?? ""
        isEmailVerified = try c.decodeIfPresent(Bool.self, forKey:.isEmailVerified) ?? false
        isPrivate = try c.decodeIfPresent(Bool.self, forKey:.isPrivate) ?? false
        isCreator = try c.decodeIfPresent(Bool.self, forKey:.isCreator) ?? false
        creatorVerified = try c.decodeIfPresent(Bool.self, forKey:.creatorVerified) ?? false
        creatorCategory = try c.decodeIfPresent(String.self, forKey:.creatorCategory) ?? ""
        creatorWebsite = try c.decodeIfPresent(String.self, forKey:.creatorWebsite) ?? ""
    }
    var cacheSafe: Account { Account(id:id,name:name,username:username,email:email,bio:bio,avatar:avatar.hasPrefix("data:image") ? "" : avatar,isEmailVerified:isEmailVerified,isPrivate:isPrivate,isCreator:isCreator,creatorVerified:creatorVerified,creatorCategory:creatorCategory,creatorWebsite:creatorWebsite) }
}

enum MomentType: String, Codable, CaseIterable, Identifiable, Hashable {
    case photo, checkin, eating, cooking, craving, thought
    var id: String { rawValue }
    var title: String { switch self { case .photo:"Food Photo"; case .checkin:"Check In"; case .eating:"Eating"; case .cooking:"Cooking"; case .craving:"Craving"; case .thought:"Thought" } }
    var subtitle: String { switch self { case .photo:"Bagikan foto makanan"; case .checkin:"Check-in di restoran"; case .eating:"Sedang makan apa"; case .cooking:"Sedang memasak apa"; case .craving:"Lagi ingin makan apa"; case .thought:"Cerita kuliner atau opini" } }
    var systemImage: String { switch self { case .photo:"camera.fill"; case .checkin:"mappin.and.ellipse"; case .eating:"fork.knife"; case .cooking:"frying.pan.fill"; case .craving:"face.smiling.inverse"; case .thought:"square.and.pencil" } }
}

enum MomentVisibility: String, Codable, CaseIterable, Identifiable, Hashable {
    case everyone, friends, closeFoodies = "close_foodies", selected, onlyMe = "only_me"
    var id: String { rawValue }
    var title: String { switch self { case .everyone:"Everyone"; case .friends:"Friends"; case .closeFoodies:"Close Foodies"; case .selected:"Selected Friends"; case .onlyMe:"Only Me" } }
    var subtitle: String { switch self { case .everyone:"Semua orang di Fodd"; case .friends:"Teman yang saling mengikuti"; case .closeFoodies:"Lingkaran foodie terdekat"; case .selected:"Hanya teman yang dipilih"; case .onlyMe:"Jurnal pribadi Anda" } }
    var systemImage: String { switch self { case .everyone:"globe.asia.australia.fill"; case .friends:"person.2.fill"; case .closeFoodies:"star.fill"; case .selected:"person.crop.circle.badge.checkmark"; case .onlyMe:"lock.fill" } }
}

enum MomentReaction: String, Codable, CaseIterable, Identifiable, Hashable {
    case love, yummy, fire, wow
    var id: String { rawValue }
    var emoji: String { switch self { case .love:"❤️"; case .yummy:"🤤"; case .fire:"🔥"; case .wow:"😍" } }
}

struct Member: Identifiable, Codable, Hashable {
    let id, name, username, bio, avatar: String
    let followersCount, followingCount: Int
    var isFollowing: Bool
    var isCloseFoodie: Bool
    var isPrivate: Bool
    var followRequestPending: Bool
    var isBlocked: Bool
    var isCreator: Bool
    var creatorVerified: Bool
    var creatorCategory: String
    var creatorWebsite: String

    enum CodingKeys:String,CodingKey { case id,name,username,bio,avatar,followersCount,followingCount,isFollowing,isCloseFoodie,isPrivate,followRequestPending,isBlocked,isCreator,creatorVerified,creatorCategory,creatorWebsite }
    init(from decoder:Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        id=try c.decode(String.self,forKey:.id); name=try c.decode(String.self,forKey:.name); username=try c.decode(String.self,forKey:.username)
        bio=try c.decodeIfPresent(String.self,forKey:.bio) ?? ""; avatar=try c.decodeIfPresent(String.self,forKey:.avatar) ?? ""
        followersCount=try c.decodeIfPresent(Int.self,forKey:.followersCount) ?? 0; followingCount=try c.decodeIfPresent(Int.self,forKey:.followingCount) ?? 0
        isFollowing=try c.decodeIfPresent(Bool.self,forKey:.isFollowing) ?? false; isCloseFoodie=try c.decodeIfPresent(Bool.self,forKey:.isCloseFoodie) ?? false
        isPrivate=try c.decodeIfPresent(Bool.self,forKey:.isPrivate) ?? false; followRequestPending=try c.decodeIfPresent(Bool.self,forKey:.followRequestPending) ?? false; isBlocked=try c.decodeIfPresent(Bool.self,forKey:.isBlocked) ?? false
        isCreator=try c.decodeIfPresent(Bool.self,forKey:.isCreator) ?? false; creatorVerified=try c.decodeIfPresent(Bool.self,forKey:.creatorVerified) ?? false; creatorCategory=try c.decodeIfPresent(String.self,forKey:.creatorCategory) ?? ""; creatorWebsite=try c.decodeIfPresent(String.self,forKey:.creatorWebsite) ?? ""
    }
    init(id:String,name:String,username:String,bio:String,avatar:String,followersCount:Int,followingCount:Int,isFollowing:Bool,isCloseFoodie:Bool,isPrivate:Bool,followRequestPending:Bool,isBlocked:Bool,isCreator:Bool=false,creatorVerified:Bool=false,creatorCategory:String="",creatorWebsite:String="") {
        self.id=id;self.name=name;self.username=username;self.bio=bio;self.avatar=avatar;self.followersCount=followersCount;self.followingCount=followingCount;self.isFollowing=isFollowing;self.isCloseFoodie=isCloseFoodie;self.isPrivate=isPrivate;self.followRequestPending=followRequestPending;self.isBlocked=isBlocked;self.isCreator=isCreator;self.creatorVerified=creatorVerified;self.creatorCategory=creatorCategory;self.creatorWebsite=creatorWebsite
    }
    var cacheSafe: Member { Member(id:id,name:name,username:username,bio:bio,avatar:avatar.hasPrefix("data:image") ? "" : avatar,followersCount:followersCount,followingCount:followingCount,isFollowing:isFollowing,isCloseFoodie:isCloseFoodie,isPrivate:isPrivate,followRequestPending:followRequestPending,isBlocked:isBlocked,isCreator:isCreator,creatorVerified:creatorVerified,creatorCategory:creatorCategory,creatorWebsite:creatorWebsite) }
}

struct Moment: Identifiable, Codable, Hashable {
    let id, caption, image, createdAt, userId, name, username, avatar: String
    let creatorVerified: Bool
    let momentType: MomentType
    let locationName, locationAddress: String
    let latitude, longitude: Double?
    let visibility: MomentVisibility
    let taggedNames: [String]
    var likes, commentCount: Int
    var isLiked: Bool
    var reactions: [String:Int]
    var myReaction: String?

    enum CodingKeys:String,CodingKey { case id,caption,image,createdAt,userId,name,username,avatar,creatorVerified,momentType,locationName,locationAddress,latitude,longitude,visibility,taggedNames,likes,commentCount,isLiked,reactions,myReaction }
    init(from decoder:Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        id=try c.decode(String.self,forKey:.id); caption=try c.decode(String.self,forKey:.caption); image=try c.decodeIfPresent(String.self,forKey:.image) ?? ""
        createdAt=try c.decode(String.self,forKey:.createdAt); userId=try c.decode(String.self,forKey:.userId); name=try c.decode(String.self,forKey:.name); username=try c.decode(String.self,forKey:.username); avatar=try c.decodeIfPresent(String.self,forKey:.avatar) ?? ""; creatorVerified=try c.decodeIfPresent(Bool.self,forKey:.creatorVerified) ?? false
        momentType=try c.decodeIfPresent(MomentType.self,forKey:.momentType) ?? .photo; locationName=try c.decodeIfPresent(String.self,forKey:.locationName) ?? ""; locationAddress=try c.decodeIfPresent(String.self,forKey:.locationAddress) ?? ""
        latitude=try c.decodeIfPresent(Double.self,forKey:.latitude); longitude=try c.decodeIfPresent(Double.self,forKey:.longitude); visibility=try c.decodeIfPresent(MomentVisibility.self,forKey:.visibility) ?? .everyone
        taggedNames=try c.decodeIfPresent([String].self,forKey:.taggedNames) ?? []; likes=try c.decodeIfPresent(Int.self,forKey:.likes) ?? 0; commentCount=try c.decodeIfPresent(Int.self,forKey:.commentCount) ?? 0; isLiked=try c.decodeIfPresent(Bool.self,forKey:.isLiked) ?? false
        reactions=try c.decodeIfPresent([String:Int].self,forKey:.reactions) ?? [:]; myReaction=try c.decodeIfPresent(String.self,forKey:.myReaction)
    }

    init(id:String,caption:String,image:String,createdAt:String,userId:String,name:String,username:String,avatar:String,creatorVerified:Bool=false,momentType:MomentType,locationName:String,locationAddress:String,latitude:Double?,longitude:Double?,visibility:MomentVisibility,taggedNames:[String],likes:Int,commentCount:Int,isLiked:Bool,reactions:[String:Int],myReaction:String?) {
        self.id=id;self.caption=caption;self.image=image;self.createdAt=createdAt;self.userId=userId;self.name=name;self.username=username;self.avatar=avatar;self.creatorVerified=creatorVerified;self.momentType=momentType;self.locationName=locationName;self.locationAddress=locationAddress;self.latitude=latitude;self.longitude=longitude;self.visibility=visibility;self.taggedNames=taggedNames;self.likes=likes;self.commentCount=commentCount;self.isLiked=isLiked;self.reactions=reactions;self.myReaction=myReaction
    }

    var cacheSafe: Moment {
        Moment(id:id,caption:caption,image:image.hasPrefix("data:image") ? "" : image,createdAt:createdAt,userId:userId,name:name,username:username,avatar:avatar.hasPrefix("data:image") ? "" : avatar,creatorVerified:creatorVerified,momentType:momentType,locationName:locationName,locationAddress:locationAddress,latitude:latitude,longitude:longitude,visibility:visibility,taggedNames:taggedNames,likes:likes,commentCount:commentCount,isLiked:isLiked,reactions:reactions,myReaction:myReaction)
    }
}

struct MomentComment: Identifiable, Codable, Hashable {
    let id, body, createdAt, userId, name, username, avatar: String
}

struct AppNotification: Identifiable, Codable, Hashable {
    let id, type, body, createdAt, actorName: String
    let isRead: Bool
    let planId: String?
}

struct ChatMessage: Identifiable, Codable, Hashable {
    let id, senderId, receiverId, body, createdAt: String
    let isRead: Bool

    enum CodingKeys: String, CodingKey { case id, senderId, receiverId, body, createdAt, isRead }
    init(from decoder: Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        id=try c.decode(String.self,forKey:.id)
        senderId=try c.decode(String.self,forKey:.senderId)
        receiverId=try c.decode(String.self,forKey:.receiverId)
        body=try c.decode(String.self,forKey:.body)
        createdAt=try c.decode(String.self,forKey:.createdAt)
        isRead=try c.decodeIfPresent(Bool.self,forKey:.isRead) ?? true
    }
}

struct Conversation: Identifiable, Codable, Hashable {
    let member: Member
    let lastMessage: String
    let lastMessageAt: String
    let unreadCount: Int
    var id: String { member.id }
}

struct Restaurant: Identifiable, Codable, Hashable {
    let id, name, category, image: String
    let rating: Double
    let distance, price: String
    var isSaved: Bool
    let address, phone, hours, menu, website: String
    let latitude, longitude: Double?
    let isVerified: Bool
    let ownerCount: Int
    let isManagedByMe: Bool
    let managementRole: String

    enum CodingKeys: String, CodingKey { case id,name,category,image,rating,distance,price,isSaved,address,phone,hours,menu,website,latitude,longitude,isVerified,ownerCount,isManagedByMe,managementRole }
    init(from decoder: Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        id=try c.decode(String.self,forKey:.id)
        name=try c.decode(String.self,forKey:.name)
        category=try c.decode(String.self,forKey:.category)
        image=try c.decode(String.self,forKey:.image)
        rating=try c.decodeIfPresent(Double.self,forKey:.rating) ?? 0
        distance=try c.decodeIfPresent(String.self,forKey:.distance) ?? ""
        price=try c.decodeIfPresent(String.self,forKey:.price) ?? ""
        isSaved=try c.decodeIfPresent(Bool.self,forKey:.isSaved) ?? false
        address=try c.decodeIfPresent(String.self,forKey:.address) ?? ""
        phone=try c.decodeIfPresent(String.self,forKey:.phone) ?? ""
        hours=try c.decodeIfPresent(String.self,forKey:.hours) ?? ""
        menu=try c.decodeIfPresent(String.self,forKey:.menu) ?? ""
        website=try c.decodeIfPresent(String.self,forKey:.website) ?? ""
        latitude=try c.decodeIfPresent(Double.self,forKey:.latitude)
        longitude=try c.decodeIfPresent(Double.self,forKey:.longitude)
        isVerified=try c.decodeIfPresent(Bool.self,forKey:.isVerified) ?? false
        ownerCount=try c.decodeIfPresent(Int.self,forKey:.ownerCount) ?? 0
        isManagedByMe=try c.decodeIfPresent(Bool.self,forKey:.isManagedByMe) ?? false
        managementRole=try c.decodeIfPresent(String.self,forKey:.managementRole) ?? ""
    }
}

struct PlaceReview: Identifiable, Codable, Hashable {
    let id: String
    let placeId: String
    let rating: Int
    let body, photo, createdAt, userId, name, username, avatar: String
}

struct SearchResults: Decodable {
    let members: [Member]
    let restaurants: [Restaurant]
    let moments: [Moment]
}


struct FollowState: Decodable {
    let isFollowing: Bool
    let pending: Bool
    let message: String
}

struct FollowRequest: Identifiable, Codable, Hashable {
    let member: Member
    let createdAt: String
    var id: String { member.id }
}

struct FoddUserSettings: Codable, Hashable {
    var isPrivate: Bool
    var pushFollows: Bool
    var pushLikes: Bool
    var pushComments: Bool
    var pushMessages: Bool
    var pushRecommendations: Bool
    var pushTogether: Bool

    enum CodingKeys: String, CodingKey { case isPrivate,pushFollows,pushLikes,pushComments,pushMessages,pushRecommendations,pushTogether }
    init(isPrivate:Bool,pushFollows:Bool,pushLikes:Bool,pushComments:Bool,pushMessages:Bool,pushRecommendations:Bool=true,pushTogether:Bool=true) {
        self.isPrivate=isPrivate;self.pushFollows=pushFollows;self.pushLikes=pushLikes;self.pushComments=pushComments;self.pushMessages=pushMessages;self.pushRecommendations=pushRecommendations;self.pushTogether=pushTogether
    }
    init(from decoder:Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        isPrivate=try c.decodeIfPresent(Bool.self,forKey:.isPrivate) ?? false
        pushFollows=try c.decodeIfPresent(Bool.self,forKey:.pushFollows) ?? true
        pushLikes=try c.decodeIfPresent(Bool.self,forKey:.pushLikes) ?? true
        pushComments=try c.decodeIfPresent(Bool.self,forKey:.pushComments) ?? true
        pushMessages=try c.decodeIfPresent(Bool.self,forKey:.pushMessages) ?? true
        pushRecommendations=try c.decodeIfPresent(Bool.self,forKey:.pushRecommendations) ?? true
        pushTogether=try c.decodeIfPresent(Bool.self,forKey:.pushTogether) ?? true
    }
}

struct TastePreferences: Codable, Hashable {
    var cuisines: [String]
    var moods: [String]
    var spicyLevel: Int
    var priceSensitivity: Int
    var adventurousLevel: Int
    let updatedAt: String?

    init(cuisines:[String]=[],moods:[String]=[],spicyLevel:Int=2,priceSensitivity:Int=2,adventurousLevel:Int=2,updatedAt:String?=nil) {
        self.cuisines=cuisines;self.moods=moods;self.spicyLevel=spicyLevel;self.priceSensitivity=priceSensitivity;self.adventurousLevel=adventurousLevel;self.updatedAt=updatedAt
    }
}

struct TasteTrait: Codable, Hashable, Identifiable {
    let name: String
    let score: Int
    let icon: String
    var id: String { name }
}

struct TasteDNA: Codable, Hashable {
    let favoriteCategories: [String]
    let traits: [TasteTrait]
    let sampleSize: Int
    let confidence: Int
    let preferences: TastePreferences
    let updatedAt: String
}

struct SmartRestaurant: Codable, Hashable, Identifiable {
    let restaurant: Restaurant
    let matchScore: Int
    let reason: String
    let badges: [String]
    let distanceKm: Double?
    var id: String { restaurant.id }
}

struct FoodMemory: Codable, Hashable, Identifiable {
    let id: String
    let caption: String
    let image: String
    let locationName: String
    let locationAddress: String
    let createdAt: String
    let yearsAgo: Int
}

struct SmartFoodDashboard: Codable, Hashable {
    let taste: TasteDNA
    let forYou: [SmartRestaurant]
    let becauseYouLiked: [SmartRestaurant]
    let becauseBasis: String?
    let trending: [SmartRestaurant]
    let hiddenGems: [SmartRestaurant]
    let memories: [FoodMemory]
    let moods: [String]
}

struct FoodCollection: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var description: String
    var isPrivate: Bool
    var itemCount: Int
    let createdAt: String
    let ownerId: String
    let ownerName: String
    let myRole: String
    let memberCount: Int

    enum CodingKeys:String,CodingKey { case id,name,description,isPrivate,itemCount,createdAt,ownerId,ownerName,myRole,memberCount }
    init(from decoder:Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        id=try c.decode(String.self,forKey:.id);name=try c.decode(String.self,forKey:.name);description=try c.decodeIfPresent(String.self,forKey:.description) ?? "";isPrivate=try c.decodeIfPresent(Bool.self,forKey:.isPrivate) ?? true;itemCount=try c.decodeIfPresent(Int.self,forKey:.itemCount) ?? 0;createdAt=try c.decode(String.self,forKey:.createdAt);ownerId=try c.decodeIfPresent(String.self,forKey:.ownerId) ?? "";ownerName=try c.decodeIfPresent(String.self,forKey:.ownerName) ?? "You";myRole=try c.decodeIfPresent(String.self,forKey:.myRole) ?? "owner";memberCount=try c.decodeIfPresent(Int.self,forKey:.memberCount) ?? 0
    }
}

struct SharedCollectionMember: Identifiable, Codable, Hashable { let id,name,username,avatar,role:String }

enum DiningRSVP: String, Codable, CaseIterable, Identifiable {
    case pending, going, maybe, declined
    var id:String { rawValue }
    var title:String { switch self { case .pending:"Belum jawab"; case .going:"Ikut"; case .maybe:"Mungkin"; case .declined:"Tidak ikut" } }
    var icon:String { switch self { case .pending:"clock"; case .going:"checkmark.circle.fill"; case .maybe:"questionmark.circle.fill"; case .declined:"xmark.circle.fill" } }
}

struct DiningHost: Codable, Hashable { let id,name,username,avatar:String }
struct DiningMember: Identifiable, Codable, Hashable { let id,name,username,avatar:String; let rsvp:DiningRSVP; let isHost:Bool }
struct DiningCandidate: Identifiable, Codable, Hashable { let restaurant:Restaurant; let voteCount:Int; let myVote:Bool; let proposedBy:String; var id:String { restaurant.id } }
struct DiningPlan: Identifiable, Codable, Hashable {
    let id,title,note,scheduledAt,status,hostId,createdAt:String
    let isHost:Bool
    let myRsvp:DiningRSVP
    let host:DiningHost
    let selectedRestaurant:Restaurant?
    let memberCount,goingCount,maybeCount,photoCount,messageCount:Int
    let members:[DiningMember]
    let candidates:[DiningCandidate]
}
struct DiningPlanMessage: Identifiable, Codable, Hashable { let id,body,createdAt,userId,name,username,avatar:String }
struct DiningPlanPhoto: Identifiable, Codable, Hashable { let id,image,caption,createdAt,userId,name,username,avatar:String }
struct RSVPResponse: Decodable { let rsvp: DiningRSVP }

enum ReportReason: String, Codable, CaseIterable, Identifiable {
    case spam, harassment, hate, sexual, violence, misinformation, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .spam: "Spam atau penipuan"
        case .harassment: "Perundungan atau pelecehan"
        case .hate: "Ujaran kebencian"
        case .sexual: "Konten seksual"
        case .violence: "Kekerasan"
        case .misinformation: "Informasi menyesatkan"
        case .other: "Lainnya"
        }
    }
}

struct CreatorProfile: Codable, Hashable {
    let id: String
    let isCreator, isVerified: Bool
    let category, website: String
    let creatorSince: String?
    let momentCount, followersCount, totalLikes, totalComments, reviewCount: Int
}

struct RestaurantClaim: Identifiable, Codable, Hashable {
    let id, restaurantId: String
    let restaurantName: String?
    let businessName, role, note, status, createdAt: String
}

struct MenuItem: Identifiable, Codable, Hashable {
    let id, restaurantId, name, description, category, image, createdAt: String
    let price, sortOrder: Int
    let isAvailable: Bool
}

struct RestaurantPost: Identifiable, Codable, Hashable {
    let id, restaurantId, caption, image, createdAt, authorId, authorName: String
    let authorVerified: Bool
}

struct ActionResponse: Decodable {
    let message: String
    let devCode: String?
}

struct UnreadSummary: Decodable {
    let messages: Int
    let notifications: Int
}

enum APIError: LocalizedError {
    case invalidURL, invalidResponse, unauthorized(String), server(String)
    var errorDescription: String? {
        switch self {
        case .invalidURL: "Alamat server tidak valid."
        case .invalidResponse: "Respons server tidak valid."
        case .unauthorized(let message), .server(let message): message
        }
    }
}

struct APIClient {
    private let session = URLSession.shared
    private var baseURL: URL? {
        guard var raw = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String else { return nil }
        raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !raw.contains("$("), var url = URL(string: raw),
              let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme), url.host != nil else { return nil }
        if !url.absoluteString.hasSuffix("/") { url.appendPathComponent("") }
        return url
    }

    func register(name: String, username: String, email: String, password: String) async throws -> AuthResponse {
        try await request("api/auth/register", method:"POST", body:["name":name,"username":username,"email":email,"password":password])
    }
    func login(email: String, password: String) async throws -> AuthResponse {
        try await request("api/auth/login", method:"POST", body:["email":email,"password":password])
    }
    func forgotPassword(email:String) async throws -> ActionResponse {
        try await request("api/auth/forgot-password",method:"POST",body:["email":email])
    }
    func resetPassword(email:String,code:String,newPassword:String) async throws -> ActionResponse {
        try await request("api/auth/reset-password",method:"POST",body:["email":email,"code":code,"newPassword":newPassword])
    }
    func changePassword(currentPassword:String,newPassword:String,token:String) async throws -> ActionResponse {
        try await request("api/auth/change-password",method:"POST",token:token,body:["currentPassword":currentPassword,"newPassword":newPassword])
    }
    func requestEmailVerification(token:String) async throws -> ActionResponse {
        try await request("api/auth/request-verification",method:"POST",token:token)
    }
    func verifyEmail(code:String,token:String) async throws -> Account {
        try await request("api/auth/verify-email",method:"POST",token:token,body:["code":code])
    }
    func deleteAccount(password:String,token:String) async throws -> ActionResponse {
        try await request("api/account",method:"DELETE",token:token,body:["password":password])
    }
    func logout(token:String) async throws {
        let _:EmptyResponse = try await request("api/auth/logout",method:"POST",token:token)
    }
    func unregisterDevice(deviceToken:String,token:String) async throws {
        let _:EmptyResponse = try await request("api/devices/\(escapedPath(deviceToken))",method:"DELETE",token:token)
    }

    func me(token: String) async throws -> Account { try await request("api/me", token: token) }
    func updateMe(name: String, bio: String, avatar: String, token: String) async throws -> Account {
        try await request("api/me",method:"PATCH",token:token,body:["name":name,"bio":bio,"avatar":avatar])
    }
    func creatorProfile(token:String) async throws -> CreatorProfile { try await request("api/creator/me",token:token) }
    func updateCreatorProfile(isCreator:Bool,category:String,website:String,token:String) async throws -> Account {
        try await request("api/creator/me",method:"PATCH",token:token,body:["isCreator":isCreator,"category":category,"website":website])
    }

    func members(search: String, token: String) async throws -> [Member] {
        try await request("api/users?search=\(escaped(search))",token:token)
    }
    func follow(id: String, enabled: Bool, token: String) async throws -> FollowState {
        if enabled { return try await request("api/users/\(id)/follow",method:"PUT",token:token) }
        let _: EmptyResponse = try await request("api/users/\(id)/follow",method:"DELETE",token:token)
        return FollowState(isFollowing:false,pending:false,message:"Tidak mengikuti")
    }
    func followRequests(token:String) async throws -> [FollowRequest] { try await request("api/follow-requests",token:token) }
    func respondFollowRequest(id:String,accept:Bool,token:String) async throws {
        let _:EmptyResponse=try await request("api/follow-requests/\(id)",method:"POST",token:token,body:["accept":accept])
    }
    func blockedUsers(token:String) async throws -> [Member] { try await request("api/blocked-users",token:token) }
    func setBlocked(id:String,enabled:Bool,token:String) async throws {
        let _:EmptyResponse=try await request("api/users/\(id)/block",method:enabled ? "PUT":"DELETE",token:token)
    }
    func report(targetType:String,targetId:String,reason:ReportReason,details:String,token:String) async throws -> ActionResponse {
        try await request("api/reports",method:"POST",token:token,body:["targetType":targetType,"targetId":targetId,"reason":reason.rawValue,"details":details])
    }
    func closeFoodies(token:String) async throws -> [Member] { try await request("api/close-foodies",token:token) }
    func setCloseFoodie(id:String,enabled:Bool,token:String) async throws {
        let _:EmptyResponse=try await request("api/close-foodies/\(id)",method:enabled ? "PUT":"DELETE",token:token)
    }

    func restaurants(search:String="",token:String?=nil) async throws -> [Restaurant] {
        try await request("api/restaurants?search=\(escaped(search))",token:token)
    }
    func upsertRestaurant(id:String,name:String,category:String,address:String,phone:String,website:String,latitude:Double,longitude:Double,distance:String,token:String) async throws -> Restaurant {
        try await request("api/restaurants/\(escapedPath(id))",method:"PUT",token:token,body:["name":name,"category":category,"address":address,"phone":phone,"website":website,"latitude":latitude,"longitude":longitude,"distance":distance])
    }
    func saveRestaurant(id:String,enabled:Bool,token:String) async throws {
        let _:EmptyResponse=try await request("api/restaurants/\(escapedPath(id))/save",method:enabled ? "PUT":"DELETE",token:token)
    }
    func savedRestaurants(token:String) async throws -> [Restaurant] { try await request("api/me/saved-restaurants",token:token) }

    func claimRestaurant(id:String,businessName:String,role:String,note:String,token:String) async throws -> RestaurantClaim {
        try await request("api/restaurants/\(escapedPath(id))/claim",method:"POST",token:token,body:["businessName":businessName,"role":role,"note":note])
    }
    func restaurantClaims(token:String) async throws -> [RestaurantClaim] { try await request("api/me/restaurant-claims",token:token) }
    func myRestaurants(token:String) async throws -> [Restaurant] { try await request("api/my-restaurants",token:token) }
    func updateManagedRestaurant(_ item:Restaurant,name:String,category:String,address:String,phone:String,hours:String,website:String,price:String,image:String,token:String) async throws -> Restaurant {
        try await request("api/restaurant-studio/restaurants/\(escapedPath(item.id))",method:"PATCH",token:token,body:["name":name,"category":category,"address":address,"phone":phone,"hours":hours,"website":website,"price":price,"image":image])
    }
    func restaurantMenu(id:String,token:String?=nil) async throws -> [MenuItem] { try await request("api/restaurants/\(escapedPath(id))/menu",token:token) }
    func createMenuItem(restaurantId:String,name:String,description:String,category:String,price:Int,image:String,isAvailable:Bool,sortOrder:Int,token:String) async throws -> MenuItem {
        try await request("api/restaurants/\(escapedPath(restaurantId))/menu",method:"POST",token:token,body:["name":name,"description":description,"category":category,"price":price,"image":image,"isAvailable":isAvailable,"sortOrder":sortOrder])
    }
    func updateMenuItem(restaurantId:String,itemId:String,name:String,description:String,category:String,price:Int,image:String,isAvailable:Bool,sortOrder:Int,token:String) async throws -> MenuItem {
        try await request("api/restaurants/\(escapedPath(restaurantId))/menu/\(escapedPath(itemId))",method:"PATCH",token:token,body:["name":name,"description":description,"category":category,"price":price,"image":image,"isAvailable":isAvailable,"sortOrder":sortOrder])
    }
    func deleteMenuItem(restaurantId:String,itemId:String,token:String) async throws { let _:EmptyResponse=try await request("api/restaurants/\(escapedPath(restaurantId))/menu/\(escapedPath(itemId))",method:"DELETE",token:token) }
    func restaurantPosts(id:String,token:String?=nil) async throws -> [RestaurantPost] { try await request("api/restaurants/\(escapedPath(id))/posts",token:token) }
    func createRestaurantPost(restaurantId:String,caption:String,image:String,token:String) async throws -> RestaurantPost { try await request("api/restaurants/\(escapedPath(restaurantId))/posts",method:"POST",token:token,body:["caption":caption,"image":image]) }
    func deleteRestaurantPost(restaurantId:String,postId:String,token:String) async throws { let _:EmptyResponse=try await request("api/restaurants/\(escapedPath(restaurantId))/posts/\(escapedPath(postId))",method:"DELETE",token:token) }

    func settings(token:String) async throws -> FoddUserSettings { try await request("api/settings",token:token) }
    func updateSettings(_ settings:FoddUserSettings,token:String) async throws -> FoddUserSettings {
        try await request("api/settings",method:"PATCH",token:token,body:["isPrivate":settings.isPrivate,"pushFollows":settings.pushFollows,"pushLikes":settings.pushLikes,"pushComments":settings.pushComments,"pushMessages":settings.pushMessages,"pushRecommendations":settings.pushRecommendations,"pushTogether":settings.pushTogether])
    }

    func tastePreferences(token:String) async throws -> TastePreferences { try await request("api/smart/preferences",token:token) }
    func updateTastePreferences(_ value:TastePreferences,token:String) async throws -> TastePreferences {
        try await request("api/smart/preferences",method:"PATCH",token:token,body:["cuisines":value.cuisines,"moods":value.moods,"spicyLevel":value.spicyLevel,"priceSensitivity":value.priceSensitivity,"adventurousLevel":value.adventurousLevel])
    }
    func smartDashboard(latitude:Double?=nil,longitude:Double?=nil,mood:String="",token:String) async throws -> SmartFoodDashboard {
        var params:[String]=[]
        if let latitude { params.append("lat=\(latitude)") }
        if let longitude { params.append("lon=\(longitude)") }
        if !mood.isEmpty { params.append("mood=\(escaped(mood))") }
        let suffix=params.isEmpty ? "" : "?"+params.joined(separator:"&")
        return try await request("api/smart/dashboard\(suffix)",token:token)
    }
    func smartEvent(type:String,restaurantId:String?=nil,query:String="",weight:Double=1,token:String) async throws {
        var body:[String:Any]=["eventType":type,"query":query,"weight":weight]
        if let restaurantId { body["restaurantId"]=restaurantId }
        let _:EmptyResponse=try await request("api/smart/events",method:"POST",token:token,body:body)
    }

    func collections(token:String) async throws -> [FoodCollection] { try await request("api/collections",token:token) }
    func createCollection(name:String,description:String,isPrivate:Bool,token:String) async throws -> FoodCollection {
        try await request("api/collections",method:"POST",token:token,body:["name":name,"description":description,"isPrivate":isPrivate])
    }
    func deleteCollection(id:String,token:String) async throws { let _:EmptyResponse=try await request("api/collections/\(id)",method:"DELETE",token:token) }
    func collectionRestaurants(id:String,token:String) async throws -> [Restaurant] { try await request("api/collections/\(id)/restaurants",token:token) }
    func setCollectionRestaurant(collectionId:String,restaurantId:String,enabled:Bool,token:String) async throws {
        let _:EmptyResponse=try await request("api/collections/\(collectionId)/restaurants/\(escapedPath(restaurantId))",method:enabled ? "PUT":"DELETE",token:token)
    }
    func collectionMembers(id:String,token:String) async throws -> [SharedCollectionMember] { try await request("api/collections/\(id)/members",token:token) }
    func shareCollection(id:String,userId:String,role:String="editor",token:String) async throws { let _:EmptyResponse=try await request("api/collections/\(id)/members",method:"POST",token:token,body:["userId":userId,"role":role]) }
    func removeCollectionMember(id:String,userId:String,token:String) async throws { let _:EmptyResponse=try await request("api/collections/\(id)/members/\(userId)",method:"DELETE",token:token) }

    func diningPlans(token:String) async throws -> [DiningPlan] { try await request("api/together/plans",token:token) }
    func diningPlan(id:String,token:String) async throws -> DiningPlan { try await request("api/together/plans/\(id)",token:token) }
    func createDiningPlan(title:String,note:String,scheduledAt:String,memberIds:[String],candidateRestaurantIds:[String],token:String) async throws -> DiningPlan {
        try await request("api/together/plans",method:"POST",token:token,body:["title":title,"note":note,"scheduledAt":scheduledAt,"memberIds":memberIds,"candidateRestaurantIds":candidateRestaurantIds])
    }
    func updateDiningPlan(id:String,title:String?=nil,note:String?=nil,scheduledAt:String?=nil,status:String?=nil,selectedRestaurantId:String?=nil,clearSelected:Bool=false,token:String) async throws -> DiningPlan {
        var body:[String:Any]=[:];if let title {body["title"]=title};if let note {body["note"]=note};if let scheduledAt {body["scheduledAt"]=scheduledAt};if let status {body["status"]=status};if clearSelected {body["selectedRestaurantId"]=NSNull()} else if let selectedRestaurantId {body["selectedRestaurantId"]=selectedRestaurantId}
        return try await request("api/together/plans/\(id)",method:"PATCH",token:token,body:body)
    }
    func inviteToDiningPlan(id:String,memberIds:[String],token:String) async throws { let _:EmptyResponse=try await request("api/together/plans/\(id)/invite",method:"POST",token:token,body:["memberIds":memberIds]) }
    func diningRSVP(id:String,rsvp:DiningRSVP,token:String) async throws -> RSVPResponse { try await request("api/together/plans/\(id)/rsvp",method:"POST",token:token,body:["rsvp":rsvp.rawValue]) }
    func setDiningCandidate(planId:String,restaurantId:String,enabled:Bool,token:String) async throws { let _:EmptyResponse=try await request("api/together/plans/\(planId)/candidates/\(escapedPath(restaurantId))",method:enabled ? "PUT":"DELETE",token:token) }
    func voteDiningPlan(id:String,restaurantId:String,token:String) async throws { let _:EmptyResponse=try await request("api/together/plans/\(id)/vote",method:"PUT",token:token,body:["restaurantId":restaurantId]) }
    func diningMessages(id:String,token:String) async throws -> [DiningPlanMessage] { try await request("api/together/plans/\(id)/messages",token:token) }
    func sendDiningMessage(id:String,body:String,token:String) async throws -> DiningPlanMessage { try await request("api/together/plans/\(id)/messages",method:"POST",token:token,body:["body":body]) }
    func diningPhotos(id:String,token:String) async throws -> [DiningPlanPhoto] { try await request("api/together/plans/\(id)/photos",token:token) }
    func addDiningPhoto(id:String,image:String,caption:String,token:String) async throws -> DiningPlanPhoto { try await request("api/together/plans/\(id)/photos",method:"POST",token:token,body:["image":image,"caption":caption]) }
    func deleteDiningPhoto(planId:String,photoId:String,token:String) async throws { let _:EmptyResponse=try await request("api/together/plans/\(planId)/photos/\(photoId)",method:"DELETE",token:token) }
    func createTogetherMoment(planId:String,caption:String,image:String,token:String) async throws -> Moment { try await request("api/together/plans/\(planId)/moment",method:"POST",token:token,body:["caption":caption,"image":image]) }
    func registerLiveActivity(planId:String,activityToken:String,token:String) async throws { let _:EmptyResponse=try await request("api/together/plans/\(planId)/live-activity",method:"PUT",token:token,body:["activityToken":activityToken]) }
    func unregisterLiveActivity(planId:String,token:String) async throws { let _:EmptyResponse=try await request("api/together/plans/\(planId)/live-activity",method:"DELETE",token:token) }

    func reviews(placeId:String,token:String?=nil) async throws -> [PlaceReview] {
        try await request("api/places/\(escapedPath(placeId))/reviews",token:token)
    }
    func addReview(placeId:String,placeName:String,address:String,latitude:Double,longitude:Double,rating:Int,body:String,photo:String,token:String) async throws -> PlaceReview {
        try await request("api/places/\(escapedPath(placeId))/reviews",method:"POST",token:token,body:[
            "placeName":placeName,"address":address,"latitude":latitude,"longitude":longitude,
            "rating":rating,"body":body,"photo":photo
        ])
    }

    func notifications(markRead:Bool=false,token:String) async throws -> [AppNotification] {
        try await request("api/notifications?markRead=\(markRead ? "true":"false")",token:token)
    }
    func markNotificationsRead(token:String) async throws {
        let _:EmptyResponse=try await request("api/notifications/read",method:"POST",token:token)
    }
    func unreadSummary(token:String) async throws -> UnreadSummary { try await request("api/unread",token:token) }

    func moments(token: String) async throws -> [Moment] { try await request("api/moments",token:token) }
    func createMoment(caption:String,image:String,type:MomentType,locationName:String,locationAddress:String,latitude:Double?,longitude:Double?,visibility:MomentVisibility,taggedUserIds:[String],selectedUserIds:[String],token:String) async throws -> Moment {
        var body:[String:Any]=["caption":caption,"image":image,"momentType":type.rawValue,"locationName":locationName,"locationAddress":locationAddress,"visibility":visibility.rawValue,"taggedUserIds":taggedUserIds,"selectedUserIds":selectedUserIds]
        if let latitude { body["latitude"]=latitude }; if let longitude { body["longitude"]=longitude }
        return try await request("api/moments",method:"POST",token:token,body:body)
    }
    func moments(userId: String, token: String) async throws -> [Moment] { try await request("api/users/\(userId)/moments",token:token) }
    func like(momentId: String, enabled: Bool, token: String) async throws {
        let _:EmptyResponse=try await request("api/moments/\(momentId)/like",method:enabled ? "PUT":"DELETE",token:token)
    }
    func react(momentId:String,reaction:MomentReaction?,token:String) async throws {
        if let reaction { let _:EmptyResponse=try await request("api/moments/\(momentId)/reaction",method:"PUT",token:token,body:["reaction":reaction.rawValue]) }
        else { let _:EmptyResponse=try await request("api/moments/\(momentId)/reaction",method:"DELETE",token:token) }
    }
    func comments(momentId: String, token: String) async throws -> [MomentComment] { try await request("api/moments/\(momentId)/comments",token:token) }
    func addComment(momentId: String, body: String, token: String) async throws -> MomentComment {
        try await request("api/moments/\(momentId)/comments",method:"POST",token:token,body:["body":body])
    }

    func conversations(token:String) async throws -> [Conversation] { try await request("api/conversations",token:token) }
    func messages(with id: String, token: String) async throws -> [ChatMessage] { try await request("api/messages/\(id)",token:token) }
    func sendMessage(to id: String, body: String, token: String) async throws -> ChatMessage {
        try await request("api/messages/\(id)",method:"POST",token:token,body:["body":body])
    }

    func search(_ text:String,token:String) async throws -> SearchResults {
        try await request("api/search?q=\(escaped(text))",token:token)
    }

    func registerDevice(deviceToken:String,token:String) async throws {
        let _:EmptyResponse=try await request("api/devices",method:"POST",token:token,body:["deviceToken":deviceToken,"platform":"ios"])
    }

    private var unreserved: CharacterSet { CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~")) }
    private func escaped(_ value:String) -> String { value.addingPercentEncoding(withAllowedCharacters:unreserved) ?? value }
    private func escapedPath(_ value:String) -> String { value.addingPercentEncoding(withAllowedCharacters:unreserved) ?? value }

    private func request<T: Decodable>(_ path: String, method: String = "GET", token: String? = nil, body: [String:Any]? = nil) async throws -> T {
        guard let baseURL, let url = URL(string:path,relativeTo:baseURL)?.absoluteURL else { throw APIError.invalidURL }
        var request=URLRequest(url:url)
        request.httpMethod=method
        request.setValue("application/json",forHTTPHeaderField:"Accept")
        if let token { request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization") }
        if let body {
            request.setValue("application/json",forHTTPHeaderField:"Content-Type")
            request.httpBody=try JSONSerialization.data(withJSONObject:body)
        }
        let (data,response)=try await session.data(for:request)
        guard let http=response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 204 {
            guard let empty = EmptyResponse() as? T else { throw APIError.invalidResponse }
            return empty
        }
        guard (200..<300).contains(http.statusCode) else {
            let message=(try? JSONDecoder().decode(ServerError.self,from:data).error) ?? "Server error \(http.statusCode)"
            if http.statusCode == 401 { throw APIError.unauthorized(message) }
            throw APIError.server(message)
        }
        return try JSONDecoder().decode(Envelope<T>.self,from:data).data
    }
}

private struct ServerError: Decodable { let error:String }
private struct EmptyResponse: Codable { init() {} }
