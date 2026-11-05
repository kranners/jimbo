-- butler's helper on this Mac, loaded by Hammerspoon from jimbo's butler-access module. It answers butler's `mac`
-- over ssh, through curl to a loopback HTTP server that wants the token in tokenFile, and does what VNC alone cannot:
-- choose menu items by name, list and press the controls of a dialog, list every display, picture one and click on
-- it, and move the front window to a display. It runs inside Hammerspoon, so it uses Hammerspoon's own Accessibility
-- and Screen Recording grants, never ssh's.
local port = tonumber("@port@")
local tokenFile = os.getenv("HOME") .. "/.local/state/butler-access/hammerspoon-token"
local shots = os.getenv("HOME") .. "/.local/state/butler-access/shots"
local pictureWidth = 1512

local ax = hs.axuielement
local M = {}

local function fail(message)
  error({ butler = message }, 0)
end

local function needAccessibility()
  if not hs.accessibilityState() then
    fail("Hammerspoon has no Accessibility permission on this Mac yet: Aaron turns Hammerspoon on in System Settings, Privacy & Security, Accessibility")
  end
end

local function readToken()
  local file = io.open(tokenFile)
  if not file then
    return nil
  end
  local line = file:read("l") or ""
  file:close()
  return line:match("^X%-Butler%-Token: (%S+)$")
end

-- Titles compare without case, surrounding space or a trailing ellipsis, so "Export vault" finds "Export Vault…".
local function plain(text)
  text = tostring(text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  text = text:gsub("…$", ""):gsub("%.%.%.$", "")
  return (text:gsub("%s+$", ""))
end

local function attr(element, name)
  local ok, value = pcall(element.attributeValue, element, name)
  if ok then
    return value
  end
  return nil
end

local function children(element)
  return attr(element, "AXChildren") or {}
end

local function findApp(name)
  if not name or name == "" or name == "front" then
    local window = hs.window.frontmostWindow()
    local app = window and window:application() or hs.application.frontmostApplication()
    return app or fail("no app is in front")
  end
  local app = hs.application.get(name)
  if app then
    return app
  end
  for _, running in ipairs(hs.application.runningApplications()) do
    if plain(running:name()) == plain(name) then
      return running
    end
  end
  fail(name .. " is not running; open it first with open -a")
end

local function appElement(app)
  local element = ax.applicationElement(app)
  pcall(element.setTimeout, element, 3)
  -- Electron apps, Bitwarden among them, build their accessibility tree only when asked like this.
  pcall(element.setAttributeValue, element, "AXManualAccessibility", true)
  return element
end

-- macOS's own password and Touch ID prompts, which only Aaron answers.
local guarded = {
  ["com.apple.SecurityAgent"] = true,
  ["com.apple.LocalAuthentication.UIAgent"] = true,
  ["com.apple.coreautha"] = true,
}

local function isGuarded(app)
  return guarded[app:bundleID() or ""] or app:name() == "SecurityAgent"
end

-- Menus

local function shortcut(item)
  local key = attr(item, "AXMenuItemCmdChar")
  if not key or key == "" then
    return nil
  end
  local modifiers = attr(item, "AXMenuItemCmdModifiers") or 0
  local parts = {}
  if modifiers & 8 == 0 then
    table.insert(parts, "cmd")
  end
  if modifiers & 4 ~= 0 then
    table.insert(parts, "ctrl")
  end
  if modifiers & 2 ~= 0 then
    table.insert(parts, "option")
  end
  if modifiers & 1 ~= 0 then
    table.insert(parts, "shift")
  end
  table.insert(parts, key:lower())
  return table.concat(parts, "-")
end

-- The items of a menu bar item or a menu item with a submenu: the children of its one AXMenu child.
local function menuItems(element)
  for _, child in ipairs(children(element)) do
    if attr(child, "AXRole") == "AXMenu" then
      return children(child)
    end
  end
  return {}
end

local function describeItem(item, depth, lines, deeper)
  local title = attr(item, "AXTitle") or ""
  if title == "" then
    return
  end
  local line = string.rep("  ", depth) .. title
  local key = shortcut(item)
  if key then
    line = line .. "  (" .. key .. ")"
  end
  if attr(item, "AXEnabled") == false then
    line = line .. "  [disabled]"
  end
  local mark = attr(item, "AXMenuItemMarkChar")
  if mark and mark ~= "" then
    line = line .. "  [checked]"
  end
  local sub = menuItems(item)
  if #sub > 0 then
    line = line .. "  >"
  end
  table.insert(lines, line)
  if #sub > 0 and deeper > 0 then
    for _, child in ipairs(sub) do
      describeItem(child, depth + 1, lines, deeper - 1)
    end
  end
end

local function matching(items, title)
  local exact, prefixed = {}, {}
  for _, item in ipairs(items) do
    local name = plain(attr(item, "AXTitle"))
    if name ~= "" then
      if name == plain(title) then
        table.insert(exact, item)
      elseif name:sub(1, #plain(title)) == plain(title) then
        table.insert(prefixed, item)
      end
    end
  end
  if #exact > 0 then
    return exact[1]
  end
  if #prefixed == 1 then
    return prefixed[1]
  end
  return nil, #prefixed
end

-- menu {app, path}: with no path lists the menu bar and each menu's items; with a path to a menu lists it; with a
-- path to an item chooses it.
function M.menu(args)
  needAccessibility()
  local app = findApp(args.app)
  local element = appElement(app)
  local bar = attr(element, "AXMenuBar") or fail(app:name() .. " has no menu bar")
  local lines = {}
  local path = args.path or {}
  if #path == 0 then
    table.insert(lines, app:name() .. "'s menus, with each item and its shortcut; > marks a submenu:")
    for _, top in ipairs(children(bar)) do
      describeItem(top, 0, lines, 1)
    end
    return table.concat(lines, "\n")
  end
  local items, current, chosen = children(bar), nil, {}
  for index, title in ipairs(path) do
    local found, ambiguous = matching(items, title)
    if not found then
      local names = {}
      for _, item in ipairs(items) do
        local name = attr(item, "AXTitle")
        if name and name ~= "" then
          table.insert(names, name)
        end
      end
      fail(string.format("no %s %q in %s%s; it has: %s", index == 1 and "menu" or "item", title,
        index == 1 and (app:name() .. "'s menu bar") or table.concat(chosen, " > "),
        (ambiguous or 0) > 1 and (", and " .. ambiguous .. " items start with it") or "", table.concat(names, ", ")))
    end
    current = found
    table.insert(chosen, attr(found, "AXTitle"))
    items = menuItems(found)
  end
  if #items > 0 then
    table.insert(lines, table.concat(chosen, " > ") .. ":")
    for _, item in ipairs(items) do
      describeItem(item, 1, lines, 2)
    end
    return table.concat(lines, "\n")
  end
  if attr(current, "AXEnabled") == false then
    fail(table.concat(chosen, " > ") .. " is disabled right now")
  end
  app:activate()
  hs.timer.usleep(150000)
  -- An item that opens a modal dialog can hold AXPress until its timeout, though the item was chosen.
  local ok, why = pcall(current.performAction, current, "AXPress")
  if not ok and not tostring(why):find("timeout", 1, true) and not tostring(why):find("ancel", 1, true) then
    fail("could not choose " .. table.concat(chosen, " > ") .. ": " .. tostring(why))
  end
  return "chose " .. app:name() .. " > " .. table.concat(chosen, " > ")
end

-- Dialogs

local kinds = {
  AXButton = "button",
  AXDefaultButton = "button",
  AXMenuButton = "menu button",
  AXPopUpButton = "pop-up",
  AXCheckBox = "checkbox",
  AXRadioButton = "radio",
  AXTextField = "field",
  AXTextArea = "text area",
  AXComboBox = "combo box",
  AXSecureTextField = "password field",
  AXDisclosureTriangle = "disclosure",
  AXLink = "link",
  AXStaticText = "text",
}

local function short(text, limit)
  text = tostring(text or ""):gsub("%s+", " ")
  if #text > limit then
    return text:sub(1, limit) .. "…"
  end
  return text
end

local function label(element)
  for _, name in ipairs({ "AXTitle", "AXDescription", "AXPlaceholderValue", "AXHelp" }) do
    local value = attr(element, name)
    if type(value) == "string" and value ~= "" then
      return value
    end
  end
  local titled = attr(element, "AXTitleUIElement")
  if titled then
    local value = attr(titled, "AXValue")
    if type(value) == "string" and value ~= "" then
      return value
    end
  end
  local role = attr(element, "AXRole")
  if role == "AXButton" or role == "AXStaticText" or role == "AXLink" then
    for _, child in ipairs(children(element)) do
      local value = attr(child, "AXValue") or attr(child, "AXTitle")
      if type(value) == "string" and value ~= "" then
        return value
      end
    end
    local value = attr(element, "AXValue")
    if type(value) == "string" then
      return value
    end
  end
  return ""
end

local function frontWindow(element)
  return attr(element, "AXFocusedWindow") or attr(element, "AXMainWindow") or (attr(element, "AXWindows") or {})[1]
end

local function controls(window)
  local found = {}
  local function walk(element, depth)
    if depth > 40 or #found >= 200 then
      return
    end
    local role = attr(element, "AXRole")
    local kind = kinds[role]
    if attr(element, "AXSubrole") == "AXSecureTextField" then
      kind = "password field"
    end
    if kind and not (kind == "text" and label(element) == "") then
      table.insert(found, { element = element, kind = kind })
    end
    -- A button's text is its own label, so its children are not listed again.
    if kind ~= "button" and kind ~= "link" and kind ~= "text" then
      for _, child in ipairs(children(element)) do
        walk(child, depth + 1)
      end
    end
  end
  walk(window, 0)
  return found
end

local function dialogTarget(args)
  needAccessibility()
  local app = findApp(args.app)
  local element = appElement(app)
  local window = frontWindow(element) or fail(app:name() .. " has no window open")
  return app, window, controls(window)
end

-- dialog {app}: the front window of app, or of whatever is in front, with every control numbered.
function M.dialog(args)
  local app, window, found = dialogTarget(args)
  local lines = {}
  local title = attr(window, "AXTitle")
  table.insert(lines, string.format("%s, window %q%s:", app:name(), title or "", attr(window, "AXModal") and ", modal" or ""))
  if isGuarded(app) then
    table.insert(lines, "This is macOS's own password or Touch ID prompt: hand it to Aaron, and press nothing here.")
  end
  for index, control in ipairs(found) do
    local element = control.element
    local line = string.format("  [%d] %s %q", index, control.kind, short(label(element), 80))
    if control.kind == "field" or control.kind == "text area" or control.kind == "combo box" then
      line = line .. string.format(" = %q", short(attr(element, "AXValue") or "", 80))
    elseif control.kind == "password field" then
      line = line .. " (a password: Aaron types it, never you)"
    elseif control.kind == "checkbox" or control.kind == "radio" then
      line = line .. ((attr(element, "AXValue") == 1) and " [on]" or " [off]")
    elseif control.kind == "pop-up" then
      line = line .. string.format(" = %q", short(attr(element, "AXValue") or "", 60))
    end
    if attr(element, "AXFocused") then
      line = line .. " [focused]"
    end
    if attr(element, "AXEnabled") == false then
      line = line .. " [disabled]"
    end
    if attr(element, "AXSubrole") == "AXDefaultButton" or attr(window, "AXDefaultButton") == element then
      line = line .. " [default, enter presses it]"
    end
    table.insert(lines, line)
  end
  if #found == 0 then
    table.insert(lines, "  no controls found; look at the screen instead")
  elseif #found >= 200 then
    table.insert(lines, "  (stopped at 200 controls)")
  end
  return table.concat(lines, "\n")
end

local function pick(found, wanted, allowed)
  local index = tonumber(wanted)
  if index then
    return found[index] or fail("there is no control " .. wanted .. "; list them again with dialog")
  end
  local hits = {}
  for _, control in ipairs(found) do
    if allowed[control.kind] and plain(label(control.element)) == plain(wanted) then
      table.insert(hits, control)
    end
  end
  if #hits == 1 then
    return hits[1]
  end
  fail(#hits == 0 and ("no control named " .. wanted .. "; list them with dialog") or (#hits .. " controls are named " .. wanted .. "; press one by its number from dialog"))
end

-- press {control, app}: presses a button, checkbox, radio, pop-up or link, by its number from dialog or its name.
function M.press(args)
  local app, _, found = dialogTarget(args)
  if isGuarded(app) then
    fail("that is macOS's own password or Touch ID prompt, which only Aaron answers")
  end
  local control = pick(found, args.control, { button = true, ["menu button"] = true, checkbox = true, radio = true, ["pop-up"] = true, link = true, disclosure = true })
  local name = short(label(control.element), 80)
  local ok, why = pcall(control.element.performAction, control.element, "AXPress")
  if not ok and not tostring(why):find("timeout", 1, true) then
    fail("could not press " .. name .. ": " .. tostring(why))
  end
  return string.format("pressed %s %q in %s", control.kind, name, app:name())
end

-- focus {control, app}: puts the keyboard focus on a field, so type fills it.
function M.focus(args)
  local app, _, found = dialogTarget(args)
  local control = pick(found, args.control, { field = true, ["text area"] = true, ["combo box"] = true, ["password field"] = true, ["pop-up"] = true })
  if control.kind == "password field" then
    fail("that is a password field: Aaron types into it, never you")
  end
  control.element:setAttributeValue("AXFocused", true)
  return string.format("focused %s %q in %s; type now fills it", control.kind, short(label(control.element), 80), app:name())
end

-- secure {}: whether the keyboard focus is in a password field, so type refuses to fill one.
function M.secure()
  local front = hs.application.frontmostApplication()
  if front and isGuarded(front) then
    return { secure = true }
  end
  if not hs.accessibilityState() then
    return { secure = false, unknown = true }
  end
  local element = attr(ax.systemWideElement(), "AXFocusedUIElement")
  if not element then
    return { secure = false }
  end
  return { secure = attr(element, "AXRole") == "AXSecureTextField" or attr(element, "AXSubrole") == "AXSecureTextField" }
end

-- front {}: the front app and its focused window's title, with the page's URL where the window exposes one as
-- AXDocument, so mac can tell a messaging, mail or payment screen before pressing Return or clicking there.
function M.front()
  local app = hs.application.frontmostApplication()
  if not app then
    return { app = "", title = "", url = "" }
  end
  local result = { app = app:name() or "", bundle = app:bundleID() or "", title = "", url = "" }
  if not hs.accessibilityState() then
    return result
  end
  local window = attr(ax.applicationElement(app), "AXFocusedWindow")
  if window then
    result.title = tostring(attr(window, "AXTitle") or "")
    result.url = tostring(attr(window, "AXDocument") or "")
  end
  return result
end

-- Displays

-- Every display, the one with the menu bar first, then left to right, numbered from 1 in that order.
local function screens()
  local primary = hs.screen.primaryScreen()
  local list = hs.screen.allScreens()
  table.sort(list, function(a, b)
    if a:id() == primary:id() or b:id() == primary:id() then
      return a:id() == primary:id()
    end
    local fa, fb = a:fullFrame(), b:fullFrame()
    if fa.x ~= fb.x then
      return fa.x < fb.x
    end
    return fa.y < fb.y
  end)
  return list
end

local function screenAt(wanted)
  local list = screens()
  local index = tonumber(wanted)
  if index then
    return list[index] or fail("there is no display " .. wanted .. "; this Mac has " .. #list), index
  end
  for number, screen in ipairs(list) do
    if plain(screen:name()):find(plain(wanted), 1, true) then
      return screen, number
    end
  end
  fail("no display named " .. tostring(wanted) .. "; list them with displays")
end

function M.displays()
  local list, result = screens(), {}
  for index, screen in ipairs(list) do
    local frame, mode = screen:fullFrame(), screen:currentMode() or {}
    table.insert(result, {
      index = index,
      name = screen:name() or "",
      x = frame.x, y = frame.y, w = frame.w, h = frame.h,
      scale = mode.scale or 1,
      primary = index == 1,
      builtin = (screen:name() or ""):find("Built%-in") ~= nil,
    })
  end
  return result
end

-- snapshot {display}: a PNG of one display, scaled to at most pictureWidth wide, in base64.
function M.snapshot(args)
  local screen, index = screenAt(args.display)
  if hs.screenRecordingState and not hs.screenRecordingState() then
    fail("Hammerspoon has no Screen Recording permission on this Mac yet: Aaron turns Hammerspoon on in System Settings, Privacy & Security, Screen & System Audio Recording; until then look shows only the main display")
  end
  local frame, mode = screen:fullFrame(), screen:currentMode() or {}
  hs.fs.mkdir(shots)
  local path = string.format("%s/display-%d.png", shots, index)
  os.remove(path)
  local width = math.min(pictureWidth, math.floor(frame.w * (mode.scale or 1)))
  local _, ok = hs.execute(string.format("/usr/sbin/screencapture -x -t png -R%d,%d,%d,%d '%s' && /usr/bin/sips --resampleWidth %d '%s' > /dev/null",
    math.floor(frame.x), math.floor(frame.y), math.floor(frame.w), math.floor(frame.h), path, width, path))
  if not ok then
    local image = screen:snapshot()
    if not image or not image:saveToFile(path) then
      fail("could not picture display " .. index)
    end
    hs.execute(string.format("/usr/bin/sips --resampleWidth %d '%s' > /dev/null", width, path))
  end
  local file = io.open(path, "rb") or fail("could not picture display " .. index)
  local data = file:read("a")
  file:close()
  return {
    png = hs.base64.encode(data),
    index = index, name = screen:name() or "",
    x = frame.x, y = frame.y, w = frame.w, h = frame.h,
  }
end

-- click {x, y, button}: a click at a point of the whole desktop, in points from the main display's top-left.
function M.click(args)
  needAccessibility()
  local types, properties = hs.eventtap.event.types, hs.eventtap.event.properties
  local point = { x = args.x, y = args.y }
  local down, up = types.leftMouseDown, types.leftMouseUp
  if args.button == "right" then
    down, up = types.rightMouseDown, types.rightMouseUp
  end
  hs.mouse.absolutePosition(point)
  hs.timer.usleep(30000)
  for count = 1, args.button == "double" and 2 or 1 do
    hs.eventtap.event.newMouseEvent(down, point):setProperty(properties.mouseEventClickState, count):post()
    hs.eventtap.event.newMouseEvent(up, point):setProperty(properties.mouseEventClickState, count):post()
  end
  return "clicked"
end

-- move_window {display}: moves the front window onto a display, keeping its size where it fits.
function M.move_window(args)
  needAccessibility()
  local window = hs.window.frontmostWindow() or fail("no window is in front")
  local screen, index = screenAt(args.display)
  window:moveToScreen(screen, false, true, 0)
  local frame = window:frame()
  return string.format("moved %s's window %q to display %d, %s, now at %d,%d %dx%d points",
    window:application():name(), window:title() or "", index, screen:name() or "", frame.x, frame.y, frame.w, frame.h)
end

function M.status()
  return {
    accessibility = hs.accessibilityState(),
    screenRecording = hs.screenRecordingState and hs.screenRecordingState() or false,
    version = hs.processInfo.version,
  }
end

local function respond(body, code)
  return hs.json.encode(body), code, { ["Content-Type"] = "application/json" }
end

butlerServer = hs.httpserver.new(false, false)
butlerServer:setInterface("localhost")
butlerServer:setPort(port)
butlerServer:setCallback(function(method, _, headers, body)
  local token, sent = readToken(), nil
  for name, value in pairs(headers or {}) do
    if name:lower() == "x-butler-token" then
      sent = value
    end
  end
  if method ~= "POST" or not token or sent ~= token then
    return respond({ ok = false, error = "forbidden" }, 403)
  end
  local ok, result = pcall(function()
    local request = hs.json.decode(body or "") or fail("the request is not JSON")
    local handler = M[request.verb] or fail("unknown verb " .. tostring(request.verb))
    return handler(request.args or {})
  end)
  if ok then
    return respond({ ok = true, result = result }, 200)
  end
  return respond({ ok = false, error = type(result) == "table" and result.butler or tostring(result) }, 200)
end)
butlerServer:start()

-- Ask once, so Aaron sees macOS's own prompt to grant Accessibility after the first install.
if not hs.accessibilityState() then
  hs.accessibilityState(true)
end

butlerReload = hs.pathwatcher.new(hs.configdir, function()
  hs.reload()
end):start()

-- Records why the screen locked, so butler's `mac hosts` and the machines monitor can say so instead of guessing:
-- every lock, sleep, screen saver and session event goes to lockEvents, and each lock writes lastLock, one line of
-- its time and the cause read from what came just before it, which an unlock removes. It only listens; it changes
-- no setting, so it runs on pilot too.
local lockState = os.getenv("HOME") .. "/.local/state/butler-access"
local lockEvents = lockState .. "/lock-events"
local lastLock = lockState .. "/last-lock"
local recent = {}

local function minutes(seconds)
  local m = math.floor((seconds or 0) / 60)
  return m == 1 and "1 minute" or (m .. " minutes")
end

local function lockCause(now, idle)
  local function within(name, window)
    for i = #recent, 1, -1 do
      local event = recent[i]
      if now - event.at > window then
        return nil
      end
      if event.name == name then
        return event
      end
    end
    return nil
  end
  local wake = within("systemDidWake", 120)
  if wake then
    local slept = within("systemWillSleep", 7 * 24 * 3600)
    return "it locked as the Mac woke from sleep"
      .. (slept and (", having slept since " .. os.date("%H:%M", slept.at)) or "")
  end
  local saver = within("screensaverDidStart", 120)
  if saver then
    return "the screen saver started after " .. minutes(saver.idle) .. " idle and locked the screen"
  end
  local dark = within("screensDidSleep", 120)
  if dark then
    return "the display went to sleep after " .. minutes(dark.idle) .. " idle and the lock followed it"
  end
  if within("sessionDidResignActive", 120) then
    return "the session switched to the login window, as fast user switching does"
  end
  if idle < 30 then
    return "it was locked directly while in use, by the lock keys, the Touch ID button, a hot corner or the menu"
  end
  return "it was locked directly after " .. minutes(idle)
    .. " idle, with no screen saver, display sleep or system sleep before it, so something told macOS to lock,"
    .. " such as a management policy, a lock shortcut or another app"
end

local lockNames = {}
for name, value in pairs(hs.caffeinate.watcher) do
  if type(value) == "number" then
    lockNames[value] = name
  end
end

butlerLockWatcher = hs.caffeinate.watcher.new(function(kind)
  local name = lockNames[kind] or tostring(kind)
  local now, idle = os.time(), hs.host.idleTime() or 0
  table.insert(recent, { name = name, at = now, idle = idle })
  if #recent > 50 then
    table.remove(recent, 1)
  end
  os.execute("/bin/mkdir -p '" .. lockState .. "'")
  local line = os.date("%Y-%m-%dT%H:%M:%S%z", now) .. " " .. name .. " idle=" .. math.floor(idle)
    .. " power=" .. tostring(hs.battery.powerSource())
  if name == "screensDidLock" then
    local cause = lockCause(now, idle)
    line = line .. " cause: " .. cause
    local file = io.open(lastLock, "w")
    if file then
      file:write(now .. "\t" .. os.date("%H:%M", now) .. "\t" .. cause .. "\n")
      file:close()
    end
  elseif name == "screensDidUnlock" then
    os.remove(lastLock)
  end
  local log = io.open(lockEvents, "a")
  if log then
    log:write(line .. "\n")
    log:close()
  end
end):start()

-- Keeps the event log to its newest 500 lines, once per load.
os.execute("f='" .. lockEvents .. "'; [ -f \"$f\" ] && /usr/bin/tail -n 500 \"$f\" > \"$f.new\" && /bin/mv \"$f.new\" \"$f\"")
