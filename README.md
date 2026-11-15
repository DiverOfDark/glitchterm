# GlitchTerm

A cyberpunk watch face for the Garmin Venu 4: stacked glitch time with terminal-style readouts.

- 24-hour time with seconds
- Date, battery bar, steps, weather (weather comes from the paired phone)
- Whole-screen glitch bursts in time with your heart rate; random bursts when there is no reading
- Always-on mode: dim outline digits that shift each minute against burn-in

Built for the Venu 4 45mm (454x454). Fonts and layout for the 41mm (390x390) are included, but that
device is not yet listed in `manifest.xml`.

## Build

Needs the [Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) with the Venu 4 device
downloaded, Java, and a developer key.

```
SDK=$(cat ~/.Garmin/ConnectIQ/current-sdk.cfg)
java -jar $SDK/bin/monkeybrains.jar -o bin/glitchterm.prg -f monkey.jungle \
    -y ~/.Garmin/ConnectIQ/developer_key.der -d venu445mm -w
```

Install by copying `bin/glitchterm.prg` to `GARMIN/Apps` on the watch over USB.

## Tools

- `tools/genfonts.py` regenerates the bitmap fonts and launcher icon (needs Pillow).
- `tools/simshot.sh` runs the build in the simulator on a virtual display and saves screenshots.
  It expects an Ubuntu 22.04 distrobox with `xvfb` and `imagemagick`.

## Tuning

Burst length, frame rate and the no-heart-rate fallback are constants at the top of
`source/GlitchTermView.mc`.

## Fonts

[Orbitron](https://fonts.google.com/specimen/Orbitron) and
[Share Tech Mono](https://fonts.google.com/specimen/Share+Tech+Mono), both under the SIL Open Font
License. The licence texts are in `tools/ttf/`.
