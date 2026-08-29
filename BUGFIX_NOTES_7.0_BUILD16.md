# Fodd 7.0 Personal Team — Build 16 Bugfix

Build 16 fixes the Xcode compile diagnostics reported after Build 15.

## Fixed
- Removed MainActor access from the nonisolated feed sort comparison by capturing `accountId` before sorting.
- Rewrote Change Password async condition so `await` is not used inside the `&&` autoclosure.
- Replaced two stale `relativeTime(...)` calls with the existing `relativeDate(...)` helper.
- Made `CLLocationManagerDelegate` callbacks nonisolated and marshalled UI state updates back to `MainActor`.
- Build number bumped to 16.

## Unchanged
- Marketing version remains 7.0.
- Bundle identifier remains `com.meruartama.fodd`.
- API base URL remains `https://fodd-ios-production.up.railway.app/`.
- Personal Team limitations remain in place (no remote Push, App Group, SharePlay, or remote Dynamic Island in this edition).
