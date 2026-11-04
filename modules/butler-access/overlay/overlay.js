// Butler's on-screen overlay: Butler in a porthole at the top right of the main screen, with up to three speech
// bubbles beneath him, shown while butler on spike drives this Mac.
//
// butler's Hammerspoon helper runs this, through the launcher in ./default.nix, while ~/.local/state/butler-overlay/active exists, and
// `butler-overlay` writes the events it shows to ~/.local/state/butler-overlay/events, one line each:
// `<epoch seconds>\t<show|say|act|work|hide>\t<text>`. It polls that file ten times a second while it runs, fades out
// and exits on `hide` or after IDLE seconds without an event, so nothing runs while it is hidden. `work` and `act` keep
// him in his working pose, hands tapping and gold ripples round the porthole, until WORKING seconds pass without one,
// which spike's overlay relay sends every few seconds while any of butler's turns runs.
//
// The window's sharingType is none, so captures that honour it, Screen Sharing's among them where macOS still does,
// leave him out of the screenshots butler's own `mac` takes; Aaron sees him on the screen itself all the same.
//
// The window is borderless, transparent, click-through and never key, on every Space and over full-screen apps, so
// neither Aaron's mouse and keyboard nor butler's own clicks ever land on it. It draws only its own window, so it
// needs no Accessibility or Screen Recording grant. It is JXA, run by macOS's own osascript, so nothing is compiled.
ObjC.import('Cocoa');
ObjC.import('QuartzCore');
ObjC.import('stdlib');

const ART = '@art@';
const IDLE = @idle@;
const STATE = $.NSHomeDirectory().js + '/.local/state/butler-overlay';
const EVENTS = STATE + '/events';
const ACTIVE = STATE + '/active';

const FADE = 0.35;
const WORKING = 20;
const BUBBLE_SECONDS = 9;
const MAX_BUBBLES = 3;
const MAX_CHARACTERS = 160;
const TICK = 0.1;

// Points. Butler's art is 1000 by 1150, drawn at 150 by 172.5.
const FIGURE_W = 150;
const FIGURE_H = 172.5;
const W = 320;
const H = 480;
const MARGIN = 10;
const BUBBLE_MAX_W = 250;
const BUBBLE_PAD_X = 12;
const BUBBLE_PAD_Y = 8;
const BUBBLE_GAP = 8;
// From the art's top, so Butler's tail-ended bubble starts just under the porthole.
const BUBBLE_TOP = FIGURE_H + 4;

const app = $.NSApplication.sharedApplication;
app.setActivationPolicy(1); // NSApplicationActivationPolicyAccessory: no Dock icon, never activated.
app.finishLaunching;

const files = $.NSFileManager.defaultManager;
const now = () => Date.now() / 1000;
const number = value => $.NSNumber.numberWithDouble(value);
const easeInOut = () => $.CAMediaTimingFunction.functionWithControlPoints(0.42, 0, 0.58, 1);
const easeOut = () => $.CAMediaTimingFunction.functionWithControlPoints(0.2, 0.8, 0.3, 1);
const linear = () => $.CAMediaTimingFunction.functionWithName('linear');
const easeIn = () => $.CAMediaTimingFunction.functionWithControlPoints(0.5, 0, 0.9, 0.4);
const color = (r, g, b, a) => $.NSColor.colorWithSRGBRedGreenBlueAlpha(r / 255, g / 255, b / 255, a).CGColor;

function readEvents() {
  const data = $.NSData.dataWithContentsOfFile(EVENTS);
  if (data.isNil()) return [];
  let text = $.NSString.alloc.initWithDataEncoding(data, 4); // UTF-8
  if (text.isNil()) text = $.NSString.alloc.initWithDataEncoding(data, 5); // Latin-1 never fails
  return text.js.split('\n').filter(line => line).map(line => {
    const [at, verb, ...rest] = line.split('\t');
    return { at: Number(at) || 0, verb, text: rest.join(' ').trim() };
  });
}

function dark() {
  const style = $.NSUserDefaults.standardUserDefaults.stringForKey('AppleInterfaceStyle');
  return !style.isNil() && style.js === 'Dark';
}

// The screen with the menu bar, below the menu bar and the notch.
function place() {
  const screen = $.NSScreen.screens.objectAtIndex(0);
  const visible = screen.visibleFrame;
  win.setFrameDisplay($.NSMakeRect(
    visible.origin.x + visible.size.width - W - MARGIN,
    visible.origin.y + visible.size.height - H - MARGIN,
    W, H), false);
  return screen.backingScaleFactor;
}

const win = $.NSWindow.alloc.initWithContentRectStyleMaskBackingDefer($.NSMakeRect(0, 0, W, H), 0, 2, false);
win.setOpaque(false);
win.setBackgroundColor($.NSColor.clearColor);
win.setHasShadow(false);
win.setIgnoresMouseEvents(true);
win.setReleasedWhenClosed(false);
win.setCanHide(false);
// Above full-screen apps, the Dock and the menu bar.
win.setLevel(1000);
// canJoinAllSpaces | stationary | ignoresCycle | fullScreenAuxiliary
win.setCollectionBehavior(1 | 16 | 64 | 256);
// NSWindowSharingNone: left out of screen captures that honour it, so butler's screenshots do not show himself.
win.setSharingType(0);

const view = win.contentView;
view.setWantsLayer(true);
const root = view.layer;

// Everything fades together through the stage's opacity.
const stage = $.CALayer.layer;
stage.setFrame($.NSMakeRect(0, 0, W, H));
stage.setOpacity(0);
root.addSublayer(stage);

// Layers use bottom-up coordinates; `top` is measured down from the window's top edge.
const figureFrame = $.NSMakeRect(W - FIGURE_W, H - FIGURE_H, FIGURE_W, FIGURE_H);

function art(name, anchor) {
  const layer = $.CALayer.layer;
  layer.setContents($.NSImage.alloc.initWithContentsOfFile(ART + '/' + name + '.png'));
  layer.setContentsGravity('resize');
  if (anchor) {
    // anchor in the art's own 1000 by 1150 units, from its top left
    layer.setAnchorPoint($.NSMakePoint(anchor[0] / 1000, 1 - anchor[1] / 1150));
  }
  layer.setFrame($.NSMakeRect(0, 0, FIGURE_W, FIGURE_H));
  return layer;
}

function group(anchor) {
  const layer = $.CALayer.layer;
  if (anchor) layer.setAnchorPoint($.NSMakePoint(anchor[0] / 1000, 1 - anchor[1] / 1150));
  layer.setFrame($.NSMakeRect(0, 0, FIGURE_W, FIGURE_H));
  return layer;
}

const figure = $.CALayer.layer;
figure.setFrame(figureFrame);
stage.addSublayer(figure);

const back = art('back');
const clipped = group();
clipped.setMask(art('mask'));
const torso = group([500, 820]);
const body = art('body');
const head = group([500, 500]);
const headArt = art('head');
const eye = art('eye', [439, 274]);
const pupil = art('pupil', [564, 259]);
const brows = art('brows');
const bow = art('bow', [500, 522]);
const rim = art('rim');
const handLeft = art('hand-left', [330, 1066]);
const handRight = art('hand-right', [670, 1066]);

// Gold ripples spreading from the porthole's rim while he works: a circle of radius 360 resting on the art's bottom
// edge, centred at 500, 756 of its 1000 by 1150 units.
const ripple = $.CALayer.layer;
const RIM_R = 360 * FIGURE_W / 1000;
ripple.setBounds($.NSMakeRect(0, 0, 2 * RIM_R, 2 * RIM_R));
ripple.setPosition($.NSMakePoint(500 * FIGURE_W / 1000, FIGURE_H - 756 * FIGURE_H / 1150));
ripple.setCornerRadius(RIM_R);
ripple.setBorderWidth(2);
ripple.setBorderColor(color(201, 162, 74, 1));
ripple.setOpacity(0);
figure.addSublayer(ripple);
figure.addSublayer(back);
figure.addSublayer(clipped);
clipped.addSublayer(torso);
torso.addSublayer(body);
torso.addSublayer(head);
head.addSublayer(headArt);
head.addSublayer(eye);
head.addSublayer(pupil);
head.addSublayer(brows);
torso.addSublayer(bow);
figure.addSublayer(rim);
figure.addSublayer(handLeft);
figure.addSublayer(handRight);

// One animation of a layer's key path. `repeat` loops it for good, `autoreverse` swings it back each time, `additive`
// adds it to whatever else animates that path, and `hold` keeps its last value once it ends.
function animate(layer, key, path, values, duration, options) {
  const o = options || {};
  const animation = $.CAKeyframeAnimation.animationWithKeyPath(path);
  animation.setValues($(values.map(number)));
  if (o.times) animation.setKeyTimes($(o.times.map(number)));
  animation.setDuration(duration);
  animation.setCalculationMode('linear');
  animation.setTimingFunction(o.timing || easeInOut());
  if (o.repeat) animation.setRepeatCount(1e9);
  if (o.autoreverse) animation.setAutoreverses(true);
  if (o.offset) animation.setTimeOffset(o.offset);
  if (o.additive) animation.setAdditive(true);
  if (o.hold) {
    animation.setFillMode('forwards');
    animation.setRemovedOnCompletion(false);
  }
  layer.addAnimationForKey(animation, key);
}

const loop = (layer, key, path, from, to, duration, offset) =>
  animate(layer, key, path, [from, to], duration, { repeat: true, autoreverse: true, offset });

// Idle, always: he floats in the porthole and breathes, sways and bobs his head, fidgets with his bow tie, glances
// about and blinks every few seconds, so he never looks like a still picture.
function idle() {
  loop(figure, 'float', 'transform.translation.y', -1.5, 1.5, 2.6);
  loop(torso, 'breathe', 'transform.translation.y', 0, 3, 1.8);
  loop(torso, 'breathe-scale', 'transform.scale.x', 1, 1.015, 1.8);
  loop(head, 'sway', 'transform.rotation.z', -0.06, 0.06, 3.4, 1.1);
  loop(head, 'bob', 'transform.translation.y', 0, 1.8, 1.8, 0.4);
  loop(bow, 'fidget', 'transform.rotation.z', -0.05, 0.05, 2.2, 0.7);
  loop(handLeft, 'rest', 'transform.translation.y', 0, 1.6, 1.8);
  loop(handRight, 'rest', 'transform.translation.y', 0, 1.6, 1.8, 0.3);
  const blink = { times: [0, 0.9, 0.93, 0.96, 1], repeat: true, timing: linear() };
  animate(eye, 'blink', 'transform.scale.y', [1, 1, 0.08, 1, 1], 4.2, blink);
  animate(pupil, 'blink', 'transform.scale.y', [1, 1, 0.08, 1, 1], 4.2, blink);
  const glance = { times: [0, 0.3, 0.36, 0.55, 0.61, 1], repeat: true, timing: linear() };
  animate(pupil, 'glance', 'transform.translation.x', [0, 0, 3.5, 3.5, 0, 0], 7.3, glance);
  animate(pupil, 'glance-y', 'transform.translation.y', [0, 0, 1.5, 1.5, 0, 0], 7.3, glance);
}

// Speaking: brows up, a tilt of the head and a wiggle of the bow tie, on top of whatever else he is doing.
function speak() {
  animate(brows, 'speak', 'transform.translation.y', [0, 5, 5, 3, 0], 1.2, { times: [0, 0.15, 0.55, 0.7, 1], additive: true });
  animate(head, 'speak', 'transform.rotation.z', [0, 0.1, 0.07, 0], 1, { times: [0, 0.25, 0.6, 1], additive: true });
  animate(bow, 'speak', 'transform.rotation.z', [0, 0.22, -0.16, 0.1, 0], 0.8, { additive: true });
}

// Working, for as long as butler's turns keep sending `work` or `act`: knitted brows, a nod towards the work, both
// hands tapping on the rim as if typing, and gold ripples spreading from the porthole.
let working = false;
let workingUntil = 0;

function work() {
  workingUntil = now() + WORKING;
  if (working) return;
  working = true;
  animate(brows, 'knit', 'transform.translation.y', [0, -2.5], 0.3, { additive: true, hold: true });
  animate(head, 'nod', 'transform.rotation.z', [0, -0.06, 0, -0.04, 0], 1.4, { repeat: true, additive: true });
  animate(handLeft, 'tap', 'transform.translation.y', [0, 4, 0, 0, 3, 0], 0.6, { repeat: true, additive: true, timing: linear() });
  animate(handRight, 'tap', 'transform.translation.y', [0, 0, 4, 0, 0, 3, 0], 0.6, { repeat: true, additive: true, timing: linear() });
  animate(ripple, 'ripple', 'transform.scale', [1, 1.32], 1.8, { repeat: true, timing: easeOut() });
  animate(ripple, 'ripple-fade', 'opacity', [0.8, 0], 1.8, { repeat: true, timing: easeOut() });
}

function rest() {
  if (!working) return;
  working = false;
  ['nod', 'tap'].forEach(key => { head.removeAnimationForKey(key); handLeft.removeAnimationForKey(key); handRight.removeAnimationForKey(key); });
  brows.removeAnimationForKey('knit');
  animate(brows, 'unknit', 'transform.translation.y', [-2.5, 0], 0.4, { additive: true });
  ripple.removeAnimationForKey('ripple');
  ripple.removeAnimationForKey('ripple-fade');
}

let scale = place();
idle();

// Bubbles, newest first, directly under Butler with its tail pointing up at him.
let bubbles = [];
let leaving = [];

function bubble(text, kind) {
  const isDark = dark();
  const words = text.length > MAX_CHARACTERS ? text.slice(0, MAX_CHARACTERS - 1) + '…' : text;
  let font = $.NSFont.systemFontOfSize(kind === 'act' ? 11.5 : 12.5);
  if (kind === 'act') font = $.NSFontManager.sharedFontManager.convertFontToHaveTrait(font, 1); // italic
  const attributes = $.NSDictionary.dictionaryWithObjectForKey(font, 'NSFont');
  const measured = $(words).boundingRectWithSizeOptionsAttributes(
    $.NSMakeSize(BUBBLE_MAX_W - 2 * BUBBLE_PAD_X, 1000), 1, attributes);
  const textW = Math.ceil(measured.size.width) + 3;
  const textH = Math.ceil(measured.size.height) + 1;
  const w = Math.max(textW + 2 * BUBBLE_PAD_X, 48);
  const h = textH + 2 * BUBBLE_PAD_Y;

  const layer = $.CALayer.layer;
  // Grows from, hangs from and falls about its top right corner, under Butler.
  layer.setAnchorPoint($.NSMakePoint(1, 1));
  layer.setBounds($.NSMakeRect(0, 0, w, h));
  layer.setCornerRadius(Math.min(14, h / 2));
  layer.setBackgroundColor(isDark ? color(31, 42, 48, 0.94) : color(255, 251, 240, 0.97));
  layer.setBorderWidth(1);
  layer.setBorderColor(isDark ? color(201, 162, 74, 0.55) : color(184, 146, 58, 0.6));
  layer.setShadowOpacity(isDark ? 0.4 : 0.18);
  layer.setShadowRadius(6);
  layer.setShadowOffset($.NSMakeSize(0, -2));

  const tail = $.CALayer.layer;
  tail.setBounds($.NSMakeRect(0, 0, 10, 10));
  tail.setPosition($.NSMakePoint(w - 38, h));
  tail.setValueForKeyPath(number(Math.PI / 4), 'transform.rotation.z');
  tail.setBackgroundColor(layer.backgroundColor);
  layer.addSublayer(tail);

  const ink = kind === 'act'
    ? (isDark ? [190, 200, 205] : [90, 98, 104])
    : (isDark ? [245, 239, 224] : [23, 34, 43]);
  // The text is an attributed string carrying its font and colour, since CATextLayer's own `font` is a CFTypeRef
  // the JXA bridge does not pass an NSFont to.
  const styled = $.NSMutableDictionary.dictionary;
  styled.setObjectForKey(font, 'NSFont');
  styled.setObjectForKey($.NSColor.colorWithSRGBRedGreenBlueAlpha(ink[0] / 255, ink[1] / 255, ink[2] / 255, 1), 'NSColor');
  const label = $.CATextLayer.layer;
  label.setFrame($.NSMakeRect(BUBBLE_PAD_X, BUBBLE_PAD_Y, w - 2 * BUBBLE_PAD_X, textH));
  label.setString($.NSAttributedString.alloc.initWithStringAttributes($(words), styled));
  label.setWrapped(true);
  label.setContentsScale(scale);
  layer.addSublayer(label);
  layer.setContentsScale(scale);

  return { layer, tail, h, until: now() + BUBBLE_SECONDS };
}

// Lays the bubbles out under Butler, newest first, with only the newest one's tail showing.
function stack(animate) {
  $.CATransaction.begin;
  $.CATransaction.setAnimationDuration(animate ? 0.28 : 0);
  $.CATransaction.setAnimationTimingFunction(easeOut());
  $.CATransaction.setDisableActions(!animate);
  let top = BUBBLE_TOP;
  bubbles.forEach((item, index) => {
    item.layer.setPosition($.NSMakePoint(W - 10, H - top));
    item.tail.setOpacity(index === 0 ? 1 : 0);
    top += item.h + BUBBLE_GAP;
  });
  $.CATransaction.commit;
}

// The oldest bubble drops off the bottom of the stack, tipping over as it goes.
function fall(item) {
  $.CATransaction.begin;
  $.CATransaction.setAnimationDuration(0.45);
  $.CATransaction.setAnimationTimingFunction(easeIn());
  const position = item.layer.position;
  item.layer.setPosition($.NSMakePoint(position.x + 6, position.y - 70));
  item.layer.setValueForKeyPath(number(-0.35), 'transform.rotation.z');
  item.layer.setOpacity(0);
  $.CATransaction.commit;
  leaving.push({ layer: item.layer, at: now() + 0.5 });
}

// A bubble that has had its time fades away where it is.
function expire(item) {
  $.CATransaction.begin;
  $.CATransaction.setAnimationDuration(0.3);
  item.layer.setOpacity(0);
  $.CATransaction.commit;
  leaving.push({ layer: item.layer, at: now() + 0.35 });
}

function say(text, kind) {
  if (!text) return;
  const item = bubble(text, kind);
  bubbles.unshift(item);
  while (bubbles.length > MAX_BUBBLES) fall(bubbles.pop());
  // Starts at its place under Butler, then pops in.
  $.CATransaction.begin;
  $.CATransaction.setDisableActions(true);
  item.layer.setPosition($.NSMakePoint(W - 10, H - BUBBLE_TOP));
  stage.addSublayer(item.layer);
  $.CATransaction.commit;
  animate(item.layer, 'pop', 'transform.scale', [0.6, 1.06, 1], 0.28, { times: [0, 0.65, 1] });
  animate(item.layer, 'appear', 'opacity', [0, 1], 0.16);
  stack(true);
  if (kind === 'act') work();
  else speak();
}

let shown = false;
let hideAt = 0;
let lastEvent = now();
let seen = 0;

function fade(visible) {
  $.CATransaction.begin;
  $.CATransaction.setAnimationDuration(FADE);
  stage.setOpacity(visible ? 1 : 0);
  $.CATransaction.commit;
}

// He rises into view from below the porthole's rim, with a little overshoot, and sinks back down as he fades out.
function show() {
  hideAt = 0;
  if (shown) return;
  shown = true;
  scale = place();
  win.orderFrontRegardless;
  figure.removeAnimationForKey('sink');
  animate(figure, 'rise', 'transform.translation.y', [-40, 5, 0], 0.65, { times: [0, 0.7, 1], additive: true, timing: easeOut() });
  animate(figure, 'rise-scale', 'transform.scale', [0.8, 1.03, 1], 0.65, { times: [0, 0.7, 1], timing: easeOut() });
  fade(true);
}

function hide() {
  if (!shown && hideAt) return;
  shown = false;
  rest();
  animate(figure, 'sink', 'transform.translation.y', [0, -40], FADE, { additive: true, hold: true, timing: easeIn() });
  fade(false);
  hideAt = now() + FADE + 0.1;
}

function apply(event, replaying) {
  lastEvent = Math.max(lastEvent, event.at);
  if (event.verb === 'hide') {
    hide();
    return;
  }
  if (!['show', 'say', 'act', 'work'].includes(event.verb)) return;
  show();
  const fresh = !(replaying && now() - event.at > BUBBLE_SECONDS);
  if ((event.verb === 'work' || event.verb === 'act') && now() - event.at < WORKING) work();
  // A bubble from before this process started is shown only while it would still be up.
  if ((event.verb === 'say' || event.verb === 'act') && fresh) say(event.text, event.verb);
}

function poll(replaying) {
  const events = readEvents();
  // butler-overlay starts a fresh file for each session.
  if (events.length < seen) seen = 0;
  events.slice(seen).forEach(event => apply(event, replaying));
  seen = events.length;
}

function tick() {
  poll(false);
  const time = now();
  if (working && time > workingUntil) rest();
  bubbles.filter(item => time > item.until).forEach(item => {
    bubbles = bubbles.filter(other => other !== item);
    expire(item);
    stack(true);
  });
  leaving.filter(item => time > item.at).forEach(item => item.layer.removeFromSuperlayer);
  leaving = leaving.filter(item => time <= item.at);
  if (shown && time - lastEvent > IDLE) {
    // Heard nothing from butler for IDLE seconds: a crashed or interrupted turn never leaves him on screen.
    files.removeItemAtPathError(ACTIVE, null);
    hide();
  }
  if (!shown && hideAt && time > hideAt) {
    win.orderOut(null);
    $.exit(0);
  }
}

if (!files.fileExistsAtPath(ACTIVE)) $.exit(0);
const touched = files.attributesOfItemAtPathError(ACTIVE, null);
lastEvent = touched.isNil() ? now() : touched.fileModificationDate.timeIntervalSince1970;
const startup = readEvents();
// Only the events since the session's last `show` matter on start: older ones belong to a session already over.
startup.forEach(event => { lastEvent = Math.max(lastEvent, event.at); });
if (now() - lastEvent > IDLE || (startup.length && startup[startup.length - 1].verb === 'hide')) {
  files.removeItemAtPathError(ACTIVE, null);
  $.exit(0);
}
guarded(() => poll(true));
if (!shown) show();

// One event that fails to draw is logged and skipped, never the end of him: an exception escaping the loop would end
// it, and Hammerspoon starts it again while `active` exists, so he would only flash up and vanish, over and over.
let lastError = '';
function guarded(fn) {
  try {
    fn();
  } catch (error) {
    const text = String(error && error.message || error);
    if (text !== lastError) console.log('butler-overlay: ' + text);
    lastError = text;
  }
}

const mode = $('kCFRunLoopDefaultMode');
for (;;) {
  const event = app.nextEventMatchingMaskUntilDateInModeDequeue(0xFFFFFFFF, $.NSDate.dateWithTimeIntervalSinceNow(TICK), mode, true);
  if (!event.isNil()) app.sendEvent(event);
  guarded(tick);
}
