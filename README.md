# Fretwise

Learn the guitar neck in standard tuning, step by step, with a bluegrass slant.

- **Learn**: 19 stages, from the open strings to the whole neck, then G-C-D chords, boom-chuck bass and the number system.
- **Explore, Drill, Chords, Scales & Keys**: a tap-to-hear fretboard with a live piano strip.
- **Life-size**: the screen becomes the neck at real scale (25.5" steel string). Swipe to slide along it.
- **Tuner**: reference tones, and a needle tuner that listens through the microphone.

Live site: https://aeharper98.github.io/fretwise/

## Layout

```
web/                  the app (plain HTML/CSS/JS, no build step)
  index.html
  samples/            acoustic guitar samples (see samples/CREDITS.md)
  icons/              app icons, 1024px master included
  privacy.html        privacy policy for the App Store listing
.github/workflows/    website deploy (GitHub Pages)
```

## Run locally

```
cd web && python3 -m http.server 8000
```

Open http://localhost:8000. The microphone works on `localhost` and on the HTTPS site.

## Roadmap to the App Store

1. Website on GitHub Pages (done when Pages is switched on).
2. Wrap `web/` with Capacitor as a native iOS app; add the microphone permission text and a small native audio-session fix so sound stays on the speaker while listening.
3. GitHub Actions build on a macOS runner that signs with an App Store Connect API key and uploads to TestFlight.
4. App Store listing: screenshots, description, privacy policy (`web/privacy.html`).
