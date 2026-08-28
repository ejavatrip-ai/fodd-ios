# Fodd 6.1 Build 8 — QA Checklist

## Source
- [x] Swift sources parse successfully.
- [x] InteractionFeedback.swift included in PBXSourcesBuildPhase.
- [x] Five WAV assets included in PBXResourcesBuildPhase.
- [x] Info.plist parses.
- [x] Entitlements parses.

## Motion
- [x] Chat outgoing bubble spring/pop.
- [x] Chat incoming bubble spring/pop only for unseen message IDs.
- [x] Auto-scroll animation respects Reduce Motion.
- [x] Reaction bounce.
- [x] Bookmark micro-bounce.
- [x] Check-in selection animation.
- [x] Feed scroll transition.
- [x] Loading breathing animation.
- [x] Publish success toast.

## Audio & Haptic
- [x] Send sound.
- [x] Receive sound.
- [x] Reaction sound.
- [x] Check-in sound.
- [x] Publish success sound.
- [x] Sound setting persisted in UserDefaults.
- [x] Haptic setting persisted in UserDefaults.
- [x] Ambient audio session mixes with other audio.

## Backend
- [x] Node syntax check.
- [x] npm test passes.
- [x] Backend remains compatible with v6 privacy/session fixes.

## Final device checks still recommended in Xcode
- [ ] Build on an actual iPhone target.
- [ ] Verify custom WAV volume with Ring/Silent switch.
- [ ] Verify Reduce Motion on a physical iPhone.
- [ ] Verify APNs + in-chat receive sound do not feel duplicated in the chosen notification configuration.
