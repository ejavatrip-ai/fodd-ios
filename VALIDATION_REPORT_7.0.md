# Validation Report — Fodd 7.0 Build 13

Validated in the ChatGPT build environment on 2026-08-28.

## Passed
- Swift source parse: PASS (main app + Widget Extension).
- `APIClient.swift` Linux typecheck with `FoundationNetworking` compatibility import: PASS.
- Backend JavaScript syntax (`node --check`): PASS.
- Backend automated tests: **12/12 PASS**.
- Apple Experience backend tests: **3/3 PASS**.
- Existing Creator/Restaurant, Smart Food, and Together tests: PASS.
- Xcode `project.pbxproj` OpenStep plist validation: PASS.
- Main `Info.plist`: PASS.
- Main entitlements: PASS.
- Widget `Info.plist`: PASS.
- Widget entitlements: PASS.
- Main + Widget `PrivacyInfo.xcprivacy`: PASS.
- Widget Extension embedded in main target: static project check PASS.
- App Group present on app + widget: PASS.
- Group Activities entitlement present on main app: PASS.
- `NSSupportsLiveActivities`: PASS.
- Dynamic Island source present: PASS.
- App Intents/App Shortcuts source present: PASS.
- Spotlight integration source present: PASS.
- SharePlay GroupActivity source present: PASS.
- MapKit Look Around source present: PASS.
- Backend APNs `liveactivity` topic/push-type source present: PASS.
- Live Activity migration ordering: PASS.
- Marketing version: **7.0**.
- Build number: **13**.
- Backend package version: **7.0.0**.
- Basic production-secret pattern scan: PASS.

## Apple-specific implementation notes
- Widget and Live Activity live in target `FoddWidget`.
- App Group is configured as `group.com.fodd.app` in source and must also exist in the user's Apple Developer Team.
- Push notification signing/provisioning must be configured for the user's real App ID.
- Remote Live Activity uses APNs topic `<APNS_BUNDLE_ID>.push-type.liveactivity`.
- Privacy manifests declare required-reason UserDefaults usage; App Store Connect privacy answers remain a deployment responsibility and must reflect actual collected data.

## Requires Xcode / physical-device validation
This environment does not include Apple's iOS SDK, Xcode signing services, Developer Portal profiles, or an iPhone runtime. Therefore these final release gates still require a Mac/iPhone:
- Full Xcode compile/link/archive/sign for both targets.
- Provisioning profile acceptance of App Groups, Push Notifications, and Group Activities.
- Home Screen Widget timeline/rendering.
- Lock Screen Live Activity and Dynamic Island rendering.
- APNs Live Activity token delivery through Railway production APNs credentials.
- Siri/App Shortcuts registration and invocation.
- Spotlight indexing/search UI.
- SharePlay session behavior during FaceTime/Messages.
- Apple Maps Look Around availability/runtime.
- TestFlight/App Store Connect upload validation.
