# Fodd 7.0 Personal Team Edition — Validation Report

Build: 16
Marketing Version: 7.0
Main Bundle ID: `com.meruartama.fodd`
API Base URL: `https://fodd-ios-production.up.railway.app/`

## Build 16 fixes
- Feed ranking no longer reads `AppStore.account` from the sorting closure.
- Async password change no longer places `await` on the RHS of `&&`.
- Restaurant post timestamps use the existing `relativeDate` helper.
- Core Location delegate callbacks bridge state updates back to `MainActor`.

## Personal Team changes retained
- Main app App Groups entitlement removed.
- Main app Push Notifications entitlement removed.
- Group Activities entitlement removed.
- Widget Extension is not a dependency of the main Fodd target.
- `FODD_PERSONAL_TEAM` compilation condition enabled for Debug and Release.
- Remote push registration, SharePlay, and remote Live Activity remain disabled.

## Validation
- Swift parser (all app + widget Swift files): PASS
- Targeted Xcode error-pattern scan: PASS
- Backend JavaScript syntax: PASS
- Backend automated tests: PASS
- Main Info.plist: PASS
- Main entitlements plist: PASS
- Widget Info.plist: PASS
- Widget entitlements plist: PASS
- Bundle identifier: PASS
- API base URL: PASS
- Build number 16: PASS
