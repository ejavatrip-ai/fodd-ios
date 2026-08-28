# Release Notes — Fodd 6.4 Together — Build 11

## Highlight
Fodd 6.4 mengubah pengalaman makan dari aktivitas individual menjadi perjalanan sosial lengkap: **buat rencana, undang teman, RSVP, vote restoran, chat grup, makan, kumpulkan foto, lalu jadikan Group Food Moment**.

## Added
- Dining Plans / Makan Bareng.
- RSVP Going / Maybe / Declined.
- Multi-candidate restaurant voting.
- Host restaurant selection dan plan completion.
- Per-plan group chat.
- Group Food Album dengan contributor metadata.
- Group Food Moment yang terhubung ke Food Diary.
- Shared Collections dengan owner/editor/viewer.
- Push preference `Together`.
- APNs context `planId`.
- Deep link `fodd://together/<plan-id>`.
- Together segment di Inbox.
- Makan Bareng shortcut di Create hub dan Restaurant Detail.

## Backend
- Tambahan schema Dining Plans, members, candidates, votes, messages, photos.
- `moments.plan_id` dan `notifications.plan_id`.
- Permission checks untuk plans dan shared collections.
- Block integration untuk plan/shared membership.
- Push context dapat membawa metadata plan.

## Compatibility
Migration bersifat additive. Data Fodd 6.0–6.3 tetap dipertahankan.

## Version
- Marketing Version: 6.4
- Build: 11
- Backend package: 6.4.0
