# Mobile build and release

The project uses Flutter 3.44.1 / Dart 3.12.1. CI pins that SDK and checks Android
debug, unsigned Android release and unsigned iPhone release compilation. CI uses
placeholder Supabase settings and does not test the hosted backend or produce a
configured store release.

## Android

For local review with the existing app configuration:

```powershell
flutter build apk --debug --dart-define-from-file=.env
```

For a store release, copy `android/key.properties.example` to
`android/key.properties` and fill it locally using your upload keystore. Relative
keystore paths resolve from the `android` directory; Windows paths should use
forward slashes. The real properties file and `.jks`/`.keystore` files are ignored
by Git. The project does not generate or retain an upload identity for you.

```powershell
flutter build appbundle --release --dart-define-from-file=.env
```

Release builds require that configuration and never fall back to the debug
signing key. To compile release mode without a signing identity for QA only:

```powershell
flutter build apk --release --android-project-arg=smartBillingUnsignedRelease=true --dart-define-from-file=.env
```

That artifact is unsigned; it is not an installable/store-ready signed release.
Follow [Flutter's Android signing guide](https://docs.flutter.dev/deployment/android#sign-the-app)
to create and manage the actual upload identity. Store publishing and certificate
verification remain separate release steps.

## iPhone

Use macOS with Xcode. CI performs this unsigned compile check:

```sh
flutter build ios --release --no-codesign --dart-define=SUPABASE_URL=https://example.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_ci_only
```

The project uses Flutter's Swift Package Manager integration and currently targets
iOS 13.0. The installed scanner and image picker package manifests support that
target. This still needs an actual Xcode build; package declarations alone do not
prove compatibility.

For a device/TestFlight build, configure your Apple team, registered bundle ID,
signing/provisioning and the real app settings, then follow
[Flutter's iOS release guide](https://docs.flutter.dev/deployment/ios).
Unsigned compilation does not verify installation, auth callbacks, scanner,
gallery permissions, PDF sharing/printing, APNs, or store acceptance.
