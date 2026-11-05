-- Butler's on-screen overlay: Butler in a porthole at the top right of the main screen, with up to three speech
-- bubbles beneath him, shown while butler on spike drives this Mac or works on anything at all.
--
-- It draws inside Hammerspoon itself, with hs.canvas, loaded from jimbo's butler-access module beside butler.lua, so
-- no process of its own runs. It used to be a JXA script run by osascript, first from a LaunchAgent and then from
-- Hammerspoon, and on pilot every run of it ended killed with SIGKILL before it drew anything, while Hammerspoon,
-- a signed app already running, is never killed. `butler-overlay` writes the events it shows to
-- ~/.local/state/butler-overlay/events, one line each, `<epoch seconds>\t<show|say|act|work|hide>\t<text>`, and touches
-- `active`. Every second this checks for `active`; while it exists it reads the events ten times a second, draws him
-- at FPS frames a second, and stops, deleting its canvas, on `hide` or after IDLE seconds without an event, so a
-- crashed or interrupted turn never leaves him on screen and nothing runs while he is hidden. `work` and `act` keep
-- him in his working pose, hands tapping and gold ripples round the porthole, until WORKING seconds pass without one.
--
-- The canvas is transparent, click-through and never key, on every Space and over full-screen apps, so neither
-- Aaron's mouse and keyboard nor butler's own clicks land on it. Every frame is computed from the clock, so a slow
-- frame never piles up animations, and an error drawing one is logged once and skipped.
local ART = "@art@"
local IDLE = tonumber("@idle@")
local STATE = os.getenv("HOME") .. "/.local/state/butler-overlay"
local EVENTS = STATE .. "/events"
local ACTIVE = STATE .. "/active"
-- Touched every second while he is drawn, which `butler-overlay status` reads.
local DRAWING = STATE .. "/drawing"
local LOG = os.getenv("HOME") .. "/Library/Logs/butler-overlay.log"

local FADE = 0.35
local WORKING = 20
local BUBBLE_SECONDS = 9
local MAX_BUBBLES = 3
local MAX_CHARACTERS = 160
local FPS = 24
local POLL = 0.1

-- Points. Butler's art is 1000 by 1150 units, drawn at 150 by 172.5 points, so U art units make a point.
local FIGURE_W = 150
local FIGURE_H = 172.5
local U = 1000 / FIGURE_W
local W = 320
local H = 480
local MARGIN = 10
local BUBBLE_MAX_W = 250
local BUBBLE_PAD_X = 12
local BUBBLE_PAD_Y = 8
local BUBBLE_GAP = 8
local BUBBLE_TOP = FIGURE_H + 4

local function note(text)
  local log = io.open(LOG, "a")
  if log then
    log:write(os.date("%Y-%m-%dT%H:%M:%S%z") .. " " .. text .. "\n")
    log:close()
  end
end

local now = hs.timer.secondsSinceEpoch

local function mtime(path)
  return hs.fs.attributes(path, "modification")
end

local function readEvents()
  local file = io.open(EVENTS)
  if not file then
    return {}
  end
  local events = {}
  for line in file:lines() do
    local at, verb, text = line:match("^([^\t]*)\t([^\t]*)\t?(.*)$")
    if at then
      events[#events + 1] = { at = tonumber(at) or 0, verb = verb, text = (text:gsub("\t", " "):gsub("^%s+", ""):gsub("%s+$", "")) }
    end
  end
  file:close()
  return events
end

-- Easing: CSS-style cubic Béziers from (0, 0) to (1, 1), as Core Animation's timing functions are.
local function bezier(x1, y1, x2, y2)
  local function at(a, b, t)
    return 3 * a * (1 - t) ^ 2 * t + 3 * b * (1 - t) * t ^ 2 + t ^ 3
  end
  return function(p)
    if p <= 0 then return 0 end
    if p >= 1 then return 1 end
    local lo, hi = 0, 1
    for _ = 1, 24 do
      local mid = (lo + hi) / 2
      if at(x1, x2, mid) < p then lo = mid else hi = mid end
    end
    return at(y1, y2, (lo + hi) / 2)
  end
end
local easeInOut = bezier(0.42, 0, 0.58, 1)
local easeOut = bezier(0.2, 0.8, 0.3, 1)
local easeIn = bezier(0.5, 0, 0.9, 0.4)
local linear = function(p) return p end

local function clamp(p)
  return math.max(0, math.min(1, p))
end

-- The value at `elapsed` seconds of a keyframe animation over `duration`, its timing applied to the whole of it, as
-- Core Animation's CAKeyframeAnimation does; `times` defaults to evenly spaced keyframes.
local function keyframes(values, duration, elapsed, o)
  o = o or {}
  if o.repeating then
    elapsed = elapsed % duration
  end
  local p = (o.timing or easeInOut)(clamp(elapsed / duration))
  local times = o.times
  if not times then
    times = {}
    for i = 1, #values do
      times[i] = (i - 1) / (#values - 1)
    end
  end
  for i = 2, #values do
    if p <= times[i] then
      local span = times[i] - times[i - 1]
      local f = span > 0 and (p - times[i - 1]) / span or 1
      return values[i - 1] + (values[i] - values[i - 1]) * f
    end
  end
  return values[#values]
end

-- A value swinging from `from` to `to` and back for good, `duration` each way.
local function loop(from, to, duration, t, offset)
  local phase = (t + (offset or 0)) % (2 * duration)
  local p = phase < duration and phase / duration or 2 - phase / duration
  return from + (to - from) * easeInOut(p)
end

-- A one-shot animation that started at `at`: nothing before it or once it is over, unless it holds its last value.
local function once(at, values, duration, t, o)
  if not at or t < at then
    return 0
  end
  if t - at > duration and not (o and o.hold) then
    return 0
  end
  return keyframes(values, duration, t - at, o)
end

local function color(r, g, b, a)
  return { red = r / 255, green = g / 255, blue = b / 255, alpha = a }
end

local images = {}
local function image(name)
  if not images[name] then
    images[name] = hs.image.imageFromPath(ART .. "/" .. name .. ".png")
  end
  return images[name]
end

-- A transformation from a list of steps, outermost first, as nested drawing contexts apply them:
-- {"t", x, y} translates, {"r", radians} rotates, {"s", x, y} scales, each about the current origin.
local function matrix(steps)
  local m = hs.canvas.matrix.identity()
  for _, step in ipairs(steps) do
    if step[1] == "t" then
      m = m:translate(step[2], step[3])
    elseif step[1] == "r" then
      -- The canvas is flipped, y running down, so a turn that reads anticlockwise in Core Animation is negative here.
      m = m:rotate(-math.deg(step[2]))
    else
      m = m:scale(step[2], step[3])
    end
  end
  return m
end

local function join(...)
  local all = {}
  for _, steps in ipairs({ ... }) do
    for _, step in ipairs(steps) do
      all[#all + 1] = step
    end
  end
  return all
end

-- Steps about a pivot in art units.
local function about(x, y, inner)
  return join({ { "t", x, y } }, inner, { { "t", -x, -y } })
end

local overlay

local function stop(why)
  local o = overlay
  overlay = nil
  if o then
    if o.timer then o.timer:stop() end
    if o.canvas then o.canvas:delete() end
  end
  os.remove(DRAWING)
  if why then note("overlay stopped: " .. why) end
end

local function place(o)
  local screen = hs.screen.primaryScreen()
  local frame = screen:frame()
  o.canvas:frame({ x = frame.x + frame.w - W - MARGIN, y = frame.y + MARGIN, w = W, h = H })
end

local function textStyle(kind, dark)
  local font = { name = hs.styledtext.defaultFonts.system.name, size = kind == "act" and 11.5 or 12.5 }
  if kind == "act" then
    local ok, italic = pcall(hs.styledtext.convertFont, font, hs.styledtext.fontTraits.italicFont)
    if ok and italic then font = italic end
  end
  local ink = kind == "act" and (dark and { 190, 200, 205 } or { 90, 98, 104 })
    or (dark and { 245, 239, 224 } or { 23, 34, 43 })
  return { font = font, color = color(ink[1], ink[2], ink[3], 1) }
end

-- Words wrapped greedily to the bubble's width, measured with the canvas's own text layout.
local function wrap(o, words, style)
  local limit = BUBBLE_MAX_W - 2 * BUBBLE_PAD_X
  local function width(text)
    return o.canvas:minimumTextSize(hs.styledtext.new(text, style)).w
  end
  local lines, line = {}, ""
  for word in words:gmatch("%S+") do
    local candidate = line == "" and word or line .. " " .. word
    if line ~= "" and width(candidate) > limit then
      lines[#lines + 1] = line
      line = word
    else
      line = candidate
    end
  end
  if line ~= "" then lines[#lines + 1] = line end
  return table.concat(lines, "\n")
end

local function bubble(o, text, kind)
  local dark = hs.host.interfaceStyle() == "Dark"
  if utf8.len(text) and utf8.len(text) > MAX_CHARACTERS then
    text = text:sub(1, utf8.offset(text, MAX_CHARACTERS) - 1) .. "…"
  end
  local style = textStyle(kind, dark)
  local styled = hs.styledtext.new(wrap(o, text, style), style)
  local size = o.canvas:minimumTextSize(styled)
  local textW = math.ceil(size.w) + 3
  local textH = math.ceil(size.h) + 1
  return {
    styled = styled,
    w = math.max(textW + 2 * BUBBLE_PAD_X, 48),
    h = textH + 2 * BUBBLE_PAD_Y,
    textW = textW,
    textH = textH,
    dark = dark,
    born = now(),
    until_ = now() + BUBBLE_SECONDS,
  }
end

-- Lays the bubbles out under Butler, newest first, each easing to its place.
local function stack(o)
  local top = BUBBLE_TOP
  for _, item in ipairs(o.bubbles) do
    if item.top ~= top then
      item.fromTop = item.top or top
      item.top = top
      item.movedAt = now()
    end
    top = top + item.h + BUBBLE_GAP
  end
end

local function speak(o)
  o.speakAt = now()
end

local function work(o)
  o.workingUntil = now() + WORKING
  if o.working then return end
  o.working = true
  o.workAt = now()
  o.unknitAt = nil
end

local function rest(o)
  if not o.working then return end
  o.working = false
  o.unknitAt = now()
end

local function say(o, text, kind)
  if text == "" then return end
  local item = bubble(o, text, kind)
  table.insert(o.bubbles, 1, item)
  while #o.bubbles > MAX_BUBBLES do
    local oldest = table.remove(o.bubbles)
    oldest.leaveAt, oldest.falls = now(), true
    o.leaving[#o.leaving + 1] = oldest
  end
  stack(o)
  if kind == "act" then work(o) else speak(o) end
end

local function fade(o, visible)
  local t = now()
  o.fromAlpha = o.alpha or 0
  o.toAlpha = visible and 1 or 0
  o.fadeAt = t
end

-- He rises into view from below the porthole's rim, with a little overshoot, and sinks back down as he fades out.
local function show(o)
  o.hideAt = nil
  if o.shown then return end
  o.shown = true
  place(o)
  o.canvas:show()
  o.sinkAt = nil
  o.riseAt = now()
  fade(o, true)
end

local function hide(o)
  if not o.shown and o.hideAt then return end
  o.shown = false
  rest(o)
  o.sinkAt = now()
  fade(o, false)
  o.hideAt = now() + FADE + 0.1
end

local function apply(o, event, replaying)
  o.lastEvent = math.max(o.lastEvent, event.at)
  if event.verb == "hide" then
    hide(o)
    return
  end
  if not ({ show = true, say = true, act = true, work = true })[event.verb] then return end
  show(o)
  local fresh = not (replaying and now() - event.at > BUBBLE_SECONDS)
  if (event.verb == "work" or event.verb == "act") and now() - event.at < WORKING then work(o) end
  -- A bubble from before he started is shown only while it would still be up.
  if (event.verb == "say" or event.verb == "act") and fresh then say(o, event.text, event.verb) end
end

local function poll(o, replaying)
  local events = readEvents()
  -- butler-overlay starts a fresh file for each session.
  if #events < o.seen then o.seen = 0 end
  for i = o.seen + 1, #events do
    -- One event that fails to draw is logged and skipped, never retried on every poll.
    local ok, problem = pcall(apply, o, events[i], replaying)
    if not ok then note("overlay skipped an event: " .. tostring(problem)) end
  end
  o.seen = #events
end

-- The figure's elements for time t, in art units, the canvas scaled down to points by the base step.
local function figure(o, t)
  local elapsed = t - o.started
  local base = { { "t", W - FIGURE_W, 0 }, { "s", 1 / U, 1 / U } }

  local rise = once(o.riseAt, { -40, 5, 0 }, 0.65, t, { times = { 0, 0.7, 1 }, timing = easeOut })
  local riseScale = o.riseAt and t - o.riseAt <= 0.65
      and keyframes({ 0.8, 1.03, 1 }, 0.65, t - o.riseAt, { times = { 0, 0.7, 1 }, timing = easeOut })
    or 1
  local sink = once(o.sinkAt, { 0, -40 }, FADE, t, { hold = true, timing = easeIn })
  local float = loop(-1.5, 1.5, 2.6, elapsed)
  local figureSteps = join(base, { { "t", 0, -(float + rise + sink) * U } }, about(500, 575, { { "s", riseScale, riseScale } }))

  local torsoSteps = join(figureSteps, { { "t", 0, -loop(0, 3, 1.8, elapsed) * U } },
    about(500, 820, { { "s", loop(1, 1.015, 1.8, elapsed), 1 } }))

  local speaking = o.speakAt
  local nod = o.working and keyframes({ 0, -0.06, 0, -0.04, 0 }, 1.4, t - o.workAt, { repeating = true }) or 0
  local headTurn = loop(-0.06, 0.06, 3.4, elapsed, 1.1)
    + once(speaking, { 0, 0.1, 0.07, 0 }, 1, t, { times = { 0, 0.25, 0.6, 1 } })
    + nod
  local headSteps = join(torsoSteps, { { "t", 0, -loop(0, 1.8, 1.8, elapsed, 0.4) * U } },
    about(500, 500, { { "r", headTurn } }))

  local blinkOptions = { times = { 0, 0.9, 0.93, 0.96, 1 }, repeating = true, timing = linear }
  local blink = keyframes({ 1, 1, 0.08, 1, 1 }, 4.2, elapsed, blinkOptions)
  local glanceOptions = { times = { 0, 0.3, 0.36, 0.55, 0.61, 1 }, repeating = true, timing = linear }
  local glanceX = keyframes({ 0, 0, 3.5, 3.5, 0, 0 }, 7.3, elapsed, glanceOptions)
  local glanceY = keyframes({ 0, 0, 1.5, 1.5, 0, 0 }, 7.3, elapsed, glanceOptions)

  local browsY = once(speaking, { 0, 5, 5, 3, 0 }, 1.2, t, { times = { 0, 0.15, 0.55, 0.7, 1 } })
  if o.working then
    browsY = browsY + once(o.workAt, { 0, -2.5 }, 0.3, t, { hold = true })
  elseif o.unknitAt then
    browsY = browsY + once(o.unknitAt, { -2.5, 0 }, 0.4, t)
  end

  local bowTurn = loop(-0.05, 0.05, 2.2, elapsed, 0.7) + once(speaking, { 0, 0.22, -0.16, 0.1, 0 }, 0.8, t)

  local tapLeft = o.working and keyframes({ 0, 4, 0, 0, 3, 0 }, 0.6, t - o.workAt, { repeating = true, timing = linear }) or 0
  local tapRight = o.working and keyframes({ 0, 0, 4, 0, 0, 3, 0 }, 0.6, t - o.workAt, { repeating = true, timing = linear }) or 0
  local restLeft = loop(0, 1.6, 1.8, elapsed)
  local restRight = loop(0, 1.6, 1.8, elapsed, 0.3)

  local function picture(name, steps)
    return {
      type = "image",
      image = image(name),
      frame = { x = 0, y = 0, w = 1000, h = 1150 },
      imageScaling = "scaleToFit",
      transformation = matrix(steps),
    }
  end

  local elements = {}
  local function add(element) elements[#elements + 1] = element end

  if o.working then
    local p = ((t - o.workAt) % 1.8) / 1.8
    local grow = 1 + 0.32 * easeOut(p)
    add({
      type = "circle",
      center = { x = 500, y = 756 },
      radius = 360,
      action = "stroke",
      strokeColor = color(201, 162, 74, 0.8 * (1 - easeOut(p))),
      strokeWidth = 2 * U,
      transformation = matrix(join(figureSteps, about(500, 756, { { "s", grow, grow } }))),
    })
  end
  add(picture("back", figureSteps))
  -- The figure is clipped to the porthole's inside and everything above its centre line, as ./butler.svg's mask is,
  -- so his head and shoulders rise over the rim while below the waist the rim cuts him off.
  local k = 0.5523 * 352
  add({
    type = "segments",
    action = "clip",
    closed = true,
    coordinates = {
      { x = 0, y = 0 },
      { x = 1000, y = 0 },
      { x = 1000, y = 756 },
      { x = 852, y = 756 },
      { x = 500, y = 1108, c1x = 852, c1y = 756 + k, c2x = 500 + k, c2y = 1108 },
      { x = 148, y = 756, c1x = 500 - k, c1y = 1108, c2x = 148, c2y = 756 + k },
      { x = 0, y = 756 },
    },
    transformation = matrix(figureSteps),
  })
  add(picture("body", torsoSteps))
  add(picture("head", headSteps))
  add(picture("eye", join(headSteps, about(439, 274, { { "s", 1, blink } }))))
  add(picture("pupil", join(headSteps, { { "t", glanceX * U, -glanceY * U } }, about(564, 259, { { "s", 1, blink } }))))
  add(picture("brows", join(headSteps, { { "t", 0, -browsY * U } })))
  add(picture("bow", join(torsoSteps, about(500, 522, { { "r", bowTurn } }))))
  add({ type = "resetClip" })
  add(picture("rim", figureSteps))
  add(picture("hand-left", join(figureSteps, { { "t", 0, -(restLeft + tapLeft) * U } })))
  add(picture("hand-right", join(figureSteps, { { "t", 0, -(restRight + tapRight) * U } })))
  return elements
end

-- One bubble's elements, hanging from its top right corner under Butler.
local function bubbleElements(item, t, newest)
  local top = item.top
  if item.movedAt and t - item.movedAt < 0.28 then
    top = item.fromTop + (item.top - item.fromTop) * easeOut((t - item.movedAt) / 0.28)
  end
  local x, y = W - 10, top
  local alpha = clamp((t - item.born) / 0.16)
  local scale = t - item.born < 0.28 and keyframes({ 0.6, 1.06, 1 }, 0.28, t - item.born, { times = { 0, 0.65, 1 } }) or 1
  local dx, dy, turn = 0, 0, 0
  if item.leaveAt then
    if item.falls then
      local p = easeIn(clamp((t - item.leaveAt) / 0.45))
      dx, dy, turn = 6 * p, 70 * p, 0.35 * p
      alpha = alpha * (1 - p)
    else
      alpha = alpha * (1 - clamp((t - item.leaveAt) / 0.3))
    end
  end
  local steps = { { "t", x + dx, y + dy }, { "r", -turn }, { "s", scale, scale }, { "t", -item.w, 0 } }
  local m = matrix(steps)
  local fill = item.dark and color(31, 42, 48, 0.94 * alpha) or color(255, 251, 240, 0.97 * alpha)
  local border = item.dark and color(201, 162, 74, 0.55 * alpha) or color(184, 146, 58, 0.6 * alpha)
  local elements = {
    {
      type = "rectangle",
      frame = { x = 0, y = 0, w = item.w, h = item.h },
      roundedRectRadii = { xRadius = math.min(14, item.h / 2), yRadius = math.min(14, item.h / 2) },
      action = "strokeAndFill",
      fillColor = fill,
      strokeColor = border,
      strokeWidth = 1,
      withShadow = true,
      shadow = { blurRadius = 6, color = { alpha = (item.dark and 0.4 or 0.18) * alpha }, offset = { h = -2, w = 0 } },
      transformation = m,
    },
  }
  if newest then
    -- The tail points up at Butler from the newest bubble alone.
    local cx = item.w - 38
    elements[#elements + 1] = {
      type = "segments",
      action = "fill",
      closed = true,
      fillColor = fill,
      coordinates = { { x = cx - 7, y = 0.5 }, { x = cx, y = -6.5 }, { x = cx + 7, y = 0.5 } },
      transformation = m,
    }
  end
  elements[#elements + 1] = {
    type = "text",
    text = item.styled,
    frame = { x = BUBBLE_PAD_X, y = BUBBLE_PAD_Y, w = item.w - 2 * BUBBLE_PAD_X + 2, h = item.textH + 2 },
    transformation = m,
  }
  return elements, alpha
end

local function draw(o, t)
  local elements = figure(o, t)
  for index, item in ipairs(o.bubbles) do
    local parts = bubbleElements(item, t, index == 1)
    for _, part in ipairs(parts) do elements[#elements + 1] = part end
  end
  for _, item in ipairs(o.leaving) do
    local parts = bubbleElements(item, t, false)
    for _, part in ipairs(parts) do elements[#elements + 1] = part end
  end
  o.canvas:replaceElements(elements)
  if o.fadeAt then
    o.alpha = o.fromAlpha + (o.toAlpha - o.fromAlpha) * easeInOut(clamp((t - o.fadeAt) / FADE))
  end
  o.canvas:alpha(o.alpha or 0)
end

local function tick(o)
  local t = now()
  if t - o.polled >= POLL then
    o.polled = t
    poll(o, false)
    if o.working and t > o.workingUntil then rest(o) end
    local kept = {}
    for _, item in ipairs(o.bubbles) do
      if t > item.until_ then
        item.leaveAt = t
        o.leaving[#o.leaving + 1] = item
      else
        kept[#kept + 1] = item
      end
    end
    if #kept ~= #o.bubbles then
      o.bubbles = kept
      stack(o)
    end
    local still = {}
    for _, item in ipairs(o.leaving) do
      if t - item.leaveAt < 0.5 then still[#still + 1] = item end
    end
    o.leaving = still
    if o.shown and t - o.lastEvent > IDLE then
      -- Heard nothing from butler for IDLE seconds: a crashed or interrupted turn never leaves him on screen.
      os.remove(ACTIVE)
      hide(o)
    end
    if t - o.touched >= 1 then
      o.touched = t
      local mark = io.open(DRAWING, "w")
      if mark then mark:close() end
    end
  end
  draw(o, t)
  if not o.shown and o.hideAt and t > o.hideAt then
    stop()
  end
end

local function start()
  local touched = mtime(ACTIVE)
  if not touched then return end
  local t = now()
  local events = readEvents()
  local last = touched
  for _, event in ipairs(events) do last = math.max(last, event.at) end
  -- Only the events since the session's last `show` matter on start: older ones belong to a session already over.
  if t - last > IDLE or (#events > 0 and events[#events].verb == "hide") then
    os.remove(ACTIVE)
    return
  end
  local canvas = hs.canvas.new({ x = 0, y = 0, w = W, h = H })
  canvas:level(hs.canvas.windowLevels.screenSaver)
  canvas:behaviorAsLabels({ "canJoinAllSpaces", "stationary", "ignoresCycle", "fullScreenAuxiliary" })
  canvas:clickActivating(false)
  canvas:canvasMouseEvents(false, false, false, false)
  canvas:alpha(0)
  local o = {
    canvas = canvas,
    started = t,
    polled = t,
    touched = 0,
    lastEvent = last,
    seen = 0,
    bubbles = {},
    leaving = {},
    alpha = 0,
  }
  overlay = o
  local errors = {}
  o.timer = hs.timer.doEvery(1 / FPS, function()
    if overlay ~= o then return end
    local ok, problem = pcall(tick, o)
    if not ok then
      problem = tostring(problem)
      if not errors[problem] then
        errors[problem] = true
        note("overlay frame failed: " .. problem)
      end
    end
  end)
  poll(o, true)
  if not o.shown then show(o) end
end

-- A start that fails is logged and tried again 5 seconds later, so a broken one never retries every second.
local failed = 0
butlerOverlayCheck = hs.timer.doEvery(1, function()
  if overlay or not mtime(ACTIVE) or now() - failed < 5 then return end
  local ok, problem = pcall(start)
  if not ok then
    failed = now()
    note("overlay could not start: " .. tostring(problem))
    stop()
  end
end)

os.remove(DRAWING)
