# App Store Readiness — Fodd 7.0

## Sudah di source
- Privacy Manifest main app dan Widget Extension.
- App deletion/account safety dari versi sebelumnya.
- Report/block/moderation untuk user-generated content.
- No hardcoded production APNs key/admin token.
- Usage descriptions untuk lokasi/foto sesuai Info.plist yang ada.
- App Group, Push, Group Activities entitlements di source.

## Harus diselesaikan di Apple Developer / App Store Connect
- Register App IDs untuk main app dan widget.
- Enable App Groups pada kedua App IDs dan buat `group.com.fodd.app` (atau ganti sesuai Team Anda).
- Enable Push Notifications.
- Pastikan provisioning profile mengandung Group Activities entitlement untuk SharePlay.
- Upload APNs Auth Key secara aman ke Railway environment, jangan ke source.
- Isi App Privacy answers sesuai data yang benar-benar dikumpulkan backend.
- Siapkan Privacy Policy URL, Support URL, age rating, screenshots, review notes, dan demo account bila reviewer membutuhkan login.
- Test account deletion, report/block, restaurant claim/admin workflow, dan semua paywall bila kelak ditambahkan.

## Device QA
Uji minimal pada iPhone nyata. Dynamic Island hanya terlihat penuh pada model yang mendukung Dynamic Island; Live Activity tetap dapat diuji di Lock Screen pada device/iOS yang mendukung ActivityKit.
