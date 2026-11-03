// Remote Desk: the launcher and a touch-first noVNC viewer, served by spike's remote-desk gateway.
import RFB from '/novnc/core/rfb.js';
import KeyTable from '/novnc/core/input/keysym.js';
import keysyms from '/novnc/core/input/keysymdef.js';

const $ = (id) => document.getElementById(id);
const views = ['login', 'launcher', 'viewer'];
const show = (name) => views.forEach((view) => { $(view).hidden = view !== name; });

let idleMinutes = 15;
let refreshTimer = null;

async function api(path, options = {}) {
  const response = await fetch(path, { credentials: 'same-origin', ...options });
  if (response.status === 401) { showLogin(); throw new Error('logged out'); }
  const body = response.headers.get('content-type')?.includes('json') ? await response.json() : {};
  if (!response.ok) throw new Error(body.error || response.statusText);
  return body;
}

// ---- login -----------------------------------------------------------------------------------------------------

function showLogin(message = '') {
  stopRefresh();
  $('login-error').textContent = message;
  show('login');
}

$('login-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  $('login-error').textContent = '';
  const response = await fetch('/api/login', {
    method: 'POST',
    credentials: 'same-origin',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ device: $('device').value.trim(), password: $('password').value }),
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) { $('login-error').textContent = body.error || 'could not log in'; return; }
  $('password').value = '';
  idleMinutes = body.idleMinutes;
  showLauncher(body.device);
});

$('logout').addEventListener('click', async () => {
  await api('/api/logout', { method: 'POST' }).catch(() => {});
  showLogin();
});

// ---- launcher --------------------------------------------------------------------------------------------------

function stopRefresh() { clearInterval(refreshTimer); refreshTimer = null; }

function showLauncher(device) {
  $('launcher-message').textContent = '';
  if (device) $('whoami').textContent = `as ${device}`;
  show('launcher');
  refreshHosts();
  stopRefresh();
  refreshTimer = setInterval(refreshHosts, 10000);
}

const osNames = { macos: 'macOS', linux: 'NixOS', windows: 'Windows' };

function describe(host) {
  if (host.state === 'down') return ['down', host.detail || 'not answering'];
  if (host.state === 'refused') return ['refused', host.detail];
  if (host.state !== 'up') return ['', 'checking…'];
  const system = osNames[host.os] || host.os;
  const screen = host.screen === 'unknown' ? (host.detail || 'screen unknown') : host.screen;
  return [/^locked|login/i.test(host.screen) ? 'locked' : 'up', `up, ${system}, ${screen}`];
}

async function refreshHosts() {
  let hosts;
  try { hosts = await api('/api/hosts'); } catch { return; }
  const list = $('hosts');
  list.replaceChildren(...hosts.map((host) => {
    const [dot, text] = describe(host);
    const item = document.createElement('li');
    item.className = 'card host';
    const name = document.createElement('div');
    name.className = 'name';
    name.textContent = host.label;
    const state = document.createElement('div');
    state.className = 'state';
    const light = document.createElement('span');
    light.className = `dot ${dot}`;
    const words = document.createElement('span');
    words.className = 'words';
    words.textContent = text;
    state.append(light, words);
    if (host.butler) state.append(pill('Butler is connected', 'butler'));
    for (const viewer of host.viewers) state.append(pill(`${viewer} is viewing`));
    item.append(name, state);
    if (host.note) {
      const note = document.createElement('div');
      note.className = 'muted small';
      note.textContent = host.note;
      item.append(note);
    }
    const connect = document.createElement('button');
    connect.className = 'connect';
    connect.textContent = 'Connect';
    connect.disabled = host.state !== 'up';
    connect.addEventListener('click', () => openScreen(host));
    item.append(connect);
    return item;
  }));
}

function pill(text, kind = '') {
  const element = document.createElement('span');
  element.className = `pill ${kind}`;
  element.textContent = text;
  return element;
}

// ---- viewer ----------------------------------------------------------------------------------------------------

let rfb = null;
let current = null;
let closeReason = '';
let zoom = 1;
let lastAlive = 0;
let lastInput = Date.now();
let idleTimer = null;
const mods = { super: 0, ctrl: 0, alt: 0, shift: 0 }; // 0 off, 1 next key only, 2 locked
const modKeys = { super: KeyTable.XK_Super_L, ctrl: KeyTable.XK_Control_L, alt: KeyTable.XK_Alt_L, shift: KeyTable.XK_Shift_L };

function notice(text, seconds = 4) {
  const element = $('notice');
  element.textContent = text;
  element.hidden = !text;
  clearTimeout(notice.timer);
  if (text && seconds) notice.timer = setTimeout(() => { element.hidden = true; }, seconds * 1000);
}

function touched() {
  lastInput = Date.now();
  if (lastInput - lastAlive > 60000) {
    lastAlive = lastInput;
    api('/api/alive', { method: 'POST' }).catch(() => {});
  }
}

function openScreen(host) {
  stopRefresh();
  current = host;
  closeReason = '';
  show('viewer');
  const mac = host.os === 'macos';
  $('mod-super').textContent = mac ? '⌘' : 'Win';
  $('mod-alt').textContent = mac ? '⌥' : 'Alt';
  $('title').textContent = host.label + (host.butler ? ' · Butler is here too' : '');
  setZoom(1);
  notice('Connecting…', 0);

  const socket = new WebSocket(`wss://${location.host}/api/screen/${encodeURIComponent(host.name)}`, ['binary']);
  socket.addEventListener('close', (event) => { closeReason = event.reason; });
  rfb = new RFB($('screen'), socket, { shared: true });
  rfb.scaleViewport = true;
  rfb.resizeSession = false;
  rfb.focusOnClick = false;
  rfb.showDotCursor = true;
  rfb.qualityLevel = host.os === 'windows' ? 5 : 6;
  rfb.compressionLevel = 2;
  rfb.background = '#000';
  Object.keys(mods).forEach((mod) => { mods[mod] = 0; });
  renderMods();
  rfb.addEventListener('connect', () => { notice(host.butler ? 'Connected. Butler is connected to this machine too.' : 'Connected'); });
  rfb.addEventListener('disconnect', (event) => {
    const reason = closeReason || (event.detail.clean ? 'disconnected' : 'the connection dropped');
    closeScreen(reason);
  });
  rfb.addEventListener('securityfailure', (event) => { closeReason = `refused: ${event.detail.reason || 'wrong password'}`; });
  rfb.addEventListener('credentialsrequired', (event) => askCredentials(event.detail.types));

  clearInterval(idleTimer);
  lastInput = Date.now();
  idleTimer = setInterval(() => {
    if (Date.now() - lastInput > idleMinutes * 60000) disconnect(`closed after ${idleMinutes} idle minutes`);
  }, 15000);
}

function askCredentials(types) {
  notice('');
  const form = $('credentials');
  $('cred-title').textContent = `${current.label}: screen-sharing password`;
  $('cred-user-row').hidden = !types.includes('username');
  $('cred-user').value = types.includes('username') ? '' : current.name;
  form.hidden = false;
  $(types.includes('username') ? 'cred-user' : 'cred-password').focus();
  form.onsubmit = (event) => {
    event.preventDefault();
    const credentials = { password: $('cred-password').value };
    if (types.includes('username')) credentials.username = $('cred-user').value;
    if (types.includes('target')) credentials.target = '';
    $('cred-password').value = '';
    form.hidden = true;
    notice('Connecting…', 0);
    rfb.sendCredentials(credentials);
  };
}

function disconnect(reason) {
  closeReason = reason;
  if (rfb) rfb.disconnect();
}

function closeScreen(reason) {
  clearInterval(idleTimer);
  $('credentials').hidden = true;
  setPan(false);
  $('kbd').blur();
  rfb = null;
  notice('');
  showLauncher();
  $('launcher-message').textContent = reason ? `${current.label}: ${reason}` : '';
}

$('back').addEventListener('click', () => disconnect(''));

// ---- keys ------------------------------------------------------------------------------------------------------

function renderMods() {
  document.querySelectorAll('[data-mod]').forEach((button) => {
    const state = mods[button.dataset.mod];
    button.classList.toggle('on', state > 0);
    button.classList.toggle('locked', state === 2);
  });
}

let lastModTap = {};
document.querySelectorAll('[data-mod]').forEach((button) => {
  button.addEventListener('click', () => {
    const mod = button.dataset.mod;
    const now = Date.now();
    // One tap holds the modifier for the next key, a double tap locks it, a tap on a locked one releases it.
    if (mods[mod] === 2) mods[mod] = 0;
    else if (mods[mod] === 1 && now - (lastModTap[mod] || 0) < 400) mods[mod] = 2;
    else mods[mod] = mods[mod] ? 0 : 1;
    lastModTap[mod] = now;
    renderMods();
    touched();
  });
});

function press(keysym, extra = {}) {
  if (!rfb || !keysym) return;
  touched();
  const held = Object.keys(mods).filter((mod) => mods[mod] || extra[mod]);
  held.forEach((mod) => rfb.sendKey(modKeys[mod], null, true));
  rfb.sendKey(keysym, null, true);
  rfb.sendKey(keysym, null, false);
  held.reverse().forEach((mod) => rfb.sendKey(modKeys[mod], null, false));
  Object.keys(mods).forEach((mod) => { if (mods[mod] === 1) mods[mod] = 0; });
  renderMods();
}

const named = {
  Escape: KeyTable.XK_Escape, Tab: KeyTable.XK_Tab, Enter: KeyTable.XK_Return, Backspace: KeyTable.XK_BackSpace,
  Delete: KeyTable.XK_Delete, ArrowLeft: KeyTable.XK_Left, ArrowUp: KeyTable.XK_Up, ArrowRight: KeyTable.XK_Right,
  ArrowDown: KeyTable.XK_Down, Home: KeyTable.XK_Home, End: KeyTable.XK_End, PageUp: KeyTable.XK_Page_Up,
  PageDown: KeyTable.XK_Page_Down,
};
for (let n = 1; n <= 12; n++) named[`F${n}`] = KeyTable[`XK_F${n}`];

document.querySelectorAll('[data-key]').forEach((button) => {
  button.addEventListener('click', () => { press(named[button.dataset.key]); $('more-menu').hidden = true; });
});
document.querySelectorAll('[data-combo]').forEach((button) => {
  button.addEventListener('click', () => {
    const parts = button.dataset.combo.split('+');
    const key = parts.pop();
    press(named[key], Object.fromEntries(parts.map((mod) => [mod, true])));
    $('more-menu').hidden = true;
  });
});

function typeText(text) {
  for (const char of text) {
    if (char === '\n') press(KeyTable.XK_Return);
    else press(keysyms.lookup(char.codePointAt(0)));
  }
}

const kbd = $('kbd');
$('keyboard').addEventListener('click', () => {
  if (document.activeElement === kbd) kbd.blur();
  else kbd.focus();
});
kbd.addEventListener('focus', () => $('keyboard').classList.add('on'));
kbd.addEventListener('blur', () => $('keyboard').classList.remove('on'));

// A hardware keyboard's special keys and shortcuts arrive as keydown; typed characters come through beforeinput.
kbd.addEventListener('keydown', (event) => {
  const extra = { super: event.metaKey, ctrl: event.ctrlKey, alt: event.altKey, shift: event.shiftKey && !!named[event.key] };
  if (named[event.key]) {
    event.preventDefault();
    press(named[event.key], extra);
  } else if ((event.metaKey || event.ctrlKey) && event.key.length === 1) {
    event.preventDefault();
    press(keysyms.lookup(event.key.toLowerCase().codePointAt(0)), { ...extra, shift: event.shiftKey });
  }
});
kbd.addEventListener('beforeinput', (event) => {
  event.preventDefault();
  if (event.inputType === 'insertText' || event.inputType === 'insertReplacementText' || event.inputType === 'insertFromPaste') {
    typeText(event.data ?? event.dataTransfer?.getData('text/plain') ?? '');
  } else if (event.inputType === 'insertLineBreak' || event.inputType === 'insertParagraph') {
    press(KeyTable.XK_Return);
  } else if (event.inputType.startsWith('deleteContentBackward') || event.inputType.startsWith('deleteWordBackward')) {
    press(KeyTable.XK_BackSpace);
  } else if (event.inputType.startsWith('deleteContentForward')) {
    press(KeyTable.XK_Delete);
  }
});
kbd.addEventListener('input', () => { if (kbd.value) { typeText(kbd.value); kbd.value = ''; } });

$('paste').addEventListener('click', () => {
  $('more-menu').hidden = true;
  const text = prompt('Text to type on the remote machine');
  if (text) typeText(text);
});

// Tapping a key must not take focus from the keyboard's input, or iOS closes the on-screen keyboard.
['toolbar', 'more-menu'].forEach((id) => $(id).addEventListener('mousedown', (event) => event.preventDefault()));

$('more').addEventListener('click', () => { $('more-menu').hidden = !$('more-menu').hidden; });
$('toggle-bar').addEventListener('click', () => {
  $('more-menu').hidden = true;
  $('toolbar').hidden = true;
  $('show-bar').hidden = false;
});
$('show-bar').addEventListener('click', () => { $('toolbar').hidden = false; $('show-bar').hidden = true; });

// ---- zoom and pan ----------------------------------------------------------------------------------------------
// Fit shows the whole remote screen; zooming grows the noVNC container inside a scrolling box, and pan mode turns
// one finger into scrolling and two into pinch zoom, while outside it every touch goes to the remote machine.

function framebuffer() {
  const canvas = $('screen').querySelector('canvas');
  return canvas && canvas.width ? { width: canvas.width, height: canvas.height } : null;
}

function fitScale() {
  const fb = framebuffer();
  const box = $('scroller');
  return fb ? Math.min(box.clientWidth / fb.width, box.clientHeight / fb.height) : 1;
}

function setZoom(next, focusX, focusY) {
  const box = $('scroller');
  const fb = framebuffer();
  const fit = fitScale();
  const maximum = fb ? Math.max(1, 3 / fit) : 1;
  const previous = zoom;
  zoom = Math.min(Math.max(next, 1), maximum);
  const screen = $('screen');
  if (!fb || zoom === 1) {
    screen.style.width = '100%';
    screen.style.height = '100%';
  } else {
    screen.style.width = `${Math.max(box.clientWidth, fb.width * fit * zoom)}px`;
    screen.style.height = `${Math.max(box.clientHeight, fb.height * fit * zoom)}px`;
  }
  const x = focusX ?? box.clientWidth / 2;
  const y = focusY ?? box.clientHeight / 2;
  const ratio = zoom / previous;
  box.scrollLeft = (box.scrollLeft + x) * ratio - x;
  box.scrollTop = (box.scrollTop + y) * ratio - y;
}

function setPan(on) {
  $('panlayer').hidden = !on;
  $('pan').classList.toggle('on', on);
  if (rfb) rfb.viewOnly = on;
}

$('pan').addEventListener('click', () => setPan($('panlayer').hidden));
$('fit').addEventListener('click', () => setZoom(1));
$('actual').addEventListener('click', () => { setZoom(1 / fitScale()); setPan(true); notice('Pan mode: drag to move, pinch to zoom, ✋ to control again'); });
window.addEventListener('resize', () => setZoom(zoom));

let gesture = null;
const layer = $('panlayer');
layer.addEventListener('touchstart', (event) => {
  event.preventDefault();
  touched();
  const box = $('scroller');
  const touches = [...event.touches];
  if (touches.length >= 2) {
    const [a, b] = touches;
    gesture = { pinch: Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY), zoom, x: (a.clientX + b.clientX) / 2, y: (a.clientY + b.clientY) / 2 };
  } else {
    gesture = { x: touches[0].clientX, y: touches[0].clientY, left: box.scrollLeft, top: box.scrollTop };
  }
}, { passive: false });
layer.addEventListener('touchmove', (event) => {
  event.preventDefault();
  if (!gesture) return;
  const box = $('scroller');
  const rect = box.getBoundingClientRect();
  const touches = [...event.touches];
  if (gesture.pinch && touches.length >= 2) {
    const [a, b] = touches;
    const distance = Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY);
    setZoom(gesture.zoom * distance / gesture.pinch, gesture.x - rect.left, gesture.y - rect.top);
  } else if (!gesture.pinch) {
    box.scrollLeft = gesture.left - (touches[0].clientX - gesture.x);
    box.scrollTop = gesture.top - (touches[0].clientY - gesture.y);
  }
}, { passive: false });
layer.addEventListener('touchend', (event) => { if (event.touches.length === 0) gesture = null; });
layer.addEventListener('wheel', (event) => {
  event.preventDefault();
  const box = $('scroller');
  const rect = box.getBoundingClientRect();
  if (event.ctrlKey) setZoom(zoom * Math.exp(-event.deltaY / 100), event.clientX - rect.left, event.clientY - rect.top);
  else { box.scrollLeft += event.deltaX; box.scrollTop += event.deltaY; }
}, { passive: false });

['touchstart', 'pointerdown', 'keydown'].forEach((type) => $('viewer').addEventListener(type, touched, { passive: true }));

// ---- start -----------------------------------------------------------------------------------------------------

api('/api/me').then((me) => { idleMinutes = me.idleMinutes; showLauncher(me.device); }).catch(() => {});
