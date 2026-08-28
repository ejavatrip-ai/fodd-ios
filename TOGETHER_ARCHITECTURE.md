# Fodd Together Architecture

## Lifecycle

`Planning → Invite → RSVP → Candidate Restaurants → Vote → Host Selects → Group Chat → Eat → Group Album → Group Food Moment → Completed`

Satu `dining_plan` menjadi sumber kebenaran untuk seluruh anggota. iOS tidak menyimpan status voting/RSVP hanya secara lokal.

## Database

### dining_plans
Host, judul, catatan, waktu rencana, status, restoran terpilih, timestamps.

### dining_plan_members
Membership dan RSVP setiap foodie.

### dining_plan_candidates
Restoran kandidat pada plan.

### dining_plan_votes
Satu pilihan aktif per peserta per plan. Constraint menjaga vote tidak terduplikasi untuk user/plan.

### dining_plan_messages
Channel chat khusus plan.

### dining_plan_photos
Group album dan contributor.

### collection_members
Sharing Collections dengan role `editor` atau `viewer`; owner tetap berada pada record collection utama.

### moments.plan_id
Menghubungkan Group Food Moment ke Dining Plan asal.

### notifications.plan_id
Memberi konteks agar push/deep-link Together dapat membuka plan yang tepat.

## Permission Model

### Dining Plan
- Host: edit plan, invite/remove, manage candidates, memilih restoran final, complete/cancel, moderasi album.
- Member: RSVP, vote, chat, upload album, create group moment selama masih memiliki access.
- Non-member: tidak dapat membaca plan.
- Block relationship membatalkan/menolak akses relasional yang relevan.

### Shared Collections
- Owner: semua aksi + manage member/role.
- Editor: baca dan mutate restaurant list.
- Viewer: read-only.

## Notification

Preference `pushTogether` mengontrol notifikasi plan/shared collaboration. Payload APNs dapat membawa `planId`; iOS mengubahnya menjadi deep link `fodd://together/<plan-id>`.

## Compatibility

6.4 mempertahankan Smart Food 6.3. Kandidat restoran masih dapat memanfaatkan restoran nyata Apple Maps yang telah diimpor serta Taste DNA/Match Score di permukaan discovery.
