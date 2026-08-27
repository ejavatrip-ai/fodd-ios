import Foundation

@MainActor
final class AppStore: ObservableObject {
    @Published var account: Account?
    @Published var members: [Member] = []
    @Published var moments: [Moment] = []
    @Published var restaurants: [Restaurant] = []
    @Published var isOnline = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api = APIClient()
    private var token: String? {
        get { UserDefaults.standard.string(forKey:"fodd.session") }
        set { UserDefaults.standard.set(newValue,forKey:"fodd.session") }
    }
    var isAuthenticated: Bool { account != nil }

    func restore() async {
        isLoading=true; defer { isLoading=false }
        do {
            restaurants=try await api.restaurants(); isOnline=true
            if let token { account=try await api.me(token:token); try await refreshPrivate() }
        } catch { if account != nil { logout() }; errorMessage=error.localizedDescription }
    }

    func login(email: String, password: String) async -> Bool {
        await authenticate { try await api.login(email:email,password:password) }
    }
    func register(name: String, username: String, email: String, password: String) async -> Bool {
        await authenticate { try await api.register(name:name,username:username,email:email,password:password) }
    }
    private func authenticate(_ action: () async throws -> AuthResponse) async -> Bool {
        isLoading=true; errorMessage=nil; defer { isLoading=false }
        do { let result=try await action(); token=result.token; account=result.user; try await refreshPrivate(); return true }
        catch { errorMessage=error.localizedDescription; return false }
    }
    func refreshPrivate() async throws {
        guard let token else { return }
        async let momentRequest=api.moments(token:token)
        async let memberRequest=api.members(search:"",token:token)
        moments=try await momentRequest; members=try await memberRequest
    }
    func searchMembers(_ text: String) async {
        guard let token else { return }
        do { members=try await api.members(search:text,token:token) } catch { errorMessage=error.localizedDescription }
    }
    func toggleFollow(_ member: Member) async {
        guard let token, let index=members.firstIndex(where:{$0.id==member.id}) else { return }
        do { try await api.follow(id:member.id,enabled:!member.isFollowing,token:token); members[index].isFollowing.toggle() }
        catch { errorMessage=error.localizedDescription }
    }
    func updateProfile(name: String, bio: String) async -> Bool {
        guard let token else { return false }
        do { account=try await api.updateMe(name:name,bio:bio,token:token); return true }
        catch { errorMessage=error.localizedDescription; return false }
    }
    func createMoment(caption: String, image: String) async -> Bool {
        guard let token else { return false }
        do { try await api.createMoment(caption:caption,image:image,token:token); moments=try await api.moments(token:token); return true }
        catch { errorMessage=error.localizedDescription; return false }
    }
    func messages(with member: Member) async -> [ChatMessage] {
        guard let token else { return [] }
        do { return try await api.messages(with:member.id,token:token) }
        catch { errorMessage=error.localizedDescription; return [] }
    }
    func sendMessage(to member: Member, body: String) async -> ChatMessage? {
        guard let token else { return nil }
        do { return try await api.sendMessage(to:member.id,body:body,token:token) }
        catch { errorMessage=error.localizedDescription; return nil }
    }
    func logout() { token=nil; account=nil; members=[]; moments=[] }
}
