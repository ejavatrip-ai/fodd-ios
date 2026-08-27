import SwiftUI

private let brand = Color(red: 0.96, green: 0.11, blue: 0.16)
private let orange = Color(red: 1.00, green: 0.38, blue: 0.10)

struct Restaurant: Identifiable, Codable {
    let id: String
    let name: String
    let category: String
    let image: String
    let rating: Double
    let distance: String
    let price: String
}

let fallbackRestaurants = [
    Restaurant(id: "kopi-nok", name: "Kopi Nok", category: "Kafe • Sarapan", image: "Cafe", rating: 4.8, distance: "600 m", price: "Rp20–45K"),
    Restaurant(id: "dapur-nusantara", name: "Dapur Nusantara", category: "Indonesia • Halal", image: "FoodHero", rating: 4.9, distance: "1,2 km", price: "Rp25–60K"),
    Restaurant(id: "mie-ceria", name: "Mie Ceria", category: "Mi • Asia", image: "Noodles", rating: 4.7, distance: "1,8 km", price: "Rp18–35K"),
    Restaurant(id: "burger-social", name: "Burger Social", category: "Burger • Barat", image: "Burgers", rating: 4.6, distance: "2,1 km", price: "Rp35–80K")
]

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selection = 0
    @State private var showCreate = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selection) {
                NavigationStack { HomeView() }.tag(0)
                NavigationStack { ExploreView() }.tag(1)
                Color.clear.tag(2)
                NavigationStack { FriendsView() }.tag(3)
                NavigationStack { ProfileView() }.tag(4)
            }
            HStack {
                TabButton("house.fill", "Home", 0, selection: $selection)
                TabButton("safari.fill", "Explore", 1, selection: $selection)
                Button { showCreate = true } label: {
                    Image(systemName: "plus").font(.title2.bold()).foregroundStyle(.white)
                        .frame(width: 58, height: 58).background(brand).clipShape(Circle())
                        .shadow(color: brand.opacity(0.35), radius: 10, y: 5)
                }.offset(y: -20)
                TabButton("person.2.fill", "Friends", 3, selection: $selection)
                TabButton("person.crop.circle.fill", "Profile", 4, selection: $selection)
            }
            .padding(.horizontal, 8).padding(.top, 10).padding(.bottom, 4)
            .background(.ultraThinMaterial).overlay(alignment: .top) { Divider() }
        }
        .tint(brand)
        .sheet(isPresented: $showCreate) { CreateMomentView() }
        .task { await store.refresh() }
    }
}

struct TabButton: View {
    let icon: String, title: String, index: Int
    @Binding var selection: Int
    init(_ icon: String, _ title: String, _ index: Int, selection: Binding<Int>) {
        self.icon = icon; self.title = title; self.index = index; _selection = selection
    }
    var body: some View {
        Button { selection = index } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold))
                Text(title).font(.caption2)
            }.foregroundStyle(selection == index ? brand : .secondary).frame(maxWidth: .infinity)
        }
    }
}

struct BrandHeader: View {
    let title: String
    var body: some View {
        HStack {
            Image(systemName: "mappin.and.ellipse").font(.title2.bold())
            Text(title).font(.title2.bold())
            Spacer()
            Button(action: {}) { Image(systemName: "bell.fill") }
            Button(action: {}) { Image(systemName: "paperplane.fill") }
        }.foregroundStyle(.white).padding(.horizontal).padding(.top, 8).padding(.bottom, 14)
            .background(LinearGradient(colors: [brand, .red], startPoint: .leading, endPoint: .trailing))
    }
}

struct HomeView: View {
    @State private var liked = false
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                BrandHeader(title: "Fodd")
                ZStack(alignment: .bottom) {
                    Image("FoodHero").resizable().scaledToFill().frame(height: 210).clipped()
                    LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Temukan rasa baru").font(.title2.bold())
                            Text("Rekomendasi pilihan dekat kamu")
                        }.foregroundStyle(.white)
                        Spacer()
                    }.padding()
                }
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                    Text("Cari restoran, menu, atau teman").foregroundStyle(.secondary)
                    Spacer(); Image(systemName: "slider.horizontal.3")
                }.padding(12).background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 14)).padding()
                StoryRow()
                PostCard(liked: $liked)
                RestaurantSection(title: "Lagi populer")
            }.padding(.bottom, 88)
        }.ignoresSafeArea(edges: .top).background(Color(.systemGroupedBackground))
    }
}

struct StoryRow: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 15) {
                ForEach(Array(fallbackRestaurants.enumerated()), id: \.offset) { i, item in
                    VStack(spacing: 5) {
                        Image(item.image).resizable().scaledToFill().frame(width: 58, height: 58).clipShape(Circle())
                            .overlay(Circle().stroke(LinearGradient(colors: [brand, orange], startPoint: .top, endPoint: .bottom), lineWidth: 3))
                        Text(["Kamu", "Nadia", "Rizky", "Maya"][i]).font(.caption)
                    }
                }
            }.padding(.horizontal)
        }.padding(.bottom, 12)
    }
}

struct PostCard: View {
    @Binding var liked: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image("Cafe").resizable().scaledToFill().frame(width: 42, height: 42).clipShape(Circle())
                VStack(alignment: .leading) { Text("Nadia Putri").font(.subheadline.bold()); Text("Kopi Nok • 12 menit").font(.caption).foregroundStyle(.secondary) }
                Spacer(); Image(systemName: "ellipsis")
            }.padding(.horizontal)
            Image("Burgers").resizable().scaledToFill().frame(height: 285).clipped()
            HStack(spacing: 20) {
                Button { withAnimation(.bouncy) { liked.toggle() } } label: { Image(systemName: liked ? "heart.fill" : "heart").foregroundStyle(liked ? brand : .primary) }
                Image(systemName: "bubble.right"); Image(systemName: "paperplane"); Spacer(); Image(systemName: "bookmark")
            }.font(.title3).padding(.horizontal)
            Text("1.248 suka").font(.subheadline.bold()).padding(.horizontal)
            Text("Makan sore paling seru bareng teman. Burgernya juicy banget! 🍔").font(.subheadline).padding(.horizontal)
            Text("Lihat 36 komentar").font(.subheadline).foregroundStyle(.secondary).padding(.horizontal)
        }.padding(.vertical).background(Color(.systemBackground))
    }
}

struct ExploreView: View {
    @EnvironmentObject private var store: AppStore
    @State private var search = ""
    @State private var category = "Semua"
    let categories = ["Semua", "Kafe", "Halal", "Burger", "Mi"]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                BrandHeader(title: "Explore")
                VStack(alignment: .leading, spacing: 10) {
                    Text("Mau nongkrong di mana hari ini?").font(.title.bold())
                    HStack { Image(systemName: "magnifyingglass"); TextField("Cari tempat atau menu", text: $search); Image(systemName: "location.fill").foregroundStyle(brand) }
                        .padding(13).background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 14))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack { ForEach(categories, id: \.self) { item in
                            Button(item) { category = item }.buttonStyle(ChipStyle(active: category == item))
                        }}
                    }
                }.padding(.horizontal)
                ZStack(alignment: .bottomLeading) {
                    Image("Cafe").resizable().scaledToFill().frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 22))
                    LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom).clipShape(RoundedRectangle(cornerRadius: 22))
                    VStack(alignment: .leading) { Text("Pilihan minggu ini").font(.caption.bold()); Text("Kopi Nok").font(.title2.bold()); Text("Kafe nyaman • 600 m") }.foregroundStyle(.white).padding()
                }.padding(.horizontal)
                HStack(spacing: 7) {
                    Circle().fill(store.isOnline ? .green : .orange).frame(width: 8, height: 8)
                    Text(store.isOnline ? "Data online dari Railway" : "Mode offline • data lokal").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }.padding(.horizontal)
                RestaurantSection(title: "Tempat dekat kamu", items: store.restaurants)
            }.padding(.bottom, 90)
        }.ignoresSafeArea(edges: .top).background(Color(.systemGroupedBackground))
    }
}

struct ChipStyle: ButtonStyle {
    let active: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.bold()).padding(.horizontal, 16).padding(.vertical, 9)
            .foregroundStyle(active ? .white : .primary).background(active ? brand : Color(.secondarySystemBackground)).clipShape(Capsule())
    }
}

struct RestaurantSection: View {
    let title: String
    var items: [Restaurant] = fallbackRestaurants
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(title).font(.title3.bold()); Spacer(); Text("Lihat semua").font(.subheadline).foregroundStyle(brand) }.padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) { ForEach(items) { item in RestaurantCard(item: item) } }.padding(.horizontal)
            }
        }
    }
}

struct RestaurantCard: View {
    let item: Restaurant
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(item.image).resizable().scaledToFill().frame(width: 205, height: 130).clipShape(RoundedRectangle(cornerRadius: 16))
            Text(item.name).font(.headline)
            Text(item.category).font(.caption).foregroundStyle(.secondary)
            HStack { Label(String(format: "%.1f", item.rating), systemImage: "star.fill").foregroundStyle(orange); Text("• \(item.distance)"); Spacer(); Text(item.price) }.font(.caption)
        }.padding(10).background(Color(.systemBackground)).clipShape(RoundedRectangle(cornerRadius: 18)).shadow(color: .black.opacity(0.05), radius: 8, y: 3)
    }
}

struct FriendsView: View {
    var body: some View {
        List {
            Section { ForEach(Array(fallbackRestaurants.enumerated()), id: \.offset) { i, item in
                HStack(spacing: 12) {
                    Image(item.image).resizable().scaledToFill().frame(width: 52, height: 52).clipShape(Circle())
                    VStack(alignment: .leading) { Text(["Nadia Putri", "Rizky Aditya", "Maya Lestari", "Dimas Pratama"][i]).font(.headline); Text(["Yuk cobain tempat baru!", "Foto makanannya keren 🔥", "Sampai ketemu nanti", "Kirim lokasi ya"][i]).font(.subheadline).foregroundStyle(.secondary) }
                    Spacer(); Text("1\(i):2\(i)").font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 5)
            }} header: { Text("Pesan terbaru") }
        }.safeAreaInset(edge: .top, spacing: 0) { BrandHeader(title: "Friends") }.padding(.bottom, 70)
    }
}

struct ProfileView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                BrandHeader(title: "Profile")
                Image("FoodHero").resizable().scaledToFill().frame(width: 100, height: 100).clipShape(Circle()).overlay(Circle().stroke(brand, lineWidth: 4))
                Text("Food Explorer").font(.title2.bold()); Text("Menjelajah rasa, satu tempat setiap hari 🍜").foregroundStyle(.secondary)
                HStack { Stat("24", "Momen"); Stat("1.2K", "Pengikut"); Stat("386", "Mengikuti") }
                Button("Edit Profil") {}.font(.headline).foregroundStyle(brand).frame(maxWidth: .infinity).padding().overlay(RoundedRectangle(cornerRadius: 14).stroke(brand)).padding(.horizontal)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                    ForEach((0..<12), id: \.self) { i in Image(fallbackRestaurants[i % 4].image).resizable().scaledToFill().frame(height: 125).clipped() }
                }
            }.padding(.bottom, 85)
        }.ignoresSafeArea(edges: .top)
    }
}

struct Stat: View {
    let value: String, label: String
    init(_ value: String, _ label: String) { self.value = value; self.label = label }
    var body: some View { VStack { Text(value).font(.headline); Text(label).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity) }
}

struct CreateMomentView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var caption = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image("Noodles").resizable().scaledToFill().frame(height: 280).clipShape(RoundedRectangle(cornerRadius: 24)).padding()
                TextField("Tulis pengalaman makanmu…", text: $caption, axis: .vertical).padding().background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 14)).padding(.horizontal)
                HStack { Label("Lokasi", systemImage: "mappin"); Spacer(); Label("Tandai teman", systemImage: "person.badge.plus") }.padding(.horizontal).foregroundStyle(brand)
                Spacer()
                if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
                Button(isSending ? "Mengirim…" : "Bagikan Momen") {
                    isSending = true
                    Task {
                        do { try await store.createMoment(caption: caption); dismiss() }
                        catch { errorMessage = error.localizedDescription; isSending = false }
                    }
                }.disabled(caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                    .font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity).padding().background(brand).clipShape(RoundedRectangle(cornerRadius: 16)).padding()
            }.navigationTitle("Momen Baru").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarLeading) { Button("Batal") { dismiss() } } }
        }
    }
}

#Preview { ContentView().environmentObject(AppStore()) }
