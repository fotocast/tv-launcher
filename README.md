# TV Launcher

Turn a Mac connected to your TV into a one-click media launcher. Start Joyn series and movies,
YouTube channels and videos, and your own links. Control everything from a Mac app or an iPhone web app.

```
Your laptop / iPhone                   Mac connected to the TV (server)
┌──────────────────────┐   HTTP :8081  ┌───────────────────────────────────┐
│ TV Launcher app      │ ────────────▶ │ VoiceServer                       │
│ (SwiftUI, macOS)     │               │  • reads episodes from joyn.de    │
└──────────────────────┘               │  • reads YouTube channels         │
┌──────────────────────┐               │  • opens them in the browser      │
│ Web app (iPhone)     │ ────────────▶ │  • presses play, seek, fullscreen │
│ (Safari, Home Screen)│               │  • serves the web app             │
└──────────────────────┘               └───────────────────────────────────┘
```

> The user interface is currently in **German**. Joyn is a German streaming service; YouTube and custom
> links work everywhere.

## Features

- **Home page** with a "continue watching" card, the newest episodes, and tiles for all series, YouTube
  channels, movies, recently started videos and custom shows.
- **Joyn series**: the current and previous season are read automatically from joyn.de.
- **Joyn movies**: search them in the built-in browser, keep them in a "Filme" collection, or paste a link.
- **YouTube channels** with thumbnails, split into videos and shorts. Refreshed every 30 minutes.
- **Single YouTube videos**: paste a link in the iPhone web app (YouTube app → Share → Copy link).
- **Custom shows** made of any links.
- **Configurable keys per show** for play/pause, seek back/forward and fullscreen, plus a key that is pressed
  automatically after opening.
- **Remote control**: play/pause, ±10 s and fullscreen buttons. Two remote modes in the Mac app:
  - forward the laptop's keyboard and trackpad to the TV Mac
  - click on a screenshot of the TV Mac
- **Plug & play**: the server wakes the display and dismisses the Bluetooth setup assistant, so the TV Mac
  works without a keyboard.
- **Zero configuration**: the app finds the server on your network via Bonjour.

## Requirements

- macOS 13 Ventura or later on both Macs. Intel and Apple silicon are supported, and Macs running macOS through
  OpenCore Legacy Patcher work too.
- Both Macs (and the iPhone) on the same network.
- On the TV Mac: Firefox, Google Chrome or Safari, signed in to the services you use.

## Install

1. Download **`TV-Launcher-<version>.pkg`** from the
   [latest release](https://github.com/fotocast/tv-launcher/releases/latest).
2. Open it. The package is not notarized by Apple, so macOS blocks it the first time:
   - macOS 13–14: **right-click → Open → Open**.
   - macOS 15 and later: double-click, then go to **System Settings → Privacy & Security** and click
     **Open Anyway**.
3. Choose what to install on this Mac:
   - **App (remote control)** for the Mac you sit at.
   - **Server (Mac connected to the TV)** for the TV Mac. You can install both on one Mac.

### After installing the server

On the TV Mac:

1. **System Settings → Privacy & Security → Accessibility**: turn on **VoiceServer**. It needs this to press
   play/pause and the other keys. If it is not listed, add `~/TheVoiceServer/VoiceServer` with **+**.
2. Optional: **Screen & System Audio Recording** for **VoiceServer**. This is only needed for the
   "Bildschirm anklicken" (click on the screen) remote mode.
3. Sign in to Joyn / YouTube in the browser.
4. To run it without a keyboard: **Users & Groups → Automatically log in as …** and
   **Lock Screen → Require password after screen saver begins: Never**.
5. If the firewall asks whether to accept incoming connections, click **Allow**.

### Use it

- **Mac app**: open *TV Launcher*. It finds the server automatically. You can also set the address in
  *Settings (⌘,) → Allgemein*.
- **iPhone**: open `http://<name-of-the-TV-Mac>.local:8081` in Safari, then **Share → Add to Home Screen**.
  The app's settings show the exact address.
- **Add shows**: *Settings → Shows → +*. Choose a Joyn series or movie (built-in browser), a YouTube channel
  or a custom show with links.

### Uninstall

```bash
sudo bash "/Library/Application Support/TV Launcher/uninstall.sh"
```

Your saved shows stay in `~/Library/Application Support/TheVoiceServer/` on the TV Mac.

## Build from source

Requires Xcode or the Command Line Tools (`xcode-select --install`). There are no third-party dependencies.

```bash
bash scripts/build-installer.sh   # universal installer → dist/TV-Launcher-<version>.pkg
bash scripts/build-app.sh         # build the app only and copy it to /Applications
```

For development you can also deploy the server over SSH. Copy `scripts/config.example.sh` to
`scripts/config.sh`, fill in the TV Mac's address and user, then run:

```bash
bash scripts/install-server.sh
```

`scripts/sign-server.sh` signs the server with a self-signed certificate that is created once in
`~/Library/Application Support/TheVoiceBuild/`. Because the signature stays stable, the Accessibility
permission survives reinstalls.

### Project layout

| Folder | Contents |
|---|---|
| `Sources/VoiceCore` | Shared models (`Show`, `Episode`, API types), the Joyn catalog reader, YouTube channel reader |
| `Sources/VoiceServer` | HTTP server (Network.framework), playback, key presses, screenshots, Bonjour |
| `Sources/VoiceApp` | SwiftUI Mac app |
| `Public` | iPhone web app (plain HTML/CSS/JS, served by the server) |
| `installer` | Installer pages and scripts used by `build-installer.sh` |
| `scripts` | Build and install scripts |

## HTTP API

The server listens on port 8081. All bodies are JSON.

| Request | Description |
|---|---|
| `GET /api/health` | `{"ok": true}` |
| `GET /api/shows` | All shows in custom order, last played episode, `playedAt` per show |
| `POST /api/shows` `{"show": {...}}` | Create or update a show |
| `POST /api/shows/delete` `{"id"}` | Delete a show |
| `POST /api/shows/order` `{"ids": [...]}` | Save the custom order |
| `GET /api/episodes?show=<id>` | Episodes of a show (cached) |
| `POST /api/refresh?show=<id>` | Reload episodes now |
| `POST /api/play` `{"show", "id"}` | Open an episode on the TV Mac |
| `POST /api/movies` `{"movie": "<joyn.de/filme/… link>", "play": bool}` | Add a Joyn movie, optionally start it |
| `POST /api/youtube` `{"video": "<YouTube link or ID>", "play": bool}` | Add a single YouTube video, optionally start it |
| `POST /api/control` `{"action": "playpause \| back \| forward \| fullscreen"}` | Press the key configured for the last played show |
| `POST /api/input` `{"events": [...]}` | Remote input: keys, pointer moves, clicks, scrolling |
| `GET /api/screenshot` | JPEG of the TV Mac's main display |

## Troubleshooting

- **A video opens but does not start**: the server presses the show's start key after opening. That requires
  the Accessibility permission for VoiceServer (see above).
- **The app cannot find the server**: make sure both Macs are on the same network, and that "Local Network" is
  allowed for TV Launcher in *System Settings → Privacy & Security → Local Network*. Or enter the address
  manually in the app's settings.
- **Server log** (on the TV Mac): `tail -f ~/Library/Logs/TheVoiceServer.log`
- **Restart the server** (on the TV Mac):
  `launchctl kickstart -k gui/$(id -u)/io.github.fotocast.tvlauncher.server`

## Disclaimer

This is an independent hobby project. It is not affiliated with Joyn, YouTube or any broadcaster. It only opens
the regular web pages in your own browser; you need your own accounts where required.
