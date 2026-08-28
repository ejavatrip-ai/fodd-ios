# Fodd 7.0 — Apple Experience Architecture

## Targets
`Fodd` adalah main iOS app. `FoddWidget` adalah Widget Extension yang memuat Home Screen Widget dan ActivityKit Live Activity/Dynamic Island UI.

## Shared Container
`FoddAppleShared.swift` dikompilasi ke kedua target. `FoddSharedContainer` memakai suite `group.com.fodd.app` untuk `FoddWidgetSnapshot` dan pending route dari App Intent/widget ke main app.

## Widget Flow
AppStore refresh → `FoddAppleExperienceManager.sync()` → widget snapshot disimpan di App Group → `WidgetCenter.reloadAllTimelines()` → Widget membaca snapshot tanpa network dependency.

## Spotlight Flow
Saat data utama berubah, manager membuat `CSSearchableItem` untuk restoran, moments, followed/close foodies, dan planned Dining Plans. `contentURL` memakai deep link `fodd://`.

## Live Activity Flow
DiningPlan Detail → `AppStore.startDiningLiveActivity()` → ActivityKit meminta local activity dengan `pushType: .token` → token APNs Activity dikirim ke backend → backend menyimpan token participant → perubahan Together memicu `sendLiveActivityUpdate()` → APNs liveactivity payload memperbarui Dynamic Island/Lock Screen → completed/cancelled mengirim event `end`.

## SharePlay Flow
Dining Plan → `FoddTogetherShareActivity` → `prepareForActivation()` → bila activation preferred, `activate()`. Metadata membawa title dan restaurant context.

## Look Around
Restaurant Detail → `MKLookAroundSceneRequest(coordinate:)` → hanya render `LookAroundPreview` bila scene tersedia → full viewer melalui `lookAroundViewer`.

## Security Boundaries
- Live Activity token hanya dapat didaftarkan oleh user yang punya `planAccess`.
- APNs private key tetap server-only.
- App Group hanya untuk state ringan widget/deep link, bukan auth token.
- Session tetap berada di Keychain dari Fodd 6.2.
