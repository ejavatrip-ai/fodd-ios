# Fodd 7.0 — Personal Team Edition (Build 14)

Edition ini dibuat untuk instalasi langsung ke iPhone menggunakan Apple ID / Personal Team gratis.

## Sudah dinonaktifkan untuk signing gratis
- App Groups
- Push Notifications (remote APNs)
- Group Activities / SharePlay
- Widget embedding + shared App Group data
- Dynamic Island / remote Live Activity

Source fitur Apple Experience tetap ada dan dapat diaktifkan lagi ketika memakai Apple Developer Program.

## Bundle Identifier siap pakai
- Main app: `com.meruartama.fodd`
- Widget source: `com.meruartama.fodd.widget`

## Cara install
1. Buka `Fodd.xcodeproj`.
2. Klik TARGET `Fodd` > Signing & Capabilities.
3. Centang Automatically manage signing.
4. Pilih `Meru Artama (Personal Team)`.
5. Pilih scheme `Fodd`, bukan `FoddWidget`.
6. Pilih iPhone Anda.
7. Product > Clean Build Folder.
8. Tekan Command+R.

Jika Bundle ID sudah pernah terpakai, ganti `com.meruartama.fodd` ke identifier unik milik Anda.
