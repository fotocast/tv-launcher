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
- **YouTube browser** in both apps: search YouTube and start any video on the TV with one tap, or add channels.
- **Close tab button** (⌘W in the TV Mac's browser) and **clear YouTube history** (the list of started videos).
- **Subtitles button**: toggles subtitles where the player has a key for it (YouTube: C; Joyn has none).
- **Custom shows** made of any links.
- **Manage shows from the iPhone or iPad**: add Joyn series, YouTube channels, Joyn movies and custom shows,
  rename, edit links, delete, reorder and sort (custom / recently watched / A–Z).
- **iPad layout** with a sidebar like the Mac app, and a two-column remote in landscape.
- **Key presets**: save a key layout under a name and apply it to any show (built-in: Joyn, YouTube, Standard).
- **English and German** in the Mac app and the web app (Settings → Language).
- **Settings** for auto fullscreen, start volume, number of Joyn seasons, YouTube refresh, home page sections,
  tile size, reverse scrolling, keyboard shortcuts (⌥⌘K play/pause …), server status/log/restart and backup/restore.
- **Volume and sleep timer** in the remote. With sound over HDMI (where macOS can't change the volume) the
  player's volume keys are used instead (YouTube ↑/↓/M).
- **Configurable keys per show** for play/pause, seek back/forward and fullscreen, plus a key that is pressed
  automatically after opening.
- **Remote control**: play/pause, ±10 s and fullscreen buttons. Two remote modes in the Mac app:
  - forward the laptop's keyboard and trackpad to the TV Mac
  - click on a screenshot of the TV Mac
- **One tab only**: before each start the server quits the browser cleanly, so old tabs never pile up
  (Firefox is configured not to restore them; turn off with `--close-old-tabs false`).
- **Plug & play**: the server wakes the display and dismisses the Bluetooth setup assistant, so the TV Mac
  works without a keyboard.
- **Zero configuration**: the app finds the server on your network via Bonjour.

## Requirements

- macOS 13 Ventura or later on both Macs. Intel and Apple silicon are supported, and Macs running macOS through
  OpenCore Legacy Patcher work too.
- Both Macs (and the iPhone) on the same network.
- On the TV Mac: Firefox, Google Chrome or Safari, signed in to the services you use.

## Install

There are two installers – one for each Mac. Download them from the
[latest release](https://github.com/fotocast/tv-launcher/releases/latest):

| On this Mac | Download | What it does |
|---|---|---|
| The Mac **connected to the TV** | **`TV-Launcher-Server-<version>.pkg`** | Installs the server, starts it at every login, turns off the Bluetooth setup assistant at startup and opens the Accessibility settings for you |
| Your **laptop** (or any Mac you sit at) | **`TV-Launcher-App-<version>.pkg`** | Installs the TV Launcher app and opens it – it finds the TV Mac by itself |

**Opening the installer the first time:** it is not notarized by Apple (that needs a paid developer account),
so macOS blocks it once:
- macOS 13–14: **right-click → Open → Open**.
- macOS 15 and later: double-click, then **System Settings → Privacy & Security → Open Anyway**.

Then just click **Continue → Install**. The installers show English or German depending on your Mac's language.

### After installing the server

On the TV Mac, one switch is left – System Settings opens at the right place by itself:

1. **Privacy & Security → Accessibility**: turn on **VoiceServer** (needed to press play/pause and the other keys).
   If it is not listed, add `~/TheVoiceServer/VoiceServer` with **+** (press ⇧⌘G to type the path).
2. Sign in to Joyn / YouTube in the browser once.
3. To run it like a console without keyboard and mouse: **Users & Groups → Automatically log in as …** and
   **Lock Screen → screen saver and "Require password": Never**.
4. Optional: **Screen & System Audio Recording** for **VoiceServer** – only for the "click on screen" remote mode.
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
bash scripts/build-installer.sh   # both installers → dist/TV-Launcher-App-<version>.pkg and …-Server-…
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
| `GET/POST /api/settings`, `GET /api/status`, `GET /api/log`, `POST /api/restart` | Server settings, status, log, restart |
| `GET/POST /api/volume` `{"action": "up \| down \| mute \| set"}`, `POST /api/sleep` `{"minutes"}` | Volume and sleep timer |
| `GET /api/backup`, `POST /api/restore` | Backup and restore shows, presets and settings |
| `GET /api/presets`, `POST /api/presets` `{"preset"}`, `POST /api/presets/delete` `{"id"}` | Key presets |
| `POST /api/shows/add` `{"kind": "joyn \| youtube \| custom", "input", "name"}` | Create a show from a link (default keys) |
| `POST /api/shows/delete` `{"id"}` | Delete a show |
| `POST /api/shows/order` `{"ids": [...]}` | Save the custom order |
| `GET /api/episodes?show=<id>` | Episodes of a show (cached) |
| `POST /api/refresh?show=<id>` | Reload episodes now |
| `POST /api/play` `{"show", "id"}` | Open an episode on the TV Mac |
| `POST /api/movies` `{"movie": "<joyn.de/filme/… link>", "play": bool}` | Add a Joyn movie, optionally start it |
| `POST /api/youtube` `{"video": "<YouTube link or ID>", "play": bool}` | Add a single YouTube video, optionally start it |
| `GET /api/youtube/search?q=<text>` | Search YouTube: videos, shorts and channels |
| `POST /api/youtube/clear` | Clear the list of started YouTube videos |
| `POST /api/control` `{"action": "playpause \| back \| forward \| fullscreen \| subtitles \| closetab"}` | Press the key configured for the last played show |
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

## License

TV Launcher is open source under the [MIT License](LICENSE). Contributions and forks are welcome.

## Disclaimer

This is an independent hobby project. It is not affiliated with Joyn, YouTube or any broadcaster. It only opens
the regular web pages in your own browser; you need your own accounts where required.
