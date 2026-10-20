// TV Launcher – Web-App fürs iPhone und iPad.
// Spricht nur relative Adressen (/api/...) an. Ab 768 px Breite (iPad) gibt es statt der Tab-Leiste
// eine Seitenleiste mit allen Shows wie in der Mac-App.
"use strict";

const state = {
  shows: [],
  episodes: {},        // Show-ID → Folgen
  lastPlayedByShow: {}, // Show-ID → Folgen-ID
  lastPlayed: null,    // {show, id} – zuletzt gestartet über alle Shows
  show: null,          // ausgewählte Show
  season: null,
  group: "Videos",     // YouTube: "Videos" oder "Shorts"
  search: "",
  playingKey: null,
  loading: false,
  playedAt: {},        // Show-ID → Zeitpunkt (ISO) des letzten Starts
  tab: "episodes",
  sort: "custom",      // "custom" | "recent" | "name"
  collapsed: new Set(), // eingeklappte Shows in der Seitenleiste
  addKind: "joyn",
  editing: null,       // Kopie der Show im Bearbeiten-Fenster
  yt: { query: "", videos: [], channels: [], loading: false, playing: null },
  presets: [],         // Tasten-Presets (eingebaute Vorlagen zuerst)
  server: { settings: null, status: null }, // Einstellungen und Zustand des Mac mini
};

const wide = window.matchMedia("(min-width: 768px)");

const $ = (id) => document.getElementById(id);

// ---------- Schnittstelle ----------

async function api(path, body) {
  // Meldungen des Servers in der gewählten Sprache
  const options = body === undefined
    ? { cache: "no-store", headers: { "Accept-Language": lang() } }
    : { method: "POST", headers: { "Content-Type": "application/json", "Accept-Language": lang() }, body: JSON.stringify(body) };
  const response = await fetch(path, options);
  let data = {};
  try { data = await response.json(); } catch (_) { /* leere Antwort */ }
  if (!response.ok) throw new Error(data.error || `Server-Fehler ${response.status}`);
  return data;
}

async function loadShow(id, refresh) {
  const path = `/api/${refresh ? "refresh" : "episodes"}?show=${encodeURIComponent(id)}`;
  const data = await api(path, refresh ? {} : undefined);
  state.episodes[id] = (data.episodes || []).map((e) => ({ ...e, show: e.show || id }));
  state.lastPlayedByShow[id] = data.lastPlayedID || null;
}

async function load(refresh = false) {
  if (state.loading) return;
  state.loading = true;
  setSpinning(true);
  try {
    applyShows(await api("/api/shows"));
    if (!state.shows.some((s) => s.id === state.show)) {
      state.show = state.lastPlayed?.show || state.shows[0]?.id || null;
    }
    render();
    // Beim Aktualisieren nur die ausgewählte Show neu von Joyn laden, die anderen aus dem Speicher
    const results = await Promise.allSettled(
      state.shows.map((s) => loadShow(s.id, refresh && s.id === state.show)));
    const failed = results.filter((r) => r.status === "rejected");
    if (failed.length) toast(failed[0].reason.message, true);
    if (!seasons().includes(state.season)) state.season = seasons()[0] ?? null;
    render();
  } catch (error) {
    toast(`Mac mini nicht erreichbar: ${error.message}`, true);
    if (!state.shows.length) showEmpty("Keine Verbindung zum Mac mini.");
  } finally {
    state.loading = false;
    setSpinning(false);
  }
}

function applyShows(data) {
  state.shows = data.shows || [];
  state.lastPlayed = data.lastPlayed || null;
  state.playedAt = data.playedAt || {};
}

function setSpinning(on) {
  for (const button of document.querySelectorAll(".refresh-button")) button.classList.toggle("spinning", on);
}

async function play(episode) {
  if (state.playingKey) return;
  state.playingKey = key(episode);
  render();
  try {
    const data = await api("/api/play", { show: episode.show, id: episode.id });
    state.lastPlayed = { show: episode.show, id: episode.id };
    state.lastPlayedByShow[episode.show] = episode.id;
    state.playedAt[episode.show] = new Date().toISOString();
    toast(data.message || "Läuft auf dem Mac mini");
  } catch (error) {
    toast(`Abspielen fehlgeschlagen: ${error.message}`, true);
  } finally {
    state.playingKey = null;
    render();
  }
}

async function control(action) {
  try {
    const data = await api("/api/control", { action });
    toast(data.message);
  } catch (error) {
    toast(error.message, true);
  }
}

// ---------- Hilfen ----------

const YOUTUBE_VIDEOS = "custom-youtube-videos";
const key = (e) => `${e.show}/${e.id}`;
const showByID = (id) => state.shows.find((s) => s.id === id) || null;
const currentShow = () => showByID(state.show);
const episodesOf = (id) => state.episodes[id] || [];
const allEpisodes = () => state.shows.flatMap((s) => episodesOf(s.id));
const seasonsOf = (id) => [...new Set(episodesOf(id).map((e) => e.season))].sort((a, b) => b - a);
const seasons = () => seasonsOf(state.show);

const KIND_NAMES = { joyn: "Joyn-Serie", youtube: "YouTube-Kanal", movies: "Joyn-Filme", custom: "Eigene Links" };
const KIND_ICONS = { joyn: "tv", youtube: "youtube", movies: "film", custom: "link" };
const kindName = (show) => show.id === YOUTUBE_VIDEOS ? "YouTube-Videos" : KIND_NAMES[show.kind] || "";
const kindIcon = (show) => show.id === YOUTUBE_VIDEOS ? "youtube" : KIND_ICONS[show.kind] || "link";

// Shows in der gewählten Sortierung (bei gleichem Rang gilt die eigene Reihenfolge) – wie in der Mac-App
function sortedShows() {
  const shows = [...state.shows];
  if (state.sort === "name") {
    return shows.sort((a, b) => a.name.localeCompare(b.name, "de", { sensitivity: "base", numeric: true }));
  }
  if (state.sort === "recent") {
    const order = new Map(state.shows.map((s, i) => [s.id, i]));
    const dates = {};
    for (const [id, value] of Object.entries(state.playedAt)) dates[id] = Date.parse(value) || 0;
    const last = state.lastPlayed?.show;
    if (last && dates[last] === undefined) dates[last] = Math.max(0, ...Object.values(dates)) + 1;
    return shows.sort((a, b) => {
      const x = dates[a.id], y = dates[b.id];
      if (x !== undefined && y !== undefined && x !== y) return y - x;
      if (x !== undefined && y === undefined) return -1;
      if (x === undefined && y !== undefined) return 1;
      return order.get(a.id) - order.get(b.id);
    });
  }
  return shows;
}

// Kurzinfo unter dem Show-Namen, z. B. "Staffel 16 · 12 Folgen"
function showInfo(show) {
  const list = episodesOf(show.id);
  if (show.kind === "joyn") {
    const all = seasonsOf(show.id);
    if (!all.length) return state.episodes[show.id] ? "Keine Folgen gefunden" : "Lädt …";
    const count = list.filter((e) => e.season === all[0]).length;
    return `Staffel ${all[0]} · ${count} Folgen` + (all.length > 1 ? ` · ${all.length} Staffeln` : "");
  }
  if (show.kind === "youtube") {
    const videos = list.filter((e) => groupOf(e) === "Videos").length;
    const shorts = list.length - videos;
    if (!list.length) return state.episodes[show.id] ? "Keine Videos gefunden" : "Lädt …";
    return shorts ? `${videos} Videos · ${shorts} Shorts` : `${videos} Videos`;
  }
  const n = list.length;
  if (show.kind === "movies") return n === 1 ? "1 Film" : `${n} Filme`;
  if (show.id === YOUTUBE_VIDEOS) return n === 1 ? "1 Video" : `${n} Videos`;
  return n === 1 ? "1 Link" : `${n} Links`;
}

// Bild der Show (Joyn: Titelbild, YouTube: Kanalbild) oder ein Symbol
function showArtwork(show, className) {
  const box = el("span", `art ${className}`);
  box.classList.toggle("art-round", show.kind === "youtube" && !!show.image);
  if (show.image) {
    const img = el("img");
    img.src = show.image;
    img.alt = "";
    img.loading = "lazy";
    box.appendChild(img);
  } else {
    box.classList.add(`art-${kindIcon(show)}`);
    box.appendChild(icon(kindIcon(show)));
  }
  return box;
}
const isLast = (e) => state.lastPlayedByShow[e.show] === e.id;
const code = (e) => e.season > 0 ? `S${e.season} F${e.number}` : `Nr. ${e.number}`;

function lastPlayed() {
  const ref = state.lastPlayed;
  return ref ? episodesOf(ref.show).find((e) => e.id === ref.id) || null : null;
}

function nextEpisode() {
  const last = lastPlayed();
  if (!last) return null;
  const ordered = [...episodesOf(last.show)].sort((a, b) => a.season - b.season || a.number - b.number);
  const index = ordered.findIndex((e) => e.id === last.id);
  return index >= 0 ? ordered[index + 1] || null : null;
}

// Joyn schreibt Umlaute als ae/oe/ue, daher wird die Suche entsprechend angeglichen.
const normalize = (text) => text.toLowerCase()
  .replaceAll("ä", "ae").replaceAll("ö", "oe").replaceAll("ü", "ue").replaceAll("ß", "ss");

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function icon(name) {
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  const use = document.createElementNS("http://www.w3.org/2000/svg", "use");
  use.setAttribute("href", `#i-${name}`);
  svg.appendChild(use);
  return svg;
}

let toastTimer;
function toast(message, isError = false) {
  if (!message) return;
  const box = $("toast");
  box.textContent = message;
  box.classList.toggle("error", isError);
  box.classList.add("visible");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => box.classList.remove("visible"), isError ? 5000 : 2500);
}

function showEmpty(text) {
  $("empty").textContent = text;
  $("empty").hidden = false;
}

// ---------- Darstellung ----------

function render() {
  renderTitle();
  renderHero();
  renderShows();
  renderSeasons();
  renderEpisodes();
  renderNow();
  renderSidebar();
  renderManage();
  renderYouTube();
}

function renderTitle() {
  const title = !wide.matches ? "TV Launcher"
    : state.search.trim() ? "Suche"
    : currentShow()?.name || "Mediathek";
  $("episodes-title").textContent = title;
}

// ---------- Seitenleiste (iPad) ----------

function selectShow(id, { season, group } = {}) {
  state.show = id;
  state.season = season ?? seasons()[0] ?? null;
  if (group) state.group = group;
  try { localStorage.setItem("show", id); } catch (_) { /* privater Modus */ }
  clearSearch();
  showTab("episodes");
  render();
}

function clearSearch() {
  state.search = "";
  for (const input of document.querySelectorAll(".search-input")) input.value = "";
}

function renderSidebar() {
  if (!wide.matches) return;
  for (const item of document.querySelectorAll(".side-item")) {
    item.classList.toggle("selected", item.dataset.nav === state.tab && (state.tab !== "episodes" || !state.show));
  }
  const box = $("side-shows");
  box.replaceChildren();
  const inLibrary = state.tab === "episodes" && !state.search.trim();
  for (const entry of sidebarEntries()) {
    if (!entry.folder) {
      box.appendChild(sidebarShow(entry.shows[0], inLibrary));
      continue;
    }
    const key = folderKey(entry.folder);
    const collapsed = state.collapsed.has(key);
    const head = el("button", "side-folder");
    head.appendChild(icon("folder"));
    head.appendChild(el("span", "side-folder-name", entry.folder));
    head.appendChild(el("span", "side-folder-count", String(entry.shows.length)));
    const chevron = el("span", "side-toggle" + (collapsed ? "" : " open"));
    chevron.appendChild(icon("chevron"));
    head.appendChild(chevron);
    head.addEventListener("click", () => {
      collapsed ? state.collapsed.delete(key) : state.collapsed.add(key);
      saveCollapsed();
      renderSidebar();
    });
    box.appendChild(head);
    if (!collapsed) {
      const inner = el("div", "side-folder-shows");
      for (const show of entry.shows) inner.appendChild(sidebarShow(show, inLibrary));
      box.appendChild(inner);
    }
  }
}

const folderKey = (name) => `folder:${name}`;

// Alle Ordnernamen in der eigenen Reihenfolge
const folders = () => [...new Set(state.shows.map((s) => s.folder).filter(Boolean))];

// Shows in der gewählten Sortierung, Shows mit Ordner zusammengefasst – wie in der Mac-App
function sidebarEntries() {
  const entries = [];
  const byFolder = new Map();
  for (const show of sortedShows()) {
    if (show.folder) {
      if (byFolder.has(show.folder)) byFolder.get(show.folder).shows.push(show);
      else {
        const entry = { folder: show.folder, shows: [show] };
        byFolder.set(show.folder, entry);
        entries.push(entry);
      }
    } else {
      entries.push({ folder: null, shows: [show] });
    }
  }
  if (state.sort === "name") {
    const title = (e) => e.folder || e.shows[0].name;
    entries.sort((a, b) => title(a).localeCompare(title(b), "de", { sensitivity: "base", numeric: true }));
  }
  return entries;
}

function sidebarShow(show, inLibrary) {
  {
    const sub = show.kind === "joyn" ? seasonsOf(show.id).map((s) => ({ label: `Staffel ${s}`, season: s }))
      : show.kind === "youtube" ? ["Videos", "Shorts"]
        .filter((g) => episodesOf(show.id).some((e) => groupOf(e) === g)).map((g) => ({ label: g, group: g }))
      : [];
    const collapsed = state.collapsed.has(show.id);
    const group = el("div", "side-group");

    const head = el("div", "side-show");
    const select = el("button", "side-show-button");
    select.classList.toggle("selected", inLibrary && show.id === state.show && sub.length < 2);
    select.appendChild(showArtwork(show, "art-small"));
    select.appendChild(el("span", "side-show-name", show.name));
    select.addEventListener("click", () => {
      state.collapsed.delete(show.id);
      saveCollapsed();
      selectShow(show.id, sub[0] || {});
    });
    head.appendChild(select);
    if (sub.length > 1) {
      const toggle = el("button", "side-toggle");
      toggle.setAttribute("aria-label", collapsed ? "Ausklappen" : "Einklappen");
      toggle.classList.toggle("open", !collapsed);
      toggle.appendChild(icon("chevron"));
      toggle.addEventListener("click", () => {
        collapsed ? state.collapsed.delete(show.id) : state.collapsed.add(show.id);
        saveCollapsed();
        renderSidebar();
      });
      head.appendChild(toggle);
    }
    group.appendChild(head);

    if (sub.length > 1 && !collapsed) {
      for (const item of sub) {
        const button = el("button", "side-sub", item.label);
        const active = item.season !== undefined ? state.season === item.season : state.group === item.group;
        button.classList.toggle("selected", inLibrary && show.id === state.show && active);
        button.addEventListener("click", () => selectShow(show.id, item));
        group.appendChild(button);
      }
    }
    return group;
  }
}

function saveCollapsed() {
  try { localStorage.setItem("collapsed", [...state.collapsed].join("\n")); } catch (_) { /* privater Modus */ }
}

function setSort(sort) {
  state.sort = sort;
  try { localStorage.setItem("showSort", sort); } catch (_) { /* privater Modus */ }
  for (const select of document.querySelectorAll(".sort-select")) select.value = sort;
  render();
}

// ---------- YouTube durchsuchen ----------

async function searchYouTube(event) {
  event.preventDefault();
  const input = $("yt-query");
  const query = input.value.trim();
  if (!query) return;
  input.blur();
  // Ein eingefügter Video-Link startet sofort
  if (/youtu\.?be/i.test(query)) {
    await playYouTube(query);
    input.value = "";
    return;
  }
  state.yt.loading = true;
  state.yt.query = query;
  renderYouTube();
  try {
    const data = await api(`/api/youtube/search?q=${encodeURIComponent(query)}`);
    state.yt.videos = data.videos || [];
    state.yt.channels = data.channels || [];
  } catch (error) {
    state.yt.videos = [];
    state.yt.channels = [];
    toast(error.message, true);
  } finally {
    state.yt.loading = false;
    renderYouTube();
  }
}

async function playYouTube(video) {
  if (state.yt.playing) return;
  state.yt.playing = video;
  renderYouTube();
  try {
    const data = await api("/api/youtube", { video, play: true });
    toast(data.message || "Läuft am Fernseher");
    await load();
  } catch (error) {
    toast(error.message, true);
  } finally {
    state.yt.playing = null;
    renderYouTube();
  }
}

async function clearHistory() {
  if (!confirm("YouTube-Verlauf löschen?\nDie Liste „YouTube-Videos“ wird geleert – in der App und hier. Kanäle bleiben.")) return;
  try {
    applyShows(await api("/api/youtube/clear", {}));
    state.episodes[YOUTUBE_VIDEOS] = [];
    state.lastPlayedByShow[YOUTUBE_VIDEOS] = null;
    toast("YouTube-Verlauf gelöscht");
    render();
  } catch (error) {
    toast(error.message, true);
  }
}

async function addChannel(channel, button) {
  button.disabled = true;
  try {
    applyShows(await api("/api/shows/add", { kind: "youtube", input: channel.id, name: "" }));
    channel.added = true;
    toast(`„${channel.name}“ hinzugefügt`);
    const show = state.shows.find((s) => s.channel === channel.id);
    if (show) loadShow(show.id).then(render).catch(() => {});
    render();
  } catch (error) {
    toast(error.message, true);
    button.disabled = false;
  }
  renderYouTube();
}

function renderYouTube() {
  const yt = state.yt;
  const channels = $("yt-channels");
  channels.replaceChildren();
  for (const channel of yt.channels) {
    const item = el("div", "yt-channel");
    const avatar = el("img", "yt-avatar");
    avatar.src = channel.image || "";
    avatar.alt = "";
    item.appendChild(avatar);
    const text = el("div", "yt-channel-text");
    text.appendChild(el("div", "yt-channel-name", channel.name));
    text.appendChild(el("div", "yt-channel-meta", [channel.handle, channel.subscribers].filter(Boolean).join(" · ")));
    item.appendChild(text);
    const button = el("button", channel.added ? "pill pill-gray yt-add" : "pill pill-accent yt-add");
    button.appendChild(icon(channel.added ? "check" : "plus"));
    button.appendChild(document.createTextNode(channel.added ? "Hinzugefügt" : "Kanal"));
    button.disabled = channel.added;
    button.addEventListener("click", () => addChannel(channel, button));
    item.appendChild(button);
    channels.appendChild(item);
  }

  const videos = yt.videos.filter((v) => !v.isShort);
  const shorts = yt.videos.filter((v) => v.isShort);
  for (const [list, box, title] of [[videos, "yt-videos", "yt-videos-title"], [shorts, "yt-shorts", "yt-shorts-title"]]) {
    $(box).replaceChildren(...list.map((v) => { const li = el("li"); li.appendChild(ytCard(v)); return li; }));
    $(title).hidden = !list.length;
  }
  // Ohne Suche: zuletzt gestartete Videos mit „Verlauf löschen“
  const history = episodesOf(YOUTUBE_VIDEOS).slice(0, 12);
  const showHistory = !yt.query && !yt.loading && history.length > 0;
  $("yt-history").hidden = !showHistory;
  $("yt-history-list").replaceChildren(...(showHistory ? history.map((e) => {
    const li = el("li");
    li.appendChild(gridCard(e));
    return li;
  }) : []));

  const empty = $("yt-empty");
  empty.hidden = showHistory || yt.videos.length > 0 || yt.channels.length > 0;
  empty.textContent = yt.loading ? "Suche läuft …"
    : yt.query ? "Nichts gefunden." : "Suche nach Videos oder Kanälen.";
}

function ytCard(video) {
  const card = el("button", "card");
  card.classList.toggle("is-playing", state.yt.playing === video.id);
  const frame = el("span", "card-thumb");
  frame.appendChild(thumb(video, ""));
  if (video.duration) frame.appendChild(el("span", "card-duration", video.duration));
  const playIcon = el("span", "card-play");
  playIcon.appendChild(icon("play"));
  frame.appendChild(playIcon);
  card.appendChild(frame);
  card.appendChild(el("span", "card-title", video.title));
  const meta = video.isShort ? video.views : [video.channel, video.views, video.published].filter(Boolean).join(" · ");
  if (meta) card.appendChild(el("span", "card-subtitle", meta));
  card.addEventListener("click", () => playYouTube(video.id));
  return card;
}

// ---------- Einstellungen ----------

// Lokale Einstellungen dieses Geräts (localStorage)
const local = {
  get(key, fallback) {
    try { const v = localStorage.getItem(key); return v === null ? fallback : JSON.parse(v); } catch (_) { return fallback; }
  },
  set(key, value) {
    try { localStorage.setItem(key, JSON.stringify(value)); } catch (_) { /* privater Modus */ }
  },
};

async function loadServerInfo() {
  const [settings, status] = await Promise.allSettled([api("/api/settings"), api("/api/status")]);
  if (settings.status === "fulfilled") state.server.settings = settings.value;
  if (status.status === "fulfilled") state.server.status = status.value;
  renderSettings();
  renderVolume();
}

let settingsTimer;
function saveServerSettings() {
  clearTimeout(settingsTimer);
  settingsTimer = setTimeout(async () => {
    try {
      state.server.settings = await api("/api/settings", { settings: state.server.settings });
      toast(t("Gesichert"));
    } catch (error) {
      toast(error.message, true);
    }
    renderSettings();
  }, 500);
}

// Wert in einer Auswahl setzen; fehlt die Option (z. B. aus der Mac-App gesetzt), wird sie ergänzt
function selectValue(select, value, label) {
  const text = String(value);
  if (![...select.options].some((o) => o.value === text)) select.appendChild(new Option(label ?? text, text));
  select.value = text;
}

function renderSettings() {
  const s = state.server.settings;
  $("set-language").value = local.get("lang", "system");
  $("set-hero").checked = local.get("showHero", true);
  $("set-pad-speed").value = local.get("padSpeed", 1);
  $("set-invert").checked = local.get("invertScroll", false);
  if (s) {
    $("set-fullscreen").checked = s.autoFullscreen;
    $("row-fullscreen-delay").hidden = !s.autoFullscreen;
    const delay = $("set-fullscreen-delay");
    if (!delay.options.length) {
      for (const sec of [0, 1, 2, 3, 5, 8, 10, 15]) delay.appendChild(new Option(t("{n} Sekunden", { n: sec }), sec));
    }
    selectValue(delay, Math.round(s.fullscreenDelay), t("{n} Sekunden", { n: Math.round(s.fullscreenDelay) }));
    $("set-volume-on").checked = s.startVolume !== undefined && s.startVolume !== null;
    $("row-volume").hidden = !$("set-volume-on").checked;
    $("set-volume").value = s.startVolume ?? 50;
    $("set-volume-value").textContent = `${s.startVolume ?? 50} %`;
    selectValue($("set-seasons"), s.joynSeasons, t("Die neuesten {n}", { n: s.joynSeasons }));
    selectValue($("set-youtube"), s.youtubeRefreshMinutes, t("alle {n} Minuten", { n: s.youtubeRefreshMinutes }));
  }
  const st = state.server.status;
  const list = $("status-list");
  list.replaceChildren();
  const row = (label, value, ok) => {
    const r = el("div", "form-row");
    r.appendChild(el("span", "form-label", label));
    const v = el("span", "form-value", value);
    if (ok === true) v.classList.add("ok");
    if (ok === false) v.classList.add("bad");
    r.appendChild(v);
    list.appendChild(r);
  };
  if (st) {
    row(t("Version"), st.version);
    row(t("Rechner"), st.host);
    row(t("Browser"), st.browser + (st.closeOldTabs ? ` · ${t("alte Tabs schließen")}` : ""));
    row(t("Bedienungshilfen"), st.accessibility ? `✓ ${t("erlaubt")}` : `✗ ${t("fehlt")}`, st.accessibility);
    row(t("Bildschirmaufnahme"), st.screenRecording ? `✓ ${t("erlaubt")}` : `✗ ${t("fehlt")}`, st.screenRecording);
    row(t("Läuft seit"), new Date(st.startedAt).toLocaleString(lang(), { dateStyle: "medium", timeStyle: "short" }));
    if (st.sleepAt) row(t("Sleep-Timer"), t("bis {time}", { time: new Date(st.sleepAt).toLocaleTimeString(lang(), { timeStyle: "short" }) }));
  } else {
    row(t("Status"), t("Lädt …"));
  }
  $("app-version").textContent = `TV Launcher · Web-App`;
}

function renderVolume() {
  const st = state.server.status;
  $("volume-label").textContent = !st || st.volume === undefined ? "–" : st.muted ? t("stumm") : `${st.volume} %`;
  const sleep = $("sleep-select");
  sleep.options[0].text = st?.sleepAt
    ? t("bis {time}", { time: new Date(st.sleepAt).toLocaleTimeString(lang(), { timeStyle: "short" }) })
    : t("Sleep-Timer");
  sleep.value = "";
}

async function changeVolume(action) {
  try {
    const data = await api("/api/volume", { action });
    if (data.volume !== undefined) {
      if (state.server.status) Object.assign(state.server.status, { volume: data.volume, muted: data.muted });
      else state.server.status = { volume: data.volume, muted: data.muted };
    }
    if (data.message) toast(data.message);
    renderVolume();
  } catch (error) {
    toast(error.message, true);
  }
}

async function setSleep(minutes) {
  try {
    state.server.status = await api("/api/sleep", { minutes });
    toast(minutes > 0 ? t("Sleep-Timer: {n} Min.", { n: minutes }) : t("Sleep-Timer aus"));
  } catch (error) {
    toast(error.message, true);
  }
  renderVolume();
  renderSettings();
}

function setupSettings() {
  $("set-language").addEventListener("change", (e) => {
    local.set("lang", e.target.value);
    location.reload();
  });
  $("set-hero").addEventListener("change", (e) => { local.set("showHero", e.target.checked); render(); });
  $("set-pad-speed").addEventListener("input", (e) => local.set("padSpeed", Number(e.target.value)));
  $("set-invert").addEventListener("change", (e) => local.set("invertScroll", e.target.checked));
  const server = (fn) => () => {
    if (!state.server.settings) return;
    fn(state.server.settings);
    renderSettings();
    saveServerSettings();
  };
  $("set-fullscreen").addEventListener("change", server((s) => { s.autoFullscreen = $("set-fullscreen").checked; }));
  $("set-fullscreen-delay").addEventListener("change", server((s) => { s.fullscreenDelay = Number($("set-fullscreen-delay").value); }));
  $("set-volume-on").addEventListener("change", server((s) => {
    s.startVolume = $("set-volume-on").checked ? (state.server.status?.volume ?? 50) : null;
  }));
  $("set-volume").addEventListener("input", () => { $("set-volume-value").textContent = `${$("set-volume").value} %`; });
  $("set-volume").addEventListener("change", server((s) => { s.startVolume = Number($("set-volume").value); }));
  $("set-seasons").addEventListener("change", server((s) => { s.joynSeasons = Number($("set-seasons").value); }));
  $("set-youtube").addEventListener("change", server((s) => { s.youtubeRefreshMinutes = Number($("set-youtube").value); }));

  $("show-log").addEventListener("click", async () => {
    const box = $("server-log");
    try {
      const response = await fetch("/api/log?lines=200", { cache: "no-store" });
      box.textContent = await response.text();
      box.hidden = false;
      box.scrollTop = box.scrollHeight;
    } catch (error) {
      toast(error.message, true);
    }
  });
  $("restart-server").addEventListener("click", async () => {
    if (!confirm(t("Server neu starten?\nEr ist in wenigen Sekunden wieder da."))) return;
    try {
      toast((await api("/api/restart", {})).message);
      setTimeout(loadServerInfo, 4000);
    } catch (error) {
      toast(error.message, true);
    }
  });
  $("restore-file").addEventListener("change", async (e) => {
    const file = e.target.files[0];
    e.target.value = "";
    if (!file) return;
    let backup;
    try { backup = JSON.parse(await file.text()); } catch (_) { backup = null; }
    if (!backup || backup.app !== "TV Launcher") {
      toast(t("Das ist keine TV-Launcher-Sicherung."), true);
      return;
    }
    if (!confirm(t("Sicherung einspielen?\nAlle Shows, Presets und Einstellungen des Mac mini werden ersetzt."))) return;
    try {
      const response = await fetch("/api/restore", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(backup) });
      if (!response.ok) throw new Error((await response.json()).error || response.status);
      toast(t("Sicherung eingespielt"));
      state.episodes = {};
      await load();
      await loadServerInfo();
    } catch (error) {
      toast(error.message, true);
    }
  });
  for (const button of document.querySelectorAll("[data-volume]")) {
    button.addEventListener("click", () => changeVolume(button.dataset.volume));
  }
  $("sleep-select").addEventListener("change", (e) => { if (e.target.value !== "") setSleep(Number(e.target.value)); });
}

// ---------- Shows verwalten ----------

const ADD_KINDS = {
  joyn: { label: "Joyn-Serie", placeholder: "Link: joyn.de/serien/…",
    hint: "Auf joyn.de die Seite der Serie öffnen, Link kopieren und hier einfügen. Ohne Name wird der Name von Joyn übernommen." },
  youtube: { label: "YouTube", placeholder: "Kanal-Link, @Name oder Video-Link",
    hint: "Kanal-Link, @Name oder der Link eines Videos aus dem Kanal. Videos und Shorts werden alle 30 Minuten geladen." },
  movie: { label: "Joyn-Film", placeholder: "Link: joyn.de/filme/…",
    hint: "Der Film landet in der Sammlung „Filme“ und startet von dort mit einem Tipp." },
  custom: { label: "Eigene", placeholder: null,
    hint: "Leere Show anlegen – danach öffnet sie sich und du trägst beliebige Links ein." },
};

const SORTS = { custom: "Eigene", recent: "Zuletzt", name: "A–Z" };

function segmented(box, options, selected, onSelect) {
  box.replaceChildren();
  for (const [value, label] of Object.entries(options)) {
    const button = el("button", "", label);
    button.type = "button";
    button.setAttribute("role", "tab");
    button.setAttribute("aria-selected", String(value === selected));
    button.addEventListener("click", () => onSelect(value));
    box.appendChild(button);
  }
}

function renderAddForm() {
  const kind = ADD_KINDS[state.addKind];
  segmented($("add-kind"), Object.fromEntries(Object.entries(ADD_KINDS).map(([k, v]) => [k, v.label])),
    state.addKind, (value) => {
      state.addKind = value;
      renderAddForm();
    });
  $("add-input").hidden = !kind.placeholder;
  $("add-input").placeholder = kind.placeholder || "";
  $("add-name").hidden = state.addKind === "movie";
  $("add-name").placeholder = state.addKind === "custom" ? "Name der Show" : "Name (optional)";
  $("add-hint").textContent = kind.hint;
}

function renderManage() {
  segmented($("sort-segmented"), SORTS, state.sort, setSort);
  const box = $("manage-list");
  box.replaceChildren();
  let lastFolder = null;
  state.shows.forEach((show, index) => {
    if (show.folder && show.folder !== lastFolder) box.appendChild(folderRow(show.folder));
    lastFolder = show.folder || null;
    const item = el("li");
    if (show.folder) item.classList.add("in-folder");
    const row = el("div", "manage-row");
    const open = el("button", "manage-open");
    open.appendChild(showArtwork(show, "art-medium"));
    const text = el("span", "row-text");
    text.appendChild(el("span", "manage-name", show.name));
    text.appendChild(el("span", "row-subtitle", showInfo(show)));
    open.appendChild(text);
    open.addEventListener("click", () => openEditor(show.id));
    row.appendChild(open);
    for (const [name, offset, label] of [["up", -1, "Nach oben"], ["down", 1, "Nach unten"]]) {
      const button = el("button", "circle-button");
      button.setAttribute("aria-label", label);
      button.appendChild(icon(name));
      button.disabled = index + offset < 0 || index + offset >= state.shows.length;
      button.addEventListener("click", () => moveShow(show.id, offset));
      row.appendChild(button);
    }
    item.appendChild(row);
    box.appendChild(item);
  });
}

// Überschrift eines Ordners in der Liste „Deine Shows“: umbenennen oder auflösen
function folderRow(name) {
  const item = el("li", "folder-row");
  item.appendChild(icon("folder"));
  item.appendChild(el("span", "folder-row-name", name));
  const rename = el("button", "text-button", "Umbenennen");
  rename.addEventListener("click", async () => {
    const to = (prompt(t("Neuer Name für den Ordner „{name}“:", { name }), name) || "").trim();
    if (to && to !== name) await renameFolder(name, to);
  });
  const dissolve = el("button", "text-button", "Auflösen");
  dissolve.addEventListener("click", async () => {
    if (confirm(t("Ordner „{name}“ auflösen?\nDie Shows bleiben erhalten.", { name }))) await renameFolder(name, "");
  });
  item.append(rename, dissolve);
  return item;
}

async function renameFolder(from, to) {
  try {
    applyShows(await api("/api/folders/rename", { from, to }));
    if (state.collapsed.delete(folderKey(from)) && to) state.collapsed.add(folderKey(to));
    saveCollapsed();
    render();
  } catch (error) {
    toast(error.message, true);
  }
}

async function moveShow(id, offset) {
  const ids = state.shows.map((s) => s.id);
  const from = ids.indexOf(id);
  const to = from + offset;
  if (from < 0 || to < 0 || to >= ids.length) return;
  ids.splice(to, 0, ids.splice(from, 1)[0]);
  // Sofort anzeigen, dann speichern – angeordnet wird die eigene Reihenfolge
  state.shows = ids.map(showByID);
  if (state.sort !== "custom") setSort("custom"); else render();
  try {
    applyShows(await api("/api/shows/order", { ids }));
  } catch (error) {
    toast(`Reihenfolge nicht gespeichert: ${error.message}`, true);
    await load();
  }
}

async function addShow(event) {
  event.preventDefault();
  const form = event.currentTarget;
  const button = form.querySelector("button");
  const input = $("add-input").value.trim();
  const name = $("add-name").value.trim();
  if (state.addKind !== "custom" && !input) {
    toast("Bitte zuerst einen Link einfügen.", true);
    return;
  }
  button.disabled = true;
  const before = new Set(state.shows.map((s) => s.id));
  try {
    if (state.addKind === "movie") {
      const data = await api("/api/movies", { movie: input, play: false });
      toast(data.message);
      await load();
    } else {
      applyShows(await api("/api/shows/add", { kind: state.addKind, input, name }));
      const added = state.shows.find((s) => !before.has(s.id));
      if (added) {
        toast(`„${added.name}“ hinzugefügt`);
        render();
        loadShow(added.id).then(render).catch((error) => toast(error.message, true));
        if (added.kind === "custom") openEditor(added.id);
      }
    }
    $("add-input").value = "";
    $("add-name").value = "";
    for (const field of form.querySelectorAll("input")) field.blur();
  } catch (error) {
    toast(error.message, true);
  } finally {
    button.disabled = false;
  }
}

// ---------- Show bearbeiten ----------

const newID = () => Array.from({ length: 4 }, () => Math.random().toString(16).slice(2, 10)).join("").slice(0, 32);

function openEditor(id) {
  const show = showByID(id);
  if (!show) return;
  state.editing = JSON.parse(JSON.stringify(show));
  renderEditor();
  api("/api/presets").then((data) => {
    state.presets = data.presets || [];
    if (state.editing) renderEditor();
  }).catch(() => {});
  $("sheet").hidden = false;
  document.body.classList.add("sheet-open");
}

function closeEditor() {
  state.editing = null;
  $("sheet").hidden = true;
  document.body.classList.remove("sheet-open");
}

function field(label, input) {
  const row = el("label", "form-row");
  row.appendChild(el("span", "form-label", label));
  row.appendChild(input);
  return row;
}

function textInput(value, placeholder, onInput, type = "text") {
  const input = el("input", "form-input");
  input.type = type;
  input.value = value || "";
  input.placeholder = placeholder;
  input.autocomplete = "off";
  input.spellcheck = false;
  input.addEventListener("input", () => onInput(input.value));
  return input;
}

function renderEditor() {
  const show = state.editing;
  const body = $("sheet-body");
  body.replaceChildren();
  $("sheet-title").textContent = show.name || "Show";

  const head = el("div", "sheet-art");
  head.appendChild(showArtwork(show, "art-large"));
  const meta = el("div", "sheet-meta");
  meta.appendChild(el("div", "sheet-kind", kindName(show)));
  const source = show.kind === "joyn" ? `https://www.joyn.de/serien/${show.id}`
    : show.kind === "youtube" && show.channel ? `https://www.youtube.com/channel/${show.channel}` : null;
  if (source) {
    const link = el("a", "sheet-link", show.kind === "joyn" ? "Auf Joyn ansehen" : "Kanal auf YouTube");
    link.href = source;
    link.target = "_blank";
    link.rel = "noopener";
    meta.appendChild(link);
  }
  head.appendChild(meta);
  body.appendChild(head);

  const group = el("div", "form-group");
  group.appendChild(field("Name", textInput(show.name, "Name", (value) => {
    show.name = value;
    $("sheet-title").textContent = value || "Show";
  })));
  const folderInput = textInput(show.folder || "", t("Kein Ordner"), (value) => { show.folder = value.trim() || null; });
  folderInput.setAttribute("list", "folder-list");
  const list = el("datalist");
  list.id = "folder-list";
  for (const name of folders()) list.appendChild(new Option(name, name));
  group.appendChild(field("Ordner", folderInput));
  group.appendChild(list);
  body.appendChild(group);

  if (show.kind === "custom") {
    body.appendChild(el("h3", "form-title", show.id === YOUTUBE_VIDEOS ? "Videos" : "Links"));
    const links = el("div", "form-group");
    show.links.forEach((link, index) => {
      const row = el("div", "link-row");
      const inputs = el("div", "link-inputs");
      inputs.appendChild(textInput(link.title, "Titel", (value) => { link.title = value; }));
      inputs.appendChild(textInput(link.url, "https://…", (value) => { link.url = value; }, "url"));
      row.appendChild(inputs);
      row.appendChild(removeButton(() => { show.links.splice(index, 1); renderEditor(); }));
      links.appendChild(row);
    });
    const add = el("button", "form-add");
    add.type = "button";
    add.appendChild(icon("plus"));
    add.appendChild(el("span", "", "Link hinzufügen"));
    add.addEventListener("click", () => {
      show.links.push({ id: newID(), title: "", url: "" });
      renderEditor();
      const inputs = body.querySelectorAll(".link-row .form-input");
      inputs[inputs.length - 2]?.focus();
    });
    links.appendChild(add);
    body.appendChild(links);
    body.appendChild(el("p", "hint hint-below", "Jeder Link erscheint als eigene „Folge“ und wird im Browser am Mac am Fernseher geöffnet."));
  }

  if (show.kind === "movies") {
    body.appendChild(el("h3", "form-title", "Filme"));
    const list = el("div", "form-group");
    if (!show.links.length) list.appendChild(el("div", "form-empty", "Noch keine Filme."));
    show.links.forEach((link, index) => {
      const row = el("div", "movie-row");
      const img = el("img", "movie-thumb");
      if (link.image) img.src = link.image;
      img.alt = "";
      row.appendChild(img);
      row.appendChild(el("span", "movie-title", link.title));
      row.appendChild(removeButton(() => { show.links.splice(index, 1); renderEditor(); }));
      list.appendChild(row);
    });
    body.appendChild(list);
  }

  const c = show.controls || {};
  const keys = [["Pause/Weiter", c.playPause], ["Zurück", c.back], ["Vor", c.forward], ["Vollbild", c.fullscreen],
    ["Untertitel", c.subtitles], ["Lauter", c.volumeUp], ["Leiser", c.volumeDown], ["Ton aus/an", c.mute]];
  body.appendChild(el("h3", "form-title", "Tasten am Mac"));
  const keyList = el("div", "form-group");
  for (const [label, binding] of keys) {
    const row = el("div", "form-row");
    row.appendChild(el("span", "form-label", label));
    row.appendChild(el("span", "form-value", binding?.kind === "none" ? "–" : binding?.label || "–"));
    keyList.appendChild(row);
  }
  if (c.start && c.start.kind !== "none") {
    const row = el("div", "form-row");
    row.appendChild(el("span", "form-label", "Beim Start"));
    row.appendChild(el("span", "form-value", `${c.start.label} nach ${Math.round(c.startDelay || 0)} s`));
    keyList.appendChild(row);
  }
  if (state.presets.length) {
    const row = el("label", "form-row");
    row.appendChild(el("span", "form-label", "Preset"));
    const select = el("select", "form-select");
    const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
    const current = state.presets.find((p) => same(p.controls, c));
    select.appendChild(new Option(current ? current.name : "Eigene Belegung", "", true, true));
    for (const preset of state.presets) {
      if (preset === current) continue;
      select.appendChild(new Option(`${preset.name}${preset.builtIn ? "" : " (eigenes)"}`, preset.id));
    }
    select.addEventListener("change", () => {
      const preset = state.presets.find((p) => p.id === select.value);
      if (!preset) return;
      show.controls = JSON.parse(JSON.stringify(preset.controls));
      renderEditor();
      toast(`„${preset.name}“ übernommen – zum Speichern „Sichern“ tippen`);
    });
    row.appendChild(select);
    keyList.insertBefore(row, keyList.firstChild);
  }
  body.appendChild(keyList);
  const savePreset = el("button", "form-add");
  savePreset.type = "button";
  savePreset.appendChild(icon("plus"));
  savePreset.appendChild(el("span", "", "Belegung als Preset sichern …"));
  savePreset.addEventListener("click", saveAsPreset);
  const presetGroup = el("div", "form-group form-group-spaced");
  presetGroup.appendChild(savePreset);
  body.appendChild(presetGroup);
  body.appendChild(el("p", "hint hint-below",
    "Presets gelten für alle Shows, in der App und hier. Einzelne Tasten änderst du in der Mac-App unter Einstellungen → Shows."));

  const remove = el("button", "danger-button", "Show löschen");
  remove.type = "button";
  remove.addEventListener("click", deleteEditing);
  body.appendChild(remove);
}

function removeButton(action) {
  const button = el("button", "remove-button");
  button.type = "button";
  button.setAttribute("aria-label", "Entfernen");
  button.appendChild(icon("minus"));
  button.addEventListener("click", action);
  return button;
}

async function saveAsPreset() {
  const show = state.editing;
  if (!show) return;
  const name = (prompt("Name für das Preset, z. B. ARD Mediathek:") || "").trim();
  if (!name) return;
  try {
    const data = await api("/api/presets", { preset: { id: "", name, controls: show.controls } });
    state.presets = data.presets || [];
    toast(`Preset „${name}“ gesichert`);
    renderEditor();
  } catch (error) {
    toast(error.message, true);
  }
}

async function saveEditing() {
  const show = state.editing;
  if (!show) return;
  show.name = show.name.trim();
  if (!show.name) {
    toast("Die Show braucht einen Namen.", true);
    return;
  }
  show.links = show.links
    .map((l) => ({ ...l, title: l.title.trim(), url: l.url.trim() }))
    .filter((l) => l.title || l.url)
    .map((l) => ({ ...l, url: l.url && !/^https?:\/\//i.test(l.url) ? `https://${l.url}` : l.url,
      title: l.title || l.url }));
  $("sheet-save").disabled = true;
  try {
    applyShows(await api("/api/shows", { show }));
    closeEditor();
    toast("Gesichert");
    await loadShow(show.id).catch(() => {});
    render();
  } catch (error) {
    toast(error.message, true);
  } finally {
    $("sheet-save").disabled = false;
  }
}

async function deleteEditing() {
  const show = state.editing;
  if (!show || !confirm(`„${show.name}“ löschen?\nDie Show verschwindet aus der App und der Web-App.`)) return;
  try {
    applyShows(await api("/api/shows/delete", { id: show.id }));
    delete state.episodes[show.id];
    if (state.show === show.id) state.show = state.shows[0]?.id || null;
    closeEditor();
    toast(`„${show.name}“ gelöscht`);
    render();
  } catch (error) {
    toast(error.message, true);
  }
}

function renderHero() {
  const last = lastPlayed();
  $("hero").hidden = !last || state.search !== "" || !local.get("showHero", true);
  if (!last) return;
  const show = showByID(last.show);
  const position = last.season > 0 ? `Staffel ${last.season}, Folge ${last.number}` : `Nr. ${last.number}`;
  $("hero-caption").textContent = `Zuletzt gesehen · ${show ? show.name : ""} · ${position}`;
  $("hero-title").textContent = last.title;
  $("hero-subtitle").textContent = last.subtitle;
  $("hero-subtitle").hidden = !last.subtitle;
  const next = nextEpisode();
  $("hero-next").hidden = !next;
  if (next) $("hero-next").querySelector("span").textContent = `Nächste: ${next.title}`;
  $("hero-play").disabled = $("hero-next").disabled = !!state.playingKey;
}

function renderShows() {
  const box = $("shows");
  box.replaceChildren();
  box.hidden = state.search !== "" || state.shows.length < 2;
  for (const entry of sidebarEntries()) {
    if (entry.folder) {
      const label = el("span", "chip-folder");
      label.appendChild(icon("folder"));
      label.appendChild(document.createTextNode(entry.folder));
      box.appendChild(label);
    }
    for (const show of entry.shows) box.appendChild(showChip(show));
  }
}

function showChip(show) {
  {
    const button = el("button", "", show.name);
    button.setAttribute("role", "tab");
    button.setAttribute("aria-selected", String(show.id === state.show));
    button.addEventListener("click", () => {
      state.show = show.id;
      state.season = seasons()[0] ?? null;
      try { localStorage.setItem("show", show.id); } catch (_) { /* privater Modus */ }
      render();
    });
    return button;
  }
}

// YouTube-Gruppen der ausgewählten Show, nur wenn vorhanden (ältere Daten ohne Gruppe = Videos)
const groupOf = (e) => e.group || "Videos";
const groups = () => ["Videos", "Shorts"].filter((g) => episodesOf(state.show).some((e) => groupOf(e) === g));

function renderSeasons() {
  const box = $("seasons");
  box.replaceChildren();
  if (currentShow()?.kind === "youtube") {
    const list = groups();
    if (!list.includes(state.group)) state.group = list[0] || "Videos";
    box.hidden = state.search !== "" || list.length < 2;
    for (const group of list) {
      const button = el("button", "", group);
      button.setAttribute("role", "tab");
      button.setAttribute("aria-selected", String(group === state.group));
      button.addEventListener("click", () => {
        state.group = group;
        render();
      });
      box.appendChild(button);
    }
    return;
  }
  const list = seasons();
  box.hidden = state.search !== "" || list.length < 2 || (currentShow()?.kind ?? "joyn") !== "joyn";
  for (const season of list) {
    const button = el("button", "", `Staffel ${season}`);
    button.setAttribute("role", "tab");
    button.setAttribute("aria-selected", String(season === state.season));
    button.addEventListener("click", () => {
      state.season = season;
      render();
    });
    box.appendChild(button);
  }
}

function renderEpisodes() {
  const query = normalize(state.search.trim());
  const show = currentShow();
  let list;
  if (query) {
    list = allEpisodes().filter((e) => normalize(
      `${showByID(e.show)?.name || ""} ${code(e)} ${e.title} ${e.subtitle} staffel ${e.season} folge ${e.number}`)
      .includes(query));
  } else if (show?.kind === "youtube") {
    list = episodesOf(show.id).filter((e) => groupOf(e) === state.group);
  } else if (show && show.kind !== "joyn") {
    list = episodesOf(show.id);
  } else {
    list = episodesOf(state.show).filter((e) => e.season === state.season);
  }

  // YouTube-Kanäle und Filme als Raster mit großen Vorschaubildern
  const asGrid = !query && (show?.kind === "youtube" || show?.kind === "movies" || show?.id === YOUTUBE_VIDEOS);
  // Bei Filmen und der Sammlung "YouTube-Videos" lässt sich direkt ein Link einfügen
  const linkTarget = show?.kind === "movies" ? "Joyn-Filmlink einfügen (joyn.de/filme/…)"
    : show?.id === YOUTUBE_VIDEOS ? "YouTube-Link einfügen" : null;
  $("link-form").hidden = query !== "" || !linkTarget;
  $("history-clear").hidden = query !== "" || show?.id !== YOUTUBE_VIDEOS || !episodesOf(YOUTUBE_VIDEOS).length;
  if (linkTarget) $("link-form").querySelector("input").placeholder = linkTarget;
  const box = $("episodes");
  box.className = !asGrid ? "list"
    : show?.kind === "youtube" && state.group === "Shorts" ? "grid shorts" : "grid";
  box.replaceChildren();
  for (const episode of list) {
    const item = el("li");
    item.appendChild(asGrid ? gridCard(episode) : listRow(episode, query));
    box.appendChild(item);
  }

  const loaded = show && state.episodes[show.id] !== undefined;
  $("empty").hidden = list.length > 0 || (!loaded && !query);
  if (!list.length && (loaded || query)) {
    showEmpty(query ? "Keine Folge gefunden"
      : show?.id === YOUTUBE_VIDEOS ? "Noch keine Videos – oben einen YouTube-Link einfügen."
      : show?.kind === "custom" ? "Noch keine Links – unter „Shows“ die Show öffnen und Links eintragen."
      : show?.kind === "movies" ? "Noch keine Filme – oben einen Joyn-Filmlink einfügen."
      : show?.kind === "youtube" ? "Keine Videos gefunden"
      : "Keine Folge gefunden");
  }
}

function thumb(episode, className) {
  const img = el("img", className);
  img.src = episode.thumbnail;
  img.alt = "";
  img.loading = "lazy";
  img.decoding = "async";
  return img;
}

function listRow(episode, query) {
  const row = el("button", "row");
  row.classList.toggle("is-last", isLast(episode));
  row.classList.toggle("is-playing", key(episode) === state.playingKey);
  row.appendChild(episode.thumbnail
    ? thumb(episode, "row-thumb")
    : el("span", "badge", String(episode.number).padStart(2, "0")));

  const text = el("span", "row-text");
  const title = el("span", "row-title");
  if (query) {
    const name = showByID(episode.show)?.name || "";
    title.appendChild(el("span", "tag", episode.season > 0 ? `${name} · S${episode.season}` : name));
  }
  title.appendChild(el("span", "row-title-text", episode.title));
  if (isLast(episode)) title.appendChild(el("span", "tag", "zuletzt"));
  text.appendChild(title);
  if (episode.subtitle) text.appendChild(el("span", "row-subtitle", episode.subtitle));
  row.appendChild(text);

  const playIcon = el("span", "row-play");
  playIcon.appendChild(icon("play"));
  row.appendChild(playIcon);
  row.addEventListener("click", () => play(episode));
  return row;
}

function gridCard(episode) {
  const card = el("button", "card");
  card.classList.toggle("is-playing", key(episode) === state.playingKey);
  const frame = el("span", "card-thumb");
  if (episode.thumbnail) frame.appendChild(thumb(episode, ""));
  if (isLast(episode)) frame.appendChild(el("span", "card-tag", "zuletzt"));
  const playIcon = el("span", "card-play");
  playIcon.appendChild(icon("play"));
  frame.appendChild(playIcon);
  card.appendChild(frame);
  card.appendChild(el("span", "card-title", episode.title));
  if (episode.subtitle) card.appendChild(el("span", "card-subtitle", episode.subtitle));
  card.addEventListener("click", () => play(episode));
  return card;
}

// Link (YouTube-Video oder Joyn-Film) merken und sofort am Fernseher starten
async function startLink(event) {
  event.preventDefault();
  const form = event.currentTarget;
  const input = form.querySelector("input");
  const button = form.querySelector("button");
  const link = input.value.trim();
  if (!link) return;
  let request;
  if (/youtu\.?be|^[A-Za-z0-9_-]{11}$/i.test(link)) {
    request = api("/api/youtube", { video: link, play: true });
  } else if (/joyn\.de\/(play\/)?filme\//i.test(link)) {
    request = api("/api/movies", { movie: link, play: true });
  } else {
    toast("Bitte einen YouTube-Link oder einen Joyn-Filmlink einfügen.", true);
    return;
  }
  button.disabled = true;
  try {
    const data = await request;
    toast(data.message);
    input.value = "";
    input.blur();
    await load();
  } catch (error) {
    toast(error.message, true);
  } finally {
    button.disabled = false;
  }
}

function renderNow() {
  const box = $("now");
  box.replaceChildren();
  // Untertitel nur, wenn die zuletzt gestartete Show eine Taste dafür hat (YouTube: C, Joyn: keine)
  const lastShow = showByID(state.lastPlayed?.show);
  const subtitles = lastShow?.controls?.subtitles;
  $("subtitles").disabled = !subtitles || subtitles.kind === "none";
  $("subtitles").title = $("subtitles").disabled
    ? "Für diese Show gibt es keine Untertitel-Taste (z. B. Joyn)" : `Untertitel an/aus (${subtitles.label})`;
  const last = lastPlayed();
  if (!last) return;
  const show = showByID(last.show);
  box.appendChild(el("div", "now-caption", `Zuletzt gestartet · ${show ? show.name : ""} · ${code(last)}`));
  box.appendChild(el("div", "now-title", last.title));
  if (last.subtitle) box.appendChild(el("div", "now-subtitle", last.subtitle));
}

// ---------- Tabs ----------

function showTab(name) {
  if (!["episodes", "youtube", "remote", "manage", "settings"].includes(name)) name = "episodes";
  state.tab = name;
  for (const tab of document.querySelectorAll(".tab")) {
    tab.setAttribute("aria-selected", String(tab.dataset.tab === name));
  }
  $("view-episodes").hidden = name !== "episodes";
  $("view-remote").hidden = name !== "remote";
  $("view-manage").hidden = name !== "manage";
  $("view-youtube").hidden = name !== "youtube";
  $("view-settings").hidden = name !== "settings";
  if (name === "settings" || name === "remote") loadServerInfo();
  renderSidebar();
  try { localStorage.setItem("tab", name); } catch (_) { /* privater Modus */ }
  window.scrollTo(0, 0);
}

// ---------- Trackpad & Tasten (Fernsteuerung über /api/input) ----------

const input = { queue: [], sending: false };

function sendInput(event) {
  const last = input.queue[input.queue.length - 1];
  // Bewegungen und Scrollen zusammenfassen, solange noch eine Anfrage unterwegs ist
  if (last && last.kind === event.kind && (event.kind === "move" || event.kind === "scroll")) {
    last.dx += event.dx;
    last.dy += event.dy;
  } else {
    input.queue.push(event);
  }
  flushInput();
}

async function flushInput() {
  if (input.sending || !input.queue.length) return;
  const events = input.queue;
  input.queue = [];
  input.sending = true;
  try {
    await api("/api/input", { events });
  } catch (error) {
    toast(error.message, true);
  } finally {
    input.sending = false;
    flushInput();
  }
}

function click(button, clicks) {
  sendInput({ kind: "button", button, down: true, clicks });
  sendInput({ kind: "button", button, down: false, clicks });
}

function setupPad() {
  const pad = $("pad");
  const gesture = { mode: null, x: 0, y: 0, start: 0, moved: false, lastTap: 0 };
  const center = (touches) => {
    let x = 0, y = 0;
    for (const t of touches) { x += t.clientX; y += t.clientY; }
    return { x: x / touches.length, y: y / touches.length };
  };

  pad.addEventListener("touchstart", (event) => {
    event.preventDefault();
    pad.classList.add("touching");
    const count = event.touches.length;
    if (count === 1 && gesture.mode === null) {
      gesture.mode = "move";
      gesture.start = Date.now();
      gesture.moved = false;
    } else if (count === 2) {
      // zweiter Finger: zum Scrollen wechseln (oder Rechtsklick beim Tippen)
      gesture.mode = gesture.moved ? "ignore" : "scroll";
    } else if (count > 2) {
      gesture.mode = "ignore";
    }
    const point = center(event.touches);
    gesture.x = point.x;
    gesture.y = point.y;
  }, { passive: false });

  pad.addEventListener("touchmove", (event) => {
    event.preventDefault();
    const point = center(event.touches);
    const dx = point.x - gesture.x;
    const dy = point.y - gesture.y;
    gesture.x = point.x;
    gesture.y = point.y;
    if (Math.abs(dx) + Math.abs(dy) > 2) gesture.moved = true;
    if (gesture.mode === "move" && event.touches.length === 1) {
      // leichte Beschleunigung: schnelle Bewegungen kommen weiter
      const speed = (1.8 + Math.min(Math.hypot(dx, dy), 30) * 0.12) * local.get("padSpeed", 1);
      sendInput({ kind: "move", dx: dx * speed, dy: dy * speed });
    } else if (gesture.mode === "scroll" && event.touches.length === 2) {
      const direction = local.get("invertScroll", false) ? -2 : 2;
      sendInput({ kind: "scroll", dx: dx * direction, dy: dy * direction });
    }
  }, { passive: false });

  const end = (event) => {
    event.preventDefault();
    if (event.touches.length > 0) {
      // von zwei auf einen Finger: nicht plötzlich weiterbewegen
      if (gesture.mode === "scroll" && gesture.moved) gesture.mode = "ignore";
      const point = center(event.touches);
      gesture.x = point.x;
      gesture.y = point.y;
      return;
    }
    pad.classList.remove("touching");
    const isTap = !gesture.moved && Date.now() - gesture.start < 300;
    if (isTap && gesture.mode === "move") {
      const now = Date.now();
      click(0, now - gesture.lastTap < 350 ? 2 : 1);
      gesture.lastTap = now;
    } else if (isTap && gesture.mode === "scroll") {
      click(1, 1);
    }
    gesture.mode = null;
  };
  pad.addEventListener("touchend", end, { passive: false });
  pad.addEventListener("touchcancel", end, { passive: false });
}

function setupKeys() {
  for (const key of document.querySelectorAll(".key")) {
    key.addEventListener("click", () => {
      const code = Number(key.dataset.key);
      sendInput({ kind: "key", code, down: true, flags: 0 });
      sendInput({ kind: "key", code, down: false, flags: 0 });
    });
  }
}

// ---------- Start ----------

function setup() {
  for (const button of document.querySelectorAll(".refresh-button")) {
    button.addEventListener("click", () => load(true));
  }
  $("link-form").addEventListener("submit", startLink);
  $("remote-link-form").addEventListener("submit", startLink);
  $("add-form").addEventListener("submit", addShow);
  $("yt-form").addEventListener("submit", searchYouTube);
  for (const button of document.querySelectorAll(".history-clear")) button.addEventListener("click", clearHistory);
  renderYouTube();
  for (const input of document.querySelectorAll(".search-input")) {
    input.addEventListener("input", () => {
      state.search = input.value;
      for (const other of document.querySelectorAll(".search-input")) if (other !== input) other.value = input.value;
      if (state.search && state.tab !== "episodes") showTab("episodes");
      render();
    });
  }
  for (const item of document.querySelectorAll(".side-item")) {
    item.addEventListener("click", () => {
      if (item.dataset.nav === "episodes") {
        // "Mediathek" ohne bestimmte Show: Weiterschauen-Karte und zuletzt gesehene Show
        clearSearch();
        state.show = state.lastPlayed?.show || state.show;
        state.season = seasons()[0] ?? null;
      }
      showTab(item.dataset.nav);
      render();
    });
  }
  for (const select of document.querySelectorAll(".sort-select")) {
    select.addEventListener("change", () => setSort(select.value));
  }
  $("sheet-cancel").addEventListener("click", closeEditor);
  $("sheet-save").addEventListener("click", saveEditing);
  $("sheet").addEventListener("click", (event) => { if (event.target === $("sheet")) closeEditor(); });
  document.addEventListener("keydown", (event) => { if (event.key === "Escape" && state.editing) closeEditor(); });
  wide.addEventListener("change", render);
  $("hero-play").addEventListener("click", () => { const e = lastPlayed(); if (e) play(e); });
  $("hero-next").addEventListener("click", () => { const e = nextEpisode(); if (e) play(e); });
  for (const button of document.querySelectorAll("[data-action]")) {
    button.addEventListener("click", () => control(button.dataset.action));
  }
  for (const tab of document.querySelectorAll(".tab")) {
    tab.addEventListener("click", () => showTab(tab.dataset.tab));
  }
  setupPad();
  setupKeys();
  setupSettings();

  try {
    state.show = localStorage.getItem("show");
    state.sort = localStorage.getItem("showSort") || "custom";
    state.collapsed = new Set((localStorage.getItem("collapsed") || "").split("\n").filter(Boolean));
  } catch (_) { /* privater Modus */ }
  for (const select of document.querySelectorAll(".sort-select")) select.value = state.sort;
  renderAddForm();

  let tab = "episodes";
  try { tab = localStorage.getItem("tab") || tab; } catch (_) { /* privater Modus */ }
  showTab(tab);

  // Beim Zurückkehren zur App den Stand vom Mac mini holen
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") load();
  });
  load();
}

setup();
