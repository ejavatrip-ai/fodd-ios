import Foundation
import Security

@MainActor
final class AppStore: ObservableObject {
    @Published var account: Account?
    @Published var members: [Member] = []
    @Published var closeFoodies: [Member] = []
    @Published var blockedUsers: [Member] = []
    @Published var followRequests: [FollowRequest] = []
    @Published var collections: [FoodCollection] = []
    @Published var diningPlans: [DiningPlan] = []
    @Published var userSettings = FoddUserSettings(isPrivate:false,pushFollows:true,pushLikes:true,pushComments:true,pushMessages:true,pushRecommendations:true,pushTogether:true)
    @Published var tastePreferences = TastePreferences()
    @Published var smartDashboard: SmartFoodDashboard?
    @Published var creatorProfile: CreatorProfile?
    @Published var myRestaurants: [Restaurant] = []
    @Published var restaurantClaims: [RestaurantClaim] = []
    @Published var isSmartFoodLoading = false
    @Published var moments: [Moment] = []
    @Published var restaurants: [Restaurant] = []
    @Published var conversations: [Conversation] = []
    @Published var notifications: [AppNotification] = []
    @Published var unreadMessages = 0
    @Published var unreadNotifications = 0
    @Published var isOnline = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var sessionNeedsRetry = false

    private let api = APIClient()
    private var token: String? {
        get {
            if let secure=FoddKeychain.readSession(),!secure.isEmpty { return secure }
            if let legacy=UserDefaults.standard.string(forKey:"fodd.session"),!legacy.isEmpty {
                FoddKeychain.saveSession(legacy); UserDefaults.standard.removeObject(forKey:"fodd.session"); return legacy
            }
            return nil
        }
        set {
            UserDefaults.standard.removeObject(forKey:"fodd.session")
            if let newValue { FoddKeychain.saveSession(newValue) } else { FoddKeychain.deleteSession() }
        }
    }
    var isAuthenticated: Bool { account != nil }
    var hasStoredSession: Bool { token != nil }

    func restore() async {
        isLoading=true; errorMessage=nil; sessionNeedsRetry=false; defer{isLoading=false}
        if token != nil { loadCachedState() }
        if let token {
            do {
                account=try await api.me(token:token)
                try await refreshPrivate()
                isOnline=true
                await syncPushToken()
            } catch APIError.unauthorized(let message) {
                isOnline=false
                clearLocalSession()
                errorMessage=message
            } catch {
                isOnline=false
                sessionNeedsRetry=true
                errorMessage="Tidak dapat terhubung ke server. Sesi Anda tetap tersimpan dan dapat dicoba lagi."
            }
        } else {
            do {
                restaurants=try await api.restaurants()
                isOnline=true
            } catch {
                isOnline=false
                errorMessage=error.localizedDescription
            }
        }
    }

    func login(email:String,password:String) async -> Bool {
        await authenticate { try await api.login(email:email,password:password) }
    }
    func register(name:String,username:String,email:String,password:String) async -> Bool {
        await authenticate { try await api.register(name:name,username:username,email:email,password:password) }
    }
    private func authenticate(_ action:() async throws -> AuthResponse) async -> Bool {
        isLoading=true; errorMessage=nil; defer{isLoading=false}
        do {
            let result=try await action()
            token=result.token; account=result.user; isOnline=true; sessionNeedsRetry=false
            do {
                try await refreshPrivate()
            } catch {
                isOnline=false
                errorMessage="Login berhasil, tetapi sebagian data belum dapat dimuat. Tarik layar untuk mencoba lagi."
            }
            PushNotificationManager.shared.requestAuthorizationAndRegister()
            await syncPushToken()
            return true
        } catch {
            errorMessage=error.localizedDescription
            return false
        }
    }

    func refreshPrivate() async throws {
        guard let token else{return}
        async let momentRequest=api.moments(token:token)
        async let memberRequest=api.members(search:"",token:token)
        async let restaurantRequest=api.restaurants(token:token)
        async let conversationRequest=api.conversations(token:token)
        async let closeFoodiesRequest=api.closeFoodies(token:token)
        async let blockedRequest=api.blockedUsers(token:token)
        async let followRequest=api.followRequests(token:token)
        async let collectionRequest=api.collections(token:token)
        async let settingsRequest=api.settings(token:token)
        async let unreadRequest=api.unreadSummary(token:token)
        async let diningRequest=api.diningPlans(token:token)
        let (newMoments,newMembers,newRestaurants,newConversations,newCloseFoodies,newBlocked,newFollowRequests,newCollections,newSettings,summary,newDiningPlans)=try await (momentRequest,memberRequest,restaurantRequest,conversationRequest,closeFoodiesRequest,blockedRequest,followRequest,collectionRequest,settingsRequest,unreadRequest,diningRequest)
        moments=newMoments; members=newMembers; restaurants=newRestaurants; conversations=newConversations; closeFoodies=newCloseFoodies; blockedUsers=newBlocked; followRequests=newFollowRequests; collections=newCollections; userSettings=newSettings; diningPlans=newDiningPlans
        if account?.isPrivate != newSettings.isPrivate { account?.isPrivate = newSettings.isPrivate }
        unreadMessages=summary.messages; unreadNotifications=summary.notifications
        await refreshSmartFood()
        await refreshCreatorStudio()
        saveCachedState()
        FoddAppleExperienceManager.shared.sync(account:account, smartDashboard:smartDashboard, restaurants:restaurants, moments:moments, members:members, diningPlans:diningPlans)
    }

    func refreshSmartFood(latitude:Double?=nil,longitude:Double?=nil,mood:String="") async {
        guard let token else{return}
        isSmartFoodLoading=true; defer{isSmartFoodLoading=false}
        do {
            let dashboard=try await api.smartDashboard(latitude:latitude,longitude:longitude,mood:mood,token:token)
            smartDashboard=dashboard; tastePreferences=dashboard.taste.preferences; saveCachedState()
            FoddAppleExperienceManager.shared.sync(account:account, smartDashboard:smartDashboard, restaurants:restaurants, moments:moments, members:members, diningPlans:diningPlans)
        } catch {
            // Smart Food is additive: a recommendation outage must not break the main app session.
            if smartDashboard == nil { errorMessage="Rekomendasi pintar belum dapat dimuat. Fitur utama Fodd tetap dapat digunakan." }
        }
    }

    func refreshCreatorStudio() async {
        guard let token else{return}
        do {
            async let profileRequest=api.creatorProfile(token:token)
            async let restaurantsRequest=api.myRestaurants(token:token)
            async let claimsRequest=api.restaurantClaims(token:token)
            let result=try await (profileRequest,restaurantsRequest,claimsRequest)
            creatorProfile=result.0;myRestaurants=result.1;restaurantClaims=result.2
        } catch {
            // Creator/Restaurant Studio is additive and must not invalidate the main session.
        }
    }

    func saveCreatorProfile(isCreator:Bool,category:String,website:String) async -> Bool {
        guard let token else{return false}
        do { account=try await api.updateCreatorProfile(isCreator:isCreator,category:category,website:website,token:token);creatorProfile=try await api.creatorProfile(token:token);saveCachedState();FoddFeedbackManager.shared.success();return true }
        catch { errorMessage=error.localizedDescription;return false }
    }

    func claimRestaurant(_ restaurant:Restaurant,businessName:String,role:String,note:String) async -> Bool {
        guard let token else{return false}
        do { _=try await api.claimRestaurant(id:restaurant.id,businessName:businessName,role:role,note:note,token:token);restaurantClaims=try await api.restaurantClaims(token:token);FoddFeedbackManager.shared.success();return true }
        catch { errorMessage=error.localizedDescription;return false }
    }

    func restaurantMenu(_ restaurant:Restaurant) async -> [MenuItem] { do{return try await api.restaurantMenu(id:restaurant.id,token:token)}catch{errorMessage=error.localizedDescription;return[]} }
    func restaurantPosts(_ restaurant:Restaurant) async -> [RestaurantPost] { do{return try await api.restaurantPosts(id:restaurant.id,token:token)}catch{errorMessage=error.localizedDescription;return[]} }
    func updateManagedRestaurant(_ restaurant:Restaurant,name:String,category:String,address:String,phone:String,hours:String,website:String,price:String,image:String) async -> Restaurant? {
        guard let token else{return nil}
        do { let updated=try await api.updateManagedRestaurant(restaurant,name:name,category:category,address:address,phone:phone,hours:hours,website:website,price:price,image:image,token:token);await refreshCreatorStudio();restaurants=try await api.restaurants(token:token);FoddFeedbackManager.shared.success();return updated }
        catch { errorMessage=error.localizedDescription;return nil }
    }
    func createMenuItem(restaurant:Restaurant,name:String,description:String,category:String,price:Int,image:String,isAvailable:Bool=true) async -> MenuItem? {
        guard let token else{return nil};do{return try await api.createMenuItem(restaurantId:restaurant.id,name:name,description:description,category:category,price:price,image:image,isAvailable:isAvailable,sortOrder:0,token:token)}catch{errorMessage=error.localizedDescription;return nil}
    }
    func updateMenuItem(restaurant:Restaurant,item:MenuItem,name:String,description:String,category:String,price:Int,image:String,isAvailable:Bool) async -> MenuItem? {
        guard let token else{return nil};do{return try await api.updateMenuItem(restaurantId:restaurant.id,itemId:item.id,name:name,description:description,category:category,price:price,image:image,isAvailable:isAvailable,sortOrder:item.sortOrder,token:token)}catch{errorMessage=error.localizedDescription;return nil}
    }
    func deleteMenuItem(restaurant:Restaurant,item:MenuItem) async -> Bool { guard let token else{return false};do{try await api.deleteMenuItem(restaurantId:restaurant.id,itemId:item.id,token:token);return true}catch{errorMessage=error.localizedDescription;return false} }
    func createRestaurantPost(restaurant:Restaurant,caption:String,image:String) async -> RestaurantPost? { guard let token else{return nil};do{let post=try await api.createRestaurantPost(restaurantId:restaurant.id,caption:caption,image:image,token:token);FoddFeedbackManager.shared.success();return post}catch{errorMessage=error.localizedDescription;return nil} }
    func deleteRestaurantPost(restaurant:Restaurant,post:RestaurantPost) async -> Bool { guard let token else{return false};do{try await api.deleteRestaurantPost(restaurantId:restaurant.id,postId:post.id,token:token);return true}catch{errorMessage=error.localizedDescription;return false} }

    func saveTastePreferences(_ value:TastePreferences) async -> Bool {
        guard let token else{return false}
        do {
            tastePreferences=try await api.updateTastePreferences(value,token:token)
            await refreshSmartFood()
            FoddFeedbackManager.shared.success()
            return true
        } catch { errorMessage=error.localizedDescription; return false }
    }

    func trackSmartEvent(type:String,restaurantId:String?=nil,query:String="",weight:Double=1) async {
        guard let token else{return}
        try? await api.smartEvent(type:type,restaurantId:restaurantId,query:query,weight:weight,token:token)
    }

    func refreshBadges() async {
        guard let token else{return}
        do {
            let summary=try await api.unreadSummary(token:token)
            unreadMessages=summary.messages; unreadNotifications=summary.notifications
        } catch { }
    }

    func searchMembers(_ text:String) async {
        guard let token else{return}
        do{members=try await api.members(search:text,token:token)}catch{errorMessage=error.localizedDescription}
    }
    func universalSearch(_ text:String) async -> SearchResults? {
        guard let token else{return nil}
        do{return try await api.search(text,token:token)}catch{errorMessage=error.localizedDescription;return nil}
    }

    @discardableResult
    func toggleFollow(_ member:Member) async -> FollowState? {
        guard let token else{return nil}
        let current = members.first(where:{$0.id==member.id}) ?? member
        let enabled = !(current.isFollowing || current.followRequestPending)
        do {
            let state=try await api.follow(id:member.id,enabled:enabled,token:token)
            if let index=members.firstIndex(where:{$0.id==member.id}) { members[index].isFollowing=state.isFollowing; members[index].followRequestPending=state.pending }
            saveCachedState(); return state
        } catch { errorMessage=error.localizedDescription; return nil }
    }

    func refreshSafetyData() async {
        guard let token else{return}
        do {
            async let blocked=api.blockedUsers(token:token)
            async let requests=api.followRequests(token:token)
            async let settings=api.settings(token:token)
            async let lists=api.collections(token:token)
            let result=try await (blocked,requests,settings,lists)
            blockedUsers=result.0; followRequests=result.1; userSettings=result.2; collections=result.3
            if account?.isPrivate != result.2.isPrivate { account?.isPrivate=result.2.isPrivate }
            saveCachedState()
        } catch { errorMessage=error.localizedDescription }
    }

    func respondFollowRequest(_ request:FollowRequest,accept:Bool) async {
        guard let token else{return}
        do { try await api.respondFollowRequest(id:request.member.id,accept:accept,token:token); followRequests.removeAll{$0.id==request.id}; members=try await api.members(search:"",token:token); saveCachedState() }
        catch { errorMessage=error.localizedDescription }
    }

    func setBlocked(_ member:Member,enabled:Bool) async -> Bool {
        guard let token else{return false}
        do {
            try await api.setBlocked(id:member.id,enabled:enabled,token:token)
            blockedUsers=try await api.blockedUsers(token:token)
            members=try await api.members(search:"",token:token)
            moments=try await api.moments(token:token)
            conversations=try await api.conversations(token:token)
            saveCachedState(); return true
        } catch { errorMessage=error.localizedDescription; return false }
    }

    func report(targetType:String,targetId:String,reason:ReportReason,details:String) async -> Bool {
        guard let token else{return false}
        do { _=try await api.report(targetType:targetType,targetId:targetId,reason:reason,details:details,token:token); return true }
        catch { errorMessage=error.localizedDescription; return false }
    }
    func toggleCloseFoodie(_ member:Member) async {
        guard let token else{return}
        let enabled = !(members.first(where:{$0.id==member.id})?.isCloseFoodie ?? member.isCloseFoodie)
        do {
            try await api.setCloseFoodie(id:member.id,enabled:enabled,token:token)
            if let index=members.firstIndex(where:{$0.id==member.id}) { members[index].isCloseFoodie=enabled }
            closeFoodies=try await api.closeFoodies(token:token)
        } catch { errorMessage=error.localizedDescription }
    }

    func importNearbyRestaurant(_ item:NearbyRestaurant) async -> Restaurant? {
        guard let token else{return nil}
        do {
            let restaurant=try await api.upsertRestaurant(id:item.id,name:item.name,category:item.category,address:item.address,phone:item.phone,website:item.website,latitude:item.latitude,longitude:item.longitude,distance:item.distanceText,token:token)
            if let index=restaurants.firstIndex(where:{$0.id==restaurant.id}) { restaurants[index]=restaurant } else { restaurants.append(restaurant) }
            saveCachedState(); return restaurant
        } catch { errorMessage=error.localizedDescription; return nil }
    }

    func toggleSaved(_ restaurant:Restaurant) async {
        guard let token,let index=restaurants.firstIndex(where:{$0.id==restaurant.id}) else{return}
        let enabled = !restaurants[index].isSaved
        do {
            try await api.saveRestaurant(id:restaurant.id,enabled:enabled,token:token)
            restaurants[index].isSaved=enabled; saveCachedState()
            await refreshSmartFood()
        } catch { errorMessage=error.localizedDescription }
    }

    func loadNotifications(markRead:Bool=false) async {
        guard let token else{return}
        do {
            notifications=try await api.notifications(markRead:markRead,token:token)
            if markRead { unreadNotifications=0 }
        } catch { errorMessage=error.localizedDescription }
    }
    func markNotificationsRead() async {
        guard let token else{return}
        do{try await api.markNotificationsRead(token:token);unreadNotifications=0}catch{errorMessage=error.localizedDescription}
    }

    func loadConversations() async {
        guard let token else{return}
        do {
            conversations=try await api.conversations(token:token)
            unreadMessages=conversations.reduce(0){$0+$1.unreadCount}
        } catch { errorMessage=error.localizedDescription }
    }

    func updateProfile(name:String,bio:String,avatar:String) async -> Bool {
        guard let token else{return false}
        do{account=try await api.updateMe(name:name,bio:bio,avatar:avatar,token:token);saveCachedState();return true}catch{errorMessage=error.localizedDescription;return false}
    }

    func updateSettings(_ value:FoddUserSettings) async -> Bool {
        guard let token else{return false}
        do {
            userSettings=try await api.updateSettings(value,token:token)
            account?.isPrivate=userSettings.isPrivate
            saveCachedState(); return true
        } catch { errorMessage=error.localizedDescription; return false }
    }

    func createCollection(name:String,description:String,isPrivate:Bool) async -> Bool {
        guard let token else{return false}
        do { let collection=try await api.createCollection(name:name,description:description,isPrivate:isPrivate,token:token); collections.insert(collection,at:0); saveCachedState(); return true }
        catch { errorMessage=error.localizedDescription; return false }
    }
    func deleteCollection(_ collection:FoodCollection) async {
        guard let token else{return}
        do { try await api.deleteCollection(id:collection.id,token:token); collections.removeAll{$0.id==collection.id}; saveCachedState() }
        catch { errorMessage=error.localizedDescription }
    }
    func collectionRestaurants(_ collection:FoodCollection) async -> [Restaurant] {
        guard let token else{return []}
        do { return try await api.collectionRestaurants(id:collection.id,token:token) }
        catch { errorMessage=error.localizedDescription; return [] }
    }
    func setRestaurant(_ restaurant:Restaurant,in collection:FoodCollection,enabled:Bool) async -> Bool {
        guard let token else{return false}
        do {
            try await api.setCollectionRestaurant(collectionId:collection.id,restaurantId:restaurant.id,enabled:enabled,token:token)
            collections=try await api.collections(token:token); saveCachedState()
            if enabled { await refreshSmartFood() }
            return true
        } catch { errorMessage=error.localizedDescription; return false }
    }

    func startDiningLiveActivity(_ plan: DiningPlan) async -> Bool {
        guard let token else { return false }
        return await FoddAppleExperienceManager.shared.startLiveActivity(for: plan) { activityToken in
            try? await self.api.registerLiveActivity(planId: plan.id, activityToken: activityToken, token: token)
        }
    }
    func stopDiningLiveActivity(_ plan: DiningPlan) async {
        guard let token else { return }
        await FoddAppleExperienceManager.shared.stopLiveActivity(planId: plan.id)
        try? await api.unregisterLiveActivity(planId: plan.id, token: token)
    }

    func refreshDiningPlans() async { guard let token else{return};do{diningPlans=try await api.diningPlans(token:token);FoddAppleExperienceManager.shared.sync(account:account, smartDashboard:smartDashboard, restaurants:restaurants, moments:moments, members:members, diningPlans:diningPlans)}catch{errorMessage=error.localizedDescription} }
    func diningPlan(_ id:String) async -> DiningPlan? { guard let token else{return nil};do{let plan=try await api.diningPlan(id:id,token:token);if let i=diningPlans.firstIndex(where:{$0.id==id}){diningPlans[i]=plan}else{diningPlans.append(plan)};FoddAppleExperienceManager.shared.sync(account:account, smartDashboard:smartDashboard, restaurants:restaurants, moments:moments, members:members, diningPlans:diningPlans);await FoddAppleExperienceManager.shared.refreshLiveActivity(for:plan);return plan}catch{errorMessage=error.localizedDescription;return nil} }
    func createDiningPlan(title:String,note:String,date:Date,memberIds:[String],restaurantIds:[String]) async -> DiningPlan? { guard let token else{return nil};do{let f=ISO8601DateFormatter();let plan=try await api.createDiningPlan(title:title,note:note,scheduledAt:f.string(from:date),memberIds:memberIds,candidateRestaurantIds:restaurantIds,token:token);diningPlans.insert(plan,at:0);FoddAppleExperienceManager.shared.sync(account:account, smartDashboard:smartDashboard, restaurants:restaurants, moments:moments, members:members, diningPlans:diningPlans);FoddFeedbackManager.shared.success();return plan}catch{errorMessage=error.localizedDescription;return nil} }
    func inviteToDiningPlan(_ plan:DiningPlan,memberIds:[String]) async -> Bool { guard let token else{return false};do{try await api.inviteToDiningPlan(id:plan.id,memberIds:memberIds,token:token);_=await diningPlan(plan.id);return true}catch{errorMessage=error.localizedDescription;return false} }
    func diningRSVP(plan:DiningPlan,rsvp:DiningRSVP) async -> Bool { guard let token else{return false};do{_=try await api.diningRSVP(id:plan.id,rsvp:rsvp,token:token);_=await diningPlan(plan.id);FoddFeedbackManager.shared.selection();return true}catch{errorMessage=error.localizedDescription;return false} }
    func vote(plan:DiningPlan,restaurant:Restaurant) async -> Bool { guard let token else{return false};do{try await api.voteDiningPlan(id:plan.id,restaurantId:restaurant.id,token:token);_=await diningPlan(plan.id);FoddFeedbackManager.shared.selection();return true}catch{errorMessage=error.localizedDescription;return false} }
    func addCandidate(plan:DiningPlan,restaurant:Restaurant) async -> Bool { guard let token else{return false};do{try await api.setDiningCandidate(planId:plan.id,restaurantId:restaurant.id,enabled:true,token:token);_=await diningPlan(plan.id);return true}catch{errorMessage=error.localizedDescription;return false} }
    func chooseRestaurant(plan:DiningPlan,restaurant:Restaurant) async -> Bool { guard let token else{return false};do{let updated=try await api.updateDiningPlan(id:plan.id,selectedRestaurantId:restaurant.id,token:token);if let i=diningPlans.firstIndex(where:{$0.id==plan.id}){diningPlans[i]=updated};FoddFeedbackManager.shared.success();return true}catch{errorMessage=error.localizedDescription;return false} }
    func completeDiningPlan(_ plan:DiningPlan) async -> Bool { guard let token else{return false};do{let updated=try await api.updateDiningPlan(id:plan.id,status:"completed",token:token);if let i=diningPlans.firstIndex(where:{$0.id==plan.id}){diningPlans[i]=updated};return true}catch{errorMessage=error.localizedDescription;return false} }
    func diningMessages(planId:String) async -> [DiningPlanMessage] { guard let token else{return[]};do{return try await api.diningMessages(id:planId,token:token)}catch{errorMessage=error.localizedDescription;return[]} }
    func sendDiningMessage(planId:String,body:String) async -> DiningPlanMessage? { guard let token else{return nil};do{return try await api.sendDiningMessage(id:planId,body:body,token:token)}catch{errorMessage=error.localizedDescription;return nil} }
    func diningPhotos(planId:String) async -> [DiningPlanPhoto] { guard let token else{return[]};do{return try await api.diningPhotos(id:planId,token:token)}catch{errorMessage=error.localizedDescription;return[]} }
    func addDiningPhoto(planId:String,image:String,caption:String) async -> DiningPlanPhoto? { guard let token else{return nil};do{let x=try await api.addDiningPhoto(id:planId,image:image,caption:caption,token:token);_=await diningPlan(planId);return x}catch{errorMessage=error.localizedDescription;return nil} }
    func createTogetherMoment(planId:String,caption:String,image:String) async -> Bool { guard let token else{return false};do{_=try await api.createTogetherMoment(planId:planId,caption:caption,image:image,token:token);moments=try await api.moments(token:token);saveCachedState();FoddFeedbackManager.shared.success();return true}catch{errorMessage=error.localizedDescription;return false} }
    func collectionMembers(_ collection:FoodCollection) async -> [SharedCollectionMember] { guard let token else{return[]};do{return try await api.collectionMembers(id:collection.id,token:token)}catch{errorMessage=error.localizedDescription;return[]} }
    func shareCollection(_ collection:FoodCollection,with member:Member,role:String="editor") async -> Bool { guard let token else{return false};do{try await api.shareCollection(id:collection.id,userId:member.id,role:role,token:token);collections=try await api.collections(token:token);return true}catch{errorMessage=error.localizedDescription;return false} }

    func createMoment(caption:String,image:String,type:MomentType,locationName:String,locationAddress:String,latitude:Double?,longitude:Double?,visibility:MomentVisibility,taggedUserIds:[String],selectedUserIds:[String]) async -> Bool {
        guard let token else{return false}
        do {
            _=try await api.createMoment(caption:caption,image:image,type:type,locationName:locationName,locationAddress:locationAddress,latitude:latitude,longitude:longitude,visibility:visibility,taggedUserIds:taggedUserIds,selectedUserIds:selectedUserIds,token:token)
            moments=try await api.moments(token:token); saveCachedState()
            if type == .checkin { await refreshSmartFood() }
            return true
        } catch { errorMessage=error.localizedDescription; return false }
    }
    func toggleLike(_ moment:Moment) async {
        guard let token,let index=moments.firstIndex(where:{$0.id==moment.id}) else{return}
        let enabled = !moments[index].isLiked
        do {
            try await api.like(momentId:moment.id,enabled:enabled,token:token)
            moments[index].isLiked=enabled
            moments[index].likes=max(0,moments[index].likes + (enabled ? 1:-1))
        } catch { errorMessage=error.localizedDescription }
    }
    func react(_ moment:Moment,with reaction:MomentReaction) async {
        guard let token,let index=moments.firstIndex(where:{$0.id==moment.id}) else{return}
        let previous=moments[index].myReaction.flatMap(MomentReaction.init(rawValue:))
        let next:MomentReaction? = previous == reaction ? nil : reaction
        do {
            try await api.react(momentId:moment.id,reaction:next,token:token)
            if let previous { moments[index].reactions[previous.rawValue]=max(0,(moments[index].reactions[previous.rawValue] ?? 0)-1) }
            if let next { moments[index].reactions[next.rawValue]=(moments[index].reactions[next.rawValue] ?? 0)+1 }
            moments[index].myReaction=next?.rawValue
        } catch { errorMessage=error.localizedDescription }
    }
    func comments(for moment:Moment) async -> [MomentComment] {
        guard let token else{return[]}
        do{return try await api.comments(momentId:moment.id,token:token)}catch{errorMessage=error.localizedDescription;return[]}
    }
    func addComment(to moment:Moment,body:String) async -> MomentComment? {
        guard let token else{return nil}
        do {
            let comment=try await api.addComment(momentId:moment.id,body:body,token:token)
            if let index=moments.firstIndex(where:{$0.id==moment.id}){moments[index].commentCount += 1}
            return comment
        } catch { errorMessage=error.localizedDescription;return nil }
    }
    func moments(for userId:String) async -> [Moment] {
        guard let token else{return[]}
        do{return try await api.moments(userId:userId,token:token)}catch{errorMessage=error.localizedDescription;return[]}
    }

    func messages(with member:Member) async -> [ChatMessage] {
        guard let token else{return[]}
        do {
            let result=try await api.messages(with:member.id,token:token)
            await loadConversations()
            return result
        } catch { errorMessage=error.localizedDescription;return[] }
    }
    func sendMessage(to member:Member,body:String) async -> ChatMessage? {
        guard let token else{return nil}
        do {
            let result=try await api.sendMessage(to:member.id,body:body,token:token)
            await loadConversations()
            return result
        } catch { errorMessage=error.localizedDescription;return nil }
    }

    func reviews(placeId:String) async -> [PlaceReview] {
        do{return try await api.reviews(placeId:placeId,token:token)}catch{errorMessage=error.localizedDescription;return[]}
    }
    func addReview(placeId:String,placeName:String,address:String,latitude:Double,longitude:Double,rating:Int,body:String,photo:String) async -> PlaceReview? {
        guard let token else{return nil}
        do{let review=try await api.addReview(placeId:placeId,placeName:placeName,address:address,latitude:latitude,longitude:longitude,rating:rating,body:body,photo:photo,token:token);await refreshSmartFood();return review}catch{errorMessage=error.localizedDescription;return nil}
    }

    func forgotPassword(email:String) async -> ActionResponse? {
        do{return try await api.forgotPassword(email:email)}catch{errorMessage=error.localizedDescription;return nil}
    }
    func resetPassword(email:String,code:String,newPassword:String) async -> Bool {
        do{_=try await api.resetPassword(email:email,code:code,newPassword:newPassword);return true}catch{errorMessage=error.localizedDescription;return false}
    }
    func changePassword(currentPassword:String,newPassword:String) async -> Bool {
        guard let token else{return false}
        do{_=try await api.changePassword(currentPassword:currentPassword,newPassword:newPassword,token:token);return true}catch{errorMessage=error.localizedDescription;return false}
    }
    func requestVerification() async -> ActionResponse? {
        guard let token else{return nil}
        do{return try await api.requestEmailVerification(token:token)}catch{errorMessage=error.localizedDescription;return nil}
    }
    func verifyEmail(code:String) async -> Bool {
        guard let token else{return false}
        do{account=try await api.verifyEmail(code:code,token:token);saveCachedState();return true}catch{errorMessage=error.localizedDescription;return false}
    }
    func deleteAccount(password:String) async -> Bool {
        guard let token else{return false}
        do{_=try await api.deleteAccount(password:password,token:token);logout();return true}catch{errorMessage=error.localizedDescription;return false}
    }

    func syncPushToken() async {
        guard let token,let deviceToken=UserDefaults.standard.string(forKey:"fodd.deviceToken"),!deviceToken.isEmpty else{return}
        do{try await api.registerDevice(deviceToken:deviceToken,token:token)}catch{ }
    }

    func logoutFromServer() async {
        guard let token else { clearLocalSession(); return }
        if let deviceToken=UserDefaults.standard.string(forKey:"fodd.deviceToken"),!deviceToken.isEmpty {
            try? await api.unregisterDevice(deviceToken:deviceToken,token:token)
        }
        try? await api.logout(token:token)
        clearLocalSession()
    }

    func logout() { clearLocalSession() }

    private struct CachedState: Codable {
        let account: Account?
        let members: [Member]
        let closeFoodies: [Member]
        let moments: [Moment]
        let restaurants: [Restaurant]
        let conversations: [Conversation]
        let collections: [FoodCollection]
        let userSettings: FoddUserSettings
        let tastePreferences: TastePreferences?
        let smartDashboard: SmartFoodDashboard?
    }

    private var cacheURL: URL {
        let base=FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask).first!
        return base.appendingPathComponent("fodd62-state.json")
    }
    private func saveCachedState() {
        let safeConversations=conversations.prefix(40).map { Conversation(member:$0.member.cacheSafe,lastMessage:$0.lastMessage,lastMessageAt:$0.lastMessageAt,unreadCount:$0.unreadCount) }
        let snapshot=CachedState(account:account?.cacheSafe,members:Array(members.prefix(60)).map(\.cacheSafe),closeFoodies:Array(closeFoodies.prefix(30)).map(\.cacheSafe),moments:Array(moments.prefix(50)).map(\.cacheSafe),restaurants:restaurants,conversations:Array(safeConversations),collections:collections,userSettings:userSettings,tastePreferences:tastePreferences,smartDashboard:nil)
        if let data=try? JSONEncoder().encode(snapshot) {
            try? data.write(to:cacheURL,options:.atomic)
            try? FileManager.default.setAttributes([.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication],ofItemAtPath:cacheURL.path)
        }
    }
    private func loadCachedState() {
        guard let data=try? Data(contentsOf:cacheURL),let snapshot=try? JSONDecoder().decode(CachedState.self,from:data) else{return}
        account=snapshot.account; members=snapshot.members; closeFoodies=snapshot.closeFoodies; moments=snapshot.moments; restaurants=snapshot.restaurants; conversations=snapshot.conversations; collections=snapshot.collections; userSettings=snapshot.userSettings
        if let cachedTaste=snapshot.tastePreferences { tastePreferences=cachedTaste }; smartDashboard=snapshot.smartDashboard
    }
    private func clearCache() { try? FileManager.default.removeItem(at:cacheURL) }

    private func clearLocalSession() {
        token=nil; account=nil; members=[]; closeFoodies=[]; blockedUsers=[]; followRequests=[]; collections=[]; diningPlans=[]; moments=[]; restaurants=[]; conversations=[]; notifications=[]
        userSettings=FoddUserSettings(isPrivate:false,pushFollows:true,pushLikes:true,pushComments:true,pushMessages:true,pushRecommendations:true,pushTogether:true); tastePreferences=TastePreferences(); smartDashboard=nil; creatorProfile=nil; myRestaurants=[]; restaurantClaims=[]
        unreadMessages=0; unreadNotifications=0; errorMessage=nil; sessionNeedsRetry=false; isOnline=false; clearCache()
    }
}


private enum FoddKeychain {
    private static let service = "com.fodd.app.session"
    private static let account = "auth-token"

    static func readSession() -> String? {
        let query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account,kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
        var item:CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary,&item)==errSecSuccess,let data=item as? Data else{return nil}
        return String(data:data,encoding:.utf8)
    }
    static func saveSession(_ value:String) {
        deleteSession()
        guard let data=value.data(using:.utf8) else{return}
        let query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account,kSecValueData as String:data,kSecAttrAccessible as String:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        SecItemAdd(query as CFDictionary,nil)
    }
    static func deleteSession() {
        let query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account]
        SecItemDelete(query as CFDictionary)
    }
}
