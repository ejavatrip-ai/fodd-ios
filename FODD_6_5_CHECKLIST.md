# Fodd 6.5 Release Checklist

## Railway / Backend
- [ ] Deploy backend 6.5 sebelum iOS build 12 digunakan publik.
- [ ] `DATABASE_URL` aktif.
- [ ] `NODE_ENV=production`.
- [ ] `ADMIN_TOKEN` kuat dan tidak dimasukkan ke source iOS.
- [ ] Health `/health` menunjukkan version 6.5.
- [ ] Migration membuat `restaurant_claims`, `restaurant_owners`, `restaurant_menu_items`, `restaurant_posts`.

## Creator
- [ ] Aktifkan Creator Profile.
- [ ] Ubah niche dan website.
- [ ] Creator Insights tampil.
- [ ] Verified badge hanya muncul setelah admin verification.
- [ ] Verified badge tampil di profile dan feed.

## Restaurant Claim
- [ ] Import/buka restoran nyata.
- [ ] Kirim claim Owner/Manager/Staff.
- [ ] Claim muncul pending di Restaurant Studio.
- [ ] Admin approve.
- [ ] Restoran muncul di My Restaurants dan menjadi Verified.
- [ ] Admin reject menghapus ownership terkait bila ada.

## Restaurant Studio
- [ ] Owner/Manager dapat edit profil.
- [ ] Staff ditolak saat edit profil.
- [ ] Semua role pengelola dapat tambah/edit/hapus menu.
- [ ] Semua role pengelola dapat publish/hapus Restaurant Update.
- [ ] User non-manager ditolak oleh backend untuk mutation endpoint.

## iPhone QA
- [ ] Build & Run di Xcode.
- [ ] Foto menu besar dikompresi sebelum upload.
- [ ] Creator/Verified icons readable di Light/Dark Mode.
- [ ] Restaurant detail tidak terasa terlalu panjang pada iPhone kecil.
- [ ] VoiceOver label untuk verified icon terbaca.
