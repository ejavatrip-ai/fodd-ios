# Fodd 7.0 — Apple Experience — Build 13

Fodd adalah **Premium Social Food Diary** untuk iPhone. Versi 7.0 mempertahankan seluruh fitur 6.5 Creator & Restaurant, 6.4 Together, 6.3 Smart Food, 6.2 Complete & Safe, 6.1 Alive UI, serta pengalaman social diary ala Path, kemudian menambahkan integrasi Apple-native untuk membuat Fodd terasa sebagai aplikasi iOS profesional.

## Baru di Fodd 7.0

### Widget + Shared App Group
- Target `FoddWidget` terpisah di project Xcode.
- Small/Medium Home Screen Widget menampilkan Taste DNA, rekomendasi For You, Match Score, dan rencana Makan Bareng berikutnya.
- App Group: `group.com.fodd.app` untuk snapshot widget dan pending deep-link route.

### Live Activity & Dynamic Island
- Dining Plan dapat diaktifkan sebagai Live Activity.
- Menampilkan status plan, restoran terpilih/kandidat terbaik, jumlah peserta Going, jumlah chat, dan waktu acara.
- Dynamic Island memiliki compact/minimal/expanded presentation.
- Push token Live Activity didaftarkan ke backend hanya untuk participant yang terautentikasi.
- Backend APNs dapat memperbarui Live Activity ketika RSVP, kandidat, vote, restoran final, pesan grup, atau status plan berubah.
- Plan completed/cancelled mengakhiri Live Activity.

### Siri, App Shortcuts & Spotlight
- App Intents untuk membuka Explore, Food Diary, dan Together.
- App Shortcuts dapat muncul di Siri/Shortcuts tanpa konfigurasi manual dari user.
- Core Spotlight mengindeks restoran, Food Moment, foodie terkait, dan Dining Plan.
- Semua hasil kembali ke Fodd melalui deep links `fodd://`.

### SharePlay
- Dining Plan dapat dimulai sebagai Group Activity.
- SharePlay menggunakan metadata plan/restoran agar koordinasi Makan Bareng dapat dibawa ke pengalaman FaceTime/SharePlay.

### Apple Maps Look Around
- Detail restoran meminta `MKLookAroundScene` berdasarkan koordinat.
- Preview hanya muncul bila Apple menyediakan Look Around di lokasi tersebut.
- User dapat membuka full Look Around viewer dari halaman restoran.

### Apple Experience Settings
Profile → Settings → **Apple Experience** menampilkan status dan penjelasan Widget, Siri/Shortcuts, Spotlight, Live Activity, SharePlay, serta Look Around.

### App Store Readiness
- `PrivacyInfo.xcprivacy` untuk main app dan Widget Extension.
- Required-reason UserDefaults menggunakan `CA92.1` (main-app local preferences) dan `1C8F.1` (App Group sharing).
- Tidak ada production secret yang dibundel dalam source.

## Versi
Marketing Version: **7.0**  
Build: **13**  
Backend: **7.0.0**

## Sebelum Build di Xcode
1. Buka `Fodd.xcodeproj`.
2. Pilih Apple Developer Team untuk target `Fodd` dan `FoddWidget`.
3. Daftarkan App Group `group.com.fodd.app` pada App ID main + widget.
4. Aktifkan Push Notifications untuk main app.
5. Aktifkan Group Activities/SharePlay untuk main app bila provisioning profile memerlukannya.
6. Pastikan bundle identifier target sesuai App ID Anda; ubah `com.fodd.app` / `com.fodd.app.widget` bila perlu, lalu sesuaikan `APNS_BUNDLE_ID` di Railway.
7. Build di iPhone asli untuk APNs, Live Activity/Dynamic Island, widget, SharePlay, Siri, Spotlight, Maps/Look Around, haptic, audio, Keychain, dan Photos.

## Deploy Backend 7.0
Deploy folder `/backend` **sebelum mengaktifkan remote Live Activity**. Migration tetap additive/non-destructive dan menambahkan `live_activity_tokens`.

Environment utama:
- `DATABASE_URL`
- `PORT`
- `NODE_ENV=production`
- `ALLOWED_ORIGIN`
- `ADMIN_TOKEN`
- `APNS_KEY_ID`
- `APNS_TEAM_ID`
- `APNS_PRIVATE_KEY`
- `APNS_BUNDLE_ID` (default source: `com.fodd.app`)
- `APNS_ENVIRONMENT=production` untuk TestFlight/App Store; gunakan sandbox saat development sesuai setup Anda.

## Catatan Privacy
Privacy Manifest di project menangani *required-reason API declaration*. Anda tetap harus mengisi **App Privacy** di App Store Connect sesuai data nyata yang Fodd kumpulkan dan kirim ke backend (mis. account/contact info, user content, location bila digunakan, identifiers, dan usage data sesuai implementasi/deployment Anda).

Dokumen tambahan: `RELEASE_NOTES_7.0.md`, `FODD_7_0_CHECKLIST.md`, `APPLE_EXPERIENCE_ARCHITECTURE.md`, `APP_STORE_READINESS_7.0.md`, `VALIDATION_REPORT_7.0.md`.
