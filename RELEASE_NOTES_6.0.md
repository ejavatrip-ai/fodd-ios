# Fodd 6.0 Release Notes

## Design
- Premium redesign mengikuti logo Fodd: orange-red gradient, warm cream, white, neutral system colors.
- Navigasi baru: Home / Explore / + Moment / Inbox / Profile.
- Feed card, Explore, profile, inbox, composer, privacy picker, dan review memakai visual system yang konsisten.

## Social Food Diary
- Food Photo, Check In, Eating, Cooking, Craving, Thought.
- Tag foodies.
- Everyone, Friends, Close Foodies, Selected Friends, Only Me.
- Love, Yummy, Fire, Wow reactions.
- Food Diary timeline di profile.

## Close Foodies
- Backend table + endpoint baru.
- Pengaturan dari profile/member.
- Audience filtering di backend.

## Compatibility
- Migration additive dari schema v5.
- API akun/restoran/review/chat/search/APNs v5 tetap tersedia.
- Marketing version 6.0, build 6.


## Build 7 — Bug Fix Update

Build 7 menambahkan hardening privacy untuk interaksi moment, logout server + APNs device cleanup, session retry yang aman saat offline, URL encoding yang benar, optimasi foto, dan parser timestamp yang lebih robust. Detail lengkap ada di `BUGFIX_NOTES_6.0_BUILD7.md`.
