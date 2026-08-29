# Release Notes — Fodd 7.1 Build 17

## Food Stories 24h
- Stories tray pada Home.
- Photo Story dan text Story.
- Server-side expiry 24 jam melalui `expires_at`.
- Active endpoint hanya mengembalikan Story yang belum kedaluwarsa.
- Private owner archive menyimpan riwayat Story setelah 24 jam.
- View tracking satu viewer per Story.
- Reaction Story: love, yummy, fire, wow.
- Story replies dikirim ke Fodd Chat.
- Viewers list hanya dapat dibuka pemilik Story.
- Delete Story oleh pemilik.
- Audience Story mengikuti privacy Fodd: everyone/friends/close_foodies/selected/only_me.
- Block rules diterapkan pada Story visibility.

## UI/UX
- Gradient ring untuk Story unseen.
- Ring netral untuk Story seen.
- Progress bars dan auto-advance.
- Full-screen viewer dengan location, caption, reaction, reply.
- Haptic & sound effect mengikuti Alive UI settings.
- Story Archive ditambahkan ke Profile.

## Backend
Tabel additive baru:
- `stories`
- `story_audience`
- `story_views`
- `story_reactions`

Tidak ada drop table atau destructive migration.
