# Multitrax Flutter App

Flutter client for the Multitrax MVP.

- **Platform targets:** iOS, Android, macOS
- **State management:** `flutter_bloc`
- **Validation:** `formz`
- **Pagination UI:** `very_good_infinite_list`
- **Navigation tests:** `mockingjay`
- **Lints:** `very_good_analysis`

## Prerequisites

- Flutter SDK (stable)
- A running Supabase instance (local defaults shown below)

## Install

```bash
flutter pub get
```

## Run

### Development flavor

```bash
flutter run --flavor development -t lib/main_development.dart \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_ANON_KEY=<supabase-anon-key>
```

### Other flavors

```bash
flutter run --flavor staging -t lib/main_staging.dart
flutter run --flavor production -t lib/main_production.dart
```

### Explicit devices

```bash
# iOS
flutter run --flavor development -t lib/main_development.dart -d ios \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_ANON_KEY=<supabase-anon-key>

# macOS
flutter run --flavor development -t lib/main_development.dart -d macos \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_ANON_KEY=<supabase-anon-key>
```

## Quality Checks

```bash
flutter analyze
flutter test
```

## Directory Guide

- `lib/app`: app bootstrap and providers
- `lib/auth`: sign-in/sign-up and auth gate
- `lib/songs`: song list/detail state, models, repository integration
- `lib/recording`: local recording abstraction (`record` plugin)
- `lib/playback`: playback cubit, waveform services, scrub widgets
- `lib/core/storage`: local cache and persistent upload queue
- `test`: unit and widget tests

## Notes for Contributors

- Exports require a rendered mix (`current_mix_version_id` exists).
- Track playback supports independent per-track play/pause.
- Waveforms are extracted from cached takes and rendered in-track + timeline views.
