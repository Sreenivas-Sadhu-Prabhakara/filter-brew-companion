# Giri Brew Companion

Offline-first Flutter app for dialing in filter coffee brews.

## What is implemented

- Two-way ratio calculator: dose to water, or water to dose.
- Guided staged brew timer with start, pause, skip, reset, and haptics.
- Persistent brew log with add, edit, delete, ratings, tags, and notes.
- Settings for default method, strength, cup size, theme, and clear-all-data.
- Local-only privacy posture: no backend, analytics, or app manifest permissions.

## Verification

```bash
flutter analyze
flutter test
flutter build appbundle --release
jarsigner -verify build/app/outputs/bundle/release/app-release.aab
shasum -a 256 build/app/outputs/bundle/release/app-release.aab
```

Current local release bundle:

```text
build/app/outputs/bundle/release/app-release.aab
sha256 ef24a591892bc10a0ced0c6bebfb39d1d16a5e7ff06848d1c0698fef9d1c8dfe
```

Signing material is intentionally git-ignored under `android/key.properties` and
`android/app/upload-keystore.jks`.
