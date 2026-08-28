# Validation Report — Fodd 6.5 Build 12

Validated in the ChatGPT build environment on 2026-08-28.

## Passed
- Swift source parse: PASS (all `Fodd/*.swift`).
- `APIClient.swift` Linux typecheck with `FoundationNetworking`: PASS.
- Backend JavaScript syntax (`node --check`): PASS.
- Backend automated tests: **9/9 PASS**.
- Creator & Restaurant endpoint static consistency: PASS.
- 6.5 migration table/ordering static check: PASS.
- Xcode `project.pbxproj` plist syntax: PASS.
- `Info.plist`: PASS.
- `Fodd.entitlements`: PASS.
- Marketing version: **6.5**.
- Build number: **12**.
- Backend package version: **6.5.0**.

## 6.5-specific tests
- Creator Studio endpoints present.
- Restaurant Claim/Studio endpoints present.
- Creator/restaurant migration additive.
- Verified Restaurant overwrite guard present.
- Owner/Manager/Staff permission guards present.
- Admin approval inserts restaurant ownership and verifies restaurant.
- Admin rejection removes matching ownership and recalculates restaurant verification.

## Security notes
- `creator_verified` can only be changed through the admin endpoint.
- Restaurant mutations require backend ownership checks.
- Verified restaurant metadata is protected from normal import overwrite.
- `ADMIN_TOKEN` is server-only and is not embedded in iOS source.
- `.env.example` contains placeholders only; no production credential is bundled.

## Requires physical/Xcode validation
This environment does not include the Apple iOS SDK or signing identity, so the following must still be tested on a Mac/iPhone:
- Full Xcode compile/link/sign.
- Apple Maps/MapKit runtime.
- APNs delivery.
- PhotosPicker/photo upload behavior on device.
- Haptic and sound behavior.
- Keychain persistence.
- End-to-end multi-account creator/restaurant claim workflow against Railway/PostgreSQL.
