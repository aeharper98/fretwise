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
  fonts/              Inter, Bricolage Grotesque, JetBrains Mono (SIL OFL)
  icons/              app icons, 1024px master included
  privacy.html        privacy policy for the App Store listing
ios/                  Capacitor iOS project (Swift Package Manager, iPhone only, portrait)
capacitor.config.json bundle ID com.aeharper98.fretwise, serves web/
.github/workflows/
  pages.yml           website deploy on every push to main
  testflight.yml      builds the iPhone app on a GitHub Mac and uploads it to TestFlight
```

## Run locally

```
cd web && python3 -m http.server 8000
```

Open http://localhost:8000. The microphone works on `localhost` and on the HTTPS site.

## Shipping to TestFlight

The **Build for TestFlight** workflow runs from the Actions tab (Run workflow) or when a `v*` tag is pushed.
It needs four repository secrets (Settings > Secrets and variables > Actions):

| Secret | Where it comes from |
| --- | --- |
| `APPLE_TEAM_ID` | developer.apple.com > Account > Membership details > Team ID |
| `ASC_KEY_ID` | App Store Connect > Users and Access > Integrations > App Store Connect API: the key's Key ID |
| `ASC_ISSUER_ID` | Same page, "Issuer ID" above the key list |
| `ASC_KEY_P8` | The full text of the downloaded `AuthKey_XXXX.p8` file, including the BEGIN/END lines |

The key needs the **Admin** role so Xcode can create the distribution certificate and profile automatically.
Build numbers come from the workflow run number; bump `MARKETING_VERSION` in the Xcode project for a new version.

Native details: `ios/App/App/AppDelegate.swift` sets the audio session to play-and-record on the
loudspeaker (works with the silent switch on); `Info.plist` holds the microphone permission text.
