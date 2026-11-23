# Fretwise

Learn the guitar neck in standard tuning, step by step, with a bluegrass slant.

- **Learn**: about 50 stages in six phases (home and three chords, numbers in the hand, chord tones and first breaks, off-chords and roots colour, up the neck, blues and beyond), built from the research in `reports/`. Stages pass at about 90% right and come back on spaced days until mastered.
- **Practice**: Today's practice (spaced review across every passed stage), note drill, chord quiz and a weak-spots map. All practice runs on a life-size neck (25.5" scale) where you tap or play your answers; the **Whole neck** button at the top swaps it for the normal full fretboard (handy for octave shapes and anything that spans the neck), and the choice is remembered.
- **Explore**: notes, chords and scales & keys on a tap-to-hear fretboard with a live piano strip.
- **Tune**: reference tones, a needle tuner that listens through the microphone, and a boom-chuck metronome.

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

## On a TV

In the iPhone app, AirPlay Screen Mirroring (Control Centre, Screen Mirroring, pick the Apple TV or AirPlay TV) or a cable gives the TV its own landscape view instead of a copy of the phone: the whole neck with the current question, an outline of the stretch the phone is showing, the piano lighting the notes being played or heard, and a large tuner. The phone stays the controller and shows an "On TV" badge. To preview the TV page in a browser, open http://localhost:8000/?display (it waits for the phone's snapshots, so it shows the start screen).

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
