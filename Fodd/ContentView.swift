import SwiftUI

private let brand = Color(red:0.96,green:0.11,blue:0.16)

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        Group {
            if store.isLoading && store.account == nil { ProgressView("Menghubungkan Fodd…") }
            else if store.isAuthenticated { MainTabs() }
            else { AuthView() }
        }.task { await store.restore() }
    }
}

struct AuthView: View {
    @EnvironmentObject private var store: AppStore
    @State private var registerMode=false
    @State private var name=""
    @State private var username=""
    @State private var email=""
    @State private var password=""
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing:22) {
                    Image(systemName:"mappin.and.ellipse").font(.system(size:64)).foregroundStyle(brand)
                    Text("Fodd").font(.largeTitle.bold())
                    Text(registerMode ? "Buat profil member Anda" : "Masuk untuk melihat momen asli dari member Fodd").multilineTextAlignment(.center).foregroundStyle(.secondary)
                    VStack(spacing:14) {
                        if registerMode {
                            Field(title:"Nama lengkap",text:$name)
                            Field(title:"Username",text:$username,capitalization:false)
                        }
                        Field(title:"Email",text:$email,capitalization:false)
                        SecureField("Password minimal 8 karakter",text:$password).padding(14).background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius:14))
                    }
                    if let error=store.errorMessage { Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center) }
                    Button(registerMode ? "Daftar" : "Masuk") { Task { await submit() } }.buttonStyle(PrimaryButton()).disabled(store.isLoading)
                    Button(registerMode ? "Sudah punya akun? Masuk" : "Belum punya akun? Daftar") { store.errorMessage=nil; registerMode.toggle() }.foregroundStyle(brand)
                }.padding(24).frame(maxWidth:520)
            }
        }
    }
    private func login() async { _=await store.login(email:email,password:password) }
    private func register() async { _=await store.register(name:name,username:username,email:email,password:password) }
    private func submit() async { if registerMode { await register() } else { await login() } }
}

struct Field: View {
    let title:String; @Binding var text:String; var capitalization=true
    var body: some View { TextField(title,text:$text).textInputAutocapitalization(capitalization ? .words:.never).autocorrectionDisabled(!capitalization).padding(14).background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius:14)) }
}

struct MainTabs: View {
    @State private var tab=0
    @State private var composer=false
    private var selection:Binding<Int>{
        Binding(get:{tab},set:{value in
            if value==2 { composer=true } else { tab=value }
        })
    }
    var body: some View {
        TabView(selection:selection) {
            NavigationStack{FeedView()}.tabItem{Label("Home",systemImage:"house.fill")}.tag(0)
            NavigationStack{RestaurantsView()}.tabItem{Label("Explore",systemImage:"safari.fill")}.tag(1)
            Color.clear.tabItem{Label("Tambah",systemImage:"plus.circle.fill")}.tag(2)
            NavigationStack{MembersView()}.tabItem{Label("Member",systemImage:"person.2.fill")}.tag(3)
            NavigationStack{MyProfileView()}.tabItem{Label("Profil",systemImage:"person.crop.circle.fill")}.tag(4)
        }.tint(brand).sheet(isPresented:$composer){MomentComposer()}
    }
}

struct FeedView: View {
    @EnvironmentObject private var store:AppStore
    var body: some View {
        ScrollView {
            LazyVStack(spacing:16) {
                if store.moments.isEmpty {
                    ContentUnavailableView("Belum ada momen",systemImage:"photo.on.rectangle.angled",description:Text("Jadilah member pertama yang membagikan momen." )).padding(.top,80)
                } else { ForEach(store.moments){MomentCard(moment:$0)} }
            }.padding()
        }.background(Color(.systemGroupedBackground)).navigationTitle("Momen").refreshable{try? await store.refreshPrivate()}
    }
}

struct MomentCard: View {
    let moment:Moment
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack { Avatar(name:moment.name,size:44); VStack(alignment:.leading){Text(moment.name).font(.headline);Text("@\(moment.username)").font(.caption).foregroundStyle(.secondary)};Spacer() }
            Image(moment.image).resizable().scaledToFill().aspectRatio(4/3,contentMode:.fill).frame(maxWidth:.infinity).clipped().clipShape(RoundedRectangle(cornerRadius:16))
            Text(moment.caption).foregroundStyle(.primary).fixedSize(horizontal:false,vertical:true)
            Label("\(moment.likes) suka",systemImage:"heart").font(.subheadline).foregroundStyle(.secondary)
        }.padding(16).background(Color(.secondarySystemGroupedBackground)).clipShape(RoundedRectangle(cornerRadius:20))
    }
}

struct MembersView: View {
    @EnvironmentObject private var store:AppStore
    @State private var search=""
    var body: some View {
        List(store.members){member in NavigationLink(value:member){MemberRow(member:member)}}
            .navigationTitle("Member").searchable(text:$search,prompt:"Cari nama atau username")
            .onSubmit(of:.search){Task{await store.searchMembers(search)}}
            .onChange(of:search){_,value in if value.isEmpty{Task{await store.searchMembers("")}}}
            .navigationDestination(for:Member.self){MemberProfileView(member:$0)}
    }
}

struct MemberRow: View {
    @EnvironmentObject private var store:AppStore
    let member:Member
    var body: some View {
        HStack(spacing:12){Avatar(name:member.name,size:48);VStack(alignment:.leading){Text(member.name).font(.headline);Text("@\(member.username)").foregroundStyle(.secondary)};Spacer();Button(member.isFollowing ? "Mengikuti":"Ikuti"){Task{await store.toggleFollow(member)}}.buttonStyle(.borderedProminent).tint(member.isFollowing ? .gray:brand)}.padding(.vertical,4)
    }
}

struct MemberProfileView: View {
    @EnvironmentObject private var store:AppStore
    @State var member:Member
    var body: some View {
        ScrollView {
            VStack(spacing:18) {
                Avatar(name:member.name,size:96)
                Text(member.name).font(.title.bold())
                Text("@\(member.username)").foregroundStyle(.secondary)
                if !member.bio.isEmpty {
                    Text(member.bio).multilineTextAlignment(.center)
                }
                HStack {
                    Metric(value:member.followersCount,label:"Pengikut")
                    Metric(value:member.followingCount,label:"Mengikuti")
                }
                Button(member.isFollowing ? "Berhenti Mengikuti":"Ikuti Member") {
                    Task {
                        await store.toggleFollow(member)
                        member.isFollowing.toggle()
                    }
                }
                .buttonStyle(PrimaryButton())
                NavigationLink {
                    RealChatView(member:member)
                } label: {
                    Label("Kirim Pesan",systemImage:"message.fill").frame(maxWidth:.infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(24)
            .frame(maxWidth:560)
        }
        .navigationTitle("Profil Member")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct RealChatView: View {
    @EnvironmentObject private var store:AppStore
    let member:Member
    @State private var messages:[ChatMessage]=[]
    @State private var text=""
    var body: some View {
        VStack(spacing:0) {
            ScrollView {
                LazyVStack(spacing:10) {
                    ForEach(messages) { item in
                        MessageBubble(
                            text:item.body,
                            isMine:item.senderId == store.account?.id
                        )
                    }
                }
                .padding()
            }
            HStack {
                TextField("Tulis pesan…",text:$text)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius:14))
                Button {
                    Task { await send() }
                } label: {
                    Image(systemName:"paperplane.fill").font(.title2)
                }
                .disabled(text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle(member.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { messages=await store.messages(with:member) }
    }
    private func send() async {let body=text.trimmingCharacters(in:.whitespacesAndNewlines);guard !body.isEmpty else{return};if let sent=await store.sendMessage(to:member,body:body){messages.append(sent);text=""}}
}

struct MessageBubble: View {
    let text:String,isMine:Bool
    var body: some View {HStack{if isMine{Spacer(minLength:50)};Text(text).padding(12).foregroundStyle(isMine ? .white:.primary).background(isMine ? brand:Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius:16));if !isMine{Spacer(minLength:50)}}}
}

struct MyProfileView: View {
    @EnvironmentObject private var store:AppStore
    @State private var editing=false
    var body: some View {
        ScrollView {if let user=store.account{VStack(spacing:18){Avatar(name:user.name,size:96);Text(user.name).font(.title.bold());Text("@\(user.username)").foregroundStyle(.secondary);Text(user.bio.isEmpty ? "Belum ada bio":user.bio).multilineTextAlignment(.center);Button("Edit Profil"){editing=true}.buttonStyle(PrimaryButton());Button("Keluar",role:.destructive){store.logout()}.buttonStyle(.bordered)}.padding(24).frame(maxWidth:560)}}.navigationTitle("Profil Saya").sheet(isPresented:$editing){EditProfileView()}
    }
}

struct EditProfileView: View {
    @EnvironmentObject private var store:AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name=""
    @State private var bio=""
    var body: some View {NavigationStack{Form{Section("Profil"){TextField("Nama",text:$name);TextField("Bio",text:$bio,axis:.vertical)}}.navigationTitle("Edit Profil").toolbar{ToolbarItem(placement:.cancellationAction){Button("Batal"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("Simpan"){Task{if await store.updateProfile(name:name,bio:bio){dismiss()}}}}}.onAppear{name=store.account?.name ?? "";bio=store.account?.bio ?? ""}}}
}

struct RestaurantsView: View {
    @EnvironmentObject private var store:AppStore
    @State private var search=""
    private var items:[Restaurant]{store.restaurants.filter{search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.category.localizedCaseInsensitiveContains(search)}}
    var body: some View {ScrollView{LazyVStack(spacing:12){ForEach(items){item in NavigationLink(value:item){RestaurantCard(item:item)}.buttonStyle(.plain)}}.padding()}.navigationTitle("Explore").searchable(text:$search).navigationDestination(for:Restaurant.self){RestaurantDetail(item:$0)}}
}

struct RestaurantCard: View {
    let item:Restaurant
    var body: some View {HStack(spacing:14){Image(item.image).resizable().scaledToFill().frame(width:100,height:86).clipped().clipShape(RoundedRectangle(cornerRadius:14));VStack(alignment:.leading,spacing:5){Text(item.name).font(.headline);Text(item.category).foregroundStyle(.secondary);Text("⭐️ \(item.rating,specifier:"%.1f") • \(item.distance) • \(item.price)").font(.caption)};Spacer();Image(systemName:"chevron.right").foregroundStyle(.tertiary)}.padding(12).background(Color(.secondarySystemGroupedBackground)).clipShape(RoundedRectangle(cornerRadius:18))}
}

struct RestaurantDetail: View {
    let item:Restaurant
    var body: some View {ScrollView{VStack(alignment:.leading,spacing:16){Image(item.image).resizable().scaledToFill().aspectRatio(4/3,contentMode:.fill).frame(maxWidth:.infinity).clipped();VStack(alignment:.leading,spacing:10){Text(item.name).font(.largeTitle.bold());Text(item.category).foregroundStyle(.secondary);Text("⭐️ \(item.rating,specifier:"%.1f") • \(item.distance) • \(item.price)")}.padding()}}.navigationTitle(item.name).navigationBarTitleDisplayMode(.inline)}
}

struct MomentComposer: View {
    @EnvironmentObject private var store:AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var caption=""
    @State private var image="FoodHero"
    @State private var sending=false
    private let choices=["FoodHero","Cafe","Noodles","Burgers"]
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    Text("Pilih foto").font(.headline)
                    photoPicker
                    Text("Ceritakan momen Anda").font(.headline)
                    captionEditor
                    Button(sending ? "Mengirim…":"Bagikan Momen") {
                        Task { await shareMoment() }
                    }
                    .buttonStyle(PrimaryButton())
                    .disabled(caption.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || sending)
                }
                .padding(20)
                .frame(maxWidth:600)
            }
            .navigationTitle("Momen Baru")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) {
                    Button("Batal") { dismiss() }
                }
            }
        }
    }

    private var photoPicker: some View {
        ScrollView(.horizontal,showsIndicators:false) {
            HStack {
                ForEach(choices,id:\.self) { choice in
                    Button { image=choice } label: {
                        Image(choice)
                            .resizable()
                            .scaledToFill()
                            .frame(width:110,height:90)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius:14))
                            .overlay {
                                RoundedRectangle(cornerRadius:14)
                                    .stroke(image == choice ? brand:.clear,lineWidth:4)
                            }
                    }
                }
            }
        }
    }

    private var captionEditor: some View {
        TextEditor(text:$caption)
            .scrollContentBackground(.hidden)
            .foregroundStyle(.primary)
            .frame(minHeight:150)
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius:16))
            .overlay(alignment:.topLeading) {
                if caption.isEmpty {
                    Text("Tulis pengalaman makan Anda…")
                        .foregroundStyle(.secondary)
                        .padding(20)
                        .allowsHitTesting(false)
                }
            }
    }

    private func shareMoment() async {
        sending=true
        if await store.createMoment(caption:caption,image:image) {
            dismiss()
        } else {
            sending=false
        }
    }
}

struct Avatar: View {let name:String,size:CGFloat;var body:some View{ZStack{Circle().fill(brand.gradient);Text(String(name.prefix(1)).uppercased()).font(.system(size:size*0.42,weight:.bold)).foregroundStyle(.white)}.frame(width:size,height:size)}}
struct Metric: View {let value:Int,label:String;var body:some View{VStack{Text("\(value)").font(.title3.bold());Text(label).font(.caption).foregroundStyle(.secondary)}.frame(maxWidth:.infinity)}}
struct PrimaryButton: ButtonStyle {func makeBody(configuration:Configuration)->some View{configuration.label.font(.headline).foregroundStyle(.white).frame(maxWidth:.infinity).padding(14).background(brand.opacity(configuration.isPressed ? 0.7:1)).clipShape(RoundedRectangle(cornerRadius:14))}}

#Preview{ContentView().environmentObject(AppStore())}
