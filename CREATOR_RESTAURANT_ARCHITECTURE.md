# Creator & Restaurant Architecture — Fodd 6.5

## Creator Identity
Creator status disimpan pada `users`:
- `is_creator`
- `creator_verified`
- `creator_category`
- `creator_website`
- `creator_since`

`is_creator` dapat diaktifkan user. `creator_verified` hanya dapat diubah melalui endpoint admin.

## Restaurant Ownership
Ownership tidak disimpan sebagai satu kolom user pada restaurant agar satu restoran dapat dikelola beberapa account.

- `restaurant_claims`: workflow review.
- `restaurant_owners`: relation approved user ↔ restaurant dengan role.
- `restaurants.is_verified`: business verification indicator.

Role:
- Owner: profile + menu + updates.
- Manager: profile + menu + updates.
- Staff: menu + updates, tidak dapat edit business profile.

## Menu
`restaurant_menu_items` menjadi source menu resmi Fodd. Kolom `restaurants.menu` lama tetap dipertahankan untuk backward compatibility/import metadata.

## Restaurant Updates
`restaurant_posts` adalah feed resmi per restoran. Ini berbeda dari Food Moment user dan Review agar promosi bisnis tidak bercampur dengan ulasan komunitas.

## Security Boundary
Permission mutation selalu diperiksa backend menggunakan `restaurantManagementAccess()`. UI hiding bukan security boundary.

Verified Restaurant juga diberi guard pada endpoint import/upsert sehingga data bisnis verified tidak dapat ditimpa user biasa.
