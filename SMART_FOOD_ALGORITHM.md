# Smart Food Algorithm — Fodd 6.3

Fodd 6.3 tidak memerlukan API AI berbayar. Personalization memakai explainable weighted scoring.

## Input
- Explicit cuisine preferences.
- Mood preferences.
- Spicy / price / adventurous sliders.
- Saved restaurants.
- Collection additions.
- Restaurant views.
- Searches.
- Reviews.
- Check-ins.
- Recommendation opens.
- Restaurant rating and recent aggregate activity.

## Taste DNA
Explicit preference mempunyai bobot terbesar saat akun masih baru. Aktivitas nyata kemudian menambah confidence dan mengubah kategori dominan. Keyword aliases membantu mengenali cuisine dari nama/menu restoran ketika source data hanya memberi kategori umum.

## Match Score
Baseline berasal dari rating, kemudian ditambah jika kategori/menu/nama cocok dengan Taste DNA, cuisine explicit, mood aktif, dan activity score. Hasil dibatasi 55–99 agar angka tidak memberi kesan kepastian ilmiah 100%.

## Privacy
Smart events hanya dipakai untuk personalisasi akun Fodd. Feed tetap memakai privacy enforcement backend yang sama seperti 6.2. Smart dashboard tidak membuka Moment private pengguna lain.

## Cold start
Jika belum ada sinyal, Fodd memakai kategori default dan rating sebagai fallback. Setelah pengguna mengisi Taste DNA atau mulai save/search/review, ranking menjadi lebih personal.
