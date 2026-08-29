# Fodd 7.4 — Smart Reminders & Plans — Personal Team Build 20

Fodd 7.4 menjadikan **Makan Bareng / Together** sebagai fitur utama. Rencana nongkrong sekarang memiliki reminder lokal iPhone yang tetap bekerja walau aplikasi ditutup dan tidak membutuhkan Apple Developer Program berbayar.

## Fitur utama 7.4
- Smart Reminder otomatis: H-1, 2 jam, dan 30 menit sebelum acara.
- Pengguna bisa memilih kombinasi reminder per Dining Plan.
- Local Notification memiliki aksi **Lihat Rencana** dan **Buka Maps**.
- **Waktunya Berangkat** menghitung estimasi perjalanan dengan MapKit dan menambahkan buffer 10 menit.
- Reminder dijadwalkan ulang saat host mengubah tanggal/jam.
- Reminder dibatalkan otomatis saat acara completed/cancelled.
- Dashboard Together baru dengan countdown, upcoming plans, jumlah reminder, dan visual hero.
- UI Create Plan baru: jadwal, foodie invite, kandidat restoran, dan reminder dalam satu alur.
- Profile > Notifications menjelaskan bahwa Smart Reminder lokal tetap bekerja pada Personal Team.
- Seluruh Visual Refresh 7.3, Stories, Highlights, Taste Match, Smart Food, Creator/Restaurant Studio tetap tersedia.

## Personal Team
Remote APNs sosial tetap dinonaktifkan pada build Personal Team, tetapi **Smart Reminder nongkrong adalah local notification**, jadi dapat digunakan dengan Apple ID gratis setelah pengguna memberi izin notifikasi.

## Backend
Backend API tetap kompatibel dengan schema 7.3. Paket backend diberi version 7.4.0 tetapi update ini tidak membutuhkan migration database baru.

## Build
- Marketing Version: 7.4
- Build: 20
- Bundle ID: com.meruartama.fodd
- API: https://fodd-ios-production.up.railway.app/
