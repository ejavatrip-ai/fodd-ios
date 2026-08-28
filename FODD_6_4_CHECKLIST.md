# Fodd 6.4 Together — Release Checklist

## Railway / Backend
- [ ] Backup database sebelum deployment produksi.
- [ ] Deploy folder `backend` 6.4 ke Railway.
- [ ] Pastikan health endpoint mengembalikan version `6.4`.
- [ ] Pastikan migration Dining Plan dan Shared Collection berhasil.
- [ ] Pastikan `DATABASE_URL`, APNs, email, dan `ADMIN_TOKEN` tersedia.

## iOS / Xcode
- [ ] Buka `Fodd.xcodeproj`.
- [ ] Marketing Version = 6.4.
- [ ] Build = 11.
- [ ] Signing/Bundle ID benar.
- [ ] `API_BASE_URL` menunjuk Railway 6.4.

## Test dengan minimal 2 akun
- [ ] Host membuat Makan Bareng.
- [ ] Host mengundang peserta.
- [ ] Peserta melihat plan yang sama.
- [ ] RSVP Going/Maybe/Declined tersimpan.
- [ ] Tambah 2+ kandidat restoran.
- [ ] Setiap peserta hanya memiliki satu vote aktif.
- [ ] Host memilih restoran final.
- [ ] Group chat terkirim dan tersinkron.
- [ ] Push Together membuka plan yang benar.
- [ ] Album menerima foto dari beberapa contributor.
- [ ] Contributor hanya menghapus fotonya sendiri; host dapat moderasi album.
- [ ] Group Food Moment masuk ke feed/Food Diary peserta yang berhak.
- [ ] Shared Collection owner/editor/viewer mengikuti permission.
- [ ] Blocked user tidak bisa diundang/share.
- [ ] Deep link `fodd://together/<id>` membuka plan.

## UX
- [ ] Chat animation tidak menyebabkan double message.
- [ ] Sound/haptic mengikuti setting pengguna.
- [ ] Reduce Motion tetap dihormati.
- [ ] UI plan tetap usable pada Dynamic Type.
