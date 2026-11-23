# Fretwise project notes

- The whole app lives in `web/index.html` (inline CSS and JS, no build step). Keep it that way until the Capacitor step needs otherwise.
- Pitch, chord and scale data are checked by script: every chord shape in `SHAPES` must spell only its formula's notes. Re-run that check after editing shapes.
- Samples in `web/samples/` are loaded with `fetch` by relative URL, so the page must be served over http(s), not opened as a file.
- Never commit App Store Connect keys (`.p8`), certificates or provisioning profiles. They belong in GitHub Actions secrets.
- iOS: Capacitor 7 with Swift Package Manager. After changing `web/`, the CI runs `npx cap sync ios`; `ios/App/App/public` is generated and not committed. Edit native files (AppDelegate.swift, Info.plist) directly.
- The iOS build cannot be run in a Linux session; it only runs in the `testflight.yml` workflow on a macOS runner.
- The Learn path is `LEARN_ALL` in `web/index.html`. Stage kinds `notes`, `chords`, `bass`, `ear`, `numbers` are handled inline; newer kinds live in the `KINDS` registry (each has `study()` for the stage page and `gen()` for practice questions run by `Life`). Stage ids are stored in progress, so never rename an id; add new ones instead.
- Passing: a stage passes when about 90% of the last N answers are right (`passWindow`). Passed stages are re-checked by `Review` on spaced days (1, 3, 7, 16, 35) through Today's practice; two clean re-checks mark them mastered.
- `?fwtest` in the page address exposes `window.__fw` for automated checks; the stage-walk test answers every stage to completion with it.
- Microphone on iPhone: never switch the audio session while listening. In the app the page asks WebKit for `play-and-record` from the first tap (matching AppDelegate); in browsers it uses `playback` until the mic is first used, then stays on `play-and-record`. `Mic` builds its analyser on its own AudioContext made after `getUserMedia`, and rebuilds the input if it reads exact zeros for about 1.2 s.
