# Fretwise project notes

- The whole app lives in `web/index.html` (inline CSS and JS, no build step). Keep it that way until the Capacitor step needs otherwise.
- Pitch, chord and scale data are checked by script: every chord shape in `SHAPES` must spell only its formula's notes. Re-run that check after editing shapes.
- Samples in `web/samples/` are loaded with `fetch` by relative URL, so the page must be served over http(s), not opened as a file.
- Never commit App Store Connect keys (`.p8`), certificates or provisioning profiles. They belong in GitHub Actions secrets.
