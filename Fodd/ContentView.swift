import Foundation
import SwiftUI
import PhotosUI
import UIKit
import MapKit
import Combine

// MARK: - Fodd 7.0 Apple Experience Brand System

private let foddOrange = Color(red: 1.00, green: 0.35, blue: 0.07)
private let foddRed = Color(red: 1.00, green: 0.08, blue: 0.15)
private let foddCream = Color(red: 1.00, green: 0.97, blue: 0.94)
private let foddGold = Color(red: 0.96, green: 0.62, blue: 0.08)
private let brandGradient = LinearGradient(colors: [foddOrange, foddRed], startPoint: .topLeading, endPoint: .bottomTrailing)

private struct PremiumCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.primary.opacity(0.055), lineWidth: 1))
    }
}

private extension View {
    func premiumCard() -> some View { modifier(PremiumCard()) }
}

struct ContentView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Group {
            if store.isLoading && store.account == nil {
                AliveLoadingView()
            } else if store.isAuthenticated {
                MainTabs()
            } else if store.sessionNeedsRetry && store.hasStoredSession {
                SessionRetryView()
            } else {
                AuthView()
            }
        }
        .task { await store.restore() }
        .onReceive(NotificationCenter.default.publisher(for: .foddDeviceTokenDidChange)) { _ in
            Task { await store.syncPushToken() }
        }
    }
}

struct AliveLoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(brandGradient.opacity(0.10)).frame(width: 112, height: 112)
                    .scaleEffect(breathing && !reduceMotion ? 1.08 : 0.96)
                FoddMark(size: 78).scaleEffect(breathing && !reduceMotion ? 1.035 : 1)
            }
            ProgressView().tint(foddOrange)
            Text("Menyiapkan Fodd 7.0…").font(.subheadline).foregroundStyle(.secondary)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true)) { breathing = true }
        }
    }
}

struct SessionRetryView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        VStack(spacing: 18) {
            FoddMark(size: 78)
            Text("Koneksi belum tersedia").font(.title2.bold())
            Text(store.errorMessage ?? "Sesi Anda tetap aman di perangkat.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Coba Lagi") { Task { await store.restore() } }.buttonStyle(PrimaryButton())
            Button("Keluar dari akun", role: .destructive) { Task { await store.logoutFromServer() } }
        }
        .padding(28).frame(maxWidth: 460)
    }
}

// MARK: - Authentication

struct AuthView: View {
    @EnvironmentObject private var store: AppStore
    @State private var registerMode = false
    @State private var name = ""
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var forgotPassword = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 26) {
                    VStack(spacing: 14) {
                        FoddMark(size: 92)
                        Text("fodd").font(.system(size: 44, weight: .black, design: .rounded)).foregroundStyle(brandGradient)
                        Text("Eat. Share. Connect.").font(.headline).foregroundStyle(.secondary)
                        Text(registerMode ? "Buat jurnal kuliner Anda dan terhubung dengan foodies terdekat." : "Tempat untuk mengabadikan momen makan, menemukan tempat baru, dan tetap dekat dengan teman.")
                            .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 8)
                    }

                    VStack(spacing: 13) {
                        if registerMode {
                            PremiumField(title: "Nama lengkap", systemImage: "person.fill", text: $name)
                            PremiumField(title: "Username", systemImage: "at", text: $username, capitalization: false)
                        }
                        PremiumField(title: "Email", systemImage: "envelope.fill", text: $email, capitalization: false)
                            .keyboardType(.emailAddress)
                        HStack(spacing: 12) {
                            Image(systemName: "lock.fill").foregroundStyle(foddOrange).frame(width: 22)
                            SecureField("Password minimal 8 karakter", text: $password)
                                .textContentType(registerMode ? .newPassword : .password)
                        }
                        .padding(16).background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    if let error = store.errorMessage { ErrorText(error) }

                    Button(registerMode ? "Buat Akun Fodd" : "Masuk ke Fodd") { Task { await submit() } }
                        .buttonStyle(PrimaryButton()).disabled(store.isLoading)

                    if !registerMode {
                        Button("Lupa password?") { store.errorMessage = nil; forgotPassword = true }
                            .font(.subheadline.weight(.semibold)).foregroundStyle(foddOrange)
                    }

                    Button(registerMode ? "Sudah punya akun? Masuk" : "Belum punya akun? Daftar") {
                        store.errorMessage = nil; registerMode.toggle()
                    }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(foddRed)

                    Text("Fodd 7.0 • Apple Experience").font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(26).frame(maxWidth: 520)
            }
            .background(
                LinearGradient(colors: [foddCream.opacity(0.72), Color(.systemBackground)], startPoint: .top, endPoint: .center)
                    .ignoresSafeArea()
            )
            .sheet(isPresented: $forgotPassword) { ForgotPasswordView(prefilledEmail: email) }
        }
    }

    private func submit() async {
        if registerMode { _ = await store.register(name: name, username: username, email: email, password: password) }
        else { _ = await store.login(email: email, password: password) }
    }
}

struct PremiumField: View {
    let title, systemImage: String
    @Binding var text: String
    var capitalization = true
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage).foregroundStyle(foddOrange).frame(width: 22)
            TextField(title, text: $text)
                .textInputAutocapitalization(capitalization ? .words : .never)
                .autocorrectionDisabled(!capitalization)
        }
        .padding(16).background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct ForgotPasswordView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let prefilledEmail: String
    @State private var email = ""
    @State private var code = ""
    @State private var newPassword = ""
    @State private var step = 0
    @State private var message = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(step == 0 ? "Kirim kode reset" : "Masukkan kode") {
                    TextField("Email", text: $email).textInputAutocapitalization(.never).keyboardType(.emailAddress).disabled(step > 0)
                    if step > 0 {
                        TextField("Kode 6 digit", text: $code).keyboardType(.numberPad)
                        SecureField("Password baru minimal 8 karakter", text: $newPassword)
                    }
                }
                if !message.isEmpty { Section { Text(message).font(.footnote) } }
                if let error = store.errorMessage { Section { ErrorText(error) } }
                Section {
                    Button(step == 0 ? "Kirim Kode" : "Reset Password") { Task { await submit() } }
                        .disabled(email.isEmpty || (step > 0 && (code.count < 6 || newPassword.count < 8)))
                }
            }
            .tint(foddOrange)
            .navigationTitle("Lupa Password")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Tutup") { dismiss() } } }
            .onAppear { email = prefilledEmail }
        }
    }

    private func submit() async {
        store.errorMessage = nil
        if step == 0, let response = await store.forgotPassword(email: email) {
            step = 1; message = response.devCode.map { "Kode uji: \($0)" } ?? response.message
        } else if step == 1, await store.resetPassword(email: email, code: code, newPassword: newPassword) {
            message = "Password berhasil diubah. Silakan masuk dengan password baru."; step = 2
        }
    }
}

// MARK: - Navigation

private enum FoddDeepLinkDestination: Identifiable {
    case member(Member), restaurant(Restaurant), moment(Moment), plan(DiningPlan)
    var id: String {
        switch self {
        case .member(let value): "member-\(value.id)"
        case .restaurant(let value): "restaurant-\(value.id)"
        case .moment(let value): "moment-\(value.id)"
        case .plan(let value): "plan-\(value.id)"
        }
    }
}

struct MainTabs: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = 0
    @State private var composer = false
    @State private var showPublishedToast = false
    @State private var deepLinkDestination: FoddDeepLinkDestination?

    private var selection: Binding<Int> {
        Binding(get: { tab }, set: { value in
            FoddFeedbackManager.shared.selection()
            if value == 2 { composer = true } else { tab = value }
        })
    }

    var body: some View {
        TabView(selection: selection) {
            NavigationStack { FeedView() }.tabItem { Label("Home", systemImage: "house.fill") }.tag(0)
            NavigationStack { RestaurantsView() }.tabItem { Label("Explore", systemImage: "magnifyingglass") }.tag(1)
            Color.clear.tabItem { Label("Moment", systemImage: "plus.circle.fill") }.tag(2)
            NavigationStack { InboxRootView() }.tabItem { Label("Inbox", systemImage: "message.fill") }.badge(store.unreadMessages).tag(3)
            NavigationStack { MyProfileView() }.tabItem { Label("Profile", systemImage: "person.fill") }.tag(4)
        }
        .tint(foddOrange)
        .overlay(alignment: .top) {
            if showPublishedToast {
                FoddToast(icon: "sparkles", title: "Moment dibagikan", subtitle: "Momen kulinermu sudah masuk ke Food Diary.")
                    .padding(.horizontal, 16).padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.94)))
                    .zIndex(20)
            }
        }
        .sheet(isPresented: $composer) { CreateMomentHub() }
        .sheet(item: $deepLinkDestination) { destination in
            NavigationStack {
                switch destination {
                case .member(let member): MemberProfileView(member: member)
                case .restaurant(let restaurant): RestaurantDetail(item: restaurant)
                case .moment(let moment):
                    ScrollView { MomentCard(moment: moment).padding(14) }
                        .background(Color(.systemGroupedBackground))
                        .navigationTitle("Food Moment").navigationBarTitleDisplayMode(.inline)
                case .plan(let plan): DiningPlanDetailView(planID: plan.id)
                }
            }
        }
        .onOpenURL { url in Task { await openDeepLink(url) } }
        .onReceive(NotificationCenter.default.publisher(for: .foddMomentDidPublish)) { _ in
            withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.78)) { showPublishedToast = true }
            Task {
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { showPublishedToast = false }
            }
        }
        .onAppear { applyPendingAppleRoute() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { applyPendingAppleRoute() } }
        .task {
            while !Task.isCancelled {
                await store.refreshBadges()
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }

    @MainActor
    private func openDeepLink(_ url: URL) async {
        guard url.scheme?.lowercased() == "fodd", let kind=url.host?.lowercased() else { return }
        if kind == "explore" { tab = 1; return }
        let rawId=url.pathComponents.filter { $0 != "/" }.first ?? ""
        guard let id=rawId.removingPercentEncoding, !id.isEmpty else { return }

        if kind == "profile", id == store.account?.id { tab=4; return }
        if kind == "restaurant", let item=store.restaurants.first(where: { $0.id == id }) { deepLinkDestination = .restaurant(item); return }
        if kind == "moment", let item=store.moments.first(where: { $0.id == id }) { deepLinkDestination = .moment(item); return }
        if kind == "profile", let item=store.members.first(where: { $0.id == id }) { deepLinkDestination = .member(item); return }
        if kind == "together", let item=store.diningPlans.first(where: { $0.id == id }) { deepLinkDestination = .plan(item); return }

        do { try await store.refreshPrivate() } catch { store.errorMessage=error.localizedDescription }
        switch kind {
        case "profile":
            if let item=store.members.first(where: { $0.id == id }) { deepLinkDestination = .member(item) } else { tab=4 }
        case "restaurant":
            if let item=store.restaurants.first(where: { $0.id == id }) { deepLinkDestination = .restaurant(item) } else { tab=1 }
        case "moment":
            if let item=store.moments.first(where: { $0.id == id }) { deepLinkDestination = .moment(item) } else { tab=0 }
        case "together":
            await store.refreshDiningPlans(); if let item=store.diningPlans.first(where: { $0.id == id }) { deepLinkDestination = .plan(item) } else { tab=3 }
        default: break
        }
    }

    private func applyPendingAppleRoute() {
        guard let route = FoddSharedContainer.consumePendingRoute() else { return }
        switch route {
        case "explore": tab = 1
        case "profile": tab = 4
        case "together": tab = 3
        default: break
        }
    }
}

// MARK: - Feed / Food Moments

struct FeedView: View {
    @EnvironmentObject private var store: AppStore
    @State private var feedMode = 0
    @State private var showingNotifications = false

    private var visibleMoments: [Moment] {
        let following = Set(store.members.filter(\.isFollowing).map(\.id))
        if feedMode == 0 {
            let filtered = store.moments.filter { $0.userId == store.account?.id || following.contains($0.userId) }
            return filtered.isEmpty ? store.moments : filtered
        }
        let favorites=(store.smartDashboard?.taste.favoriteCategories ?? []).map{$0.lowercased()}
        let close=Set(store.closeFoodies.map(\.id))
        return store.moments.sorted { lhs,rhs in
            func score(_ moment:Moment) -> Int {
                let text="\(moment.caption) \(moment.locationName) \(moment.momentType.title)".lowercased()
                var value=moment.likes*2+moment.commentCount*3+moment.reactions.values.reduce(0,+)*2
                value += favorites.filter{text.contains($0)}.count*18
                if following.contains(moment.userId){value += 10};if close.contains(moment.userId){value += 16};if moment.userId==store.account?.id{value += 4}
                return value
            }
            let left=score(lhs),right=score(rhs)
            return left == right ? lhs.createdAt > rhs.createdAt : left > right
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                feedHeader
                if visibleMoments.isEmpty {
                    PremiumEmptyState(icon: "sparkles.rectangle.stack", title: "Belum ada Food Moment", subtitle: "Bagikan momen pertama Anda lewat tombol + di bawah.")
                        .padding(.top, 50)
                } else {
                    ForEach(visibleMoments) {
                        MomentCard(moment: $0)
                            .scrollTransition(.animated.threshold(.visible(0.16))) { content, phase in
                                content.opacity(phase.isIdentity ? 1 : 0.88).scaleEffect(phase.isIdentity ? 1 : 0.975)
                            }
                    }
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 18)
        }
        .background(Color(.systemGroupedBackground))
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingNotifications) { NotificationsView() }
        .refreshable { try? await store.refreshPrivate() }
    }

    private var feedHeader: some View {
        VStack(spacing: 13) {
            HStack {
                Image(systemName: "magnifyingglass").font(.title3).foregroundStyle(.secondary)
                Spacer()
                Text("fodd").font(.system(size: 30, weight: .black, design: .rounded)).foregroundStyle(brandGradient)
                Spacer()
                Button { showingNotifications = true } label: { BadgeIcon(systemName: "bell", count: store.unreadNotifications) }
                    .foregroundStyle(.primary)
            }
            .padding(.top, 8)

            if !store.isOnline {
                Label("Offline • menampilkan data cache",systemImage:"wifi.slash")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .frame(maxWidth:.infinity,alignment:.leading)
            }
            Picker("Feed", selection: $feedMode) {
                Text("Following").tag(0)
                Text("For You").tag(1)
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 6).padding(.bottom, 2)
    }
}

struct BadgeIcon: View {
    let systemName: String
    let count: Int
    var body: some View {
        Image(systemName: systemName).font(.title3)
            .overlay(alignment: .topTrailing) {
                if count > 0 {
                    Text(count > 99 ? "99+" : "\(count)").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                        .padding(4).background(foddRed).clipShape(Capsule()).offset(x: 9, y: -8)
                }
            }
    }
}

struct MomentCard: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let moment: Moment
    @State private var comments = false
    @State private var reactionPulse: String?
    @State private var savedPulse = false
    @State private var reportMoment = false

    private var current: Moment { store.moments.first(where: { $0.id == moment.id }) ?? moment }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 11) {
                    Avatar(name: current.name, size: 44, avatar: current.avatar)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Text(current.name).font(.headline)
                            if current.creatorVerified { Image(systemName:"checkmark.seal.fill").font(.caption).foregroundStyle(foddOrange) }
                            Image(systemName: privacyIcon(current.visibility)).font(.caption2).foregroundStyle(.secondary)
                        }
                        Text("@\(current.username) · \(relativeDate(current.createdAt))").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if current.userId != store.account?.id {
                        Menu {
                            Button(role: .destructive) { reportMoment = true } label: { Label("Laporkan momen", systemImage: "exclamationmark.bubble") }
                        } label: { Image(systemName: "ellipsis").foregroundStyle(.secondary).padding(8) }
                    } else {
                        Image(systemName: "ellipsis").foregroundStyle(.tertiary)
                    }
                }

                HStack(spacing: 7) {
                    Label(current.momentType.title, systemImage: current.momentType.systemImage)
                        .font(.caption.weight(.semibold)).foregroundStyle(foddOrange)
                    if !current.locationName.isEmpty {
                        Text("•")
                        Label(current.locationName, systemImage: "mappin").font(.caption.weight(.semibold)).foregroundStyle(foddRed).lineLimit(1)
                    }
                }

                if !current.taggedNames.isEmpty {
                    Text("bersama \(current.taggedNames.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary)
                }

                Text(current.caption).font(.body).fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)

            if !current.image.isEmpty {
                FoodImage(source: current.image)
                    .aspectRatio(4 / 3, contentMode: .fill).frame(maxWidth: .infinity).clipped()
            }

            VStack(alignment: .leading, spacing: 13) {
                reactionBar
                HStack(spacing: 18) {
                    Button { comments = true } label: { Label("\(current.commentCount) komentar", systemImage: "bubble.right") }
                    if !current.locationName.isEmpty, current.latitude != nil, current.longitude != nil {
                        Button { openMomentLocation() } label: { Label("Buka Tempat", systemImage: "map") }
                    }
                    Spacer()
                    Button {
                        FoddFeedbackManager.shared.tap()
                        withAnimation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.48)) { savedPulse = true }
                        Task {
                            await store.toggleLike(current)
                            try? await Task.sleep(nanoseconds: 180_000_000)
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { savedPulse = false }
                        }
                    } label: {
                        Image(systemName: current.isLiked ? "bookmark.fill" : "bookmark")
                            .scaleEffect(savedPulse ? 1.28 : 1)
                    }
                    .buttonStyle(PressScaleButtonStyle(scale: 0.9))
                }
                .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(15)
        }
        .premiumCard()
        .sheet(isPresented: $comments) { CommentsView(moment: current) }
        .sheet(isPresented: $reportMoment) { ReportContentView(targetType:"moment",targetId:current.id,title:"Laporkan Food Moment") }
    }

    private var reactionBar: some View {
        HStack(spacing: 9) {
            ForEach(MomentReaction.allCases) { reaction in
                let count = current.reactions[reaction.rawValue] ?? 0
                Button {
                    FoddFeedbackManager.shared.reaction()
                    withAnimation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.42)) { reactionPulse = reaction.rawValue }
                    Task {
                        await store.react(current, with: reaction)
                        try? await Task.sleep(nanoseconds: 190_000_000)
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) { reactionPulse = nil }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(reaction.emoji).scaleEffect(reactionPulse == reaction.rawValue ? 1.32 : 1)
                        if count > 0 { Text("\(count)").font(.caption.weight(.semibold)).contentTransition(.numericText()) }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(current.myReaction == reaction.rawValue ? foddCream : Color(.tertiarySystemFill))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(current.myReaction == reaction.rawValue ? foddOrange.opacity(0.45) : .clear))
                }
                .buttonStyle(PressScaleButtonStyle(scale: 0.94))
            }
            Spacer()
        }
    }

    private func openMomentLocation() {
        guard let lat = current.latitude, let lon = current.longitude else { return }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: lat, longitude: lon)))
        item.name = current.locationName
        item.openInMaps()
    }
}

// MARK: - Explore

struct RestaurantsView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var location = LocationManager()
    @StateObject private var nearby = NearbyRestaurantService()
    @State private var search = ""
    @State private var searchMembers = false
    @State private var tasteEditor = false
    @State private var selectedMood = ""

    private let fallbackMoods = ["Pedas","Coffee Time","Date Night","Hemat","Comfort Food","Dessert","Sarapan","Hidden Gems"]
    private var curated: [Restaurant] {
        store.restaurants.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.category.localizedCaseInsensitiveContains(search) || $0.address.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                exploreHeader
                SearchBar(text: $search, prompt: "Cari restoran, makanan, kota, hashtag…") {
                    Task { await searchNearby(); await store.trackSmartEvent(type:"search",query:search) }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        moodChip("", icon:"sparkles", title:"For You")
                        ForEach(store.smartDashboard?.moods ?? fallbackMoods, id:\.self) { mood in
                            moodChip(mood, icon:moodIcon(mood), title:mood)
                        }
                        Button { searchMembers = true } label: { ExploreChip(icon: "person.2.fill", title: "Foodies") }.buttonStyle(.plain)
                    }
                }

                if let taste = store.smartDashboard?.taste {
                    TasteDNACompactCard(taste:taste) { tasteEditor=true }
                } else if store.isSmartFoodLoading {
                    SmartFoodLoadingCard()
                }

                if let smart=store.smartDashboard, !smart.forYou.isEmpty {
                    SectionHeader(title: "Cocok untuk Anda", action: "Taste Match")
                    ScrollView(.horizontal, showsIndicators:false) {
                        HStack(spacing:12) {
                            ForEach(smart.forYou.prefix(10)) { item in smartRestaurantLink(item) }
                        }
                    }
                }

                if let smart=store.smartDashboard, !smart.becauseYouLiked.isEmpty {
                    SectionHeader(title: "Because You Liked…", action: smart.becauseBasis ?? "Personal")
                    ScrollView(.horizontal,showsIndicators:false) {
                        HStack(spacing:12) { ForEach(smart.becauseYouLiked.prefix(8)) { item in smartRestaurantLink(item) } }
                    }
                }

                RestaurantMap(location: location, items: nearby.items)
                if let error = location.errorMessage { Text(error).font(.footnote).foregroundStyle(.secondary) }

                SectionHeader(title: "Di sekitar Anda", action: nearby.isLoading ? "Mencari…" : "Apple Maps")
                if nearby.items.isEmpty && !nearby.isLoading {
                    PremiumEmptyState(icon: "fork.knife", title: "Belum menemukan restoran", subtitle: "Izinkan lokasi atau cari nama makanan/restoran.")
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(nearby.items.prefix(10)) { item in
                                NavigationLink(value: item) { NearbyRestaurantTile(item: item) }.buttonStyle(.plain)
                            }
                        }
                    }
                }

                if let smart=store.smartDashboard, !smart.trending.isEmpty {
                    SectionHeader(title: "Trending Near You", action: "Smart Food")
                    LazyVStack(spacing:12) { ForEach(smart.trending.prefix(5)) { item in smartRestaurantRow(item) } }
                }

                if let smart=store.smartDashboard, !smart.hiddenGems.isEmpty {
                    SectionHeader(title: "Hidden Gems", action: "Belum terlalu ramai")
                    ScrollView(.horizontal, showsIndicators:false) {
                        HStack(spacing:12) { ForEach(smart.hiddenGems.prefix(8)) { item in smartRestaurantLink(item) } }
                    }
                }

                SectionHeader(title: "Pilihan komunitas Fodd", action: "Top Picks")
                LazyVStack(spacing: 12) {
                    ForEach(curated) { item in NavigationLink(value: item) { RestaurantCard(item: item) }.buttonStyle(.plain) }
                }
            }
            .padding(16).padding(.bottom, 18)
        }
        .background(Color(.systemGroupedBackground))
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: NearbyRestaurant.self) { NearbyRestaurantDetail(item: $0) }
        .navigationDestination(for: Restaurant.self) { RestaurantDetail(item: $0) }
        .sheet(isPresented: $searchMembers) { NavigationStack { UniversalSearchView() } }
        .sheet(isPresented: $tasteEditor) { TasteProfileEditorView() }
        .onAppear { location.request() }
        .task { await store.refreshSmartFood() }
        .onChange(of: location.coordinate?.latitude) { _, _ in
            Task { await searchNearby(); await refreshSmartForLocation() }
        }
        .onChange(of: search) { _, value in if value.isEmpty { Task { await searchNearby() } } }
        .refreshable { await searchNearby(); await refreshSmartForLocation() }
    }

    private var exploreHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Explore").font(.largeTitle.bold())
                Text("Rekomendasi yang makin paham selera Anda").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Button { tasteEditor=true } label: { FoddMark(size: 46) }.buttonStyle(.plain).accessibilityLabel("Buka Taste DNA")
        }
    }

    @ViewBuilder private func moodChip(_ mood:String, icon:String, title:String) -> some View {
        Button {
            FoddFeedbackManager.shared.selection(); selectedMood=mood
            Task { await refreshSmartForLocation() }
        } label: {
            Label(title,systemImage:icon).font(.caption.weight(.semibold))
                .foregroundStyle(selectedMood==mood ? Color.white : Color.primary)
                .padding(.horizontal,12).padding(.vertical,9)
                .background(selectedMood==mood ? AnyShapeStyle(brandGradient) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
                .clipShape(Capsule())
        }.buttonStyle(.plain)
    }

    private func moodIcon(_ mood:String) -> String {
        switch mood {
        case "Pedas": "flame.fill"
        case "Coffee Time": "cup.and.saucer.fill"
        case "Date Night": "heart.fill"
        case "Hemat": "banknote.fill"
        case "Comfort Food": "house.fill"
        case "Dessert": "birthday.cake.fill"
        case "Sarapan": "sun.max.fill"
        case "Hidden Gems": "diamond.fill"
        default: "fork.knife"
        }
    }

    @ViewBuilder private func smartRestaurantLink(_ item:SmartRestaurant) -> some View {
        NavigationLink(value:item.restaurant) { SmartRestaurantTile(item:item) }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { Task { await store.trackSmartEvent(type:"recommendation_open",restaurantId:item.restaurant.id,weight:2) } })
    }

    @ViewBuilder private func smartRestaurantRow(_ item:SmartRestaurant) -> some View {
        NavigationLink(value:item.restaurant) { SmartRestaurantRow(item:item) }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { Task { await store.trackSmartEvent(type:"recommendation_open",restaurantId:item.restaurant.id,weight:2) } })
    }

    private func searchNearby() async {
        guard let coordinate = location.coordinate else { return }
        await nearby.search(center: coordinate, query: search.isEmpty ? "restaurant" : search)
    }

    private func refreshSmartForLocation() async {
        await store.refreshSmartFood(latitude:location.coordinate?.latitude,longitude:location.coordinate?.longitude,mood:selectedMood)
    }
}

struct SearchBar: View {
    @Binding var text: String
    let prompt: String
    let submit: () -> Void
    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: $text).textInputAutocapitalization(.never).onSubmit(submit)
            if !text.isEmpty { Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) } }
        }
        .padding(14).background(Color(.secondarySystemGroupedBackground)).clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
    }
}

struct ExploreChip: View {
    let icon, title: String
    var body: some View {
        Label(title, systemImage: icon).font(.caption.weight(.semibold)).foregroundStyle(.primary)
            .padding(.horizontal, 12).padding(.vertical, 9).background(Color(.secondarySystemGroupedBackground)).clipShape(Capsule())
    }
}

struct SectionHeader: View {
    let title, action: String
    var body: some View { HStack { Text(title).font(.title3.bold()); Spacer(); Text(action).font(.caption.weight(.semibold)).foregroundStyle(foddOrange) } }
}

struct TasteDNACompactCard: View {
    let taste: TasteDNA
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment:.leading,spacing:13) {
                HStack {
                    Label("Your Taste DNA",systemImage:"sparkles").font(.headline).foregroundStyle(.white)
                    Spacer()
                    Text("\(taste.confidence)%").font(.title3.bold()).foregroundStyle(.white)
                }
                Text(taste.favoriteCategories.prefix(4).joined(separator:" • "))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.94)).lineLimit(2)
                HStack(spacing:8) {
                    ForEach(taste.traits.prefix(3)) { trait in
                        HStack(spacing:4) { Image(systemName:trait.icon); Text("\(trait.score)%") }
                            .font(.caption2.bold()).foregroundStyle(.white)
                            .padding(.horizontal,8).padding(.vertical,6).background(.white.opacity(0.16)).clipShape(Capsule())
                    }
                    Spacer()
                    Image(systemName:"chevron.right").font(.caption.bold()).foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(17).background(brandGradient).clipShape(RoundedRectangle(cornerRadius:24,style:.continuous))
        }.buttonStyle(.plain)
    }
}

struct SmartFoodLoadingCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse=false
    var body: some View {
        HStack(spacing:13) {
            Image(systemName:"sparkles").font(.title2).foregroundStyle(foddOrange).scaleEffect(pulse && !reduceMotion ? 1.12:0.94)
            VStack(alignment:.leading,spacing:4) { Text("Mempelajari Taste DNA…").font(.headline); Text("Menggabungkan save, collection, review, dan preferensi Anda.").font(.caption).foregroundStyle(.secondary) }
            Spacer(); ProgressView().tint(foddOrange)
        }.padding(16).premiumCard().onAppear { guard !reduceMotion else{return};withAnimation(.easeInOut(duration:0.8).repeatForever(autoreverses:true)){pulse=true} }
    }
}

struct SmartRestaurantTile: View {
    let item: SmartRestaurant
    var body: some View {
        VStack(alignment:.leading,spacing:9) {
            ZStack(alignment:.topLeading) {
                FoodImage(source:item.restaurant.image).frame(width:220,height:132).clipped()
                Text("\(item.matchScore)% MATCH").font(.caption2.bold()).foregroundStyle(.white)
                    .padding(.horizontal,8).padding(.vertical,6).background(brandGradient).clipShape(Capsule()).padding(9)
            }
            HStack(spacing:5) { Text(item.restaurant.name).font(.headline).lineLimit(1); if item.restaurant.isVerified { Image(systemName:"checkmark.seal.fill").font(.caption).foregroundStyle(foddOrange) } }
            Text(item.reason).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            HStack(spacing:5) { Image(systemName:"star.fill").foregroundStyle(foddGold);Text(String(format:"%.1f",item.restaurant.rating));if let km=item.distanceKm { Text("• \(String(format:"%.1f km",km))").foregroundStyle(.secondary) } }
                .font(.caption.weight(.semibold))
        }.frame(width:220,alignment:.leading).padding(10).premiumCard()
    }
}

struct SmartRestaurantRow: View {
    let item: SmartRestaurant
    var body: some View {
        HStack(spacing:12) {
            FoodImage(source:item.restaurant.image).frame(width:88,height:82).clipped().clipShape(RoundedRectangle(cornerRadius:16,style:.continuous))
            VStack(alignment:.leading,spacing:5) {
                HStack { Text(item.restaurant.name).font(.headline).lineLimit(1);if item.restaurant.isVerified { Image(systemName:"checkmark.seal.fill").font(.caption).foregroundStyle(foddOrange) };Spacer();Text("\(item.matchScore)%").font(.caption.bold()).foregroundStyle(foddOrange) }
                Text(item.reason).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing:5) { Image(systemName:"star.fill").foregroundStyle(foddGold);Text(String(format:"%.1f",item.restaurant.rating));ForEach(item.badges.prefix(1),id:\.self){Text("• \($0)").foregroundStyle(.secondary)} }.font(.caption.weight(.medium))
            }
        }.padding(10).premiumCard()
    }
}

struct TasteProfileEditorView: View {
    @EnvironmentObject private var store:AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft=TastePreferences()
    @State private var saving=false
    private let cuisines=["Indonesia","Jepang","Korea","China","Asia","Barat","Italian","Indian","Seafood","Burger","Mi","Kafe","Kopi","Dessert","Bakery","Halal","Vegetarian"]
    private let moods=["Pedas","Coffee Time","Date Night","Hemat","Comfort Food","Dessert","Sarapan","Hidden Gems"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    VStack(alignment:.leading,spacing:7) {
                        Label("Taste DNA",systemImage:"sparkles").font(.title.bold()).foregroundStyle(brandGradient)
                        Text("Pilih selera dasar. Fodd akan terus menyesuaikannya dari aktivitas nyata Anda.").foregroundStyle(.secondary)
                    }
                    tasteSection("Favorit Anda",subtitle:"Pilih beberapa kategori",values:cuisines,selection:$draft.cuisines)
                    tasteSection("Mood makan",subtitle:"Kapan biasanya Anda mencari tempat makan?",values:moods,selection:$draft.moods)
                    sliderCard(title:"Level Pedas",icon:"flame.fill",value:$draft.spicyLevel,left:"Tidak pedas",right:"Ekstra pedas")
                    sliderCard(title:"Sensitif Harga",icon:"banknote.fill",value:$draft.priceSensitivity,left:"Premium",right:"Cari hemat")
                    sliderCard(title:"Food Explorer",icon:"safari.fill",value:$draft.adventurousLevel,left:"Favorit saja",right:"Suka mencoba")
                    if let dna=store.smartDashboard?.taste {
                        VStack(alignment:.leading,spacing:10) {
                            Text("DNA saat ini").font(.headline)
                            ForEach(dna.traits) { trait in
                                HStack { Label(trait.name,systemImage:trait.icon);Spacer();Text("\(trait.score)%").bold().foregroundStyle(foddOrange) }
                                ProgressView(value:Double(trait.score),total:100).tint(foddOrange)
                            }
                            Text("Confidence \(dna.confidence)% • \(dna.sampleSize) sinyal selera").font(.caption).foregroundStyle(.secondary)
                            ShareLink(item:"Taste DNA Fodd saya: \(dna.favoriteCategories.prefix(5).joined(separator: " • ")) • Food Explorer \(dna.traits.first(where:{$0.name=="Food Explorer"})?.score ?? 0)%") {
                                Label("Bagikan Taste Card",systemImage:"square.and.arrow.up").font(.subheadline.weight(.semibold)).foregroundStyle(foddOrange)
                            }
                        }.padding(16).premiumCard()
                    }
                }.padding(18)
            }
            .background(Color(.systemGroupedBackground)).navigationTitle("Smart Food").navigationBarTitleDisplayMode(.inline).tint(foddOrange)
            .toolbar {
                ToolbarItem(placement:.cancellationAction){Button("Batal"){dismiss()}}
                ToolbarItem(placement:.confirmationAction){Button(saving ? "Menyimpan…":"Simpan"){Task{saving=true;defer{saving=false};if await store.saveTastePreferences(draft){dismiss()}}}.disabled(saving)}
            }
            .task { draft=store.tastePreferences }
        }
    }

    @ViewBuilder private func tasteSection(_ title:String,subtitle:String,values:[String],selection:Binding<[String]>) -> some View {
        VStack(alignment:.leading,spacing:10) {
            Text(title).font(.headline);Text(subtitle).font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns:[GridItem(.adaptive(minimum:86),spacing:8)],alignment:.leading,spacing:8) {
                ForEach(values,id:\.self) { value in
                    let selected=selection.wrappedValue.contains(value)
                    Button {
                        FoddFeedbackManager.shared.selection()
                        var values=selection.wrappedValue
                        if selected { values.removeAll{$0==value} } else if values.count<12 { values.append(value) }
                        selection.wrappedValue=values
                    } label: {
                        Text(value).font(.caption.weight(.semibold)).foregroundStyle(selected ? .white:.primary).padding(.horizontal,11).padding(.vertical,8)
                            .background(selected ? AnyShapeStyle(brandGradient):AnyShapeStyle(Color(.tertiarySystemGroupedBackground))).clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }
        }.padding(16).premiumCard()
    }

    @ViewBuilder private func sliderCard(title:String,icon:String,value:Binding<Int>,left:String,right:String) -> some View {
        VStack(alignment:.leading,spacing:9) {
            HStack { Label(title,systemImage:icon).font(.headline);Spacer();Text("\(value.wrappedValue)/4").font(.caption.bold()).foregroundStyle(foddOrange) }
            Slider(value:Binding(get:{Double(value.wrappedValue)},set:{value.wrappedValue=Int($0.rounded())}),in:0...4,step:1).tint(foddOrange)
            HStack { Text(left);Spacer();Text(right) }.font(.caption2).foregroundStyle(.secondary)
        }.padding(16).premiumCard()
    }
}

struct RestaurantMap: View {
    @ObservedObject var location: LocationManager
    let items: [NearbyRestaurant]
    var body: some View {
        Group {
            if let coordinate = location.coordinate {
                Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 5000, longitudinalMeters: 5000))) {
                    UserAnnotation()
                    ForEach(items.prefix(20)) { item in Marker(item.name, coordinate: item.coordinate).tint(foddOrange) }
                }
            } else {
                PremiumEmptyState(icon: "location", title: "Lokasi belum tersedia", subtitle: "Izinkan akses lokasi untuk pengalaman Explore terbaik.")
            }
        }
        .frame(height: 245).clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.primary.opacity(0.05)))
    }
}

struct NearbyRestaurantTile: View {
    let item: NearbyRestaurant
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(brandGradient.opacity(0.13))
                Image(systemName: "fork.knife").font(.system(size: 30, weight: .medium)).foregroundStyle(brandGradient)
            }
            .frame(height: 112)
            Text(item.name).font(.headline).foregroundStyle(.primary).lineLimit(1)
            Text("\(item.category) • \(item.distanceText)").font(.caption).foregroundStyle(.secondary)
            Text(item.address.isEmpty ? "Lihat di Apple Maps" : item.address).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(12).frame(width: 185).premiumCard()
    }
}

struct NearbyRestaurantCard: View {
    let item: NearbyRestaurant
    var body: some View {
        HStack(spacing: 14) {
            ZStack { RoundedRectangle(cornerRadius: 16).fill(brandGradient.opacity(0.13)); Image(systemName: "fork.knife").font(.title).foregroundStyle(brandGradient) }.frame(width: 86, height: 78)
            VStack(alignment: .leading, spacing: 5) {
                Text(item.name).font(.headline).foregroundStyle(.primary)
                Text(item.category).foregroundStyle(.secondary)
                Text("\(item.distanceText) • \(item.address.isEmpty ? "Apple Maps" : item.address)").font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(12).premiumCard()
    }
}

struct NearbyRestaurantDetail: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openURL) private var openURL
    let item: NearbyRestaurant
    @State private var osm: OSMPlaceDetails?
    @State private var collectionPicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Map(initialPosition: .region(MKCoordinateRegion(center: item.coordinate, latitudinalMeters: 1200, longitudinalMeters: 1200))) {
                    Marker(item.name, coordinate: item.coordinate).tint(foddOrange)
                }
                .frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Text(item.name).font(.largeTitle.bold())
                    HStack { Label(item.category, systemImage: "fork.knife"); Spacer(); Text(item.distanceText).foregroundStyle(.secondary) }
                }

                HStack(spacing: 10) {
                    Button { openDirections() } label: { Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill") }.buttonStyle(PrimaryCompactButton())
                    Button { collectionPicker = true } label: { Label("Koleksi", systemImage: "square.stack.fill") }.buttonStyle(.bordered)
                    if !item.phone.isEmpty { Button { call(item.phone) } label: { Label("Call", systemImage: "phone.fill") }.buttonStyle(.bordered) }
                    Button { item.mapItem().openInMaps() } label: { Label("Maps", systemImage: "map.fill") }.buttonStyle(.bordered)
                }

                VStack(spacing: 15) {
                    InfoLine(icon: "mappin.and.ellipse", title: "Alamat", value: item.address.isEmpty ? "Lihat alamat lengkap di Apple Maps" : item.address)
                    InfoLine(icon: "clock", title: "Jam buka", value: (osm?.openingHours.isEmpty == false ? osm!.openingHours : "Lihat jam buka terbaru di Apple Maps"))
                    if !(osm?.cuisine ?? "").isEmpty { InfoLine(icon: "takeoutbag.and.cup.and.straw", title: "Jenis makanan", value: osm!.cuisine) }
                }
                .padding(16).premiumCard()

                let website = !item.website.isEmpty ? item.website : (osm?.website ?? "")
                if let url = URL(string: website), !website.isEmpty {
                    Button { openURL(url) } label: { Label("Menu / Website", systemImage: "safari.fill").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
                }

                ReviewSection(placeId: item.id, placeName: item.name, address: item.address, latitude: item.latitude, longitude: item.longitude)
                Text("Data lokasi, telepon, dan website berasal dari Apple Maps. Jam buka/cuisine dapat diperkaya dari OpenStreetMap bila tersedia.").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(item.name).navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented:$collectionPicker) { NearbyCollectionPickerView(item:item) }
        .task { osm = await OSMPlaceDetailsService().fetch(for: item) }
    }

    private func openDirections() { item.mapItem().openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving]) }
    private func call(_ phone: String) { if let url = URL(string: "tel://\(phone.filter { $0.isNumber || $0 == "+" })") { openURL(url) } }
}

struct RestaurantCard: View {
    @EnvironmentObject private var store: AppStore
    let item: Restaurant
    var body: some View {
        HStack(spacing: 14) {
            FoodImage(source: item.image).frame(width: 96, height: 88).clipped().clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing:5) { Text(item.name).font(.headline); if item.isVerified { Image(systemName:"checkmark.seal.fill").font(.caption).foregroundStyle(foddOrange) } }
                Text(item.category).font(.subheadline).foregroundStyle(.secondary)
                Text("★ \(item.rating, specifier: "%.1f") \(item.distance.isEmpty ? "" : "• \(item.distance)") \(item.price.isEmpty ? "" : "• \(item.price)")")
                    .font(.caption.weight(.semibold)).foregroundStyle(foddOrange)
            }
            Spacer()
            Button { Task { await store.toggleSaved(item) } } label: { Image(systemName: item.isSaved ? "bookmark.fill" : "bookmark").foregroundStyle(item.isSaved ? foddOrange : .secondary) }.buttonStyle(.plain)
        }
        .padding(12).premiumCard()
    }
}

struct RestaurantDetail: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openURL) private var openURL
    @State private var collectionPicker = false
    @State private var planComposer = false
    @State private var claimSheet = false
    @State private var menuItems: [MenuItem] = []
    @State private var restaurantPosts: [RestaurantPost] = []
    let item: Restaurant
    private var smartMatch:SmartRestaurant? {
        let all=(store.smartDashboard?.forYou ?? [])+(store.smartDashboard?.becauseYouLiked ?? [])+(store.smartDashboard?.trending ?? [])+(store.smartDashboard?.hiddenGems ?? [])
        return all.first{$0.restaurant.id==item.id}
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FoodImage(source: item.image).aspectRatio(4 / 3, contentMode: .fill).frame(maxWidth: .infinity).clipped().clipShape(RoundedRectangle(cornerRadius: 24))
                HStack(alignment:.firstTextBaseline,spacing:8) {
                    Text(item.name).font(.largeTitle.bold())
                    if item.isVerified { Image(systemName:"checkmark.seal.fill").font(.title2).foregroundStyle(foddOrange).accessibilityLabel("Verified Restaurant") }
                }
                HStack { Text(item.category).foregroundStyle(.secondary); if item.isVerified { Text("VERIFIED").font(.caption2.bold()).foregroundStyle(foddOrange).padding(.horizontal,8).padding(.vertical,4).background(foddCream,in:Capsule()) } }
                if let match=smartMatch {
                    HStack(spacing:10) {
                        ZStack { Circle().fill(brandGradient);Text("\(match.matchScore)%").font(.caption.bold()).foregroundStyle(.white) }.frame(width:48,height:48)
                        VStack(alignment:.leading,spacing:3){Text("Taste Match").font(.headline);Text(match.reason).font(.caption).foregroundStyle(.secondary)};Spacer();Image(systemName:"sparkles").foregroundStyle(foddOrange)
                    }.padding(13).premiumCard()
                }
                Text("★ \(item.rating, specifier: "%.1f") \(item.distance.isEmpty ? "" : "• \(item.distance)") \(item.price.isEmpty ? "" : "• \(item.price)")").foregroundStyle(foddOrange).fontWeight(.semibold)
                VStack(spacing: 14) {
                    if !item.address.isEmpty { InfoLine(icon: "mappin.and.ellipse", title: "Alamat", value: item.address) }
                    if !item.hours.isEmpty { InfoLine(icon: "clock", title: "Jam buka", value: item.hours) }
                    if !item.menu.isEmpty { InfoLine(icon: "menucard", title: "Menu", value: item.menu) }
                }.padding(16).premiumCard()
                FoddLookAroundCard(restaurant: item)
                if !menuItems.isEmpty { RestaurantMenuPreview(items:menuItems) }
                if !restaurantPosts.isEmpty { RestaurantUpdatesPreview(posts:restaurantPosts) }
                HStack {
                    if !item.phone.isEmpty { Button { call(item.phone) } label: { Label("Call", systemImage: "phone.fill") }.buttonStyle(.bordered) }
                    Button { collectionPicker = true } label: { Label("Koleksi", systemImage: "square.stack.fill") }.buttonStyle(.bordered)
                    Button { planComposer = true } label: { Label("Makan Bareng", systemImage: "person.3.fill") }.buttonStyle(.bordered)
                    Button { openMaps() } label: { Label("Apple Maps", systemImage: "map.fill") }.buttonStyle(PrimaryCompactButton())
                }
                if store.myRestaurants.contains(where:{$0.id==item.id}) {
                    NavigationLink { RestaurantStudioDetailView(restaurant: store.myRestaurants.first(where:{$0.id==item.id}) ?? item) } label: { Label("Kelola Restoran",systemImage:"storefront.fill").frame(maxWidth:.infinity) }.buttonStyle(PrimaryCompactButton())
                } else if let claim=store.restaurantClaims.first(where:{$0.restaurantId==item.id && $0.status=="pending"}) {
                    Label("Klaim menunggu review",systemImage:"clock.badge.checkmark").frame(maxWidth:.infinity).padding(11).foregroundStyle(foddOrange).background(foddCream,in:RoundedRectangle(cornerRadius:14)).accessibilityHint(claim.businessName)
                } else {
                    Button { claimSheet=true } label: { Label(item.isVerified ? "Ajukan Akses Pengelola" : "Klaim Restoran Ini",systemImage:"checkmark.seal").frame(maxWidth:.infinity) }.buttonStyle(.bordered)
                }
                if let url = URL(string: item.website), !item.website.isEmpty { Button { openURL(url) } label: { Label("Menu / Website", systemImage: "safari").frame(maxWidth: .infinity) }.buttonStyle(.bordered) }
                ReviewSection(placeId: item.id, placeName: item.name, address: item.address, latitude: item.latitude ?? 0, longitude: item.longitude ?? 0)
            }.padding(16)
        }
        .background(Color(.systemGroupedBackground)).navigationTitle(item.name).navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $collectionPicker) { CollectionPickerView(restaurant:item) }
        .sheet(isPresented: $planComposer) { NavigationStack { CreateDiningPlanView(initialRestaurant:item) } }
        .sheet(isPresented: $claimSheet) { ClaimRestaurantView(restaurant:item) }
        .task {
            await store.trackSmartEvent(type:"view",restaurantId:item.id,weight:1.5)
            async let menu = store.restaurantMenu(item)
            async let posts = store.restaurantPosts(item)
            menuItems = await menu; restaurantPosts = await posts
            await store.refreshCreatorStudio()
        }
    }

    private func call(_ phone: String) { if let url = URL(string: "tel://\(phone.filter { $0.isNumber || $0 == "+" })") { openURL(url) } }
    private func openMaps() {
        if let lat = item.latitude, let lon = item.longitude {
            let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: lat, longitude: lon))); mapItem.name = item.name; mapItem.openInMaps()
        } else {
            let q = item.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? item.name
            if let url = URL(string: "http://maps.apple.com/?q=\(q)") { openURL(url) }
        }
    }
}

struct InfoLine: View {
    let icon, title, value: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack { Circle().fill(foddCream); Image(systemName: icon).foregroundStyle(foddOrange) }.frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 3) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).fixedSize(horizontal: false, vertical: true) }
            Spacer()
        }
    }
}

// MARK: - Reviews

struct ReviewSection: View {
    @EnvironmentObject private var store: AppStore
    let placeId, placeName, address: String
    let latitude, longitude: Double
    @State private var reviews: [PlaceReview] = []
    @State private var composer = false
    private var average: Double { reviews.isEmpty ? 0 : Double(reviews.reduce(0) { $0 + $1.rating }) / Double(reviews.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack { Text("Reviews Fodd").font(.title3.bold()); Spacer(); if !reviews.isEmpty { Text("★ \(average, specifier: "%.1f")").foregroundStyle(foddOrange).fontWeight(.bold) } }
            Button { composer = true } label: { Label("Tulis Ulasan", systemImage: "square.and.pencil").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
            if reviews.isEmpty { Text("Belum ada ulasan dari member Fodd.").foregroundStyle(.secondary).padding(.vertical, 8) }
            ForEach(reviews) { review in
                VStack(alignment: .leading, spacing: 9) {
                    HStack { Avatar(name: review.name, size: 38, avatar: review.avatar); VStack(alignment: .leading) { Text(review.name).font(.headline); Text(String(repeating: "★", count: review.rating) + String(repeating: "☆", count: max(0, 5 - review.rating))).foregroundStyle(foddGold).font(.caption) }; Spacer() }
                    Text(review.body)
                    if !review.photo.isEmpty { FoodImage(source: review.photo).aspectRatio(4 / 3, contentMode: .fill).frame(maxWidth: .infinity).clipped().clipShape(RoundedRectangle(cornerRadius: 16)) }
                }
                .padding(14).premiumCard()
            }
        }
        .task { reviews = await store.reviews(placeId: placeId) }
        .sheet(isPresented: $composer) { ReviewComposer(placeId: placeId, placeName: placeName, address: address, latitude: latitude, longitude: longitude) { review in if let i = reviews.firstIndex(where: { $0.userId == review.userId }) { reviews[i] = review } else { reviews.insert(review, at: 0) } } }
    }
}

struct ReviewComposer: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let placeId, placeName, address: String
    let latitude, longitude: Double
    let onSaved: (PlaceReview) -> Void
    @State private var rating = 5
    @State private var bodyText = ""
    @State private var photo = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var camera = false
    @State private var sending = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Rating") { HStack { ForEach(1...5, id: \.self) { value in Button { rating = value } label: { Image(systemName: value <= rating ? "star.fill" : "star").foregroundStyle(foddGold).font(.title2) }.buttonStyle(.plain) } } }
                Section("Ulasan") { TextEditor(text: $bodyText).frame(minHeight: 120) }
                Section("Foto makanan") {
                    if !photo.isEmpty { FoodImage(source: photo).frame(height: 200).clipped().clipShape(RoundedRectangle(cornerRadius: 12)) }
                    PhotosPicker("Pilih dari Galeri", selection: $photoItem, matching: .images)
                    Button("Ambil Foto") { camera = true }
                }
                if let error = store.errorMessage { Section { ErrorText(error) } }
            }
            .tint(foddOrange).navigationTitle("Ulasan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Batal") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(sending ? "Mengirim…" : "Kirim") { Task { await save() } }.disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending) }
            }
            .sheet(isPresented: $camera) { CameraPicker { data in if let value = compressedDataURL(data) { photo = value } else { store.errorMessage = "Foto tidak dapat diproses. Coba pilih foto lain." } } }
            .onChange(of: photoItem) { _, item in Task { if let data = try? await item?.loadTransferable(type: Data.self), let value = compressedDataURL(data) { photo = value } else if item != nil { store.errorMessage = "Foto tidak dapat diproses. Coba pilih foto lain." } } }
        }
    }

    private func save() async {
        sending = true
        if let review = await store.addReview(placeId: placeId, placeName: placeName, address: address, latitude: latitude, longitude: longitude, rating: rating, body: bodyText.trimmingCharacters(in: .whitespacesAndNewlines), photo: photo) { onSaved(review); dismiss() }
        else { sending = false }
    }
}

// MARK: - Search / Members

struct UniversalSearchView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var location = LocationManager()
    @StateObject private var nearby = NearbyRestaurantService()
    @State private var query = ""
    @State private var results: SearchResults?
    @State private var searching = false

    var body: some View {
        List {
            if query.isEmpty {
                Section { Text("Cari member, restoran, makanan, kota, atau #hashtag.").foregroundStyle(.secondary) }
                Section("Foodies") { ForEach(store.members.prefix(20)) { member in NavigationLink(value: member) { MemberRow(member: member) } } }
            } else if searching {
                HStack { Spacer(); ProgressView("Mencari…"); Spacer() }
            } else {
                if let members = results?.members, !members.isEmpty { Section("Foodies") { ForEach(members) { member in NavigationLink(value: member) { MemberRow(member: member) } } } }
                if !nearby.items.isEmpty { Section("Restoran nyata • Apple Maps") { ForEach(nearby.items.prefix(15)) { item in NavigationLink(value: item) { NearbyRestaurantCard(item: item) } } } }
                if let restaurants = results?.restaurants, !restaurants.isEmpty { Section("Restoran Fodd") { ForEach(restaurants) { item in NavigationLink(value: item) { RestaurantCard(item: item) } } } }
                if let moments = results?.moments, !moments.isEmpty { Section("Food Moments") { ForEach(moments) { SearchMomentRow(moment: $0) } } }
            }
        }
        .tint(foddOrange).navigationTitle("Search").searchable(text: $query, prompt: "foodie, restoran, makanan, kota, #hashtag")
        .onSubmit(of: .search) { Task { await search() } }
        .onChange(of: query) { _, value in if value.isEmpty { results = nil; nearby.items = [] } }
        .navigationDestination(for: Member.self) { MemberProfileView(member: $0) }
        .navigationDestination(for: NearbyRestaurant.self) { NearbyRestaurantDetail(item: $0) }
        .navigationDestination(for: Restaurant.self) { RestaurantDetail(item: $0) }
        .onAppear { location.request() }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines); guard !text.isEmpty else { return }
        searching = true; defer { searching = false }
        results = await store.universalSearch(text)
        if let coordinate = location.coordinate { await nearby.search(center: coordinate, query: text) }
    }
}

struct SearchMomentRow: View {
    let moment: Moment
    var body: some View {
        HStack(spacing: 12) {
            if moment.image.isEmpty { ZStack { RoundedRectangle(cornerRadius: 12).fill(foddCream); Image(systemName: moment.momentType.systemImage).foregroundStyle(foddOrange) }.frame(width: 66, height: 66) }
            else { FoodImage(source: moment.image).frame(width: 66, height: 66).clipped().clipShape(RoundedRectangle(cornerRadius: 12)) }
            VStack(alignment: .leading, spacing: 4) { Text(moment.name).font(.headline); Text(moment.caption).lineLimit(2); Text("@\(moment.username)").font(.caption).foregroundStyle(.secondary) }
        }.padding(.vertical, 3)
    }
}

struct MemberRow: View {
    let member: Member
    var body: some View {
        HStack(spacing: 12) {
            Avatar(name: member.name, size: 48, avatar: member.avatar)
            VStack(alignment: .leading, spacing: 3) { Text(member.name).font(.headline); Text("@\(member.username)").foregroundStyle(.secondary).font(.subheadline) }
            Spacer()
            if member.isCloseFoodie { Image(systemName: "star.fill").foregroundStyle(foddGold) }
            else if member.followRequestPending { Image(systemName:"clock.fill").foregroundStyle(foddGold) }
            else if member.isFollowing { Image(systemName: "checkmark.circle.fill").foregroundStyle(foddOrange) }
            else if member.isPrivate { Image(systemName:"lock.fill").foregroundStyle(.secondary) }
        }.padding(.vertical, 4)
    }
}

struct MemberProfileView: View {
    @EnvironmentObject private var store: AppStore
    @State var member: Member
    @State private var posts: [Moment] = []
    @State private var reportUser = false
    @State private var blockConfirm = false

    private var followTitle: String {
        if member.isFollowing { return "Following" }
        if member.followRequestPending { return "Requested" }
        return member.isPrivate ? "Request Follow" : "Follow"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ProfileHero(name: member.name, username: member.username, bio: member.bio, avatar: member.avatar, isCreator: member.isCreator, creatorVerified: member.creatorVerified, creatorCategory: member.creatorCategory)
                if member.isCreator,let url=URL(string:member.creatorWebsite),!member.creatorWebsite.isEmpty { Link(destination:url){Label("Creator Website",systemImage:"link").font(.subheadline.weight(.semibold))}.tint(foddOrange) }
                HStack { Metric(value: member.followersCount, label: "Followers"); Metric(value: member.followingCount, label: "Following"); Metric(value: posts.count, label: "Moments") }
                HStack(spacing: 10) {
                    Button(followTitle) {
                        FoddFeedbackManager.shared.tap()
                        Task {
                            if let state=await store.toggleFollow(member) { member.isFollowing=state.isFollowing; member.followRequestPending=state.pending; if state.isFollowing { posts=await store.moments(for:member.id) } }
                        }
                    }.buttonStyle(PrimaryCompactButton())
                    Button { FoddFeedbackManager.shared.selection(); Task { await store.toggleCloseFoodie(member); member.isCloseFoodie.toggle() } } label: { Label(member.isCloseFoodie ? "Close Foodie" : "Add Close", systemImage: member.isCloseFoodie ? "star.fill" : "star") }.buttonStyle(.bordered)
                    .disabled(!member.isFollowing && member.isPrivate)
                }
                NavigationLink { RealChatView(member: member) } label: { Label("Message", systemImage: "message.fill").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
                if member.isPrivate && !member.isFollowing {
                    VStack(spacing:12) { Image(systemName:"lock.fill").font(.largeTitle).foregroundStyle(foddOrange); Text("Akun Privat").font(.headline); Text(member.followRequestPending ? "Permintaan mengikuti sudah dikirim. Food Diary akan tampil setelah disetujui." : "Ikuti akun ini untuk melihat Food Diary mereka.").multilineTextAlignment(.center).foregroundStyle(.secondary) }.padding(28).frame(maxWidth:.infinity).premiumCard()
                } else {
                    FoodDiaryTimeline(posts: posts)
                }
            }.padding(18).frame(maxWidth: 620)
        }
        .background(Color(.systemGroupedBackground)).navigationTitle(member.name).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement:.topBarTrailing) {
                Menu {
                    Button { reportUser=true } label:{ Label("Laporkan akun",systemImage:"exclamationmark.bubble") }
                    Button(role:.destructive) { blockConfirm=true } label:{ Label("Blokir akun",systemImage:"hand.raised.fill") }
                } label:{ Image(systemName:"ellipsis.circle") }
            }
        }
        .confirmationDialog("Blokir @\(member.username)?",isPresented:$blockConfirm,titleVisibility:.visible) {
            Button("Blokir",role:.destructive) { Task { _=await store.setBlocked(member,enabled:true) } }
            Button("Batal",role:.cancel) {}
        } message: { Text("Kalian tidak dapat saling melihat momen, mengikuti, atau mengirim pesan sampai blokir dibuka.") }
        .sheet(isPresented:$reportUser) { ReportContentView(targetType:"user",targetId:member.id,title:"Laporkan @\(member.username)") }
        .task { posts = await store.moments(for: member.id) }
    }
}

// MARK: - Create Moment ala Path

struct CreateMomentHub: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    VStack(spacing: 6) {
                        FoddMark(size: 54)
                        Text("Buat Moment").font(.title2.bold())
                        Text("Apa yang ingin Anda abadikan?").font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.bottom, 4)

                    NavigationLink { CreateDiningPlanView() } label: {
                        HStack(spacing:14) {
                            ZStack { RoundedRectangle(cornerRadius:16).fill(brandGradient);Image(systemName:"person.3.fill").font(.title2).foregroundStyle(.white) }.frame(width:54,height:54)
                            VStack(alignment:.leading,spacing:4){Text("Makan Bareng").font(.headline);Text("Undang teman, vote restoran, chat & album bersama").font(.subheadline).foregroundStyle(.secondary)}
                            Spacer();Image(systemName:"chevron.right").foregroundStyle(.tertiary)
                        }.padding(14).premiumCard()
                    }.buttonStyle(PressScaleButtonStyle(scale:0.985))

                    Divider().padding(.vertical,2)

                    ForEach(MomentType.allCases) { type in
                        NavigationLink(value: type) { MomentTypeRow(type: type) }.buttonStyle(PressScaleButtonStyle(scale: 0.985))
                    }
                }
                .padding(18)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "xmark") } } }
            .navigationDestination(for: MomentType.self) { type in MomentComposer(type: type, dismissAll: { dismiss() }) }
        }
    }
}

struct MomentTypeRow: View {
    let type: MomentType
    private var tint: Color {
        switch type { case .photo: foddRed; case .checkin: foddOrange; case .eating: foddGold; case .cooking: .green; case .craving: .purple; case .thought: .blue }
    }
    var body: some View {
        HStack(spacing: 14) {
            ZStack { RoundedRectangle(cornerRadius: 16).fill(tint.opacity(0.13)); Image(systemName: type.systemImage).font(.title2).foregroundStyle(tint) }.frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 4) { Text(type.title).font(.headline); Text(type.subtitle).font(.subheadline).foregroundStyle(.secondary) }
            Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(14).premiumCard()
    }
}

struct MomentComposer: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var location = LocationManager()
    @StateObject private var nearby = NearbyRestaurantService()
    let type: MomentType
    let dismissAll: () -> Void
    @State private var caption = ""
    @State private var image = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var camera = false
    @State private var sending = false
    @State private var visibility: MomentVisibility = .everyone
    @State private var selectedAudience = Set<String>()
    @State private var taggedUsers = Set<String>()
    @State private var audienceSheet = false
    @State private var locationName = ""
    @State private var locationAddress = ""
    @State private var latitude: Double?
    @State private var longitude: Double?

    private var needsPhoto: Bool { type == .photo }
    private var canShare: Bool {
        !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (!needsPhoto || !image.isEmpty) && (visibility != .selected || !selectedAudience.isEmpty) && !sending
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                composerIdentity
                if type != .thought { photoPicker }
                if type == .checkin { checkInPicker }

                VStack(alignment: .leading, spacing: 9) {
                    Text(promptTitle).font(.headline)
                    TextEditor(text: $caption).scrollContentBackground(.hidden).frame(minHeight: 130)
                        .padding(12).background(Color(.secondarySystemGroupedBackground)).clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(alignment: .topLeading) { if caption.isEmpty { Text(promptPlaceholder).foregroundStyle(.secondary).padding(20).allowsHitTesting(false) } }
                }

                tagFriends

                Button { audienceSheet = true } label: {
                    HStack { ZStack { Circle().fill(foddCream); Image(systemName: visibility.systemImage).foregroundStyle(foddOrange) }.frame(width: 40, height: 40); VStack(alignment: .leading) { Text("Siapa yang bisa melihat?").font(.caption).foregroundStyle(.secondary); Text(visibility.title).font(.headline) }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
                    .padding(13).premiumCard()
                }.buttonStyle(.plain)

                if let error = store.errorMessage { ErrorText(error) }

                Button(sending ? "Membagikan…" : "Bagikan Moment") { Task { await shareMoment() } }
                    .buttonStyle(PrimaryButton()).disabled(!canShare)
            }
            .padding(18)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(type.title).navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $camera) { CameraPicker { data in if let value = compressedDataURL(data) { image = value } else { store.errorMessage = "Foto tidak dapat diproses. Coba pilih foto lain." } } }
        .sheet(isPresented: $audienceSheet) { AudiencePicker(visibility: $visibility, selected: $selectedAudience) }
        .onAppear { if type == .checkin { location.request() } }
        .onChange(of: location.coordinate?.latitude) { _, _ in Task { await loadNearby() } }
    }

    private var composerIdentity: some View {
        HStack(spacing: 12) {
            Avatar(name: store.account?.name ?? "F", size: 46, avatar: store.account?.avatar ?? "")
            VStack(alignment: .leading, spacing: 3) { Text(store.account?.name ?? "Fodd Member").font(.headline); Label(type.title, systemImage: type.systemImage).font(.caption).foregroundStyle(foddOrange) }
            Spacer()
        }
    }

    private var photoPicker: some View {
        VStack(spacing: 12) {
            if !image.isEmpty { FoodImage(source: image).frame(height: 245).clipped().clipShape(RoundedRectangle(cornerRadius: 22)) }
            else {
                ZStack { RoundedRectangle(cornerRadius: 22).fill(brandGradient.opacity(0.09)); VStack(spacing: 10) { Image(systemName: "camera.fill").font(.largeTitle).foregroundStyle(foddOrange); Text(needsPhoto ? "Tambahkan foto utama" : "Foto opsional").font(.subheadline).foregroundStyle(.secondary) } }.frame(height: 170)
            }
            HStack {
                PhotosPicker(selection: $photoItem, matching: .images) { Label("Galeri", systemImage: "photo") }.buttonStyle(.bordered)
                Button { camera = true } label: { Label("Kamera", systemImage: "camera") }.buttonStyle(.bordered)
            }
        }
        .onChange(of: photoItem) { _, item in Task { if let data = try? await item?.loadTransferable(type: Data.self), let value = compressedDataURL(data) { image = value } else if item != nil { store.errorMessage = "Foto tidak dapat diproses. Coba pilih foto lain." } } }
    }

    private var checkInPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("Check-in restoran").font(.headline); Spacer(); if nearby.isLoading { ProgressView() } }
            if nearby.items.isEmpty { Text("Mencari restoran nyata dari Apple Maps di sekitar Anda…").font(.subheadline).foregroundStyle(.secondary) }
            else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(nearby.items.prefix(12)) { item in
                            Button { select(item) } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Text(item.distanceText).font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(12).frame(width: 165, alignment: .leading)
                                .background(locationName == item.name ? foddCream : Color(.secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 15))
                                .overlay(RoundedRectangle(cornerRadius: 15).stroke(locationName == item.name ? foddOrange.opacity(0.5) : .clear))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            if !locationName.isEmpty { Label(locationName, systemImage: "mappin.circle.fill").foregroundStyle(foddOrange).font(.subheadline.weight(.semibold)) }
        }
    }

    private var tagFriends: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Bersama foodies").font(.headline)
            if store.members.isEmpty { Text("Belum ada member untuk ditandai.").font(.subheadline).foregroundStyle(.secondary) }
            else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(store.members.prefix(20)) { member in
                            Button { FoddFeedbackManager.shared.selection(); if taggedUsers.contains(member.id) { taggedUsers.remove(member.id) } else { taggedUsers.insert(member.id) } } label: {
                                VStack(spacing: 5) { Avatar(name: member.name, size: 46, avatar: member.avatar); Text(member.name.components(separatedBy: " ").first ?? member.name).font(.caption).lineLimit(1) }
                                    .padding(7).background(taggedUsers.contains(member.id) ? foddCream : Color.clear).clipShape(RoundedRectangle(cornerRadius: 14))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var promptTitle: String {
        switch type { case .photo: "Ceritakan foto ini"; case .checkin: "Bagaimana tempat ini?"; case .eating: "Sedang makan apa?"; case .cooking: "Apa yang sedang Anda masak?"; case .craving: "Sedang ngidam apa?"; case .thought: "Apa yang sedang Anda pikirkan?" }
    }
    private var promptPlaceholder: String { type == .thought ? "Tulis cerita, rekomendasi, atau opini kuliner…" : "Tulis cerita singkat tentang momen ini…" }

    private func loadNearby() async { guard let coordinate = location.coordinate else { return }; await nearby.search(center: coordinate, query: "restaurant") }
    private func select(_ item: NearbyRestaurant) {
        FoddFeedbackManager.shared.checkIn()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.76)) {
            locationName = item.name; locationAddress = item.address; latitude = item.latitude; longitude = item.longitude
        }
    }
    private func shareMoment() async {
        sending = true
        let ok = await store.createMoment(caption: caption.trimmingCharacters(in: .whitespacesAndNewlines), image: image, type: type, locationName: locationName, locationAddress: locationAddress, latitude: latitude, longitude: longitude, visibility: visibility, taggedUserIds: Array(taggedUsers), selectedUserIds: Array(selectedAudience))
        if ok {
            FoddFeedbackManager.shared.success()
            NotificationCenter.default.post(name: .foddMomentDidPublish, object: nil)
            dismissAll()
        } else { sending = false }
    }
}

struct AudiencePicker: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Binding var visibility: MomentVisibility
    @Binding var selected: Set<String>

    var body: some View {
        NavigationStack {
            List {
                Section("Audience") {
                    ForEach(MomentVisibility.allCases) { item in
                        Button { FoddFeedbackManager.shared.selection(); visibility = item } label: {
                            HStack(spacing: 12) {
                                ZStack { Circle().fill(item == .closeFoodies ? Color.yellow.opacity(0.18) : foddCream); Image(systemName: item.systemImage).foregroundStyle(item == .closeFoodies ? foddGold : foddOrange) }.frame(width: 40, height: 40)
                                VStack(alignment: .leading, spacing: 3) { Text(item.title).foregroundStyle(.primary).font(.headline); Text(item.subtitle).font(.caption).foregroundStyle(.secondary) }
                                Spacer(); if visibility == item { Image(systemName: "checkmark.circle.fill").foregroundStyle(foddOrange) }
                            }
                        }.buttonStyle(.plain)
                    }
                }
                if visibility == .selected {
                    Section("Pilih teman") {
                        ForEach(store.members) { member in
                            Button { FoddFeedbackManager.shared.selection(); if selected.contains(member.id) { selected.remove(member.id) } else { selected.insert(member.id) } } label: {
                                HStack { Avatar(name: member.name, size: 40, avatar: member.avatar); VStack(alignment: .leading) { Text(member.name).foregroundStyle(.primary); Text("@\(member.username)").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: selected.contains(member.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(selected.contains(member.id) ? foddOrange : .secondary) }
                            }.buttonStyle(.plain)
                        }
                    }
                }
                if visibility == .closeFoodies && store.closeFoodies.isEmpty { Section { Text("Belum ada Close Foodies. Tambahkan dari profil member atau menu Close Foodies di profil Anda.").font(.footnote).foregroundStyle(.secondary) } }
            }
            .navigationTitle("Siapa yang bisa melihat?").navigationBarTitleDisplayMode(.inline).tint(foddOrange)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Selesai") { dismiss() }.fontWeight(.semibold) } }
        }
    }
}

// MARK: - Comments

struct CommentsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let moment: Moment
    @State private var comments: [MomentComment] = []
    @State private var text = ""
    @State private var reportComment: MomentComment?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if comments.isEmpty { PremiumEmptyState(icon: "bubble.right", title: "Belum ada komentar", subtitle: "Mulai percakapan tentang Food Moment ini.") }
                else { List(comments) { comment in HStack(alignment: .top, spacing: 10) { Avatar(name: comment.name, size: 38, avatar: comment.avatar); VStack(alignment: .leading, spacing: 4) { Text(comment.name).font(.headline); Text(comment.body).fixedSize(horizontal: false, vertical: true) }; Spacer(); if comment.userId != store.account?.id { Menu { Button(role:.destructive){reportComment=comment}label:{Label("Laporkan komentar",systemImage:"exclamationmark.bubble")} } label:{Image(systemName:"ellipsis").foregroundStyle(.secondary)} } }.padding(.vertical, 3) }.listStyle(.plain) }
                HStack { TextField("Tulis komentar…", text: $text, axis: .vertical).padding(12).background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 14)); Button { Task { await send() } } label: { Image(systemName: "paperplane.fill").font(.title2).foregroundStyle(foddOrange) }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }.padding().background(.bar)
            }
            .navigationTitle("Komentar").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Tutup") { dismiss() } } }
            .task { comments = await store.comments(for: moment) }
            .sheet(item:$reportComment) { comment in ReportContentView(targetType:"comment",targetId:comment.id,title:"Laporkan Komentar") }
        }
    }

    private func send() async { let body = text.trimmingCharacters(in: .whitespacesAndNewlines); guard !body.isEmpty else { return }; if let comment = await store.addComment(to: moment, body: body) { withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) { comments.append(comment) }; text = ""; FoddFeedbackManager.shared.messageSent() } }
}

// MARK: - Inbox / Chat

struct InboxRootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var mode = 0
    var body: some View {
        VStack(spacing:0) {
            Picker("Inbox mode",selection:$mode) { Text("Chats").tag(0);Text("Together").tag(1) }
                .pickerStyle(.segmented).padding(.horizontal,16).padding(.top,10)
            if mode == 0 { InboxContent(showClose:false) } else { TogetherPlansView() }
        }
        .task { await store.refreshDiningPlans() }
    }
}

struct InboxView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View { NavigationStack { InboxContent(showClose: true).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Tutup") { dismiss() } } } } }
}

struct InboxContent: View {
    @EnvironmentObject private var store: AppStore
    let showClose: Bool
    var body: some View {
        Group {
            if store.conversations.isEmpty {
                PremiumEmptyState(icon: "message", title: "Belum ada chat", subtitle: "Buka profil foodie lalu kirim pesan untuk memulai percakapan.")
            } else {
                List(store.conversations) { conversation in NavigationLink { RealChatView(member: conversation.member) } label: { ConversationRow(conversation: conversation) } }.listStyle(.plain)
            }
        }
        .navigationTitle("Inbox").navigationBarTitleDisplayMode(.large)
        .task { await store.loadConversations() }.refreshable { await store.loadConversations() }
    }
}

struct ConversationRow: View {
    let conversation: Conversation
    var body: some View {
        HStack(spacing: 12) {
            Avatar(name: conversation.member.name, size: 54, avatar: conversation.member.avatar)
            VStack(alignment: .leading, spacing: 5) {
                HStack { Text(conversation.member.name).font(.headline); if conversation.member.isCloseFoodie { Image(systemName: "star.fill").foregroundStyle(foddGold).font(.caption) } }
                Text(conversation.lastMessage).lineLimit(1).foregroundStyle(conversation.unreadCount > 0 ? .primary : .secondary).fontWeight(conversation.unreadCount > 0 ? .semibold : .regular)
            }
            Spacer()
            if conversation.unreadCount > 0 { Text("\(conversation.unreadCount)").font(.caption.bold()).foregroundStyle(.white).padding(7).background(foddRed).clipShape(Circle()) }
        }.padding(.vertical, 5)
    }
}

struct RealChatView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let member: Member
    @State private var messages: [ChatMessage] = []
    @State private var text = ""
    @State private var didLoadInitialMessages = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(messages) { item in
                            MessageBubble(text: item.body, isMine: item.senderId == store.account?.id)
                                .id(item.id)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: reduceMotion ? 1 : 0.78, anchor: item.senderId == store.account?.id ? .bottomTrailing : .bottomLeading).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }
                    }.padding()
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.82)) { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            HStack(spacing: 10) {
                Button {} label: { Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(foddOrange) }.disabled(true)
                TextField("Ketik pesan…", text: $text, axis: .vertical)
                    .lineLimit(1...4).padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .animation(.easeOut(duration: 0.16), value: text.isEmpty)
                Button { Task { await send() } } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.title2).foregroundStyle(foddOrange)
                        .rotationEffect(.degrees(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : -7))
                        .scaleEffect(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.96 : 1.06)
                }
                .buttonStyle(PressScaleButtonStyle(scale: 0.86))
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding().background(.bar)
        }
        .navigationTitle(member.name).navigationBarTitleDisplayMode(.inline)
        .task {
            let initial = await store.messages(with: member)
            messages = initial
            didLoadInitialMessages = true
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if Task.isCancelled { break }
                let fresh = await store.messages(with: member)
                applyIncoming(fresh)
            }
        }
    }

    private func applyIncoming(_ fresh: [ChatMessage]) {
        guard didLoadInitialMessages else { messages = fresh; didLoadInitialMessages = true; return }
        let existingIDs = Set(messages.map(\.id))
        let hasNewIncoming = fresh.contains { !existingIDs.contains($0.id) && $0.senderId != store.account?.id }
        if hasNewIncoming {
            withAnimation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.76)) { messages = fresh }
            FoddFeedbackManager.shared.messageReceived()
        } else {
            messages = fresh
        }
    }

    private func send() async {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        if let sent = await store.sendMessage(to: member, body: body) {
            text = ""
            if !messages.contains(where: { $0.id == sent.id }) {
                withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.72)) { messages.append(sent) }
            }
            FoddFeedbackManager.shared.messageSent()
        }
    }
}

struct MessageBubble: View {
    let text: String, isMine: Bool
    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 55) }
            Text(text).padding(.horizontal, 14).padding(.vertical, 11).foregroundStyle(isMine ? .white : .primary)
                .background(isMine ? AnyShapeStyle(brandGradient) : AnyShapeStyle(Color(.secondarySystemBackground)))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: Color.black.opacity(isMine ? 0.08 : 0.04), radius: 5, y: 2)
            if !isMine { Spacer(minLength: 55) }
        }
    }
}

// MARK: - Notifications

struct NotificationsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if store.notifications.isEmpty { PremiumEmptyState(icon: "bell", title: "Belum ada notifikasi", subtitle: "Aktivitas teman dan Food Moments akan tampil di sini.") }
                else {
                    List(store.notifications) { item in
                        if let planID=item.planId {
                            NavigationLink { DiningPlanDetailView(planID:planID) } label: { notificationRow(item) }
                        } else { notificationRow(item) }
                    }.listStyle(.plain)
                }
            }
            .navigationTitle("Notifikasi").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Tutup") { dismiss() } } }
            .task { await store.loadNotifications(markRead: true) }
        }
    }
    @ViewBuilder private func notificationRow(_ item:AppNotification) -> some View {
        HStack(spacing:12) {
            ZStack { Circle().fill(foddCream);Image(systemName:icon(item.type)).foregroundStyle(foddOrange) }.frame(width:42,height:42)
            VStack(alignment:.leading,spacing:4){Text(item.body);Text(relativeDate(item.createdAt)).font(.caption).foregroundStyle(.secondary)}
        }.padding(.vertical,4)
    }
    private func icon(_ type: String) -> String { switch type { case "follow": "person.badge.plus"; case "like": "heart.fill"; case "comment": "bubble.right.fill"; case "together":"person.3.fill"; default: "message.fill" } }
}

// MARK: - Profile / Food Diary / Close Foodies

struct MyProfileView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editing = false
    @State private var changePassword = false
    @State private var verifyEmail = false
    @State private var closeFoodies = false
    @State private var interactionSettings = false
    @State private var privacySafety = false
    @State private var notificationSettings = false
    @State private var collectionsSheet = false
    @State private var tasteProfile = false
    @State private var creatorStudio = false
    @State private var restaurantStudio = false
    @State private var appleExperience = false
    @State private var deleteAccount = false

    private var myMoments: [Moment] { guard let id = store.account?.id else { return [] }; return store.moments.filter { $0.userId == id } }
    private var placeCount: Int { Set(myMoments.map(\.locationName).filter { !$0.isEmpty }).count }

    var body: some View {
        ScrollView {
            if let user = store.account {
                VStack(spacing: 18) {
                    ProfileHero(name: user.name, username: user.username, bio: user.bio, avatar: user.avatar, isCreator: user.isCreator, creatorVerified: user.creatorVerified, creatorCategory: user.creatorCategory)
                    HStack { Metric(value: myMoments.count, label: "Moments"); Metric(value: placeCount, label: "Places"); Metric(value: store.closeFoodies.count, label: "Foodies") }
                        .padding(.vertical, 8).premiumCard()

                    HStack(spacing: 10) {
                        Button("Edit Profile") { editing = true }.buttonStyle(PrimaryCompactButton())
                        Button { closeFoodies = true } label: { Label("Close Foodies", systemImage: "star.fill") }.buttonStyle(.bordered)
                    }

                    if let taste=store.smartDashboard?.taste { TasteDNACompactCard(taste:taste){tasteProfile=true} }
                    if let memories=store.smartDashboard?.memories,!memories.isEmpty { FoodMemoriesSection(memories:memories) }

                    if !user.isEmailVerified {
                        Button { verifyEmail = true } label: { Label("Verifikasi email untuk keamanan akun", systemImage: "checkmark.seal").frame(maxWidth: .infinity, alignment: .leading) }
                            .buttonStyle(.bordered).tint(foddOrange)
                    }

                    FoodDiaryTimeline(posts: myMoments)

                    VStack(spacing: 10) {
                        SettingsButton(title: "Taste DNA & Smart Food", icon: "sparkles", action: { tasteProfile = true })
                        SettingsButton(title: "Creator Studio", icon: "checkmark.seal.fill", action: { creatorStudio = true })
                        SettingsButton(title: "Restaurant Studio", icon: "storefront.fill", action: { restaurantStudio = true })
                        SettingsButton(title: "Apple Experience", icon: "apple.logo", action: { appleExperience = true })
                        SettingsButton(title: "Collections", icon: "square.stack.3d.up.fill", action: { collectionsSheet = true })
                        SettingsButton(title: "Privacy & Safety", icon: "hand.raised.fill", action: { privacySafety = true })
                        SettingsButton(title: "Notification Controls", icon: "bell.and.waves.left.and.right.fill", action: { notificationSettings = true })
                        SettingsButton(title: "Close Foodies", icon: "star.fill", action: { closeFoodies = true })
                        SettingsButton(title: "Ubah Password", icon: "key.fill", action: { changePassword = true })
                        SettingsButton(title: "Sound & Haptics", icon: "waveform.and.speaker.fill", action: { interactionSettings = true })
                        SettingsButton(title: "Aktifkan Notifikasi iPhone", icon: "bell.badge.fill", action: { PushNotificationManager.shared.requestAuthorizationAndRegister() })
                    }

                    Button("Keluar", role: .destructive) { Task { await store.logoutFromServer() } }.buttonStyle(.bordered)
                    Button("Hapus Akun", role: .destructive) { deleteAccount = true }.font(.footnote)
                    Text("Fodd 7.0 • Apple Experience").font(.caption2).foregroundStyle(.tertiary).padding(.top, 4)
                }
                .padding(18).frame(maxWidth: 620)
            }
        }
        .background(Color(.systemGroupedBackground)).toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $editing) { EditProfileView() }
        .sheet(isPresented: $changePassword) { ChangePasswordView() }
        .sheet(isPresented: $verifyEmail) { VerifyEmailView() }
        .sheet(isPresented: $closeFoodies) { CloseFoodiesView() }
        .sheet(isPresented: $interactionSettings) { InteractionSettingsView() }
        .sheet(isPresented: $privacySafety) { PrivacySafetyView() }
        .sheet(isPresented: $notificationSettings) { NotificationControlsView() }
        .sheet(isPresented: $collectionsSheet) { CollectionsView() }
        .sheet(isPresented: $tasteProfile) { TasteProfileEditorView() }
        .sheet(isPresented: $creatorStudio) { CreatorStudioView() }
        .sheet(isPresented: $restaurantStudio) { RestaurantStudioHomeView() }
        .sheet(isPresented: $appleExperience) { AppleExperienceSettingsView() }
        .sheet(isPresented: $deleteAccount) { DeleteAccountView() }
    }
}

struct ProfileHero: View {
    let name, username, bio, avatar: String
    var isCreator: Bool = false
    var creatorVerified: Bool = false
    var creatorCategory: String = ""
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(brandGradient).frame(width: 112, height: 112)
                Avatar(name: name, size: 102, avatar: avatar)
            }
            HStack(spacing:6) {
                Text(name).font(.title.bold())
                if creatorVerified { Image(systemName:"checkmark.seal.fill").foregroundStyle(foddOrange).accessibilityLabel("Verified Creator") }
            }
            Text("@\(username)").foregroundStyle(.secondary)
            if isCreator {
                Label(creatorCategory.isEmpty ? "Fodd Creator" : creatorCategory,systemImage:"fork.knife.circle.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(foddOrange).padding(.horizontal,10).padding(.vertical,6).background(foddCream,in:Capsule())
            }
            if !bio.isEmpty { Text(bio).multilineTextAlignment(.center).foregroundStyle(.secondary) }
        }
        .padding(.top, 14)
    }
}

struct FoodDiaryTimeline: View {
    let posts: [Moment]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Food Diary").font(.title3.bold()); Spacer(); Text("\(posts.count) moments").font(.caption).foregroundStyle(.secondary) }
            if posts.isEmpty { Text("Jurnal kuliner Anda masih kosong.").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 30) }
            else {
                ForEach(posts.prefix(30)) { post in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 0) { Circle().fill(foddOrange).frame(width: 8, height: 8); Rectangle().fill(Color.secondary.opacity(0.18)).frame(width: 1, height: 64) }
                        VStack(alignment: .leading, spacing: 5) {
                            Text(relativeDate(post.createdAt)).font(.caption).foregroundStyle(.secondary)
                            HStack(spacing: 6) { Image(systemName: post.momentType.systemImage).foregroundStyle(foddOrange); Text(post.locationName.isEmpty ? post.momentType.title : post.locationName).font(.headline) }
                            Text(post.caption).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        if !post.image.isEmpty { FoodImage(source: post.image).frame(width: 70, height: 62).clipped().clipShape(RoundedRectangle(cornerRadius: 12)) }
                    }
                }
            }
        }
        .padding(16).premiumCard()
    }
}

struct FoodMemoriesSection: View {
    let memories:[FoodMemory]
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack { Label("Food Memories",systemImage:"clock.arrow.circlepath").font(.title3.bold());Spacer();Text("On this journey").font(.caption).foregroundStyle(foddOrange) }
            ScrollView(.horizontal,showsIndicators:false) {
                HStack(spacing:12) {
                    ForEach(memories) { memory in
                        VStack(alignment:.leading,spacing:8) {
                            ZStack(alignment:.topLeading) {
                                FoodImage(source:memory.image).frame(width:190,height:116).clipped()
                                Text(memory.yearsAgo == 1 ? "1 YEAR AGO" : "\(memory.yearsAgo) YEARS AGO")
                                    .font(.caption2.bold()).foregroundStyle(.white).padding(.horizontal,8).padding(.vertical,5).background(.black.opacity(0.58)).clipShape(Capsule()).padding(8)
                            }
                            Text(memory.locationName.isEmpty ? "Food Moment" : memory.locationName).font(.headline).lineLimit(1)
                            Text(memory.caption).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            Text(relativeDate(memory.createdAt)).font(.caption2).foregroundStyle(foddOrange)
                        }.frame(width:190,alignment:.leading).padding(9).background(Color(.tertiarySystemGroupedBackground)).clipShape(RoundedRectangle(cornerRadius:18,style:.continuous))
                    }
                }
            }
        }.padding(16).premiumCard()
    }
}

struct CloseFoodiesView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    private var filtered: [Member] { store.members.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.username.localizedCaseInsensitiveContains(query) } }

    var body: some View {
        NavigationStack {
            List {
                Section { Text("Close Foodies adalah lingkaran teman kuliner terdekat. Moment dengan audience Close Foodies hanya dapat dilihat oleh orang yang Anda pilih di sini.").font(.footnote).foregroundStyle(.secondary) }
                Section("Foodies") {
                    ForEach(filtered) { member in
                        HStack { Avatar(name: member.name, size: 44, avatar: member.avatar); VStack(alignment: .leading) { Text(member.name).font(.headline); Text("@\(member.username)").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button { FoddFeedbackManager.shared.selection(); Task { await store.toggleCloseFoodie(member) } } label: { Image(systemName: (store.members.first(where: { $0.id == member.id })?.isCloseFoodie ?? member.isCloseFoodie) ? "star.fill" : "star").foregroundStyle(foddGold).font(.title3) }.buttonStyle(.plain) }
                    }
                }
            }
            .searchable(text: $query, prompt: "Cari foodie").navigationTitle("Close Foodies").tint(foddOrange)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Selesai") { dismiss() } } }
        }
    }
}

struct InteractionSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var feedback = FoddFeedbackManager.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("Feel") {
                    Toggle(isOn: $feedback.soundEnabled) {
                        Label("Sound Effects", systemImage: "speaker.wave.2.fill")
                    }
                    Toggle(isOn: $feedback.hapticsEnabled) {
                        Label("Haptic Feedback", systemImage: "iphone.radiowaves.left.and.right")
                    }
                }
                Section("Preview") {
                    Button {
                        feedback.success()
                    } label: {
                        Label("Coba efek Fodd", systemImage: "sparkles")
                    }
                }
                Section("Motion") {
                    HStack {
                        Label("Reduce Motion iOS", systemImage: "figure.walk.motion")
                        Spacer()
                        Text(reduceMotion ? "Aktif" : "Normal").foregroundStyle(.secondary)
                    }
                    Text("Fodd otomatis mengurangi pop, scale, dan transisi saat Reduce Motion diaktifkan di Accessibility iPhone.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Text("Suara Fodd dibuat pendek dan lembut. Musik atau podcast tetap dapat berjalan karena efek memakai audio session tipe ambient.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .tint(foddOrange)
            .navigationTitle("Sound & Haptics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Selesai") { dismiss() } } }
        }
    }
}

// MARK: - Fodd 6.2 Complete & Safe + Fodd 6.3 Smart Food

struct ReportContentView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let targetType: String
    let targetId: String
    let title: String
    @State private var reason: ReportReason = .spam
    @State private var details = ""
    @State private var sending = false
    @State private var sent = false

    var body: some View {
        NavigationStack {
            Form {
                if sent {
                    Section {
                        VStack(spacing:12) {
                            Image(systemName:"checkmark.shield.fill").font(.system(size:44)).foregroundStyle(.green)
                            Text("Laporan diterima").font(.headline)
                            Text("Terima kasih membantu menjaga komunitas Fodd tetap aman. Laporan masuk ke antrean moderasi.").multilineTextAlignment(.center).foregroundStyle(.secondary)
                        }.frame(maxWidth:.infinity).padding(.vertical,18)
                    }
                } else {
                    Section("Alasan") {
                        Picker("Kategori",selection:$reason) { ForEach(ReportReason.allCases) { Text($0.title).tag($0) } }
                    }
                    Section("Detail opsional") {
                        TextField("Jelaskan masalah secara singkat",text:$details,axis:.vertical).lineLimit(3...6)
                        Text("Jangan sertakan password, kode OTP, atau informasi rahasia.").font(.caption).foregroundStyle(.secondary)
                    }
                    if let error=store.errorMessage { Section { ErrorText(error) } }
                    Section {
                        Button {
                            Task { sending=true; defer{sending=false}; if await store.report(targetType:targetType,targetId:targetId,reason:reason,details:details) { sent=true; FoddFeedbackManager.shared.success() } }
                        } label: { HStack { Spacer(); if sending { ProgressView() } else { Label("Kirim Laporan",systemImage:"paperplane.fill") }; Spacer() } }
                        .disabled(sending)
                    }
                }
            }
            .tint(foddOrange).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.confirmationAction) { Button(sent ? "Selesai":"Tutup") { dismiss() } } }
        }
    }
}

struct PrivacySafetyView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft = FoddUserSettings(isPrivate:false,pushFollows:true,pushLikes:true,pushComments:true,pushMessages:true,pushRecommendations:true,pushTogether:true)
    @State private var saving = false

    var body: some View {
        NavigationStack {
            List {
                Section("Akun") {
                    Toggle(isOn:$draft.isPrivate) {
                        Label("Private Account",systemImage:"lock.shield.fill")
                    }
                    Text(draft.isPrivate ? "Hanya follower yang Anda setujui yang dapat melihat momen untuk Everyone. Permintaan baru masuk ke Follow Requests." : "Akun publik dapat langsung diikuti. Privasi setiap Food Moment tetap mengikuti audience yang Anda pilih.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Follow Requests \(store.followRequests.isEmpty ? "" : "(\(store.followRequests.count))")") {
                    if store.followRequests.isEmpty { Text("Tidak ada permintaan baru.").foregroundStyle(.secondary) }
                    ForEach(store.followRequests) { request in
                        HStack(spacing:10) {
                            Avatar(name:request.member.name,size:42,avatar:request.member.avatar)
                            VStack(alignment:.leading) { Text(request.member.name).font(.headline); Text("@\(request.member.username)").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Button { Task { await store.respondFollowRequest(request,accept:false) } } label:{ Image(systemName:"xmark.circle.fill").font(.title3).foregroundStyle(.secondary) }.buttonStyle(.plain)
                            Button { Task { await store.respondFollowRequest(request,accept:true); FoddFeedbackManager.shared.success() } } label:{ Image(systemName:"checkmark.circle.fill").font(.title3).foregroundStyle(.green) }.buttonStyle(.plain)
                        }
                    }
                }

                Section("Blocked Accounts") {
                    if store.blockedUsers.isEmpty { Text("Belum ada akun yang diblokir.").foregroundStyle(.secondary) }
                    ForEach(store.blockedUsers) { member in
                        HStack(spacing:10) {
                            Avatar(name:member.name,size:42,avatar:member.avatar)
                            VStack(alignment:.leading) { Text(member.name).font(.headline); Text("@\(member.username)").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Button("Unblock") { Task { _=await store.setBlocked(member,enabled:false) } }.buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                }

                Section("Community Safety") {
                    Label("Report tersedia pada akun dan Food Moment",systemImage:"exclamationmark.bubble")
                    Label("Block memutus follow, request, chat, dan Close Foodies",systemImage:"hand.raised.fill")
                    Label("Spam dan konten berisiko difilter di server",systemImage:"checkmark.shield.fill")
                    Text("Fodd dirancang untuk komunitas kuliner. Hindari pelecehan, spam, ujaran kebencian, konten seksual eksplisit, dan ancaman kekerasan.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .tint(foddOrange).navigationTitle("Privacy & Safety").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction){Button("Tutup"){dismiss()}}
                ToolbarItem(placement:.confirmationAction){Button(saving ? "Menyimpan…":"Simpan"){Task{saving=true;defer{saving=false};_ = await store.updateSettings(draft)}}.disabled(saving)}
            }
            .task { await store.refreshSafetyData(); draft=store.userSettings }
        }
    }
}

struct NotificationControlsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft = FoddUserSettings(isPrivate:false,pushFollows:true,pushLikes:true,pushComments:true,pushMessages:true,pushRecommendations:true,pushTogether:true)
    @State private var saving=false

    var body: some View {
        NavigationStack {
            Form {
                Section("Push Notifications") {
                    Toggle("Follow & Follow Request",isOn:$draft.pushFollows)
                    Toggle("Likes & Reactions",isOn:$draft.pushLikes)
                    Toggle("Comments",isOn:$draft.pushComments)
                    Toggle("Messages",isOn:$draft.pushMessages)
                    Toggle("Smart Food Recommendations",isOn:$draft.pushRecommendations)
                    Toggle("Makan Bareng & Shared Collections",isOn:$draft.pushTogether)
                }
                Section {
                    Text("Pengaturan ini hanya mengontrol push notification. Aktivitas tetap tersimpan di tab Notifications agar tidak ada informasi penting yang hilang.").font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Button { PushNotificationManager.shared.requestAuthorizationAndRegister() } label:{ Label("Buka izin notifikasi iPhone",systemImage:"bell.badge.fill") }
                }
            }
            .tint(foddOrange).navigationTitle("Notification Controls").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction){Button("Batal"){dismiss()}}
                ToolbarItem(placement:.confirmationAction){Button(saving ? "Menyimpan…":"Simpan"){Task{saving=true;defer{saving=false};if await store.updateSettings(draft){dismiss()}}}.disabled(saving)}
            }
            .task { await store.refreshSafetyData(); draft=store.userSettings }
        }
    }
}

struct CollectionsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var create=false
    @State private var smartPick:Restaurant?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Simpan restoran ke daftar pribadi seperti Coffee Shop, Date Night, Wajib Dicoba, atau Kuliner Favorit.").font(.footnote).foregroundStyle(.secondary)
                }
                if let suggestions=store.smartDashboard?.forYou,!suggestions.isEmpty,!store.collections.isEmpty {
                    Section("Smart Suggestions") {
                        ForEach(suggestions.prefix(4)) { suggestion in
                            Button { smartPick=suggestion.restaurant } label: {
                                HStack(spacing:12) {
                                    FoodImage(source:suggestion.restaurant.image).frame(width:52,height:46).clipped().clipShape(RoundedRectangle(cornerRadius:10))
                                    VStack(alignment:.leading,spacing:2){Text(suggestion.restaurant.name).font(.headline).foregroundStyle(.primary);Text("\(suggestion.matchScore)% match • Tambahkan ke koleksi").font(.caption).foregroundStyle(.secondary)}
                                    Spacer();Image(systemName:"plus.circle.fill").foregroundStyle(foddOrange)
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                }
                Section("My Collections") {
                    if store.collections.isEmpty { Text("Belum ada koleksi. Buat koleksi pertama Anda.").foregroundStyle(.secondary) }
                    ForEach(store.collections) { collection in
                        NavigationLink { CollectionDetailView(collection:collection) } label: {
                            HStack(spacing:12) {
                                ZStack { RoundedRectangle(cornerRadius:12).fill(foddCream); Image(systemName:collection.isPrivate ? "lock.square.stack.fill":"square.stack.3d.up.fill").foregroundStyle(foddOrange) }.frame(width:46,height:46)
                                VStack(alignment:.leading,spacing:3){Text(collection.name).font(.headline);Text("\(collection.itemCount) tempat • \(collection.myRole == "owner" ? "Milik Anda" : "Shared by \(collection.ownerName)")\(collection.memberCount > 0 ? " • \(collection.memberCount) foodie" : "")").font(.caption).foregroundStyle(.secondary).lineLimit(1)}
                            }
                        }
                        .swipeActions { Button(role:.destructive){Task{await store.deleteCollection(collection)}} label:{Label("Hapus",systemImage:"trash")} }
                    }
                }
            }
            .tint(foddOrange).navigationTitle("Collections")
            .toolbar {
                ToolbarItem(placement:.cancellationAction){Button("Tutup"){dismiss()}}
                ToolbarItem(placement:.primaryAction){Button{create=true}label:{Image(systemName:"plus")}}
            }
            .sheet(isPresented:$create){CreateCollectionView()}
            .sheet(item:$smartPick){CollectionPickerView(restaurant:$0)}
            .task{await store.refreshSafetyData();await store.refreshSmartFood()}
        }
    }
}

struct CreateCollectionView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name=""
    @State private var description=""
    @State private var isPrivate=true
    @State private var saving=false
    var body: some View {
        NavigationStack {
            Form {
                Section("Collection") { TextField("Nama koleksi",text:$name); TextField("Deskripsi opsional",text:$description,axis:.vertical); Toggle("Private",isOn:$isPrivate) }
                Section { Text(isPrivate ? "Hanya Anda yang dapat melihat koleksi ini." : "Disiapkan untuk fitur shared/public collection berikutnya.").font(.footnote).foregroundStyle(.secondary) }
            }
            .tint(foddOrange).navigationTitle("New Collection")
            .toolbar { ToolbarItem(placement:.cancellationAction){Button("Batal"){dismiss()}}; ToolbarItem(placement:.confirmationAction){Button("Buat"){Task{saving=true;defer{saving=false};if await store.createCollection(name:name,description:description,isPrivate:isPrivate){FoddFeedbackManager.shared.success();dismiss()}}}.disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || saving)} }
        }
    }
}

struct CollectionDetailView: View {
    @EnvironmentObject private var store: AppStore
    let collection: FoodCollection
    @State private var items:[Restaurant]=[]
    @State private var sharing=false
    @State private var members:[SharedCollectionMember]=[]
    var body: some View {
        List {
            Section {
                if !collection.description.isEmpty { Text(collection.description).foregroundStyle(.secondary) }
                HStack { Label(collection.myRole == "owner" ? "Owner" : "Shared Collection",systemImage:"person.2.fill");Spacer();Text(collection.ownerName).foregroundStyle(.secondary) }
                if !members.isEmpty { ScrollView(.horizontal,showsIndicators:false){HStack{ForEach(members){member in VStack(spacing:4){Avatar(name:member.name,size:38,avatar:member.avatar);Text(member.name.components(separatedBy:" ").first ?? member.name).font(.caption2)}}}} }
            }
            Section("Places") {
                if items.isEmpty { Text("Koleksi ini masih kosong. Tambahkan restoran dari halaman detail restoran.").foregroundStyle(.secondary) }
                ForEach(items) { item in
                    NavigationLink(value:item){RestaurantCard(item:item)}
                        .swipeActions { if collection.myRole != "viewer" { Button(role:.destructive){Task{if await store.setRestaurant(item,in:collection,enabled:false){items.removeAll{$0.id==item.id}}}}label:{Label("Hapus",systemImage:"trash")} } }
                }
            }
        }
        .navigationTitle(collection.name).navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for:Restaurant.self){RestaurantDetail(item:$0)}
        .toolbar { if collection.myRole == "owner" { ToolbarItem(placement:.primaryAction){Button{sharing=true}label:{Image(systemName:"person.badge.plus")}} } }
        .sheet(isPresented:$sharing){ShareCollectionView(collection:collection)}
        .task { items=await store.collectionRestaurants(collection);members=await store.collectionMembers(collection) }
    }
}

struct CollectionPickerView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let restaurant: Restaurant
    @State private var memberships:Set<String>=[]
    @State private var loading=true
    var body: some View {
        NavigationStack {
            List {
                if store.collections.isEmpty { Text("Belum ada koleksi. Buat koleksi dari Profile → Collections terlebih dahulu.").foregroundStyle(.secondary) }
                ForEach(store.collections) { collection in
                    Button {
                        Task {
                            let enabled = !memberships.contains(collection.id)
                            if await store.setRestaurant(restaurant,in:collection,enabled:enabled) { if enabled { memberships.insert(collection.id) } else { memberships.remove(collection.id) }; FoddFeedbackManager.shared.selection() }
                        }
                    } label: {
                        HStack { Image(systemName:collection.isPrivate ? "lock.fill":"square.stack.fill").foregroundStyle(foddOrange); VStack(alignment:.leading){Text(collection.name).foregroundStyle(.primary);Text("\(collection.itemCount) tempat").font(.caption).foregroundStyle(.secondary)};Spacer();Image(systemName:memberships.contains(collection.id) ? "checkmark.circle.fill":"circle").foregroundStyle(memberships.contains(collection.id) ? foddOrange : .secondary) }
                    }.buttonStyle(.plain)
                }
            }
            .navigationTitle("Add to Collection").navigationBarTitleDisplayMode(.inline)
            .toolbar{ToolbarItem(placement:.confirmationAction){Button("Selesai"){dismiss()}}}
            .overlay { if loading { ProgressView().controlSize(.large) } }
            .task {
                if store.collections.isEmpty { await store.refreshSafetyData() }
                var found=Set<String>()
                for collection in store.collections { let items=await store.collectionRestaurants(collection); if items.contains(where:{$0.id==restaurant.id}) { found.insert(collection.id) } }
                memberships=found; loading=false
            }
        }
    }
}

struct NearbyCollectionPickerView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let item: NearbyRestaurant
    @State private var imported: Restaurant?
    @State private var importing=true

    var body: some View {
        NavigationStack {
            Group {
                if let imported { CollectionPickerView(restaurant:imported) }
                else if importing { VStack(spacing:14){ProgressView();Text("Menyiapkan tempat untuk koleksi…").foregroundStyle(.secondary)}.padding(30) }
                else { VStack(spacing:14){Image(systemName:"exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(foddOrange);Text(store.errorMessage ?? "Tempat tidak dapat ditambahkan.").multilineTextAlignment(.center);Button("Tutup"){dismiss()}}.padding(30) }
            }
            .task { imported=await store.importNearbyRestaurant(item); importing=false }
        }
    }
}

struct SettingsButton: View {
    let title, icon: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack { ZStack { Circle().fill(foddCream); Image(systemName: icon).foregroundStyle(foddOrange) }.frame(width: 38, height: 38); Text(title).fontWeight(.medium); Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
                .padding(12).premiumCard()
        }.buttonStyle(.plain)
    }
}

struct EditProfileView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var bio = ""
    @State private var avatar = ""
    @State private var photoItem: PhotosPickerItem?
    var body: some View {
        NavigationStack {
            Form {
                Section("Foto Profil") { HStack { Spacer(); Avatar(name: name.isEmpty ? "F" : name, size: 100, avatar: avatar); Spacer() }; PhotosPicker("Pilih dari Galeri", selection: $photoItem, matching: .images) }
                Section("Profil") { TextField("Nama", text: $name); TextField("Bio", text: $bio, axis: .vertical) }
                if let error = store.errorMessage { Section { ErrorText(error) } }
            }
            .tint(foddOrange).navigationTitle("Edit Profile")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Batal") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Simpan") { Task { if await store.updateProfile(name: name, bio: bio, avatar: avatar) { dismiss() } } } } }
            .onAppear { name = store.account?.name ?? ""; bio = store.account?.bio ?? ""; avatar = store.account?.avatar ?? "" }
            .onChange(of: photoItem) { _, item in Task { if let data = try? await item?.loadTransferable(type: Data.self), let value = compressedDataURL(data) { avatar = value } else if item != nil { store.errorMessage = "Foto profil tidak dapat diproses. Coba pilih foto lain." } } }
        }
    }
}

struct ChangePasswordView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var new = ""
    @State private var confirm = ""
    @State private var success = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Keamanan") { SecureField("Password sekarang", text: $current); SecureField("Password baru", text: $new); SecureField("Ulangi password baru", text: $confirm) }
                if success { Section { Label("Password berhasil diubah", systemImage: "checkmark.circle.fill").foregroundStyle(.green) } }
                if let error = store.errorMessage { Section { ErrorText(error) } }
                Section { Button("Ubah Password") { Task { if new == confirm && await store.changePassword(currentPassword: current, newPassword: new) { success = true; current = ""; new = ""; confirm = "" } } }.disabled(current.isEmpty || new.count < 8 || new != confirm) }
            }.tint(foddOrange).navigationTitle("Ubah Password").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Tutup") { dismiss() } } }
        }
    }
}

struct VerifyEmailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var message = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Email") { Text(store.account?.email ?? ""); Button("Kirim Kode Verifikasi") { Task { if let response = await store.requestVerification() { message = response.devCode.map { "Kode uji: \($0)" } ?? response.message } } } }
                Section("Kode") { TextField("6 digit", text: $code).keyboardType(.numberPad); Button("Verifikasi") { Task { if await store.verifyEmail(code: code) { dismiss() } } }.disabled(code.count < 6) }
                if !message.isEmpty { Section { Text(message).font(.footnote) } }
                if let error = store.errorMessage { Section { ErrorText(error) } }
            }.tint(foddOrange).navigationTitle("Verifikasi Email").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Tutup") { dismiss() } } }
        }
    }
}

struct DeleteAccountView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    var body: some View {
        NavigationStack {
            Form {
                Section { Text("Penghapusan akun bersifat permanen. Momen, chat, ulasan, dan data akun Anda akan dihapus.").foregroundStyle(.secondary) }
                Section("Konfirmasi") { SecureField("Password", text: $password) }
                if let error = store.errorMessage { Section { ErrorText(error) } }
                Section { Button("Hapus Akun Permanen", role: .destructive) { Task { if await store.deleteAccount(password: password) { dismiss() } } }.disabled(password.isEmpty) }
            }.navigationTitle("Hapus Akun").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Batal") { dismiss() } } }
        }
    }
}


// MARK: - Fodd 6.5 Creator & Restaurant Studio

struct RestaurantMenuPreview: View {
    let items:[MenuItem]
    private var grouped:[String:[MenuItem]] { Dictionary(grouping:items.filter(\.isAvailable),by:\.category) }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack { Label("Menu Resmi",systemImage:"menucard.fill").font(.headline);Spacer();Text("\(items.filter(\.isAvailable).count) item").font(.caption).foregroundStyle(.secondary) }
            ForEach(grouped.keys.sorted().prefix(3),id:\.self) { category in
                VStack(alignment:.leading,spacing:8) {
                    Text(category).font(.caption.bold()).foregroundStyle(foddOrange)
                    ForEach((grouped[category] ?? []).prefix(4)) { item in
                        HStack(alignment:.top,spacing:10) {
                            if !item.image.isEmpty { FoodImage(source:item.image).frame(width:54,height:54).clipShape(RoundedRectangle(cornerRadius:12)) }
                            VStack(alignment:.leading,spacing:3) { Text(item.name).fontWeight(.semibold);if !item.description.isEmpty { Text(item.description).font(.caption).foregroundStyle(.secondary).lineLimit(2) } }
                            Spacer();Text(item.price > 0 ? "Rp \(item.price.formatted(.number.grouping(.automatic)))" : "—").font(.caption.bold())
                        }
                    }
                }
            }
        }.padding(16).premiumCard()
    }
}

struct RestaurantUpdatesPreview: View {
    let posts:[RestaurantPost]
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Label("Update dari Restoran",systemImage:"megaphone.fill").font(.headline)
            ForEach(posts.prefix(4)) { post in
                VStack(alignment:.leading,spacing:8) {
                    HStack { Text(post.authorName).font(.caption.bold());if post.authorVerified { Image(systemName:"checkmark.seal.fill").font(.caption).foregroundStyle(foddOrange) };Spacer();Text(relativeTime(post.createdAt)).font(.caption2).foregroundStyle(.secondary) }
                    if !post.image.isEmpty { FoodImage(source:post.image).aspectRatio(16/9,contentMode:.fill).frame(maxWidth:.infinity).clipped().clipShape(RoundedRectangle(cornerRadius:16)) }
                    Text(post.caption).font(.subheadline)
                }.padding(.vertical,6)
                if post.id != posts.prefix(4).last?.id { Divider() }
            }
        }.padding(16).premiumCard()
    }
}

struct ClaimRestaurantView: View {
    @EnvironmentObject private var store:AppStore
    @Environment(\.dismiss) private var dismiss
    let restaurant:Restaurant
    @State private var businessName=""
    @State private var role="owner"
    @State private var note=""
    @State private var submitted=false
    var body: some View {
        NavigationStack {
            Form {
                Section { Label(restaurant.name,systemImage:restaurant.isVerified ? "checkmark.seal.fill":"storefront.fill").foregroundStyle(restaurant.isVerified ? foddOrange:.primary);Text("Klaim akan ditinjau sebelum akses pengelolaan diberikan.").font(.footnote).foregroundStyle(.secondary) }
                Section("Data Pengelola") { TextField("Nama usaha / badan usaha",text:$businessName);Picker("Peran",selection:$role){Text("Owner").tag("owner");Text("Manager").tag("manager");Text("Staff").tag("staff")};TextField("Catatan verifikasi (opsional)",text:$note,axis:.vertical).lineLimit(3...6) }
                if submitted { Section { Label("Klaim berhasil dikirim dan menunggu review.",systemImage:"checkmark.circle.fill").foregroundStyle(.green) } }
                if let error=store.errorMessage { Section { ErrorText(error) } }
                Section { Button("Kirim Klaim") { Task { if await store.claimRestaurant(restaurant,businessName:businessName.isEmpty ? restaurant.name:businessName,role:role,note:note){submitted=true} } }.disabled(submitted) }
            }.tint(foddOrange).navigationTitle("Klaim Restoran").toolbar { ToolbarItem(placement:.cancellationAction){Button("Tutup"){dismiss()}} }
            .onAppear { businessName=restaurant.name }
        }
    }
}

struct CreatorStudioView: View {
    @EnvironmentObject private var store:AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var enabled=false
    @State private var category="Food Creator"
    @State private var website=""
    private let categories=["Food Creator","Food Reviewer","Street Food","Coffee","Baking & Dessert","Home Cooking","Healthy Food","Travel & Food"]
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing:12) { Image(systemName:store.account?.creatorVerified == true ? "checkmark.seal.fill":"sparkles").font(.title).foregroundStyle(foddOrange);VStack(alignment:.leading){Text(store.account?.creatorVerified == true ? "Verified Creator":"Creator Profile").font(.headline);Text(store.account?.creatorVerified == true ? "Identitas creator telah diverifikasi Fodd.":"Bangun profil kuliner profesional Anda.").font(.caption).foregroundStyle(.secondary)} }
                    Toggle("Aktifkan Creator Profile",isOn:$enabled)
                }
                if enabled {
                    Section("Creator Identity") { Picker("Niche",selection:$category){ForEach(categories,id:\.self){Text($0)}};TextField("Website / portfolio",text:$website).textInputAutocapitalization(.never).keyboardType(.URL) }
                    if let profile=store.creatorProfile {
                        Section("Creator Insights") {
                            HStack { Metric(value:profile.momentCount,label:"Moments");Metric(value:profile.followersCount,label:"Followers");Metric(value:profile.totalLikes,label:"Likes") }
                            HStack { Metric(value:profile.totalComments,label:"Comments");Metric(value:profile.reviewCount,label:"Reviews") }
                            Text("Insights ini berasal dari aktivitas organik akun Fodd, bukan angka simulasi.").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                Section { Text("Badge Verified tidak dapat diaktifkan sendiri. Fodd Admin memverifikasi creator setelah proses review.").font(.footnote).foregroundStyle(.secondary) }
                if let error=store.errorMessage { Section { ErrorText(error) } }
            }.tint(foddOrange).navigationTitle("Creator Studio")
            .toolbar { ToolbarItem(placement:.cancellationAction){Button("Tutup"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("Simpan"){Task{if await store.saveCreatorProfile(isCreator:enabled,category:category,website:website){dismiss()}}}} }
            .task { await store.refreshCreatorStudio();enabled=store.account?.isCreator ?? false;category=(store.account?.creatorCategory.isEmpty == false ? store.account!.creatorCategory:"Food Creator");website=store.account?.creatorWebsite ?? "" }
        }
    }
}

struct RestaurantStudioHomeView: View {
    @EnvironmentObject private var store:AppStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section { Text("Kelola profil resmi, menu, dan update restoran yang klaimnya telah disetujui.").font(.footnote).foregroundStyle(.secondary) }
                Section("Restoran Saya") {
                    if store.myRestaurants.isEmpty { Text("Belum ada restoran yang Anda kelola.").foregroundStyle(.secondary) }
                    ForEach(store.myRestaurants) { restaurant in
                        NavigationLink { RestaurantStudioDetailView(restaurant:restaurant) } label: {
                            HStack(spacing:12) { FoodImage(source:restaurant.image).frame(width:52,height:52).clipShape(RoundedRectangle(cornerRadius:12));VStack(alignment:.leading){HStack{Text(restaurant.name).fontWeight(.semibold);if restaurant.isVerified{Image(systemName:"checkmark.seal.fill").foregroundStyle(foddOrange)}};Text(restaurant.managementRole.capitalized).font(.caption).foregroundStyle(.secondary)} }
                        }
                    }
                }
                Section("Status Klaim") {
                    if store.restaurantClaims.isEmpty { Text("Belum ada klaim restoran.").foregroundStyle(.secondary) }
                    ForEach(store.restaurantClaims) { claim in
                        HStack { VStack(alignment:.leading){Text(claim.restaurantName ?? claim.businessName).fontWeight(.semibold);Text(claim.role.capitalized).font(.caption).foregroundStyle(.secondary)};Spacer();Text(claim.status.uppercased()).font(.caption2.bold()).foregroundStyle(claim.status=="approved" ? .green : claim.status=="rejected" ? .red : foddOrange) }
                    }
                }
            }.navigationTitle("Restaurant Studio").toolbar { ToolbarItem(placement:.cancellationAction){Button("Tutup"){dismiss()}} }.task { await store.refreshCreatorStudio() }.refreshable { await store.refreshCreatorStudio() }
        }
    }
}

struct RestaurantStudioDetailView: View {
    @EnvironmentObject private var store:AppStore
    let restaurant:Restaurant
    @State private var menu:[MenuItem]=[]
    @State private var posts:[RestaurantPost]=[]
    @State private var profileEditor=false
    @State private var menuEditor=false
    @State private var postComposer=false
    @State private var editingMenu:MenuItem?
    var body: some View {
        List {
            Section {
                HStack(spacing:12){FoodImage(source:restaurant.image).frame(width:72,height:72).clipShape(RoundedRectangle(cornerRadius:16));VStack(alignment:.leading,spacing:4){HStack{Text(restaurant.name).font(.headline);Image(systemName:"checkmark.seal.fill").foregroundStyle(foddOrange)};Text(restaurant.managementRole.capitalized).font(.caption).foregroundStyle(.secondary);Text(restaurant.category).font(.caption).foregroundStyle(.secondary)}}
                if restaurant.managementRole != "staff" { Button { profileEditor=true } label:{Label("Edit Profil Restoran",systemImage:"pencil")}.buttonStyle(.bordered) }
            }
            Section("Menu") {
                Button { editingMenu=nil;menuEditor=true } label:{Label("Tambah Menu",systemImage:"plus.circle.fill")}
                if menu.isEmpty { Text("Belum ada menu resmi.").foregroundStyle(.secondary) }
                ForEach(menu) { item in
                    Button { editingMenu=item;menuEditor=true } label:{HStack{VStack(alignment:.leading){Text(item.name).foregroundStyle(.primary);Text("\(item.category) • \(item.price > 0 ? "Rp \(item.price.formatted(.number.grouping(.automatic)))":"Harga belum diisi")").font(.caption).foregroundStyle(.secondary)};Spacer();Image(systemName:item.isAvailable ? "checkmark.circle.fill":"pause.circle").foregroundStyle(item.isAvailable ? .green:.secondary)}}
                    .swipeActions { Button("Hapus",role:.destructive){Task{if await store.deleteMenuItem(restaurant:restaurant,item:item){await reload()}}} }
                }
            }
            Section("Restaurant Updates") {
                Button { postComposer=true } label:{Label("Buat Update",systemImage:"megaphone.fill")}
                if posts.isEmpty { Text("Belum ada update.").foregroundStyle(.secondary) }
                ForEach(posts) { post in
                    VStack(alignment:.leading,spacing:6){if !post.image.isEmpty{FoodImage(source:post.image).frame(height:130).clipped().clipShape(RoundedRectangle(cornerRadius:14))};Text(post.caption).foregroundStyle(.primary);Text(relativeTime(post.createdAt)).font(.caption2).foregroundStyle(.secondary)}
                    .swipeActions { Button("Hapus",role:.destructive){Task{if await store.deleteRestaurantPost(restaurant:restaurant,post:post){await reload()}}} }
                }
            }
        }.navigationTitle("Restaurant Studio").navigationBarTitleDisplayMode(.inline).task{await reload()}.refreshable{await reload()}
        .sheet(isPresented:$profileEditor){RestaurantProfileEditorView(restaurant:restaurant)}
        .sheet(isPresented:$menuEditor,onDismiss:{Task{await reload()}}){MenuItemEditorView(restaurant:restaurant,existing:editingMenu)}
        .sheet(isPresented:$postComposer,onDismiss:{Task{await reload()}}){RestaurantPostComposerView(restaurant:restaurant)}
    }
    private func reload() async { async let m=store.restaurantMenu(restaurant);async let p=store.restaurantPosts(restaurant);menu=await m;posts=await p }
}

struct RestaurantProfileEditorView: View {
    @EnvironmentObject private var store:AppStore
    @Environment(\.dismiss) private var dismiss
    let restaurant:Restaurant
    @State private var name="";@State private var category="";@State private var address="";@State private var phone="";@State private var hours="";@State private var website="";@State private var price="";@State private var image="";@State private var photoItem:PhotosPickerItem?
    var body: some View {
        NavigationStack { Form {
            Section("Foto") { if !image.isEmpty { FoodImage(source:image).frame(height:180).clipped().clipShape(RoundedRectangle(cornerRadius:16)) };PhotosPicker("Pilih Foto Utama",selection:$photoItem,matching:.images) }
            Section("Profil Resmi") { TextField("Nama",text:$name);TextField("Kategori",text:$category);TextField("Alamat",text:$address,axis:.vertical);TextField("Telepon",text:$phone);TextField("Jam buka",text:$hours,axis:.vertical);TextField("Kisaran harga",text:$price);TextField("Website",text:$website).keyboardType(.URL).textInputAutocapitalization(.never) }
            if let error=store.errorMessage{Section{ErrorText(error)}}
        }.tint(foddOrange).navigationTitle("Edit Restoran").toolbar{ToolbarItem(placement:.cancellationAction){Button("Batal"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("Simpan"){Task{if await store.updateManagedRestaurant(restaurant,name:name,category:category,address:address,phone:phone,hours:hours,website:website,price:price,image:image) != nil{dismiss()}}}}}.onAppear{name=restaurant.name;category=restaurant.category;address=restaurant.address;phone=restaurant.phone;hours=restaurant.hours;website=restaurant.website;price=restaurant.price;image=restaurant.image}.onChange(of:photoItem){_,item in Task{if let data=try? await item?.loadTransferable(type:Data.self),let value=compressedDataURL(data){image=value}}} }
    }
}

struct MenuItemEditorView: View {
    @EnvironmentObject private var store:AppStore
    @Environment(\.dismiss) private var dismiss
    let restaurant:Restaurant
    let existing:MenuItem?
    @State private var name="";@State private var detail="";@State private var category="Menu";@State private var price="";@State private var image="";@State private var available=true;@State private var photoItem:PhotosPickerItem?
    var body: some View {
        NavigationStack { Form {
            Section("Menu") { TextField("Nama menu",text:$name);TextField("Deskripsi",text:$detail,axis:.vertical);TextField("Kategori",text:$category);TextField("Harga (Rp)",text:$price).keyboardType(.numberPad);Toggle("Tersedia",isOn:$available) }
            Section("Foto") { if !image.isEmpty{FoodImage(source:image).frame(height:180).clipped().clipShape(RoundedRectangle(cornerRadius:16))};PhotosPicker("Pilih Foto",selection:$photoItem,matching:.images) }
            if let error=store.errorMessage{Section{ErrorText(error)}}
        }.tint(foddOrange).navigationTitle(existing==nil ? "Tambah Menu":"Edit Menu").toolbar{ToolbarItem(placement:.cancellationAction){Button("Batal"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("Simpan"){Task{let amount=Int(price.filter(\.isNumber)) ?? 0;if let existing {if await store.updateMenuItem(restaurant:restaurant,item:existing,name:name,description:detail,category:category,price:amount,image:image,isAvailable:available) != nil{dismiss()}}else if await store.createMenuItem(restaurant:restaurant,name:name,description:detail,category:category,price:amount,image:image,isAvailable:available) != nil{dismiss()}}}.disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}}.onAppear{if let x=existing{name=x.name;detail=x.description;category=x.category;price=String(x.price);image=x.image;available=x.isAvailable}}.onChange(of:photoItem){_,item in Task{if let data=try? await item?.loadTransferable(type:Data.self),let value=compressedDataURL(data){image=value}}} }
    }
}

struct RestaurantPostComposerView: View {
    @EnvironmentObject private var store:AppStore
    @Environment(\.dismiss) private var dismiss
    let restaurant:Restaurant
    @State private var caption="";@State private var image="";@State private var photoItem:PhotosPickerItem?
    var body: some View {
        NavigationStack { Form {
            Section("Update") { TextField("Promo, menu baru, jam khusus, atau kabar restoran…",text:$caption,axis:.vertical).lineLimit(4...8) }
            Section("Foto") { if !image.isEmpty{FoodImage(source:image).frame(height:200).clipped().clipShape(RoundedRectangle(cornerRadius:16))};PhotosPicker("Pilih Foto",selection:$photoItem,matching:.images) }
            if let error=store.errorMessage{Section{ErrorText(error)}}
        }.tint(foddOrange).navigationTitle("Restaurant Update").toolbar{ToolbarItem(placement:.cancellationAction){Button("Batal"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("Publish"){Task{if await store.createRestaurantPost(restaurant:restaurant,caption:caption,image:image) != nil{dismiss()}}}.disabled(caption.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}}.onChange(of:photoItem){_,item in Task{if let data=try? await item?.loadTransferable(type:Data.self),let value=compressedDataURL(data){image=value}}} }
    }
}

// MARK: - Shared UI / Media

struct FoddMark: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(brandGradient)
            Image(systemName: "mappin.and.ellipse").font(.system(size: size * 0.45, weight: .bold)).foregroundStyle(.white)
            Image(systemName: "fork.knife").font(.system(size: size * 0.20, weight: .bold)).foregroundStyle(.white).offset(y: size * 0.04)
        }
        .frame(width: size, height: size)
        .shadow(color: foddRed.opacity(0.15), radius: 12, y: 6)
    }
}

struct PremiumEmptyState: View {
    let icon, title, subtitle: String
    var body: some View {
        VStack(spacing: 12) {
            ZStack { Circle().fill(foddCream); Image(systemName: icon).font(.largeTitle).foregroundStyle(foddOrange) }.frame(width: 74, height: 74)
            Text(title).font(.headline)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(24).frame(maxWidth: .infinity)
    }
}

struct FoodImage: View {
    let source: String
    var body: some View {
        Group {
            if source.isEmpty {
                ZStack { Rectangle().fill(brandGradient.opacity(0.10)); Image(systemName: "fork.knife").font(.largeTitle).foregroundStyle(foddOrange) }
            } else if let image = decodedImage(source) {
                Image(uiImage: image).resizable().scaledToFill()
            } else if source.hasPrefix("http"), let url = URL(string: source) {
                AsyncImage(url: url) { phase in switch phase { case .success(let image): image.resizable().scaledToFill(); case .failure: ZStack { Color(.tertiarySystemFill); Image(systemName: "photo") }; default: ProgressView() } }
            } else {
                Image(source).resizable().scaledToFill()
            }
        }
    }
}

private func decodedImage(_ source: String) -> UIImage? {
    guard source.hasPrefix("data:image"), let comma = source.firstIndex(of: ",") else { return nil }
    return UIImage(data: Data(base64Encoded: String(source[source.index(after: comma)...])) ?? Data())
}

private func compressedDataURL(_ data: Data) -> String? {
    guard let image = UIImage(data: data) else { return nil }
    let maxSide: CGFloat = 1800
    let sourceSize = image.size
    let longest = max(sourceSize.width, sourceSize.height)
    let scale = longest > maxSide ? maxSide / longest : 1
    let target = CGSize(width: max(1, sourceSize.width * scale), height: max(1, sourceSize.height * scale))
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = true
    let normalized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
        UIColor.white.setFill()
        UIRectFill(CGRect(origin: .zero, size: target))
        image.draw(in: CGRect(origin: .zero, size: target))
    }
    for quality in [0.78, 0.68, 0.58, 0.48, 0.38] {
        if let jpeg = normalized.jpegData(compressionQuality: quality), jpeg.count <= 4_000_000 {
            return "data:image/jpeg;base64," + jpeg.base64EncodedString()
        }
    }
    return nil
}

struct CameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onImage: (Data) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> UIImagePickerController { let picker = UIImagePickerController(); picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary; picker.delegate = context.coordinator; picker.allowsEditing = true; return picker }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraPicker
        init(parent: CameraPicker) { self.parent = parent }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) { let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage; if let data = image?.jpegData(compressionQuality: 0.62) { parent.onImage(data) }; parent.dismiss() }
    }
}

struct Avatar: View {
    let name: String, size: CGFloat
    var avatar: String = ""
    var body: some View {
        ZStack {
            Circle().fill(brandGradient)
            if avatar.isEmpty { Text(String(name.prefix(1)).uppercased()).font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(.white) }
            else { FoodImage(source: avatar).scaledToFill() }
        }
        .frame(width: size, height: size).clipShape(Circle()).overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
    }
}

struct Metric: View {
    let value: Int, label: String
    var body: some View { VStack(spacing: 4) { Text("\(value)").font(.title3.bold()); Text(label).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity) }
}

struct ErrorText: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.footnote).foregroundStyle(foddRed).multilineTextAlignment(.center) }
}

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity).padding(15)
            .background(brandGradient.opacity(configuration.isPressed ? 0.72 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
    }
}

struct PrimaryCompactButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold)).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 11).padding(.horizontal, 14)
            .background(brandGradient.opacity(configuration.isPressed ? 0.72 : 1)).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private func privacyIcon(_ visibility: MomentVisibility) -> String { visibility.systemImage }

private func relativeDate(_ raw: String) -> String {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let standard = ISO8601DateFormatter()
    guard let date = fractional.date(from: raw) ?? standard.date(from: raw) else { return raw }
    let seconds = max(0, Date().timeIntervalSince(date))
    if seconds < 60 { return "baru saja" }
    if seconds < 3600 { return "\(Int(seconds / 60)) menit lalu" }
    if seconds < 86400 { return "\(Int(seconds / 3600)) jam lalu" }
    if seconds < 604800 { return "\(Int(seconds / 86400)) hari lalu" }
    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "id_ID"); formatter.dateFormat = "d MMM yyyy"
    return formatter.string(from: date)
}

#Preview { ContentView().environmentObject(AppStore()) }

// MARK: - Fodd 6.4 Together

struct TogetherPlansView: View {
    @EnvironmentObject private var store: AppStore
    @State private var create=false
    private var upcoming:[DiningPlan] { store.diningPlans.filter{$0.status == "planned"}.sorted{$0.scheduledAt < $1.scheduledAt} }
    private var history:[DiningPlan] { store.diningPlans.filter{$0.status != "planned"} }
    var body: some View {
        Group {
            if store.diningPlans.isEmpty {
                PremiumEmptyState(icon:"person.3.fill",title:"Belum ada Makan Bareng",subtitle:"Buat rencana, undang foodies, vote restoran, lalu ngobrol dalam satu tempat.")
            } else {
                List {
                    if !upcoming.isEmpty { Section("Upcoming") { ForEach(upcoming){plan in NavigationLink{DiningPlanDetailView(planID:plan.id)}label:{DiningPlanRow(plan:plan)}} } }
                    if !history.isEmpty { Section("History") { ForEach(history){plan in NavigationLink{DiningPlanDetailView(planID:plan.id)}label:{DiningPlanRow(plan:plan)}} } }
                }.listStyle(.plain)
            }
        }
        .navigationTitle("Together").navigationBarTitleDisplayMode(.large)
        .toolbar { ToolbarItem(placement:.primaryAction){Button{create=true}label:{Image(systemName:"plus.circle.fill").foregroundStyle(foddOrange)}} }
        .sheet(isPresented:$create){NavigationStack{CreateDiningPlanView()}}
        .refreshable { await store.refreshDiningPlans() }
        .task { await store.refreshDiningPlans() }
    }
}

struct DiningPlanRow: View {
    let plan:DiningPlan
    var body: some View {
        HStack(spacing:12) {
            ZStack { RoundedRectangle(cornerRadius:14).fill(brandGradient.opacity(0.12));Image(systemName:plan.status == "planned" ? "fork.knife.circle.fill":"checkmark.seal.fill").font(.title2).foregroundStyle(foddOrange) }.frame(width:52,height:52)
            VStack(alignment:.leading,spacing:4){Text(plan.title).font(.headline);Text(togetherDate(plan.scheduledAt)).font(.caption).foregroundStyle(.secondary);HStack(spacing:8){Label("\(plan.goingCount)",systemImage:"person.fill.checkmark");if plan.candidates.count > 0 {Label("\(plan.candidates.count)",systemImage:"checklist")};if plan.photoCount > 0 {Label("\(plan.photoCount)",systemImage:"photo.fill")}}.font(.caption2).foregroundStyle(foddOrange)}
            Spacer();if !plan.isHost {Text(plan.myRsvp.title).font(.caption.bold()).foregroundStyle(plan.myRsvp == .going ? .green : foddOrange)}
        }.padding(.vertical,4)
    }
}

struct CreateDiningPlanView: View {
    @EnvironmentObject private var store:AppStore
    @Environment(\.dismiss) private var dismiss
    let initialRestaurant:Restaurant?
    @State private var title=""
    @State private var note=""
    @State private var date=Date().addingTimeInterval(86_400)
    @State private var selectedMembers=Set<String>()
    @State private var selectedRestaurants=Set<String>()
    @State private var saving=false
    init(initialRestaurant:Restaurant?=nil){self.initialRestaurant=initialRestaurant;_selectedRestaurants=State(initialValue:Set(initialRestaurant.map{[$0.id]} ?? []))}
    var body: some View {
        Form {
            Section("Rencana") { TextField("Contoh: Dinner Jumat",text:$title);TextField("Catatan opsional",text:$note,axis:.vertical);DatePicker("Waktu",selection:$date,in:Date()...,displayedComponents:[.date,.hourAndMinute]) }
            Section("Undang Foodies") {
                if store.members.isEmpty { Text("Ikuti foodie lain agar bisa mengundang mereka.").foregroundStyle(.secondary) }
                ScrollView(.horizontal,showsIndicators:false){HStack(spacing:12){ForEach(store.members.filter{!$0.isBlocked}.prefix(30)){m in Button{if selectedMembers.contains(m.id){selectedMembers.remove(m.id)}else{selectedMembers.insert(m.id)};FoddFeedbackManager.shared.selection()}label:{VStack(spacing:5){Avatar(name:m.name,size:48,avatar:m.avatar);Text(m.name.components(separatedBy:" ").first ?? m.name).font(.caption);Image(systemName:selectedMembers.contains(m.id) ? "checkmark.circle.fill":"circle").foregroundStyle(selectedMembers.contains(m.id) ? foddOrange:.secondary)}}.buttonStyle(.plain)}}}
            }
            Section("Kandidat Restoran") {
                Text("Semua peserta bisa vote satu restoran. Anda dapat menambah kandidat lagi setelah rencana dibuat.").font(.footnote).foregroundStyle(.secondary)
                ForEach(candidatePool.prefix(10)){r in Button{if selectedRestaurants.contains(r.id){selectedRestaurants.remove(r.id)}else{selectedRestaurants.insert(r.id)}}label:{HStack{FoodImage(source:r.image).frame(width:48,height:42).clipped().clipShape(RoundedRectangle(cornerRadius:9));VStack(alignment:.leading){Text(r.name).foregroundStyle(.primary);Text(r.category).font(.caption).foregroundStyle(.secondary)};Spacer();Image(systemName:selectedRestaurants.contains(r.id) ? "checkmark.circle.fill":"circle").foregroundStyle(selectedRestaurants.contains(r.id) ? foddOrange:.secondary)}}.buttonStyle(.plain)}
            }
        }
        .navigationTitle("Makan Bareng").navigationBarTitleDisplayMode(.inline).tint(foddOrange)
        .toolbar { ToolbarItem(placement:.cancellationAction){Button("Batal"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button(saving ? "Membuat…":"Buat"){Task{saving=true;defer{saving=false};if await store.createDiningPlan(title:title.trimmingCharacters(in:.whitespacesAndNewlines),note:note.trimmingCharacters(in:.whitespacesAndNewlines),date:date,memberIds:Array(selectedMembers),restaurantIds:Array(selectedRestaurants)) != nil {dismiss()}}}.disabled(title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || saving)} }
        .task { if store.restaurants.isEmpty { try? await store.refreshPrivate() } }
    }
    private var candidatePool:[Restaurant] { var result:[Restaurant]=[];if let initialRestaurant{result.append(initialRestaurant)};for x in (store.smartDashboard?.forYou.map(\.restaurant) ?? []) + store.restaurants {if !result.contains(where:{$0.id==x.id}){result.append(x)}};return result }
}

struct DiningPlanDetailView: View {
    @EnvironmentObject private var store:AppStore
    let planID:String
    @State private var plan:DiningPlan?
    @State private var chat=false
    @State private var album=false
    @State private var addPlace=false
    @State private var invite=false
    @State private var groupMoment=false
    @State private var appleMessage=""
    var body: some View {
        ScrollView { if let plan { VStack(alignment:.leading,spacing:18) {
            VStack(alignment:.leading,spacing:8){HStack{Text(plan.title).font(.largeTitle.bold());Spacer();Text(plan.status.capitalized).font(.caption.bold()).padding(.horizontal,10).padding(.vertical,6).background(foddCream).clipShape(Capsule()).foregroundStyle(foddOrange)};Label(togetherDate(plan.scheduledAt),systemImage:"calendar.badge.clock").foregroundStyle(.secondary);if !plan.note.isEmpty{Text(plan.note).foregroundStyle(.secondary)}}
            if let selected=plan.selectedRestaurant { NavigationLink{RestaurantDetail(item:selected)}label:{VStack(alignment:.leading,spacing:8){Label("Tempat terpilih",systemImage:"checkmark.seal.fill").font(.caption.bold()).foregroundStyle(.green);HStack{FoodImage(source:selected.image).frame(width:72,height:64).clipped().clipShape(RoundedRectangle(cornerRadius:12));VStack(alignment:.leading){Text(selected.name).font(.headline);Text(selected.category).font(.caption).foregroundStyle(.secondary)};Spacer();Image(systemName:"chevron.right")}}.padding(13).premiumCard()}.buttonStyle(.plain) }
            if !plan.isHost { VStack(alignment:.leading,spacing:10){Text("RSVP").font(.headline);HStack{ForEach([DiningRSVP.going,.maybe,.declined]){r in Button{Task{if await store.diningRSVP(plan:plan,rsvp:r){self.plan=await store.diningPlan(plan.id)}}}label:{Label(r.title,systemImage:r.icon).font(.caption.bold()).padding(.horizontal,10).padding(.vertical,9).background(plan.myRsvp == r ? foddCream:Color(.secondarySystemBackground)).clipShape(Capsule()).foregroundStyle(plan.myRsvp == r ? foddOrange:.primary)}}}} }
            VStack(alignment:.leading,spacing:10){HStack{Text("Vote Restoran").font(.headline);Spacer();Button{addPlace=true}label:{Label("Tambah",systemImage:"plus")}.font(.caption)};if plan.candidates.isEmpty{Text("Belum ada kandidat restoran.").foregroundStyle(.secondary)};ForEach(plan.candidates){candidate in HStack(spacing:10){FoodImage(source:candidate.restaurant.image).frame(width:58,height:52).clipped().clipShape(RoundedRectangle(cornerRadius:10));VStack(alignment:.leading){Text(candidate.restaurant.name).font(.subheadline.bold());Text("\(candidate.voteCount) vote • oleh \(candidate.proposedBy)").font(.caption).foregroundStyle(.secondary)};Spacer();Button{Task{if await store.vote(plan:plan,restaurant:candidate.restaurant){self.plan=await store.diningPlan(plan.id)}}}label:{Image(systemName:candidate.myVote ? "checkmark.circle.fill":"circle").font(.title2).foregroundStyle(candidate.myVote ? foddOrange:.secondary)}.buttonStyle(.plain);if plan.isHost {Button{Task{if await store.chooseRestaurant(plan:plan,restaurant:candidate.restaurant){self.plan=await store.diningPlan(plan.id)}}}label:{Image(systemName:"flag.checkered").foregroundStyle(.green)}.buttonStyle(.plain)}}.padding(10).premiumCard()}}
            VStack(alignment:.leading,spacing:10){HStack{Text("Foodies").font(.headline);Spacer();if plan.isHost{Button{invite=true}label:{Label("Undang",systemImage:"person.badge.plus")}.font(.caption)}};ScrollView(.horizontal,showsIndicators:false){HStack(spacing:12){VStack{Avatar(name:plan.host.name,size:50,avatar:plan.host.avatar);Text(plan.host.name.components(separatedBy:" ").first ?? plan.host.name).font(.caption);Text("Host").font(.caption2).foregroundStyle(foddOrange)};ForEach(plan.members){m in VStack{Avatar(name:m.name,size:50,avatar:m.avatar);Text(m.name.components(separatedBy:" ").first ?? m.name).font(.caption);Text(m.rsvp.title).font(.caption2).foregroundStyle(.secondary)}}}}}
            HStack{Button{chat=true}label:{Label("Group Chat (\(plan.messageCount))",systemImage:"message.fill").frame(maxWidth:.infinity)}.buttonStyle(.borderedProminent).tint(foddOrange);Button{album=true}label:{Label("Album (\(plan.photoCount))",systemImage:"photo.on.rectangle.angled").frame(maxWidth:.infinity)}.buttonStyle(.bordered)}
            Button{groupMoment=true}label:{Label("Bagikan Group Food Moment",systemImage:"sparkles.rectangle.stack.fill").frame(maxWidth:.infinity)}.buttonStyle(.bordered)
            VStack(spacing:10) {
                HStack {
                    Button { Task { let ok=await store.startDiningLiveActivity(plan); appleMessage = ok ? "Live Activity aktif di Lock Screen / Dynamic Island." : "Live Activity tidak tersedia atau dinonaktifkan." } } label: { Label("Live Activity",systemImage:"dynamic.island").frame(maxWidth:.infinity) }.buttonStyle(.bordered)
                    Button { Task { let ok=await FoddSharePlay.start(plan:plan); appleMessage = ok ? "SharePlay dimulai." : "SharePlay membutuhkan FaceTime/Messages yang aktif atau izin pengguna." } } label: { Label("SharePlay",systemImage:"shareplay").frame(maxWidth:.infinity) }.buttonStyle(.bordered)
                }
                if !appleMessage.isEmpty { Text(appleMessage).font(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading) }
            }
            if plan.isHost && plan.status == "planned" {Button{Task{if await store.completeDiningPlan(plan){self.plan=await store.diningPlan(plan.id)}}}label:{Label("Tandai Selesai",systemImage:"checkmark.seal.fill").frame(maxWidth:.infinity)}.buttonStyle(.bordered)}
        }.padding(16) } else { ProgressView().frame(maxWidth:.infinity).padding(60) } }
        .background(Color(.systemGroupedBackground)).navigationTitle("Makan Bareng").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented:$chat){if let plan{NavigationStack{DiningGroupChatView(plan:plan)}}}
        .sheet(isPresented:$album){if let plan{NavigationStack{DiningAlbumView(plan:plan)}}}
        .sheet(isPresented:$addPlace){if let plan{DiningCandidatePicker(plan:plan,onDone:{Task{self.plan=await store.diningPlan(plan.id)}})}}
        .sheet(isPresented:$invite){if let plan{InviteDiningMembersView(plan:plan,onDone:{Task{self.plan=await store.diningPlan(plan.id)}})}}
        .sheet(isPresented:$groupMoment){if let plan{NavigationStack{TogetherMomentComposerView(plan:plan)}}}
        .task {
            plan=await store.diningPlan(planID)
            if let plan { await FoddAppleExperienceManager.shared.refreshLiveActivity(for: plan) }
        }
    }
}

struct InviteDiningMembersView: View {
    @EnvironmentObject private var store:AppStore
    @Environment(\.dismiss) private var dismiss
    let plan:DiningPlan
    let onDone:()->Void
    @State private var selected=Set<String>()
    var body: some View {
        NavigationStack {
            List(available) { member in
                Button { if selected.contains(member.id){selected.remove(member.id)}else{selected.insert(member.id)} } label: {
                    HStack { Avatar(name:member.name,size:42,avatar:member.avatar);VStack(alignment:.leading){Text(member.name).foregroundStyle(.primary);Text("@\(member.username)").font(.caption).foregroundStyle(.secondary)};Spacer();Image(systemName:selected.contains(member.id) ? "checkmark.circle.fill":"circle").foregroundStyle(selected.contains(member.id) ? foddOrange:.secondary) }
                }.buttonStyle(.plain)
            }
            .navigationTitle("Undang Foodies").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.cancellationAction){Button("Batal"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("Undang"){Task{if await store.inviteToDiningPlan(plan,memberIds:Array(selected)){onDone();dismiss()}}}.disabled(selected.isEmpty)} }
        }
    }
    private var available:[Member] { let existing=Set(plan.members.map(\.id)+[plan.hostId]);return store.members.filter{!existing.contains($0.id) && !$0.isBlocked} }
}

struct TogetherMomentComposerView: View {
    @EnvironmentObject private var store:AppStore
    @Environment(\.dismiss) private var dismiss
    let plan:DiningPlan
    @State private var caption=""
    @State private var image=""
    @State private var picker:PhotosPickerItem?
    @State private var sending=false
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                VStack(alignment:.leading,spacing:4){Label("Group Food Moment",systemImage:"person.3.sequence.fill").font(.headline).foregroundStyle(foddOrange);Text("Otomatis dibagikan ke peserta Makan Bareng dan masuk ke Food Diary Anda.").font(.caption).foregroundStyle(.secondary)}.padding(14).premiumCard()
                if !image.isEmpty { FoodImage(source:image).frame(height:250).clipped().clipShape(RoundedRectangle(cornerRadius:20)) }
                PhotosPicker(selection:$picker,matching:.images){Label(image.isEmpty ? "Pilih Foto":"Ganti Foto",systemImage:"photo.fill")}.buttonStyle(.bordered)
                TextEditor(text:$caption).frame(minHeight:130).padding(10).background(Color(.secondarySystemGroupedBackground)).clipShape(RoundedRectangle(cornerRadius:16)).overlay(alignment:.topLeading){if caption.isEmpty{Text("Ceritakan makan bareng ini…").foregroundStyle(.secondary).padding(18).allowsHitTesting(false)}}
                if let selected=plan.selectedRestaurant { Label(selected.name,systemImage:"mappin.circle.fill").foregroundStyle(foddOrange) }
                Button(sending ? "Membagikan…":"Bagikan Group Moment"){Task{sending=true;defer{sending=false};if await store.createTogetherMoment(planId:plan.id,caption:caption.trimmingCharacters(in:.whitespacesAndNewlines),image:image){NotificationCenter.default.post(name:.foddMomentDidPublish,object:nil);dismiss()}}}.buttonStyle(PrimaryButton()).disabled(caption.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || sending)
            }.padding(16)
        }.background(Color(.systemGroupedBackground)).navigationTitle(plan.title).navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.cancellationAction){Button("Tutup"){dismiss()}}}.onChange(of:picker){_,item in Task{if let data=try? await item?.loadTransferable(type:Data.self),let value=compressedDataURL(data){image=value}}}
    }
}

struct DiningCandidatePicker: View {
    @EnvironmentObject private var store:AppStore
    @Environment(\.dismiss) private var dismiss
    let plan:DiningPlan
    let onDone:()->Void
    @State private var search=""
    var body: some View {NavigationStack{List(filtered){r in Button{Task{if await store.addCandidate(plan:plan,restaurant:r){onDone();dismiss()}}}label:{RestaurantCard(item:r)}}.searchable(text:$search,prompt:"Cari restoran").navigationTitle("Tambah Kandidat").toolbar{ToolbarItem(placement:.cancellationAction){Button("Tutup"){dismiss()}}}}}
    private var filtered:[Restaurant]{let existing=Set(plan.candidates.map{$0.restaurant.id});let list=store.restaurants.filter{!existing.contains($0.id)};return search.isEmpty ? list:list.filter{$0.name.localizedCaseInsensitiveContains(search)||$0.category.localizedCaseInsensitiveContains(search)}}
}

struct DiningGroupChatView: View {
    @EnvironmentObject private var store:AppStore
    @Environment(\.dismiss) private var dismiss
    let plan:DiningPlan
    @State private var messages:[DiningPlanMessage]=[]
    @State private var text=""
    var body: some View {VStack(spacing:0){ScrollView{LazyVStack(spacing:10){ForEach(messages){m in VStack(alignment:m.userId == store.account?.id ? .trailing:.leading,spacing:3){if m.userId != store.account?.id{Text(m.name).font(.caption2).foregroundStyle(.secondary)};MessageBubble(text:m.body,isMine:m.userId == store.account?.id)}}}.padding()};HStack{TextField("Pesan ke semua…",text:$text,axis:.vertical).lineLimit(1...4).padding(12).background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius:16));Button{Task{let body=text.trimmingCharacters(in:.whitespacesAndNewlines);guard !body.isEmpty else{return};if let sent=await store.sendDiningMessage(planId:plan.id,body:body){messages.append(sent);text="";FoddFeedbackManager.shared.messageSent()}}}label:{Image(systemName:"paperplane.fill").font(.title2).foregroundStyle(foddOrange)}.disabled(text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}.padding().background(.bar)}.navigationTitle(plan.title).navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.cancellationAction){Button("Tutup"){dismiss()}}}.task{messages=await store.diningMessages(planId:plan.id);while !Task.isCancelled{try? await Task.sleep(nanoseconds:3_000_000_000);let fresh=await store.diningMessages(planId:plan.id);if fresh.count>messages.count{FoddFeedbackManager.shared.messageReceived()};messages=fresh}}}
}

struct DiningAlbumView: View {
    @EnvironmentObject private var store:AppStore
    @Environment(\.dismiss) private var dismiss
    let plan:DiningPlan
    @State private var photos:[DiningPlanPhoto]=[]
    @State private var picker:PhotosPickerItem?
    @State private var caption=""
    @State private var pendingImage=""
    var body: some View {ScrollView{VStack(alignment:.leading,spacing:14){if !pendingImage.isEmpty{FoodImage(source:pendingImage).frame(height:220).clipped().clipShape(RoundedRectangle(cornerRadius:18));TextField("Caption opsional",text:$caption);Button("Tambahkan ke album"){Task{if let photo=await store.addDiningPhoto(planId:plan.id,image:pendingImage,caption:caption){photos.insert(photo,at:0);pendingImage="";caption="";FoddFeedbackManager.shared.success()}}}.buttonStyle(PrimaryButton())};if photos.isEmpty{PremiumEmptyState(icon:"photo.on.rectangle.angled",title:"Album masih kosong",subtitle:"Semua peserta bisa menambahkan foto makan bareng ke album ini.")}else{LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:10){ForEach(photos){photo in VStack(alignment:.leading,spacing:5){FoodImage(source:photo.image).aspectRatio(1,contentMode:.fill).clipped().clipShape(RoundedRectangle(cornerRadius:14));Text(photo.name).font(.caption.bold());if !photo.caption.isEmpty{Text(photo.caption).font(.caption2).foregroundStyle(.secondary).lineLimit(2)}}}}}}.padding(16)}.navigationTitle("Group Food Album").navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.cancellationAction){Button("Tutup"){dismiss()}};ToolbarItem(placement:.primaryAction){PhotosPicker(selection:$picker,matching:.images){Image(systemName:"plus.circle.fill")}}}.onChange(of:picker){_,item in Task{if let data=try? await item?.loadTransferable(type:Data.self),let value=compressedDataURL(data){pendingImage=value}}}.task{photos=await store.diningPhotos(planId:plan.id)}}
}

struct ShareCollectionView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let collection: FoodCollection
    @State private var members: [SharedCollectionMember] = []

    var body: some View {
        NavigationStack {
            List {
                Section("Bagikan dengan foodie") {
                    ForEach(store.members.filter { member in
                        !members.contains(where: { $0.id == member.id }) && !member.isBlocked
                    }) { member in
                        Button {
                            Task {
                                if await store.shareCollection(collection, with: member) {
                                    members = await store.collectionMembers(collection)
                                    FoddFeedbackManager.shared.success()
                                }
                            }
                        } label: {
                            HStack {
                                Avatar(name: member.name, size: 42, avatar: member.avatar)
                                VStack(alignment: .leading) {
                                    Text(member.name).foregroundStyle(.primary)
                                    Text("@\(member.username) • Editor").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "person.badge.plus").foregroundStyle(foddOrange)
                            }
                        }.buttonStyle(.plain)
                    }
                }
                if !members.isEmpty {
                    Section("Sudah bergabung") {
                        ForEach(members) { member in
                            HStack {
                                Avatar(name: member.name, size: 38, avatar: member.avatar)
                                VStack(alignment: .leading) {
                                    Text(member.name)
                                    Text(member.role.capitalized).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Shared Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Tutup") { dismiss() } } }
            .task { members = await store.collectionMembers(collection) }
        }
    }
}

private func togetherDate(_ raw:String)->String { let iso=ISO8601DateFormatter();iso.formatOptions=[.withInternetDateTime,.withFractionalSeconds];let date=iso.date(from:raw) ?? ISO8601DateFormatter().date(from:raw);guard let date else{return raw};let f=DateFormatter();f.locale=Locale(identifier:"id_ID");f.dateFormat="EEE, d MMM • HH:mm";return f.string(from:date) }

