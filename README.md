# NetGuard
Flutter Android app to manage a home Wi-Fi router (Netlink HG323): status, connected devices,
MAC blacklist, website blocking, activity log.

## Status
Phase 1 complete: full UI running against `MockRouterController` (in-memory fake data).
`NetlinkHG323Controller` is an intentional stub — capture the router admin UI's real HTTP
requests first (browser DevTools > Network while using http://192.168.1.1), then implement.

## Build
- Toolchain: Flutter SDK, Android Studio (bundled JBR), Android SDK (platform 36,
  build-tools 36.0.0).
- JAVA_HOME for builds: point it at Android Studio's bundled JBR.
- Gradle runs with `-Djava.net.preferIPv4Stack=true` — already set in
  `android/gradle.properties` and needed in `GRADLE_OPTS` for the first run.

```
flutter pub get
flutter build apk
```
Output: `build\app\outputs\flutter-apk\app-release.apk` (46.8 MB, debug-signed, installs directly).

## Install on phone
Copy the APK to the phone and open it (allow "install unknown apps" for your file manager),
or with USB debugging enabled: `adb install app-release.apk`.

## Notes
- App label: `NetGuard` · package: `com.netguard.netguard` · minSdk 24 / targetSdk 36.
- Manifest already has INTERNET permission + cleartext HTTP allowed (router admin panels).
