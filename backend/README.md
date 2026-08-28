# Fodd API 7.0 — Apple Experience

Backend Node.js + Express + PostgreSQL untuk Fodd iOS 7.0. Seluruh API 6.5 tetap tersedia; 7.0 menambahkan registrasi dan remote update Live Activity untuk Dining Plans.

Health: `{"status":"ok","service":"fodd-api","version":"7.0"}`

## Live Activity API
- `PUT /api/together/plans/:id/live-activity` body `{ "activityToken": "<hex token>" }`
- `DELETE /api/together/plans/:id/live-activity`
- Endpoint hanya dapat digunakan host/member Dining Plan yang terautentikasi.
- Token disimpan per `(user_id, plan_id)` dan dihapus setelah plan berakhir.

## APNs Live Activity
Backend mengirim APNs dengan:
- `apns-topic: <APNS_BUNDLE_ID>.push-type.liveactivity`
- `apns-push-type: liveactivity`
- payload `aps.timestamp`, `aps.event`, dan `aps.content-state`.

Update dikirim setelah perubahan RSVP, candidate, vote, selected restaurant/status, dan group message. Completed/cancelled mengirim event `end`.

## Migration
Fodd 7.0 menambah tabel `live_activity_tokens`. Tidak ada drop table atau destructive migration.

## Railway
Environment: `DATABASE_URL`, `PORT`, `NODE_ENV`, `ALLOWED_ORIGIN`, `ADMIN_TOKEN`, serta `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`, `APNS_BUNDLE_ID`, `APNS_ENVIRONMENT`. Email/moderation tetap mengikuti konfigurasi versi sebelumnya.
