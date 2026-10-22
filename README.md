# TUFApp

An unofficial Windows app for browsing and downloading ADOFAI custom levels and packs from [The Universal Forums](https://tuforums.com).

- Search levels, packs, passes, leaderboard and creators
- One-click download into your ADOFAI custom level folder
- Manage downloaded levels and check for updates

## Build

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install/windows/desktop) and Visual Studio 2022 (Desktop development with C++).

```bash
flutter pub get
flutter build windows --release
```

## License

TUFApp is licensed under the [GNU General Public License v3.0](LICENSE).

Third-party components keep their own licenses:

- [Flutter](https://github.com/flutter/flutter) and Dart packages (`http`, `path`, `path_provider`, `url_launcher`, `file_selector`, `ffi`, `webview_windows`): BSD-3-Clause
- `archive`, `cupertino_icons`: MIT
- [Roboto](https://fonts.google.com/specimen/Roboto) font: SIL Open Font License 1.1 ([`assets/fonts/OFL.txt`](assets/fonts/OFL.txt))

## Disclaimer

TUFApp is not created nor approved by 7th Beat Games or the TUF Dev Team. The TUF name and logo, level data and images belong to TUF and the level creators, and are not covered by this project's license. *A Dance of Fire and Ice* is a trademark of 7th Beat Games.
