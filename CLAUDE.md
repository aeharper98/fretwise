# Fretwise project notes

- The whole app lives in `web/index.html` (inline CSS and JS, no build step). Keep it that way until the Capacitor step needs otherwise.
- Pitch, chord and scale data are checked by script: every chord shape in `SHAPES` must spell only its formula's notes. Re-run that check after editing shapes.
- Samples in `web/samples/` are loaded with `fetch` by relative URL, so the page must be served over http(s), not opened as a file.
- Never commit App Store Connect keys (`.p8`), certificates or provisioning profiles. They belong in GitHub Actions secrets.
- iOS: Capacitor 7 with Swift Package Manager. After changing `web/`, the CI runs `npx cap sync ios`; `ios/App/App/public` is generated and not committed. Edit native files (AppDelegate.swift, Info.plist) directly.
- The iOS build cannot be run in a Linux session; it only runs in the `testflight.yml` workflow on a macOS runner.
