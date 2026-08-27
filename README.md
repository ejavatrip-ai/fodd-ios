# Fodd API

Backend REST Node.js + Express + PostgreSQL untuk aplikasi iOS Fodd.

## Endpoint

- `GET /health` — status server dan database.
- `GET /api/restaurants` — daftar restoran; mendukung `?search=`.
- `GET /api/moments` — 50 momen terbaru.
- `POST /api/moments` — membuat momen baru.

Contoh payload:

```json
{
  "author": "Food Explorer",
  "caption": "Makanannya enak!",
  "restaurantId": "mie-ceria",
  "image": "Noodles"
}
```

Server wajib menerima `DATABASE_URL`. Railway otomatis memberikan `PORT`; aplikasi mendengarkan pada `0.0.0.0` agar dapat dicapai edge proxy Railway.
