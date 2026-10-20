// TV Launcher – Übersetzung der Web-App (Deutsch → Englisch).
// Die Oberfläche ist auf Deutsch geschrieben. Ist Englisch gewählt (Einstellungen → Sprache,
// oder „Wie das System“ und das Gerät ist nicht deutsch), übersetzt ein MutationObserver alle
// sichtbaren Texte, Platzhalter und Beschriftungen. Inhalte (Folgen- und Videotitel) bleiben unverändert.
"use strict";

const I18N_EN = {
  // Navigation
  "TV Launcher": "TV Launcher",
  "Mediathek": "Library",
  "YouTube": "YouTube",
  "Fernbedienung": "Remote",
  "Shows": "Shows",
  "Shows verwalten": "Manage shows",
  "Einstellungen": "Settings",
  "Suchen": "Search",
  "Suche": "Search",
  "Neu laden": "Reload",
  "Shows sortieren": "Sort shows",
  "Eigene Reihenfolge": "Custom order",
  "Zuletzt gesehen": "Recently watched",
  "Name (A–Z)": "Name (A–Z)",
  "Ausklappen": "Expand",
  "Einklappen": "Collapse",

  // Mediathek
  "Weiterschauen": "Continue",
  "Nächste": "Next",
  "Abspielen": "Play",
  "Link einfügen": "Paste a link",
  "zuletzt": "last",
  "Shorts": "Shorts",
  "Videos": "Videos",
  "Filme": "Movies",
  "YouTube-Videos": "YouTube videos",
  "Joyn-Film": "Joyn movie",
  "Keine Folge gefunden": "No episode found",
  "Keine Folgen gefunden": "No episodes found",
  "Keine Videos gefunden": "No videos found",
  "Keine Verbindung zum Mac mini.": "No connection to the TV Mac.",
  "Lädt …": "Loading …",
  "Joyn-Filmlink einfügen (joyn.de/filme/…)": "Paste a Joyn movie link (joyn.de/filme/…)",
  "YouTube-Link einfügen": "Paste a YouTube link",
  "Noch keine Filme – oben einen Joyn-Filmlink einfügen.": "No movies yet – paste a Joyn movie link above.",
  "Noch keine Links – unter „Shows“ die Show öffnen und Links eintragen.": "No links yet – open the show under “Shows” and add links.",
  "Noch keine Videos – oben einen YouTube-Link einfügen.": "No videos yet – paste a YouTube link above.",
  "Verlauf löschen": "Clear history",
  "Läuft auf dem Mac mini": "Playing on the TV Mac",
  "Läuft am Fernseher": "Playing on the TV",
  "Bitte einen YouTube-Link oder einen Joyn-Filmlink einfügen.": "Please paste a YouTube link or a Joyn movie link.",

  // YouTube
  "YouTube durchsuchen oder Link einfügen": "Search YouTube or paste a link",
  "Tippe auf ein Video – es startet am Fernseher. Kanäle fügst du mit + als Show hinzu.":
    "Tap a video – it starts on the TV. Add channels as shows with +.",
  "Zuletzt gestartet": "Recently started",
  "Suche läuft …": "Searching …",
  "Suche nach Videos oder Kanälen.": "Search for videos or channels.",
  "Nichts gefunden.": "Nothing found.",
  "Kanal": "Channel",
  "Hinzugefügt": "Added",
  "YouTube-Verlauf gelöscht": "YouTube history cleared",

  // Fernbedienung
  "Video-Link abspielen": "Play a video link",
  "YouTube- oder Joyn-Link": "YouTube or Joyn link",
  "Teilen → Link kopieren in der YouTube-App, hier einfügen – das Video startet am Fernseher.":
    "In the YouTube app: Share → Copy link, paste it here – the video starts on the TV.",
  "10 Sekunden zurück": "Back 10 seconds",
  "10 Sekunden vor": "Forward 10 seconds",
  "Pause oder weiter": "Pause or resume",
  "Vollbild": "Fullscreen",
  "Untertitel": "Subtitles",
  "Tab schließen": "Close tab",
  "Browser-Tab am Mac schließen (⌘W)": "Close the browser tab on the TV Mac (⌘W)",
  "Für diese Show gibt es keine Untertitel-Taste (z. B. Joyn)": "This show has no subtitles key (e.g. Joyn)",
  "Leiser": "Volume down",
  "Lauter": "Volume up",
  "Ton aus/an": "Mute / unmute",
  "stumm": "muted",
  "Sleep-Timer": "Sleep timer",
  "Sleep-Timer aus": "Sleep timer off",
  "Aus": "Off",
  "Trackpad": "Trackpad",
  "1 Finger bewegen = Zeiger": "Move 1 finger = pointer",
  "Tippen = Klick · Doppeltippen = Doppelklick": "Tap = click · double tap = double click",
  "2 Finger bewegen = Scrollen · 2 Finger tippen = Rechtsklick": "Move 2 fingers = scroll · tap 2 fingers = right click",
  "Tasten": "Keys",
  "Leertaste": "Space",
  "esc": "esc",

  // Shows verwalten
  "Hinzufügen": "Add",
  "Joyn-Serie": "Joyn series",
  "Eigene": "Custom",
  "Name (optional)": "Name (optional)",
  "Name der Show": "Show name",
  "Link: joyn.de/serien/…": "Link: joyn.de/serien/…",
  "Link: joyn.de/filme/…": "Link: joyn.de/filme/…",
  "Kanal-Link, @Name oder Video-Link": "Channel link, @name or video link",
  "Auf joyn.de die Seite der Serie öffnen, Link kopieren und hier einfügen. Ohne Name wird der Name von Joyn übernommen.":
    "Open the series page on joyn.de, copy the link and paste it here. Without a name, Joyn's name is used.",
  "Kanal-Link, @Name oder der Link eines Videos aus dem Kanal. Videos und Shorts werden alle 30 Minuten geladen.":
    "Channel link, @name or the link of a video from the channel. Videos and shorts are refreshed regularly.",
  "Der Film landet in der Sammlung „Filme“ und startet von dort mit einem Tipp.":
    "The movie goes into the “Movies” collection and starts from there with one tap.",
  "Leere Show anlegen – danach öffnet sie sich und du trägst beliebige Links ein.":
    "Create an empty show – it opens right away so you can add any links.",
  "Bitte zuerst einen Link einfügen.": "Please paste a link first.",
  "Sortierung": "Sorting",
  "Zuletzt": "Recent",
  "A–Z": "A–Z",
  "Deine Shows": "Your shows",
  "Nach oben": "Move up",
  "Nach unten": "Move down",
  "Mit ↑ ↓ ordnest du die Shows (eigene Reihenfolge). Tippen öffnet die Show zum Bearbeiten. Tasten für Play/Pause, Spulen und Vollbild stellst du in der Mac-App ein.":
    "Use ↑ ↓ to reorder the shows (custom order). Tap a show to edit it. Keys for play/pause, seeking and fullscreen are set in the Mac app.",
  "YouTube-Kanal": "YouTube channel",
  "Joyn-Filme": "Joyn movies",
  "Eigene Links": "Custom links",

  // Bearbeiten
  "Abbrechen": "Cancel",
  "Sichern": "Save",
  "Gesichert": "Saved",
  "Show": "Show",
  "Name": "Name",
  "Auf Joyn ansehen": "View on Joyn",
  "Kanal auf YouTube": "Channel on YouTube",
  "Links": "Links",
  "Titel": "Title",
  "Link hinzufügen": "Add link",
  "Entfernen": "Remove",
  "Jeder Link erscheint als eigene „Folge“ und wird im Browser am Mac am Fernseher geöffnet.":
    "Each link shows up as its own “episode” and opens in the browser on the TV Mac.",
  "Noch keine Filme.": "No movies yet.",
  "Tasten am Mac": "Keys on the TV Mac",
  "Preset": "Preset",
  "Eigene Belegung": "Custom layout",
  "Pause/Weiter": "Play/Pause",
  "Zurück": "Back",
  "Vor": "Forward",
  "Beim Start": "On start",
  "Keine": "None",
  "Doppelklick Bildmitte": "Double-click center",
  "Belegung als Preset sichern …": "Save layout as preset …",
  "Presets gelten für alle Shows, in der App und hier. Einzelne Tasten änderst du in der Mac-App unter Einstellungen → Shows.":
    "Presets work for all shows, in the app and here. Change single keys in the Mac app under Settings → Shows.",
  "Name für das Preset, z. B. ARD Mediathek:": "Name for the preset, e.g. ARD Mediathek:",
  "Show löschen": "Delete show",
  "Die Show braucht einen Namen.": "The show needs a name.",
  "Neue Show": "New show",

  // Einstellungen
  "Allgemein": "General",
  "Sprache": "Language",
  "Wie das System": "Same as system",
  "Deutsch": "Deutsch",
  "English": "English",
  "Weiterschauen-Karte": "Continue card",
  "Beim Start eines Videos": "When a video starts",
  "Automatisch Vollbild": "Fullscreen automatically",
  "Wartezeit": "Delay",
  "Lautstärke festlegen": "Set volume",
  "Lautstärke": "Volume",
  "Vollbild nutzt die Taste der Show (Joyn: Doppelklick auf die Bildmitte, YouTube: F).":
    "Fullscreen uses the show's key (Joyn: double-click in the center, YouTube: F).",
  "Inhalte": "Content",
  "Joyn-Staffeln": "Joyn seasons",
  "Alle": "All",
  "YouTube aktualisieren": "Refresh YouTube",
  "jede Stunde": "every hour",
  "Fernsteuerung (dieses Gerät)": "Remote control (this device)",
  "Trackpad-Tempo": "Trackpad speed",
  "Scrollrichtung umkehren": "Reverse scrolling",
  "Mac mini": "TV Mac",
  "Log anzeigen": "Show log",
  "Server neu starten": "Restart server",
  "Sicherung": "Backup",
  "Sicherung herunterladen": "Download backup",
  "Sicherung einspielen …": "Restore backup …",
  "Enthält alle Shows, eigene Tasten-Presets und die Einstellungen des Mac mini.":
    "Contains all shows, your key presets and the TV Mac's settings.",
  "Version": "Version",
  "Rechner": "Computer",
  "Browser": "Browser",
  "alte Tabs schließen": "closes old tabs",
  "Bedienungshilfen": "Accessibility",
  "Bildschirmaufnahme": "Screen recording",
  "erlaubt": "allowed",
  "fehlt": "missing",
  "Läuft seit": "Running since",
  "Status": "Status",
  "In der App (YouTube, Netflix, Prime Video, Disney+) teilen → Link kopieren, hier einfügen – es startet am Fernseher.":
    "In the app (YouTube, Netflix, Prime Video, Disney+): Share → Copy link, paste it here – it starts on the TV.",
  "Link: YouTube, Joyn, Netflix, Prime, Disney+": "Link: YouTube, Joyn, Netflix, Prime, Disney+",
  "Bitte einen YouTube-, Joyn-, Netflix-, Prime-Video- oder Disney+-Link einfügen.": "Please paste a YouTube, Joyn, Netflix, Prime Video or Disney+ link.",
  "Netflix-Link einfügen": "Paste a Netflix link",
  "Prime Video-Link einfügen": "Paste a Prime Video link",
  "Disney+-Link einfügen": "Paste a Disney+ link",
  "Link: netflix.com/title/…": "Link: netflix.com/title/…",
  "Link: primevideo.com/detail/…": "Link: primevideo.com/detail/…",
  "Link aus der Disney+-App": "Link from the Disney+ app",
  "Netflix-Titel teilen bzw. Link kopieren (netflix.com/title/…). Alle Staffeln und Folgen werden geladen.":
    "Share a Netflix title or copy its link (netflix.com/title/…). All seasons and episodes are loaded.",
  "Link einer Staffel von Prime Video. Die Folgen werden geladen; jede Folge startet die Staffel mit Autoplay.":
    "Link to a Prime Video season. The episodes are loaded; each episode starts the season with autoplay.",
  "In der Disney+-App teilen → Link kopieren. Der Titel landet in der Sammlung „Disney+“.":
    "In the Disney+ app: Share → Copy link. The title goes into the “Disney+” collection.",
  "Auf Netflix ansehen": "View on Netflix",
  "Auf Prime Video ansehen": "View on Prime Video",
  "Netflix-Film": "Netflix movie",
  "Browser am Mac mini": "Browser on the TV Mac",
  "Wie bei der Installation": "As set at installation",
  "Anderer Browser …": "Other browser …",
  "Name der Browser-App am Mac mini, z. B. Brave Browser:": "Name of the browser app on the TV Mac, e.g. Brave Browser:",
  "Netflix, Prime Video und Disney+ brauchen einen Browser mit Kopierschutz-Unterstützung. Im gewählten Browser einmal bei den Diensten anmelden.":
    "Netflix, Prime Video and Disney+ need a browser with copy-protection (DRM) support. Sign in to the services once in the chosen browser.",
  "Neuer Ordner": "New folder",
  "Anlegen": "Create",
  "Name des Ordners, z. B. Castingshows": "Folder name, e.g. Talent shows",
  "Welche Shows sollen hinein?": "Which shows go in?",
  "Gibt es den Ordner schon, kommen die angekreuzten Shows dazu.": "If the folder already exists, the checked shows are added to it.",
  "Bitte einen Namen für den Ordner eingeben.": "Please enter a folder name.",
  "Bitte mindestens eine Show ankreuzen.": "Please check at least one show.",
  "Ordner „{name}“ angelegt": "Folder “{name}” created",
  "Port": "Port",
  "Port ändern …": "Change port …",
  "Neuer Port für den Server (1024–65535):": "New port for the server (1024–65535):",
  "Bitte einen Port zwischen 1024 und 65535 wählen.": "Please choose a port between 1024 and 65535.",
  "Eigene Knöpfe": "Custom buttons",
  "Noch keine eigenen Knöpfe.": "No custom buttons yet.",
  "Knopf hinzufügen": "Add button",
  "Neuer Knopf": "New button",
  "Vorschlag": "Suggestion",
  "Auswählen …": "Choose …",
  "Nichts": "Nothing",
  "Eigener Knopf": "Custom button",
  "Nächstes Video": "Next video",
  "Vorheriges Video": "Previous video",
  "Schneller": "Faster",
  "Langsamer": "Slower",
  "Zum Anfang": "Back to start",
  "Kinomodus": "Theater mode",
  "Miniplayer": "Miniplayer",
  "Vollbild verlassen": "Exit fullscreen",
  "Bestätigen": "Confirm",
  "Pos1": "Home",
  "Ende": "End",
  "Bild↑": "Page↑",
  "Bild↓": "Page↓",
  "Erscheinen in der Fernbedienung, solange diese Show läuft – z. B. „Nächstes Video“ mit ⇧N bei YouTube.":
    "Show up in the remote while this show is playing – e.g. “Next video” with ⇧N on YouTube.",
  "Ordner": "Folder",
  "Kein Ordner": "No folder",
  "Umbenennen": "Rename",
  "Auflösen": "Remove folder",
  "Neuer Name für den Ordner „{name}“:": "New name for the folder “{name}”:",
  "Ordner „{name}“ auflösen?\nDie Shows bleiben erhalten.": "Remove the folder “{name}”?\nThe shows are kept.",
  "Lautstärke im Player": "Volume in the player",
  "{n} Sekunden": "{n} seconds",
  "bis {time}": "until {time}",
  "Sleep-Timer: {n} Min.": "Sleep timer: {n} min",
  "Die neuesten {n}": "Newest {n}",
  "alle {n} Minuten": "every {n} minutes",
  "Das ist keine TV-Launcher-Sicherung.": "This is not a TV Launcher backup.",
  "Sicherung eingespielt": "Backup restored",
  "Server neu starten?\nEr ist in wenigen Sekunden wieder da.": "Restart the server?\nIt will be back in a few seconds.",
  "Sicherung einspielen?\nAlle Shows, Presets und Einstellungen des Mac mini werden ersetzt.":
    "Restore backup?\nAll shows, presets and settings of the TV Mac will be replaced.",
  "YouTube-Verlauf löschen?\nDie Liste „YouTube-Videos“ wird geleert – in der App und hier. Kanäle bleiben.":
    "Clear YouTube history?\nThe “YouTube videos” list is emptied – in the app and here. Channels stay.",
};

// Texte mit Zahlen oder Namen: [Muster, Ersetzung] – werden der Reihe nach auf den ganzen Text angewendet
const I18N_EN_PATTERNS = [
  [/^Staffel (\d+), Folge (\d+)$/, "Season $1, episode $2"],
  [/Staffel (\d+)/g, "Season $1"],
  [/^Folge (\d+)$/, "Episode $1"],
  [/^Nr\. (\d+)$/, "No. $1"],
  [/^S(\d+) F(\d+)$/, "S$1 E$2"],
  [/(\d+) Folgen/g, "$1 episodes"],
  [/(\d+) Staffeln/g, "$1 seasons"],
  [/\b1 Video\b/g, "1 video"],
  [/(\d+) Videos/g, "$1 videos"],
  [/(\d+) Shorts/g, "$1 shorts"],
  [/\b1 Link\b/g, "1 link"],
  [/(\d+) Links/g, "$1 links"],
  [/\b1 Film\b/g, "1 movie"],
  [/^1 Titel$/, "1 title"],
  [/^(\d+) Titel$/, "$1 titles"],
  [/(\d+) Filme/g, "$1 movies"],
  [/^(\d+) Min\.$/, "$1 min"],
  [/^Die neuesten (\d+)$/, "Newest $1"],
  [/^alle (\d+) Minuten$/, "every $1 minutes"],
  [/^alle (\d+) Stunden$/, "every $1 hours"],
  [/^(\d+) Sekunden$/, "$1 seconds"],
  [/^Nächste: (.+)$/, "Next: $1"],
  [/^Zuletzt gesehen · /, "Last watched · "],
  [/^Zuletzt gestartet · /, "Last started · "],
  [/^„(.+)“ hinzugefügt$/, "“$1” added"],
  [/^„(.+)“ gelöscht$/, "“$1” deleted"],
  [/^„(.+)“ übernommen – zum Speichern „Sichern“ tippen$/, "“$1” applied – tap “Save” to keep it"],
  [/^Preset „(.+)“ gesichert$/, "Preset “$1” saved"],
  [/^„(.+)“ löschen\?\nDie Show verschwindet aus der App und der Web-App\.$/, "Delete “$1”?\nThe show disappears from the app and the web app."],
  [/^Mac mini nicht erreichbar: /, "TV Mac not reachable: "],
  [/^Abspielen fehlgeschlagen: /, "Playback failed: "],
  [/^Reihenfolge nicht gespeichert: /, "Order not saved: "],
  [/^Untertitel an\/aus \((.+)\)$/, "Subtitles on/off ($1)"],
  [/^bis (.+)$/, "until $1"],
  [/^Lautstärke im Player \((.+)\)$/, "Volume in the player ($1)"],
  [/^Sleep-Timer: (\d+) Min\.$/, "Sleep timer: $1 min"],
  [/ \(eigenes\)$/, " (custom)"],
  [/ läuft auf dem Mac mini$/, " is playing on the TV Mac"],
  [/ zu YouTube-Videos hinzugefügt$/, " added to YouTube videos"],
  [/^vor (\d+) Min\.$/, "$1 min ago"],
  [/^vor (\d+) Std\.$/, "$1 h ago"],
  [/^vor (\d+) Tagen$/, "$1 days ago"],
  [/^vor 1 Tag$/, "1 day ago"],
  [/^vor (\d+) Wochen$/, "$1 weeks ago"],
  [/^vor (\d+)\s+Monaten$/, "$1 months ago"],
  [/^vor (\d+) Jahren$/, "$1 years ago"],
  [/ Aufrufe\b/g, " views"],
];

// Inhalte, die nie übersetzt werden (Titel von Folgen, Videos, Shows)
const I18N_SKIP = ".row-title-text, .card-title, .hero-title, .hero-subtitle, .now-title, .now-subtitle, .movie-title, .yt-channel-name, .manage-name, .side-show-name, .sheet-head h2, pre, input, textarea";

function lang() {
  let choice = "system";
  try { choice = JSON.parse(localStorage.getItem("lang")) || "system"; } catch (_) { /* privater Modus */ }
  if (choice === "system") return (navigator.language || "de").toLowerCase().startsWith("de") ? "de" : "en";
  return choice;
}

const I18N_ACTIVE = lang() === "en";
document.documentElement.lang = lang();

/// Übersetzt einen Text der Oberfläche; `{name}` wird durch `vars.name` ersetzt
function t(text, vars) {
  let result = I18N_ACTIVE ? translateText(text) : text;
  if (vars) for (const [key, value] of Object.entries(vars)) result = result.replaceAll(`{${key}}`, value);
  return result;
}

function translateText(text) {
  if (!I18N_ACTIVE || !text) return text;
  const trimmed = text.trim();
  if (!trimmed) return text;
  // Zeilenumbrüche aus dem HTML wie Leerzeichen behandeln (Zeilenumbrüche in confirm-Texten bleiben)
  const key = /\n\S/.test(trimmed) ? trimmed : trimmed.replace(/\s*\n\s*/g, " ");
  if (Object.prototype.hasOwnProperty.call(I18N_EN, key)) return text.replace(trimmed, I18N_EN[key]);
  let result = trimmed;
  for (const [pattern, replacement] of I18N_EN_PATTERNS) result = result.replace(pattern, replacement);
  return result === trimmed ? text : text.replace(trimmed, result);
}

function translateNode(node) {
  if (node.nodeType === Node.TEXT_NODE) {
    if (node.parentElement?.closest(I18N_SKIP)) return;
    const translated = translateText(node.nodeValue);
    if (translated !== node.nodeValue) node.nodeValue = translated;
    return;
  }
  if (node.nodeType !== Node.ELEMENT_NODE || node.matches?.("script, style, svg")) return;
  for (const attribute of ["placeholder", "aria-label", "title"]) {
    const value = node.getAttribute?.(attribute);
    if (value) {
      const translated = translateText(value);
      if (translated !== value) node.setAttribute(attribute, translated);
    }
  }
  for (const child of node.childNodes) translateNode(child);
}

if (I18N_ACTIVE) {
  // confirm()/prompt() zeigen ihre Texte übersetzt
  const nativeConfirm = window.confirm.bind(window);
  const nativePrompt = window.prompt.bind(window);
  window.confirm = (message) => nativeConfirm(translateText(message));
  window.prompt = (message, value) => nativePrompt(translateText(message), value);

  const start = () => {
    translateNode(document.body);
    new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        if (mutation.type === "characterData") translateNode(mutation.target);
        else if (mutation.type === "attributes") translateNode(mutation.target);
        else mutation.addedNodes.forEach(translateNode);
      }
    }).observe(document.body, {
      childList: true, subtree: true, characterData: true,
      attributes: true, attributeFilter: ["placeholder", "aria-label", "title"],
    });
  };
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start);
  else start();
}
