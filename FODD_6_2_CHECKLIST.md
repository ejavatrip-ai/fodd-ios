# Fodd 6.2 — QA / Release Checklist

## Xcode
- [ ] Buka `Fodd.xcodeproj` dan pilih Signing Team.
- [ ] Clean Build Folder lalu Build.
- [ ] Jalankan pada iPhone asli.
- [ ] Cek Marketing Version 6.2 / Build 9.

## Account & privacy
- [ ] Public → Private Account.
- [ ] Kirim follow request dari akun kedua.
- [ ] Accept dan Reject follow request.
- [ ] Pastikan private Food Diary terkunci untuk non-follower.
- [ ] Ubah kembali Public dan cek pending requests.

## Safety
- [ ] Report user, Moment, comment.
- [ ] Block akun kedua dan pastikan feed/chat/search tidak memperlihatkan akun tersebut.
- [ ] Unblock dan refresh.
- [ ] Cek moderation queue menggunakan `ADMIN_TOKEN` server-only.

## Collections
- [ ] Buat collection.
- [ ] Simpan restoran backend.
- [ ] Simpan restoran Apple Maps nearby.
- [ ] Buka detail collection dan hapus item.
- [ ] Hapus collection.

## Notifications
- [ ] Matikan/aktifkan push follow.
- [ ] Matikan/aktifkan push reaction/like.
- [ ] Matikan/aktifkan push comment.
- [ ] Matikan/aktifkan push chat.

## Offline
- [ ] Login dan load feed sampai selesai.
- [ ] Matikan koneksi jaringan.
- [ ] Relaunch aplikasi; cache terakhir tetap tampil dan banner Offline muncul.
- [ ] Nyalakan jaringan dan refresh.

## Keychain
- [ ] Upgrade dari build lama dan pastikan sesi tetap terbaca.
- [ ] Logout dan pastikan sesi benar-benar terhapus.

## Deep links
- [ ] Uji `fodd://profile/<user-id>`.
- [ ] Uji `fodd://restaurant/<restaurant-id>`.
- [ ] Uji `fodd://moment/<moment-id>`.

## Regression 6.1
- [ ] Chat send/receive animation dan sound.
- [ ] Reaction bounce + haptic.
- [ ] Check-in Apple Maps.
- [ ] Post Food Moment.
- [ ] Search, review, directions, profile, Close Foodies.
- [ ] Reduce Motion dan toggle Sound/Haptics.

## Railway
- [ ] Backup database produksi.
- [ ] Deploy folder `/backend` versi 6.2.
- [ ] Set `ADMIN_TOKEN` kuat.
- [ ] Set `MODERATION_TERMS` bila diperlukan.
- [ ] Verifikasi `/api/health` menampilkan version 6.2.
