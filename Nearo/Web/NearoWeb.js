"use strict";

const sections = {
  Overview: "home",
  Messages: "message",
  Photos: "image",
  Calls: "call",
  Contacts: "users",
  Notifications: "bell",
  Files: "folder",
  Commands: "terminal",
};
const $ = (id) => document.getElementById(id);
const esc = (value) =>
  String(value ?? "").replace(
    /[&<>"']/g,
    (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c])
  );
const icon = (name) => `<svg aria-hidden="true" viewBox="0 0 24 24"><use href="#i-${esc(name)}"></use></svg>`;
const initialToken = location.hash.slice(1);
if (initialToken) {
  localStorage.setItem("nearo.session", initialToken);
  history.replaceState(null, "", location.pathname);
}
const token = localStorage.getItem("nearo.session") || "";
const state = {
  page: "Overview",
  device: "",
  thread: "",
  contact: "",
  album: "All",
  search: "",
  tab: "General",
  limit: 100,
  selection: new Set(),
};
const drafts = new Map();
let snapshot = {},
  d = {},
  info = {},
  revision = 0,
  lastView = "",
  openedThread = "";
const theme = matchMedia("(prefers-color-scheme: light)");
function appearance() {
  const light = snapshot.appearance === "light" || (snapshot.appearance !== "dark" && theme.matches);
  document.body.classList.toggle("light", light);
  const colors = snapshot.themeColors?.[light ? "light" : "dark"];
  if (colors) {
    for (const [property, value] of Object.entries(colors)) {
      document.body.style.setProperty(property, value);
    }
  }
}
theme.addEventListener("change", appearance);
appearance();

document.addEventListener("pointermove", (event) => {
  const surface = event.target.closest(".native-quick button")?.querySelector(".quick-icon");
  if (!surface || event.pointerType === "touch") return;
  const bounds = surface.getBoundingClientRect();
  surface.style.setProperty("--shine-x", ((event.clientX - bounds.left) / bounds.width) * 100 + "%");
  surface.style.setProperty("--shine-y", ((event.clientY - bounds.top) / bounds.height) * 100 + "%");
});

const button = (title, glyph, action, id = "", style = "", disabled = false) =>
  `<button type="button" class="btn ${style}" data-action="${action}" data-id="${esc(id)}" ${
    disabled ? "disabled" : ""
  }>${glyph ? icon(glyph) : ""}${esc(title)}</button>`;
const ib = (title, glyph, action, disabled = false) =>
  `<button type="button" class="iconbtn" title="${esc(title)}" aria-label="${esc(
    title
  )}" data-action="${action}" ${disabled ? "disabled" : ""}>${icon(glyph)}</button>`;
const go = (page) => `<button class="textbtn" data-page="${page}">Show All ${icon("chevron")}</button>`;
const dot = (online) => `<span class="dot ${online ? "" : "offline"}"></span>`;
const empty = (text) => `<div class="panel-empty">${esc(text)}</div>`;
const group = (title, content, page = "") =>
  `<section><div class="section-head"><h2>${esc(title)}</h2>${
    page ? go(page) : ""
  }</div><div class="card grouped">${content}</div></section>`;
const head = (title, subtitle, control = "") =>
  `<div class="page-head"><div><h1>${esc(title)}</h1><p class="sub">${esc(
    subtitle
  )}</p></div>${control}</div>`;
const date = (stamp) =>
  stamp
    ? new Date(stamp * 1000).toLocaleString([], {
        month: "short",
        day: "numeric",
        hour: "numeric",
        minute: "2-digit",
      })
    : "";
const imagePath = (kind, id, extra = "") =>
  "/api/image?" + new URLSearchParams({ device: d.id, kind, id, v: extra });
const img = (path, alt = "") => `<img data-image="${esc(path)}" alt="${esc(alt)}">`;
const avatar = (p) =>
  `<span class="avatar">${
    p.photo
      ? img(imagePath("contact", p.id))
      : esc(
          (p.name || "?")
            .trim()
            .split(/\s+/)
            .slice(0, 2)
            .map((w) => w[0])
            .join("")
            .toUpperCase()
        )
  }</span>`;
const search = (placeholder) =>
  `<label class="search">${icon("search")}<input id="search" placeholder="${esc(
    placeholder
  )}" aria-label="${esc(placeholder)}"></label>`;
const match = (...values) => values.join(" ").toLocaleLowerCase().includes(state.search.toLocaleLowerCase());
const available = (page) =>
  d.online || page === "Overview" || (page === "Calls" && (d.calls || d.canSyncCalls)) || (page === "Contacts" && d.contacts) || (page === "Photos" && d.photos);

async function api(path, options = {}) {
  const res = await fetch(path, {
    ...options,
    cache: "no-store",
    headers: { Authorization: "Bearer " + token, ...options.headers },
  });
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    const error = new Error(body.error || "Nearo couldn’t complete the request.");
    error.status = res.status;
    throw error;
  }
  return res;
}
async function act(name, args = {}) {
  await api("/api/action", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ name, device: d.id, ...args }),
  });
}
async function run(name, args = {}, message = "") {
  await act(name, args);
  if (message) toast(message);
  await refresh();
}
let timer;
function toast(message) {
  $("toast").textContent = message;
  $("toast").classList.add("show");
  clearTimeout(timer);
  timer = setTimeout(() => $("toast").classList.remove("show"), 3500);
}
function replace(el, html) {
  if (el._markup !== html) {
    el.innerHTML = html;
    el._markup = html;
  }
}
function resetSelection() {
  state.thread = state.contact = state.search = "";
  state.selection.clear();
  state.album = "All";
  state.limit = 100;
  openedThread = "";
}
function navigate(page, device = state.device) {
  if (device !== state.device) resetSelection();
  state.page = page;
  state.device = device;
  state.search = "";
  state.limit = 100;
  $("sidebar").classList.remove("open");
  refresh();
}
function sidebar() {
  const devices = snapshot.devices || [];
  const rows = (list) =>
    list
      .map(
        (p) =>
          `<button class="device ${p.id === d.id ? "active" : ""}" data-device="${esc(
            p.id
          )}"><span class="device-symbol">${icon(
            ["desktop", "laptop"].includes(p.type) ? "monitor" : "phone"
          )}</span><span class="device-info"><b>${esc(p.name)}</b><small>${dot(p.online)}${esc(
            p.statusLine
          )}</small></span>${
            p.id === d.id ? '<span class="check">' + icon("check") + "</span>" : ""
          }</button>`
      )
      .join("");
  const nearby = devices.filter((p) => p.status === "Nearby");
  return `<div class="sidebar-header"><div class="brand"><img src="/nearo-logo.png" width="30" height="30" alt=""><strong>Nearo</strong></div>${ib(
    "Hide sidebar",
    "sidebar",
    "collapse"
  )}</div>
        <div class="section-label">My devices</div>${rows(devices.filter((p) => p.status !== "Nearby"))}
        ${nearby.length ? '<div class="section-label mt">Nearby</div>' + rows(nearby) : ""}
        ${
          d.id && d.status !== "Nearby"
            ? `<div class="navgroup"><div class="section-label">${esc(d.name)}</div>${Object.entries(sections)
                .map(
                  ([name, glyph]) =>
                    `<button class="nav ${state.page === name ? "active" : ""}" data-page="${name}" ${
                      available(name) ? "" : "disabled"
                    }>${icon(glyph)}<span>${name}</span>${
                      name === "Notifications" && d.notifications
                        ? `<small class="count">${d.notifications}</small>`
                        : ""
                    }</button>`
                )
                .join("")}</div>`
            : ""
        }
        <div class="sidebar-bottom"><button class="nav" data-action="connect">${icon(
          "plus"
        )}<span>Connect a device</span></button><button class="nav ${
    state.page === "Settings" ? "active" : ""
  }" data-page="Settings">${icon("settings")}<span>Settings</span></button></div>`;
}
const searchPrompts = { Contacts: "Search contacts", Messages: "Search conversations", Photos: "Search photos", Calls: "Search calls" };
function toolbar() {
  const prompt = d.id && available(state.page) && searchPrompts[state.page];
  return `<div class="crumb"><button class="iconbtn mobile-toggle" data-action="sidebar" aria-label="Show sidebar">${icon(
    "sidebar"
  )}</button><button class="iconbtn expand-sidebar" data-action="collapse" aria-label="Show sidebar">${icon(
    "sidebar"
  )}</button><div class="window-title"><b>${esc(state.page)}</b><small>${d.id && state.page !== "Settings" ? `<span class="device-status" role="img" aria-label="${esc(d.status)}" title="${esc(d.status)}">${dot(d.online)}</span>` : ""}${esc(
    state.page === "Settings" ? "Nearo" : d.name || "Devices"
  )}</small></div></div>
        <div class="top-actions">${prompt ? search(prompt) : ""}${
          d.id && state.page !== "Settings"
            ? `${ib("Ring phone", "ring", "ring", !d.online)}${ib(
                "Share clipboard",
                "clipboard",
                "clipboard",
                !d.online
              )}${ib("Send files", "send", "sendFiles", !d.online)}<span class="toolbar-sep"></span>`
            : ""
        }${ib("Settings", "settings", "settings")}</div>`;
}
function badge(n) {
  const chat = ["messages", "whatsapp"].includes(n.app.toLowerCase()),
    sun = n.app.toLowerCase().includes("weather");
  return `<span class="notiicon ${chat ? "chat" : sun ? "sun" : ""}">${
    n.image ? img(imagePath("notice", n.id, n.date)) : icon(chat ? "message" : sun ? "sun" : "bell")
  }</span>`;
}
function notice(n, full) {
  return `<div class="${full ? "card notification-card" : "notirow"}">${badge(
    n
  )}<div class="body grow"><small class="appname">${esc(n.app)}</small><h3>${esc(n.title)}</h3><p>${esc(
    n.body
  )}</p><div class="notify-actions">
        ${n.code ? button("Copy " + n.code, "clipboard", "copy", n.code) : ""}${
    full && n.reply ? button("Reply", "message", "reply", n.id) : ""
  }${
    full && n.dismiss ? button("Dismiss", "close", "dismiss", n.id) : ""
  }</div></div><time class="meta">${esc(date(n.date))}</time></div>`;
}
const drop = () =>
  `<button class="drop" data-action="sendFiles">${icon(
    "upload"
  )}<b>Choose files to send</b><p>Browse this Mac and send directly to ${esc(d.name)}</p></button>`;
function overview() {
  const t = info.threads?.[0],
    media = info.media || {};
  const quick = [
    ["Ring", "ring", "ring"],
    ["Clipboard", "clipboard", "clipboard"],
    ["Send Files", "send", "sendFiles"],
    ["Phone Drive", "drive", info.drive === "Mounted" ? "finder" : "files"],
  ];
  return `<div class="overview-native"><section class="device-summary"><div class="device-art" aria-hidden="true"><div class="mac-phone"><div class="mac-screen"><span class="camera-dot"></span><span class="phone-time"></span><div class="wallpaper-shape one"></div><div class="wallpaper-shape two"></div>${info.wallpaper ? img(imagePath("wallpaper", "", info.wallpaper)) : ""}<div class="phone-home"></div></div></div></div>
        <div class="device-description"><div class="hero-kicker">${dot(d.online)}${esc(
    d.status
  )}</div><h1>${esc(d.name)}</h1><p class="device-caption">${
    d.type === "phone" ? "Android phone" : esc(d.type)
  }</p><div class="status-line">${
    d.battery != null
      ? `<span class="status-chip"><span class="green">${icon("battery")}</span><b>${d.battery}%</b></span>`
      : ""
  }
        <span class="status-chip">${icon("wifi")}${esc(d.connection)}</span>${
    d.network ? `<span class="status-chip">${icon("signal")}${esc(d.network)}</span>` : ""
  }</div><div class="meta">${esc(d.statusLine)}</div></div>${button(
    "Device Settings…",
    "settings",
    "deviceSettings",
    "",
    "device-settings"
  )}</section>
        <div class="quick native-quick">${quick
          .map(
            ([label, glyph, action]) =>
              `<button data-action="${action}"><span class="quick-icon">${icon(
                glyph
              )}</span><span>${label}</span></button>`
          )
          .join("")}</div>
        <div class="overview-grid"><div class="stack">${group(
          "Notifications",
          info.notices?.map((n) => notice(n, false)).join("") || empty("All caught up"),
          "Notifications"
        )}
        ${group(
          "Recent Messages",
          t
            ? `<button class="message-preview" data-action="thread" data-id="${esc(
                t.id
              )}"><span class="minirow">${avatar(t)}<span class="grow"><b>${esc(t.name)}</b><small>${esc(
                t.snippet
              )}</small></span>${icon("chevron")}</span></button>`
            : empty("No recent messages"),
          "Messages"
        )}</div>
        <div class="stack">${group(
          "File Transfer",
          '<div class="transfer-drop">' + drop() + "</div>",
          "Files"
        )}${group(
    "On Your Phone",
    ["Contacts", "Photos", "Commands"]
      .map(
        (p) =>
          `<button class="library-row" data-page="${p}"><span class="tile-icon ${sections[p]}">${icon(
            sections[p]
          )}</span><span class="grow"><b>${p}</b><small>${
            d[p.toLowerCase()]
          } ${p.toLowerCase()}</small></span>${icon("chevron")}</button>`
      )
      .join("")
  )}</div></div>
        <div class="overview-foot">${icon("shield")} Your devices communicate directly.</div>
        ${
          media.title
            ? group(
                "Now Playing",
                `<div class="pad"><b>${esc(media.title)}</b><p class="readout">${esc(
                  [media.artist, media.album].filter(Boolean).join(" · ")
                )}</p><div class="actionrow mt">${button("Previous", null, "previous")}${button(
                  media.playing ? "Pause" : "Play",
                  "play",
                  "playPause"
                )}${button("Next", null, "next")}${
                  media.canSetVolume
                    ? `<label>Volume <input type="range" id="volume" min="0" max="1" step=".01" value="${Number(
                        media.volume
                      )}"></label>`
                    : ""
                }</div></div>`
              )
            : ""
        }
        <div class="actionrow mt">${button("Ping", "signal", "ping")}${
    d.canLock ? button("Lock phone", "lock", "lock") : ""
  }${button("Unpair…", "link", "unpair")}</div></div>`;
}
function deviceState() {
  if (!d.id)
    return (
      head(
        "Connect your Android phone",
        "Open KDE Connect on your phone and request pairing on the same network."
      ) + button("Look for devices", "refresh", "discover")
    );
  return (
    head(d.name, d.statusLine) +
    `<div class="card pad"><p>${
      d.status === "Nearby"
        ? "Pair this device to share messages, files and notifications."
        : "Open KDE Connect and reconnect the phone to use device actions."
    }</p><div class="actionrow mt">
        ${
          d.status === "Nearby"
            ? d.awaiting
              ? esc("Waiting for phone… " + d.pairCode)
              : button("Pair", "link", "pair", "", "primary")
            : button("Unpair…", "link", "unpair")
        }
        ${button("Look again", "refresh", "discover")}${button(
      "Connect by address",
      "plus",
      "connect"
    )}</div></div>`
  );
}
const listRow = (p, active, action, sub) =>
  `<button class="person ${active ? "active" : ""}" aria-pressed="${active}" data-action="${action}" data-id="${esc(p.id)}">${avatar(
    p
  )}<span class="grow"><b>${esc(p.name)}</b><small>${esc(sub)}</small></span>${active ? `<span class="check">${icon("check")}</span>` : ""}</button>`;
function messages() {
  const threads = info.threads || [];
  const t = threads.find((t) => t.id === info.thread);
  const list = threads.filter((t) => match(t.name, t.snippet, ...t.addresses));
  const sims = info.sims || [];
  return `<div class="split"><div class="listpane"><div class="list-top">${ib("New message", "edit", "newSMS")}${ib(
    "Sync messages",
    "refresh",
    "refreshMessages"
  )}</div><div class="list-scroll">${
    list.map((p) => listRow(p, p.id === t?.id, "thread", p.snippet)).join("") || empty("No conversations")
  }</div></div>
        <div class="detail">${
          t
            ? `<div class="detail-head">${avatar(t)}<div class="grow"><b>${esc(t.name)}</b><br><small>${esc(
                t.addresses.join(", ")
              )} · SMS</small></div>${button("Copy", "clipboard", "copy", t.addresses.join(", "))}</div>
        <div id="chatlog" class="chatlog"><div class="day">${button(
          "Load earlier messages",
          null,
          "earlier",
          t.id
        )}</div>${(info.messages || [])
                .map(
                  (m) =>
                    `<div class="bubble ${m.out ? "me" : ""}">${esc(m.text)}${
                      m.attachments ? `<small>${m.attachments} attachment(s)</small>` : ""
                    }<small>${esc(date(m.date))}</small></div>`
                )
                .join("")}</div>
        <form class="composer" id="sms"><input id="draft" name="text" aria-label="Message" placeholder="Type a message…" value="${esc(
          drafts.get(draftKey()) || ""
        )}" required>${
                sims.length > 1
                  ? `<select name="sim" aria-label="SIM">${sims
                      .map(
                        (s) =>
                          `<option value="${esc(s.id)}" ${s.id === info.defaultSIM ? "selected" : ""}>${esc(
                            s.name
                          )}</option>`
                      )
                      .join("")}</select>`
                  : ""
              }<button class="btn primary" aria-label="Send message">${icon("send")}</button></form>`
            : empty("Choose a conversation or start a new message.")
        }</div></div>`;
}
function calls() {
  const rows = (info.calls || []).filter((c) => match(c.caller, c.number, c.kind)).map((call) => {
    const subtitle = call.number && call.caller !== call.number ? call.kind + " · " + call.number : call.kind;
    return `<div class="transfer"><span class="tile-icon">${icon("call")}</span><div class="grow"><b>${esc(
      call.caller
    )}</b><small>${esc(subtitle)}</small></div><small>${esc(date(call.date))}</small></div>`;
  });
  const status = info.syncing ? "Reading call history over Bluetooth…" : info.syncMessage || "Recent calls on " + d.name;
  return head("Calls", status, button("Sync calls", "refresh", "syncCalls", "", "", !d.canSyncCalls || info.syncing)) +
    `<div class="card grouped">${rows.join("") || empty(
      state.search ? "No matching calls" : "Allow contact and call history sharing for this Mac in your phone’s Bluetooth settings."
    )}</div>`;
}

function contacts() {
  const list = (info.contacts || []).filter((c) => match(c.name, ...c.numbers, ...c.emails));
  const c = list.find((c) => c.id === state.contact) || list[0];
  return `<div class="split"><div class="listpane"><div class="list-top">${ib(
    "Sync contacts",
    "refresh",
    "refreshContacts",
    !d.online
  )}</div><div class="list-scroll">${
    list
      .slice(0, state.limit)
      .map((p) => listRow(p, p.id === c?.id, "contact", p.numbers[0] || p.emails[0] || ""))
      .join("") || empty("No contacts")
  }${more(list)}</div></div>
        <div class="detail"><div class="detail-head"><b>Contact details</b></div>${
          c
            ? `<div class="contact-body"><div class="contact-hero">${avatar(c)}<h2>${esc(
                c.name
              )}</h2><p>${esc(c.numbers[0])}</p><div class="contact-actions">${
                c.numbers[0]
                  ? button("Message", "message", "newSMS", c.numbers[0], "primary", !d.online) +
                    button("Copy number", "clipboard", "copy", c.numbers[0])
                  : ""
              }</div></div>
        <div class="card pad"><h2>Phone numbers</h2>${
          c.numbers
            .map(
              (n) =>
                `<div class="data-row">${icon("call")}<span class="grow">${esc(n)}</span>${button(
                  "Copy",
                  "clipboard",
                  "copy",
                  n
                )}${button("Message", "message", "newSMS", n, "", !d.online)}</div>`
            )
            .join("") || empty("No numbers")
        }
        ${c.emails
          .map(
            (e) =>
              `<div class="data-row"><span class="grow">${esc(e)}</span>${button(
                "Copy",
                "clipboard",
                "copy",
                e
              )}<a class="btn" href="mailto:${encodeURIComponent(e)}">Mail</a></div>`
          )
          .join("")}<div class="divider"></div><small>Synced from ${esc(d.name)}</small></div></div>`
            : empty("No contact selected")
        }</div></div>`;
}
function more(list) {
  return list.length > state.limit ? button("Show more", null, "more") : "";
}
function photos() {
  const all = info.photos || [];
  const albums = ["All", ...new Set(all.map((p) => p.album).filter(Boolean))];
  const list = all.filter(
    (p) => (state.album === "All" || p.album === state.album) && match(p.name, p.album)
  );
  return (
    head(
      "Photos",
      "Photos and albums on " + d.name,
      button("Refresh", "refresh", "refreshPhotos", "", "", !d.online || info.loading)
    ) +
    `<div class="toolbar"><div class="filters">${albums
      .map(
        (f) =>
          `<button class="filter ${state.album === f ? "active" : ""}" data-action="album" data-id="${esc(
            f
          )}">${esc(f)}</button>`
      )
      .join("")}</div><span class="push"></span>${button(
      state.selection.size ? "Download (" + state.selection.size + ")" : "Download",
      "download",
      "saveSelection",
      "",
      "primary",
      !state.selection.size
    )}</div>
        <p class="meta">${info.loading ? "Scanning…" : list.length + " photos"}</p><div class="gallery">${list
      .slice(0, state.limit)
      .map(
        (p) =>
          `<div class="gallery-item"><button class="photo ${
            state.selection.has(p.id) ? "selected" : ""
          }" data-action="preview" data-id="${esc(p.id)}"><span class="thumb">${img(
            imagePath("thumb", p.id, p.modified),
            p.name
          )}</span><div class="photo-info"><b>${esc(p.name)}</b><small>${esc(p.album)} · ${esc(
            p.size
          )}</small></div></button><button class="selectbox" data-action="selectPhoto" data-id="${esc(
            p.id
          )}" aria-label="Select ${esc(p.name)}" role="checkbox" aria-checked="${state.selection.has(
            p.id
          )}">${state.selection.has(p.id) ? icon("check") : ""}</button></div>`
      )
      .join("")}</div>${list.length ? more(list) : empty("No photos found")}`
  );
}
function files() {
  const mounted = info.drive === "Mounted";
  const actions = mounted
    ? button("Show in Finder", "folder", "finder", "", "primary") + button("Eject", "close", "eject")
    : button(
        info.drive === "Turned off" ? "Turn on phone drives" : "Mount drive",
        "drive",
        "mount",
        "",
        "primary",
        info.drive === "Mounting"
      );
  return (
    head(
      "Files",
      "Send files and browse phone storage.",
      button("Choose files", "plus", "sendFiles", "", "primary")
    ) +
    `<div class="page-list">${group(
      "Phone drive",
      `<div class="pad"><div class="drive"><span class="tile-icon">${icon("drive")}</span><div><h3>${esc(
        d.name
      )} storage</h3><p>${esc(
        info.driveError || info.drive
      )}</p></div></div><div class="actionrow">${actions}</div></div>`
    )}
        ${group("Send to phone", '<div class="transfer-drop">' + drop() + "</div>")}${group(
      "Transfer activity",
      '<div class="pad">' +
        button("Open Downloads", "folder", "downloads") +
        (info.transfers
          ?.map(
            (t) =>
              `<div class="transfer"><span class="tile-icon">${icon("file")}</span><div class="grow"><b>${esc(
                t.name
              )}</b><small>${esc(t.size)} · ${esc(t.direction)}</small></div><small>${esc(t.status)}</small>${
                t.reveal ? button("Reveal", "folder", "reveal", t.id) : ""
              }</div>`
          )
          .join("") || empty("No transfers yet")) +
        "</div>"
    )}</div>`
  );
}
function commands() {
  return (
    head(
      "Commands",
      "Run commands on your Mac from " + d.name + ".",
      button("Add Command…", "plus", "editCommand", "", "primary")
    ) +
    group(
      "On This Mac",
      (info.commands || [])
        .map(
          (c) =>
            `<div class="command"><span class="tile-icon">${icon(
              "terminal"
            )}</span><div class="command-info"><b>${esc(c.name)}</b><code>${esc(c.code)}</code></div>${button(
              "Run",
              "play",
              "run",
              c.id
            )}${button("Options", "more", "commandOptions", c.id)}</div>`
        )
        .join("") || empty("No commands yet")
    ) +
    '<p class="help-text">Commands run with your user permissions. Only add commands you trust.</p><div class="mt">' +
    group("Shortcuts", toggle("Show my Mac shortcuts on the phone", "shortcuts", info.shortcuts)) +
    "</div>"
  );
}
function notifications() {
  return (
    head(
      "Notifications",
      d.notifications + " notifications on " + d.name,
      button("Clear all", "trash", "clear", "", "", !info.notices?.some((n) => n.dismiss))
    ) +
    `<div class="notifications-list">${
      info.notices?.map((n) => notice(n, true)).join("") || empty("You’re all caught up")
    }</div>`
  );
}

function pref(title, control) {
  return `<div class="pref"><span>${esc(title)}</span>${control}</div>`;
}
function toggle(title, key, value, device = "") {
  return pref(
    title,
    `<button class="toggle ${value ? "on" : ""}" role="switch" aria-checked="${Boolean(
      value
    )}" aria-label="${esc(title)}" data-action="toggle" data-id="${esc(key)}" data-target="${esc(
      device
    )}" data-value="${!value}"></button>`
  );
}
function selectPref(title, key, value, values, device = "") {
  return pref(
    title,
    `<select aria-label="${esc(title)}" data-pref="${key}" data-target="${esc(device)}">${values
      .map((v) => `<option value="${esc(v)}" ${v === value ? "selected" : ""}>${esc(v)}</option>`)
      .join("")}</select>`
  );
}
function settings() {
  const s = snapshot.settings;
  if (!s) return empty("Loading settings…");
  const tabs = { General: "settings", Themes: "sun", Devices: "phone", Files: "folder", Permissions: "shield", About: "nearby" };
  let body;
  switch (state.tab) {
    case "Themes": {
      const tiles = snapshot.themeOptions.map((name) => {
        const palette = snapshot.themePalettes[name];
        const swatches = ["light", "dark"].map((mode) => {
          const colors = palette[mode];
          return `<span aria-hidden="true" class="theme-sample sample-${mode}" style="--canvas:${colors["--bg"]};--rail:${colors["--side"]};--ink:${colors["--blue"]};--surface:${colors["--panel"]}"></span>`;
        }).join("");
        const selected = name === snapshot.theme;
        return `<button class="theme-choice" data-action="theme" data-id="${esc(name)}" aria-pressed="${selected}">${swatches}<span>${esc(name)}${selected ? icon("check") : ""}</span></button>`;
      }).join("");
      body = group("Appearance", selectPref("Appearance", "appearance", snapshot.appearance, ["system", "light", "dark"])) +
        `<div class="theme-gallery">${tiles}</div>`;
      break;
    }
    case "Devices":
      body =
        s.paired
          .map((p) =>
            group(
              p.name,
              toggle("Share clipboard", "deviceClipboard", p.clipboard, p.id) +
                toggle("Show phone notifications", "deviceNotifications", p.notifications, p.id) +
                pref("Paired", esc(date(p.paired))) +
                pref("Pairing", button("Unpair…", "link", "unpair", p.id))
            )
          )
          .join("") || empty("No paired devices");
      break;
    case "Files":
      body =
        group("Phone drives", toggle("Mount phones as drives", "mount", s.mount)) +
        s.paired
          .map((p) =>
            group(
              p.name,
              selectPref("Access files using", "method", p.method, ["sftp", "adb"], p.id) +
                (p.method === "adb"
                  ? pref("Wireless debugging address", button(p.adb || "Set address", null, "adb", p.id))
                  : "") +
                (p.driveError ? empty(p.driveError) : "")
            )
          )
          .join("");
      break;
    case "Permissions":
      body =
        group(
          "Permissions",
          pref(
            "Notifications",
            button(
              s.notifications ? "Open settings…" : "Allow…",
              "bell",
              "permission",
              "notificationsPermission"
            )
          ) +
            pref(
              "Accessibility",
              s.accessibility
                ? "Allowed"
                : button("Allow…", "settings", "permission", "accessibilityPermission")
            )
        ) +
        group("Presenter", pref("Laser pointer", button("Show test pointer", null, "permission", "pointer")));
      break;
    case "About":
      body = group(
        "Nearo",
        pref("Version", esc(s.version)) +
          pref("Author", "Anwarul Islam") +
          toggle("Check for updates automatically", "autoUpdate", s.autoUpdate) +
          pref("Software update", button("Check now", "refresh", "permission", "checkUpdate"))
      );
      break;
    default:
      body =
        group(
          "This Mac",
          pref("Name", button(s.mac, "edit", "renameMac")) +
            [
              ["Open at Login", "login"],
              ["Reduce motion", "reduceMotion"],
              ["Copy verification codes automatically", "copyCodes"],
              ["Show calls in a floating card", "callCard"],
              ["Pause media during calls", "pauseCalls"],
              ["Lock this Mac when your phone leaves", "awayLock"],
            ]
              .map(([label, key]) => toggle(label, key, s[key]))
              .join("")
        ) +
        group(
          "Web access",
          pref("Domain", esc(s.webDomain)) +
            pref("Loopback IP", esc(s.webIP)) +
            pref("Available on this Mac", button("Turn off web access", null, "stopWeb"))
        ) +
        group(
          "Connections",
          toggle("Find devices over Tailscale", "tailscale", s.tailscale) +
            pref("Tailscale status", esc(s.tailscaleStatus)) +
            toggle("Enable Bluetooth", "bluetooth", s.bluetooth) +
            pref("Bluetooth status", esc(s.bluetoothStatus))
        ) +
        group(
          "Identity",
          pref("Device ID", `<span class="mono">${esc(s.identity)}</span>`) +
            pref("Certificate", `<span class="mono">${esc(s.fingerprint)}</span>`) +
            pref("Listening on", esc(s.port))
        );
  }
  return `<section class="settings">${head("Settings", "Nearo on this Mac")}<div class="filters settings-tabs">${Object.entries(tabs)
    .map(
      ([tab, glyph]) =>
        `<button class="filter ${
          tab === state.tab ? "active" : ""
        }" data-action="tab" aria-pressed="${tab === state.tab}" data-id="${tab}">${icon(glyph)}${tab}</button>`
    )
    .join("")}</div><div class="page-list">${body}</div></section>`;
}

const views = {
  Overview: overview,
  Messages: messages,
  Calls: calls,
  Contacts: contacts,
  Photos: photos,
  Notifications: notifications,
  Files: files,
  Commands: commands,
  Settings: settings,
};
const draftKey = () => JSON.stringify([d.id, info.thread]);
function render() {
  appearance();
  replace($("sidebar"), sidebar());
  const activeSearch = document.activeElement?.id === "search" ? document.activeElement : null;
  const selection = activeSearch && [activeSearch.selectionStart, activeSearch.selectionEnd];
  replace($("topbar"), toolbar());
  const input = $("search");
  if (input && input.value !== state.search) input.value = state.search;
  if (input && activeSearch && activeSearch !== input) {
    input.focus({ preventScroll: true });
    input.setSelectionRange(...selection);
  }
  const content = $("content");
  content.dataset.view = state.page;
  const key = [state.device, state.page, info.thread].join("/");
  const focused = content.contains(document.activeElement) ? document.activeElement : null;
  const focus = focused?.id;
  const caret =
    focus && typeof focused.selectionStart === "number"
      ? [focused.selectionStart, focused.selectionEnd]
      : null;
  const log = $("chatlog"),
    atBottom = !log || log.scrollHeight - log.scrollTop - log.clientHeight < 4;
  const oldChat = log?.scrollTop || 0,
    listScroll = content.querySelector(".list-scroll")?.scrollTop || 0;
  let html =
    state.page === "Settings" || (d.id && (d.online || (state.page !== "Overview" && available(state.page))))
      ? views[state.page]()
      : deviceState();
  if (snapshot.request) {
    const r = snapshot.request;
    html =
      `<div class="card pad"><h2>Pair with ${esc(r.name)}?</h2><p>Verification code: ${esc(
        r.code || r.fingerprint
      )}</p><div class="actionrow">${button("Accept", "check", "acceptPair", r.id, "primary")}${button(
        "Decline",
        "close",
        "declinePair",
        r.id
      )}</div></div>` + html;
  }
  html = '<div class="wrap">' + html + "</div>";
  if (content._markup !== html) {
    replace(content, html);
    if (lastView !== key) content.scrollTop = 0;
    const list = content.querySelector(".list-scroll");
    if (list && lastView === key) list.scrollTop = listScroll;
    if (focus && lastView === key && $(focus)) {
      $(focus).focus({ preventScroll: true });
      if (caret) $(focus).setSelectionRange(...caret);
    }
    const chat = $("chatlog");
    if (chat) chat.scrollTop = atBottom || lastView !== key ? chat.scrollHeight : oldChat;
    lastView = key;
    watchImages();
  }
  const clock = content.querySelector(".phone-time");
  if (clock) {
    clock.textContent = info.phoneTime || "";
    const handset = clock.closest(".device-art");
    handset.title = info.handsetHelp || "";
    if (info.phoneTime) {
      handset.removeAttribute("aria-hidden");
      handset.setAttribute("role", "img");
      handset.setAttribute("aria-label", info.clockDescription + ", " + info.phoneTime);
    }
  }
  document.title = state.page + " · Nearo";
}
function disconnected(message) {
  $("modal").close();
  replace($("sidebar"), "");
  replace($("topbar"), "");
  replace($("content"), head("Nearo web access", message));
  snapshot = {};
  d = {};
  info = {};
  drafts.clear();
  state.selection.clear();
  clearImages();
}
async function refresh() {
  if (!token) {
    disconnected("Choose “Open Nearo on Web” in the Nearo menu bar to connect this browser.");
    return;
  }
  const mine = ++revision;
  try {
    const params = new URLSearchParams({ device: state.device, page: state.page, thread: state.thread });
    const next = await (await api("/api/state?" + params)).json();
    if (mine !== revision) return;
    snapshot = next;
    if (state.device !== next.device) {
      resetSelection();
      if ($("modal").open) $("modal").close();
    }
    state.device = next.device || "";
    d = next.devices.find((p) => p.id === state.device) || {};
    info = next.detail || {};
    if (state.page !== "Settings" && !available(state.page)) {
      navigate("Overview");
      return;
    }
    if (state.page === "Photos") {
      const ids = new Set((info.photos || []).map((p) => p.id));
      for (const id of state.selection) if (!ids.has(id)) state.selection.delete(id);
    }
    render();
    if (state.page === "Calls" && info.needsSync) await act("loadCalls");
    if (state.page === "Messages" && d.online && info.thread) {
      state.thread = info.thread;
      const threadKey = draftKey();
      if (openedThread !== threadKey) {
        openedThread = threadKey;
        await act("openThread", { id: info.thread });
      }
    }
  } catch (error) {
    if (mine !== revision) return;
    disconnected(
      error.status === 401
        ? "This link has expired. Choose “Open Nearo on Web” in the Nearo menu bar to reconnect."
        : "Nearo is unavailable. Check that the app is running and web access is on."
    );
  }
}

// Fetch visible images with the session credential. Photo URLs themselves contain no secret.
const imageCache = new Map();
function clearImages() {
  for (const entry of imageCache.values()) {
    entry.abort.abort();
    if (entry.url) URL.revokeObjectURL(entry.url);
  }
  imageCache.clear();
}
async function loadImage(el) {
  const path = el.dataset.image;
  let entry = imageCache.get(path);
  if (!entry) {
    entry = { abort: new AbortController(), url: null };
    imageCache.set(path, entry);
    entry.promise = api(path, { signal: entry.abort.signal })
      .then((r) => r.blob())
      .then((blob) => {
        if (imageCache.get(path) === entry) entry.url = URL.createObjectURL(blob);
        return entry.url;
      })
      .catch(() => null);
  }
  const url = await entry.promise;
  if (url && el.isConnected) el.src = url;
  else if (el.isConnected) el.alt = "Image unavailable";
}
const observer = new IntersectionObserver(
  (entries) => {
    for (const item of entries)
      if (item.isIntersecting) {
        observer.unobserve(item.target);
        loadImage(item.target);
      }
  },
  { rootMargin: "150px" }
);
function watchImages() {
  observer.disconnect();
  const used = new Set();
  for (const el of document.querySelectorAll("[data-image]")) {
    used.add(el.dataset.image);
    if (!el.hasAttribute("src")) observer.observe(el);
  }
  for (const [path, entry] of imageCache)
    if (!used.has(path)) {
      entry.abort.abort();
      if (entry.url) URL.revokeObjectURL(entry.url);
      imageCache.delete(path);
    }
}

const field = (label, name, value = "", area = false) =>
  `<label for="field-${name}">${esc(label)}</label>${
    area
      ? `<textarea id="field-${name}" name="${name}" required>${esc(value)}</textarea>`
      : `<input id="field-${name}" name="${name}" value="${esc(value)}" required>`
  }`;
function dialog(title, body, submit = "", handler = null) {
  const modal = $("modal");
  if (modal.open) modal.close();
  modal.innerHTML = `<form><h2>${esc(
    title
  )}</h2>${body}<p class="error" role="alert"></p><div class="modal-actions">${button(
    submit ? "Cancel" : "Close",
    null,
    "close"
  )} ${submit ? `<button class="btn primary" type="submit">${esc(submit)}</button>` : ""}</div></form>`;
  const form = modal.firstElementChild;
  form.onsubmit = async (event) => {
    event.preventDefault();
    if (!handler || form.dataset.busy) return;
    const values = Object.fromEntries(new FormData(form));
    form.dataset.busy = "true";
    form.querySelector("[type=submit]").disabled = true;
    try {
      await handler(values);
      if (modal.firstElementChild === form) modal.close();
    } catch (error) {
      form.querySelector(".error").textContent = error.message;
    } finally {
      delete form.dataset.busy;
      form.querySelector("[type=submit]").disabled = false;
    }
  };
  modal.showModal();
  watchImages();
}
function confirmAction(title, message, name, args = {}) {
  const device = d.id;
  dialog(title, `<p>${esc(message)}</p>`, "Confirm", () => run(name, { device, ...args }));
}
function preview(id) {
  const photos = (info.photos || []).filter(
    (p) => (state.album === "All" || p.album === state.album) && match(p.name, p.album)
  );
  const index = photos.findIndex((p) => p.id === id),
    p = photos[index];
  if (!p) return;
  dialog(
    p.name,
    `<p>${esc(p.album)} · ${esc(p.size)}</p><img class="modal-image" alt="${esc(p.name)}" data-image="${esc(
      imagePath("preview", p.id, p.modified)
    )}"><div class="actionrow">${button(
      "Previous",
      null,
      "preview",
      photos[index - 1]?.id,
      "",
      index === 0
    )}${button("Next", null, "preview", photos[index + 1]?.id, "", index === photos.length - 1)}${button(
      "Save to Downloads",
      "download",
      "savePhoto",
      p.id
    )}</div>`
  );
}
async function action(name, id, el) {
  const device = d.id;
  const setting = (key, value, extra = {}) => run("setting", { id: key, value, ...extra });
  switch (name) {
    case "collapse":
      if (matchMedia("(max-width:800px)").matches) $("sidebar").classList.remove("open");
      else document.querySelector(".app").classList.toggle("sidebar-collapsed");
      return;
    case "sidebar":
      $("sidebar").classList.toggle("open");
      return;
    case "close":
      $("modal").close();
      return;
    case "settings":
      navigate("Settings");
      return;
    case "deviceSettings":
      state.tab = "Devices";
      navigate("Settings");
      return;
    case "files":
      navigate("Files");
      return;
    case "theme":
      await run("setting", { id: "theme", value: id });
      return;
    case "tab":
      state.tab = id;
      render();
      return;
    case "more":
      state.limit += 100;
      render();
      return;
    case "contact":
      state.contact = id;
      render();
      return;
    case "thread":
      state.thread = id;
      navigate("Messages");
      return;
    case "album":
      state.album = id;
      state.limit = 100;
      render();
      return;
    case "selectPhoto":
      if (state.selection.has(id)) state.selection.delete(id);
      else state.selection.add(id);
      render();
      return;
    case "preview":
      preview(id);
      return;
    case "saveSelection": {
      let count = 0;
      for (const photo of [...state.selection]) {
        await act("savePhoto", { device, id: photo });
        state.selection.delete(photo);
        count++;
        render();
      }
      toast(count + " saved to Downloads");
      return;
    }
    case "savePhoto":
      await run("savePhoto", { device, id }, "Saved to Downloads");
      return;
    case "copy":
      if (navigator.clipboard) {
        await navigator.clipboard.writeText(id);
      } else {
        const field = document.createElement("textarea");
        field.value = id;
        document.body.append(field);
        field.select();
        const copied = document.execCommand("copy");
        field.remove();
        if (!copied) throw new Error("The browser couldn’t copy this text.");
      }
      toast("Copied");
      return;
    case "newSMS":
      dialog(
        "New message",
        field("Recipient phone number", "number", id) +
          field("Message", "text", "", true) +
          ((info.sims || []).length > 1
            ? `<label for="new-sim">SIM</label><select id="new-sim" name="sim">${info.sims
                .map((s) => `<option value="${esc(s.id)}">${esc(s.name)}</option>`)
                .join("")}</select>`
            : ""),
        "Send",
        async (v) => {
          await run(
            "sms",
            { device, addresses: [v.number.trim()], text: v.text, sim: v.sim },
            "Message sent to phone"
          );
        }
      );
      return;
    case "clipboard":
      dialog("Share clipboard", field("Text to send to " + d.name, "text", "", true), "Send to phone", (v) =>
        run("clipboard", { device, text: v.text }, "Clipboard shared")
      );
      return;
    case "reply":
      dialog("Reply to notification", field("Reply", "text", "", true), "Send", (v) =>
        run("reply", { device, id, text: v.text }, "Reply sent to phone")
      );
      return;
    case "connect":
      dialog("Connect a device", field("IP address or hostname", "text"), "Connect", (v) =>
        run("connect", { text: v.text.trim() })
      );
      return;
    case "unpair":
      confirmAction("Unpair device?", "You’ll need to pair again to reconnect.", "unpair", {
        device: id || device,
      });
      return;
    case "clear":
      confirmAction(
        "Clear notifications?",
        "Dismiss all dismissible notifications on " + d.name + "?",
        "clear"
      );
      return;
    case "acceptPair":
    case "declinePair": {
      const pair = snapshot.request;
      if (pair?.id === id) await run(name, { id, text: pair.code, value: pair.fingerprint });
      return;
    }
    case "commandOptions":
      dialog(
        "Command options",
        '<div class="actionrow">' +
          button("Edit", "edit", "editCommand", id) +
          button("Duplicate", "clipboard", "duplicateCommand", id) +
          button("Delete", "trash", "deleteCommand", id) +
          "</div>"
      );
      return;
    case "editCommand": {
      const c = info.commands?.find((c) => c.id === id);
      dialog(
        id ? "Edit command" : "Add command",
        field("Name", "name", c?.name) + field("Shell command", "code", c?.code, true),
        "Save",
        (v) => run("saveCommand", { device, id, text: v.name.trim(), value: v.code.trim() })
      );
      return;
    }
    case "deleteCommand":
      confirmAction("Delete command?", "Remove this command from Nearo?", "deleteCommand", { id });
      return;
    case "duplicateCommand":
      await run(name, { id });
      $("modal").close();
      return;
    case "run":
      await run("run", { id }, "Command requested");
      return;
    case "renameMac":
      dialog("Name this Mac", field("Name", "text", snapshot.settings.mac), "Save", (v) =>
        setting("mac", "", { text: v.text })
      );
      return;
    case "adb":
      dialog(
        "Wireless debugging",
        field("Address", "text", snapshot.settings.paired.find((p) => p.id === id)?.adb),
        "Save",
        (v) => setting("adb", "", { device: id, text: v.text })
      );
      return;
    case "toggle":
      await setting(id, el.dataset.value, { device: el.dataset.target || device });
      return;
    case "permission":
      await setting(id, "");
      return;
    case "stopWeb":
      dialog(
        "Turn off web access?",
        "<p>You can enable it again in Nearo Settings on this Mac.</p>",
        "Turn off",
        async () => {
          await act("stopWeb");
          disconnected("Web access is off. You can enable it again in Nearo Settings.");
        }
      );
      return;
    default:
      if (
        [
          "ring",
          "ping",
          "sendFiles",
          "lock",
          "pair",
          "discover",
          "refreshPhotos",
          "syncCalls",
          "refreshContacts",
          "refreshMessages",
          "earlier",
          "dismiss",
          "mount",
          "eject",
          "finder",
          "downloads",
          "reveal",
          "playPause",
          "previous",
          "next",
        ].includes(name)
      ) {
        await run(
          name,
          { id },
          ["ring", "ping", "sendFiles", "lock"].includes(name) ? "Request sent to Nearo" : ""
        );
      }
  }
}
document.addEventListener("click", async (e) => {
  const el = e.target.closest("[data-action],[data-page],[data-device]");
  if (!el || el.disabled || el.dataset.busy) return;
  if (el.dataset.page) {
    navigate(el.dataset.page);
    return;
  }
  if (el.dataset.device) {
    navigate("Overview", el.dataset.device);
    return;
  }
  el.dataset.busy = "true";
  try {
    await action(el.dataset.action, el.dataset.id || "", el);
  } catch (error) {
    toast(error.message);
  } finally {
    delete el.dataset.busy;
  }
});
document.addEventListener("keydown", (event) => {
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "f" && $("search") && !$("modal").open) {
    event.preventDefault();
    $("search").focus();
    $("search").select();
  }
});
document.addEventListener("input", (e) => {
  if (e.target.id === "search") {
    state.search = e.target.value;
    state.limit = 100;
    render();
  }
  if (e.target.id === "draft") drafts.set(draftKey(), e.target.value);
});
document.addEventListener("change", async (e) => {
  try {
    if (e.target.dataset.pref)
      await run("setting", {
        id: e.target.dataset.pref,
        value: e.target.value,
        device: e.target.dataset.target || d.id,
      });
    if (e.target.id === "volume") await run("volume", { text: e.target.value });
  } catch (error) {
    toast(error.message);
  }
});
document.addEventListener("submit", async (e) => {
  if (e.target.id !== "sms") return;
  e.preventDefault();
  const form = e.target,
    key = draftKey();
  if (form.dataset.busy) return;
  const values = Object.fromEntries(new FormData(form));
  form.dataset.busy = "true";
  try {
    await act("sms", { id: info.thread, text: values.text, sim: values.sim });
    drafts.delete(key);
    form.reset();
    await refresh();
    toast("Message sent to phone");
  } catch (error) {
    toast(error.message);
  } finally {
    delete form.dataset.busy;
  }
});
$("modal").addEventListener("close", watchImages);
document.addEventListener("visibilitychange", () => {
  if (!document.hidden) refresh();
});
async function poll() {
  if (!document.hidden || !lastView) await refresh();
  setTimeout(poll, 3500);
}
poll();
