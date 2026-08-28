# Fodd 6.5 — Creator & Restaurant — Build 12

## Highlights

Fodd 6.5 menambahkan lapisan profesional untuk creator dan bisnis kuliner tanpa menghilangkan social diary, Smart Food, Together, privacy, chat, Maps, dan Alive UI.

### Creator Studio
- Creator Profile opt-in.
- Niche/category dan website/portfolio.
- Creator Insights berbasis data nyata: Moments, Followers, Likes, Comments, Reviews.
- Verified Creator hanya melalui admin.
- Verified badge muncul di profile dan Food Moment feed.

### Restaurant Claim & Verification
- Claim restoran dengan role Owner/Manager/Staff.
- Pending/Approved/Rejected status.
- Admin approval menghasilkan restaurant ownership relation.
- Approved restaurant otomatis menjadi Verified Restaurant.
- Verified restaurant terlindungi dari overwrite sembarang user saat import Apple Maps.

### Restaurant Studio
- Daftar restoran yang dikelola.
- Status klaim.
- Owner/Manager dapat edit profil resmi restoran.
- Staff tidak dapat edit profil bisnis utama, tetapi tetap dapat mengelola menu/update.

### Official Menu
- CRUD menu item.
- Category, description, price, photo, availability, order.
- Menu resmi tampil langsung pada detail restoran.

### Restaurant Updates
- Pengelola dapat publish kabar/promosi/menu baru/event/jam khusus.
- Post resmi tampil pada detail restoran.

## Compatibility
- Database migration additive/non-destructive.
- Existing 6.4 data tetap dipertahankan.
- Existing users default `isCreator=false`.
- Existing restaurants default `isVerified=false`.
