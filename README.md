# Fodd — iOS SwiftUI Prototype

Prototype aplikasi sosial dan penemuan kuliner dengan backend online yang siap dipasang di Railway.

## Struktur repository

```text
Fodd.xcodeproj/     Proyek Xcode
Fodd/               Source dan aset aplikasi SwiftUI
backend/            REST API Node.js + PostgreSQL
.github/workflows/  Pengujian otomatis GitHub Actions
```

## Menjalankan

1. Buka `Fodd.xcodeproj` dengan Xcode 16 atau yang lebih baru.
2. Pilih simulator iPhone 16 (atau iPhone lain dengan iOS 17+).
3. Tekan **Run** (`⌘R`).

Gambar demo tersimpan lokal. Data restoran diambil dari Railway dan otomatis kembali ke data lokal jika koneksi gagal.

## Publikasi ke GitHub

Repository menggunakan branch utama `main`. Setelah membuat repository kosong bernama `fodd-ios` di GitHub:

```bash
git remote add origin https://github.com/USERNAME/fodd-ios.git
git push -u origin main
```

Workflow **Backend CI** menjalankan test Node.js dan pemeriksaan syntax. Workflow **iOS CI** mencoba build pada simulator melalui runner macOS setiap kali source iOS berubah.

## Men-deploy backend dari GitHub ke Railway

1. Buat **New Project** di Railway.
2. Tambahkan layanan **PostgreSQL**.
3. Pilih **Deploy from GitHub repo**, lalu pilih repository `fodd-ios`.
4. Pada pengaturan service, isi **Root Directory** dengan `/backend`.
5. Pastikan variabel `DATABASE_URL` pada layanan backend mengarah ke PostgreSQL Railway.
6. Tambahkan `NODE_ENV=production` dan `ALLOWED_ORIGIN=*`.
7. Deploy, lalu pada **Settings → Networking** pilih **Generate Domain**.
8. Buka `https://DOMAIN-ANDA/health`. Hasil yang benar adalah JSON dengan `status: ok`.
9. Di Xcode buka target **Fodd → Build Settings → User-Defined → API_BASE_URL**, lalu masukkan domain Railway dengan `/` di bagian akhir.
10. Jalankan aplikasi. Halaman Explore akan menampilkan status **Data online dari Railway**.

Jika sewaktu-waktu ingin memakai Railway CLI dari folder `backend`:

```bash
railway login
railway init --name fodd-api
railway up
railway domain
```

PostgreSQL tetap perlu ditambahkan ke project dan `DATABASE_URL` perlu tersedia sebelum service sehat.

## Fitur versi ini

- Feed sosial, story, like, dan kartu rekomendasi.
- Explore, pencarian, kategori, serta restoran populer/terdekat.
- Daftar teman dan pesan demo.
- Profil dengan galeri momen.
- Form tambah momen yang tersimpan ke PostgreSQL.
- Endpoint health check dan REST API Railway.
- Mode offline otomatis ketika backend tidak dapat dijangkau.
- App icon dan aset food photography orisinal.

## Tahap berikutnya untuk produksi

Tambahkan authentication, object storage untuk upload foto, Maps/Location, push notification, chat real-time, moderation, analytics, serta konfigurasi App Store signing.
