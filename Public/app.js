// TV Launcher – Web-App fürs iPhone.
// Spricht nur relative Adressen (/api/...) an: läuft so unverändert auf dem Mac mini
// und auf dem MacBook (dort reicht der Server die Anfragen an den Mac mini weiter).
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
};

const $ = (id) => document.getElementById(id);

// ---------- Schnittstelle ----------

async function api(path, body) {
  const options = body === undefined
    ? { cache: "no-store" }
    : { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) };
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
  $("refresh").classList.add("spinning");
  try {
    const data = await api("/api/shows");
    state.shows = data.shows || [];
    state.lastPlayed = data.lastPlayed || null;
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
    $("refresh").classList.remove("spinning");
  }
}

async function play(episode) {
  if (state.playingKey) return;
  state.playingKey = key(episode);
  render();
  try {
    const data = await api("/api/play", { show: episode.show, id: episode.id });
    state.lastPlayed = { show: episode.show, id: episode.id };
    state.lastPlayedByShow[episode.show] = episode.id;
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
const seasons = () => [...new Set(episodesOf(state.show).map((e) => e.season))].sort((a, b) => b - a);
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
  renderHero();
  renderShows();
  renderSeasons();
  renderEpisodes();
  renderNow();
}

function renderHero() {
  const last = lastPlayed();
  $("hero").hidden = !last || state.search !== "";
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
  for (const show of state.shows) {
    const button = el("button", "", show.name);
    button.setAttribute("role", "tab");
    button.setAttribute("aria-selected", String(show.id === state.show));
    button.addEventListener("click", () => {
      state.show = show.id;
      state.season = seasons()[0] ?? null;
      try { localStorage.setItem("show", show.id); } catch (_) { /* privater Modus */ }
      render();
    });
    box.appendChild(button);
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
      : show?.kind === "custom" ? "Noch keine Links – in der Mac-App unter Einstellungen → Shows eintragen."
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
  const last = lastPlayed();
  if (!last) return;
  const show = showByID(last.show);
  box.appendChild(el("div", "now-caption", `Zuletzt gestartet · ${show ? show.name : ""} · ${code(last)}`));
  box.appendChild(el("div", "now-title", last.title));
  if (last.subtitle) box.appendChild(el("div", "now-subtitle", last.subtitle));
}

// ---------- Tabs ----------

function showTab(name) {
  for (const tab of document.querySelectorAll(".tab")) {
    tab.setAttribute("aria-selected", String(tab.dataset.tab === name));
  }
  $("view-episodes").hidden = name !== "episodes";
  $("view-remote").hidden = name !== "remote";
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
      const speed = 1.8 + Math.min(Math.hypot(dx, dy), 30) * 0.12;
      sendInput({ kind: "move", dx: dx * speed, dy: dy * speed });
    } else if (gesture.mode === "scroll" && event.touches.length === 2) {
      sendInput({ kind: "scroll", dx: dx * 2, dy: dy * 2 });
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
  $("refresh").addEventListener("click", () => load(true));
  $("link-form").addEventListener("submit", startLink);
  $("remote-link-form").addEventListener("submit", startLink);
  $("search").addEventListener("input", (event) => {
    state.search = event.target.value;
    render();
  });
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

  try { state.show = localStorage.getItem("show"); } catch (_) { /* privater Modus */ }

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
