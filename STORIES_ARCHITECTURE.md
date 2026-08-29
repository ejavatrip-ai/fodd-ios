# Food Stories Architecture — Fodd 7.1

## Lifecycle
`created_at` ditetapkan server dan `expires_at` otomatis `created_at + 24 hours`.
Endpoint feed `/api/stories` hanya mengembalikan Story dengan `expires_at > NOW()`. Karena itu mengubah jam pada iPhone tidak dapat memperpanjang Story.

## Archive
Story yang kedaluwarsa tidak lagi dapat dilihat publik, tetapi pemilik dapat mengaksesnya melalui `/api/stories/archive`. Archive bersifat private dan membutuhkan session pemilik.

## Privacy
Story menggunakan visibility yang sama dengan Food Moment:
- everyone
- friends
- close_foodies
- selected
- only_me

Private-account gate dan block relationship diperiksa oleh backend sebelum Story dikembalikan atau diinteraksi.

## Engagement
`story_views` menggunakan primary key `(story_id,user_id)` sehingga satu akun tidak meningkatkan viewer count berkali-kali. `story_reactions` juga satu reaction aktif per viewer per Story. Story reply ditulis ke tabel chat `messages`, sehingga balasan langsung menjadi percakapan Fodd.

## Production media recommendation
Build ini kompatibel dengan media representation Fodd yang ada. Untuk skala produksi, pindahkan `stories.media` ke URL object storage dan gunakan tabel hanya untuk metadata/URL.
