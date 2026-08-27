# Kontribusi

Gunakan branch fitur, misalnya `feature/upload-foto`, lalu buka pull request menuju `main`.

Sebelum commit:

```bash
cd backend
npm ci
npm test
node --check src/server.js
```

Untuk iOS, buka `Fodd.xcodeproj`, pilih simulator iPhone, lalu tekan `⌘B`.

Jangan commit `.env`, token Railway, credential database, certificate signing, atau provisioning profile.
