# Fodd 6.1 — Alive UI — Build 8

Fodd 6.1 adalah update experience layer untuk membuat Fodd terasa lebih premium, responsif, dan hidup, tanpa membuat UI terlalu ramai.

## Motion

- Chat bubble baru memakai spring/pop insertion dari sisi pengirim.
- Incoming chat yang benar-benar baru dianimasikan tanpa mengulang animasi seluruh history.
- Send button berubah scale/rotation secara halus saat pesan siap dikirim.
- Reaction emoji bounce saat dipilih.
- Bookmark/save memakai micro-bounce.
- Check-in card berubah selection dengan spring animation.
- Feed Moment memakai scroll transition ringan.
- Loading Fodd memakai breathing animation.
- Publish Moment menampilkan toast sukses di bagian atas.

## Sound Effects

Custom WAV lokal, tanpa layanan eksternal:

- `fodd_send.wav` — pesan terkirim.
- `fodd_receive.wav` — pesan baru masuk ketika chat sedang terbuka.
- `fodd_reaction.wav` — reaction emoji.
- `fodd_checkin.wav` — memilih restoran/check-in.
- `fodd_success.wav` — Moment berhasil dibagikan.

Audio menggunakan AVAudioSession kategori `ambient` + `mixWithOthers`, sehingga musik/podcast tidak dihentikan.

## Haptics

- Light haptic: tab, send, save, follow.
- Selection haptic: audience, tag friend, Close Foodies, check-in.
- Soft impact: reaction dan incoming chat.
- Success notification haptic: Moment berhasil dipublish.

## User Control & Accessibility

Menu Profile → `Sound & Haptics` menyediakan:

- Sound Effects ON/OFF.
- Haptic Feedback ON/OFF.
- Preview efek.
- Status Reduce Motion iOS.

Fodd membaca `accessibilityReduceMotion`; pop/scale/spring penting akan dinonaktifkan atau dilembutkan otomatis ketika pengguna mengaktifkan Reduce Motion.

## Version

- Marketing Version: 6.1
- Build: 8
- Backend package/health label: 6.1.0 / 6.1
- Database schema: kompatibel dengan Fodd 6.0 Build 7; tidak memerlukan destructive migration.
