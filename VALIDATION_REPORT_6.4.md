# Validation Report — Fodd 6.4 Together — Build 11

Tanggal paket: 28 Agustus 2026.

## Automated gates
- Swift source parse: **PASS** — APIClient, AppStore, ContentView, FoddApp, InteractionFeedback, Services.
- APIClient Linux-compatible typecheck shim: **PASS**.
- Backend Node syntax check: **PASS**.
- Backend tests: **6/6 PASS**.
- Smart Food migration checks: **PASS**.
- Together endpoint/migration checks: **PASS**.
- Together lifecycle/target validation guards: **PASS**.
- Info.plist parse: **PASS**.
- Fodd.entitlements parse: **PASS**.
- Xcode Marketing Version: **6.4**.
- Xcode Build: **11**.
- Backend package: **6.4.0**.
- Together backend route surface: **16 routes detected**.
- Production-secret pattern scan: **PASS** (template `.env.example` intentionally excluded).
- Package hygiene: **PASS** — no node_modules/.DS_Store bundled.

## Bug/edge-case hardening included before release
- Repeated plan invite no longer emits duplicate notification/push for an existing member.
- Unknown invited users and unknown candidate restaurants are validated before FK insertion.
- Adding candidate validates that the restaurant exists.
- Voting and candidate removal close when a plan is no longer `planned`.
- Public non-members cannot enumerate Shared Collection collaborators.
- Shared Collection target account is validated before sharing.

## Limitations of this environment
A complete Xcode/iOS SDK compile, code signing, APNs delivery, MapKit UI test, PhotosPicker test, haptic/audio device feel, and multi-device end-to-end session cannot be executed in this Linux container. Run the device checklist in `FODD_6_4_CHECKLIST.md` on a Mac with Xcode and at least two test accounts/devices before App Store release.
