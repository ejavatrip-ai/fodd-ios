# Fodd 6.0 — Build 7 Bug Fix Release

Build 7 mempertahankan fitur dan desain Fodd 6.0, dengan fokus pada stabilitas, privasi, autentikasi, foto, dan konsistensi iOS/backend.

## Perbaikan utama

- Menutup celah akses interaksi pada Food Moment private. Like, reaction, dan comment sekarang memverifikasi audience/privacy di backend sebelum membaca atau menulis data.
- Mencegah notifikasi follow/like ganda ketika request yang sama dikirim ulang.
- Reaction yang sama tidak lagi menghasilkan update/notifikasi berulang.
- Logout sekarang mencabut session backend dan device token APNs milik akun pada perangkat tersebut.
- Sesi tidak lagi dihapus hanya karena Railway/server/internet sementara tidak dapat dijangkau. Session lokal hanya dihapus otomatis bila server membalas 401 (session invalid/kedaluwarsa).
- Ditambahkan layar retry koneksi saat session masih tersimpan tetapi server tidak dapat dijangkau.
- Login tetap dianggap berhasil setelah autentikasi sukses walaupun refresh salah satu feed gagal; pengguna dapat retry data tanpa kehilangan session.
- Encoding search/query dan path diperketat agar karakter seperti &, #, ?, +, dan = tidak memotong parameter URL.
- API base URL sekarang divalidasi agar placeholder build setting yang belum terisi tidak dipakai sebagai URL.
- Menghapus force-cast respons HTTP 204 dan menggantinya dengan pemeriksaan tipe aman.
- Foto kamera/galeri otomatis di-resize hingga sisi maksimum 1800 px dan dikompresi adaptif sebelum dikirim, mengurangi upload gagal dan penggunaan memori/data.
- Bila foto tetap tidak dapat diproses, UI sekarang menampilkan pesan kesalahan alih-alih gagal diam-diam.
- Parser waktu mendukung timestamp ISO-8601 dengan fractional seconds dari PostgreSQL/Node sehingga label “menit lalu/jam lalu” lebih konsisten.
- Build iOS dinaikkan ke 7; Marketing Version tetap 6.0.

## Validasi paket

- Seluruh file Swift: `swiftc -parse` lulus.
- Seluruh JavaScript backend: `node --check` lulus.
- `npm test`: lulus.
- `Info.plist` dan `Fodd.entitlements`: valid.
- Endpoint baru device-token unregister tersedia dan terhubung dari iOS.

Catatan: build/signing iOS penuh tetap perlu dijalankan dengan Xcode/macOS karena lingkungan validasi paket ini bukan macOS dan tidak memiliki iOS SDK/Xcode.
