# Fodd API 8.0 — Complete Hangout Experience

Backend Node.js + Express + PostgreSQL untuk Fodd 8.0.

Health response: `{"status":"ok","service":"fodd-api","version":"8.0"}`

## Tambahan 8.0
- Hangout preferences + availability status + invite privacy.
- Quick Hangout.
- Voting tanggal/jam Dining Plan.
- Presence `not_started / otw / arrived` + ETA minutes.
- Split Bill + receipt image + paid state.
- Shared Hangout Wishlist.
- Food Passport + Monthly Recap endpoints.
- Product event logging untuk analytics internal.
- Permission check untuk undangan berbasis friends / Close Foodies / block state.

Migration 8.0 bersifat **additive** dan tidak menghapus data versi sebelumnya.
