# Fodd 6.2 — Complete & Safe — Build 9

## Highlights

Fodd 6.2 menutup fondasi penting sebelum aplikasi digunakan komunitas yang lebih besar: moderation/reporting, blocking, private accounts, follow requests, restaurant collections, notification controls, offline cache, dan Keychain session storage.

## Safety
- Report user, Moment, dan comment.
- Block/unblock dua arah dengan cleanup relasi sosial.
- Moderation queue admin server-side.
- Filter spam/abuse dasar yang bisa diperluas melalui `MODERATION_TERMS`.
- Block relationship diterapkan pada feed, search, chat, notifications, dan unread state.

## Privacy
- Public/private account.
- Follow request accept/reject.
- Private profile lock untuk non-approved follower.
- Existing Moment audiences tetap diperiksa server-side.

## Collections
- Create/delete collections.
- Simpan/hapus restoran.
- Apple Maps places dapat di-upsert ke backend dan disimpan ke collection.

## Preferences
- Push follows, likes/reactions, comments, dan messages dapat diatur terpisah.
- APNs hanya dikirim ketika kategori terkait aktif.

## Reliability & security
- Offline state cache dengan payload foto besar disanitasi.
- URLCache memory/disk untuk resource jaringan.
- Custom URL deep links untuk profile, restaurant, dan Moment.
- Session token disimpan di iOS Keychain dan legacy token dimigrasikan otomatis.
- Backend security headers.
- Rate-limit dasar untuk auth/reset/report dan no-store cache policy pada API.
- Marketing Version 6.2, Build 9.
