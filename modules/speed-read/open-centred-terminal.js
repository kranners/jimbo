/**
 * Runs a command in a new 80×12 Terminal window, its text twice the profile's size, centred on the screen under the mouse pointer.
 */
function screenUnderMousePointer() {
  const pointer = $.NSEvent.mouseLocation;
  const screens = $.NSScreen.screens;

  for (let index = 0; index < screens.count; index++) {
    const screen = screens.objectAtIndex(index);
    const frame = screen.frame;
    const isUnderPointer =
      pointer.x >= frame.origin.x &&
      pointer.x < frame.origin.x + frame.size.width &&
      pointer.y >= frame.origin.y &&
      pointer.y < frame.origin.y + frame.size.height;

    if (isUnderPointer) {
      return screen;
    }
  }

  return $.NSScreen.mainScreen;
}

function openInNewWindow(terminal, command) {
  terminal.activate();
  return terminal.doScript(command);
}

/**
 * Runs the command in the window Terminal opens as it launches, so no blank window is left behind.
 */
function openInLaunchWindow(terminal, command) {
  terminal.activate();
  for (let i = 0; i < 50 && terminal.windows.length === 0; i++) {
    delay(0.05);
  }
  return terminal.doScript(command, { in: terminal.windows[0] });
}

function run(argv) {
  ObjC.import("AppKit");

  const visibleFrame = screenUnderMousePointer().visibleFrame;
  const primaryScreenHeight = $.NSScreen.screens.objectAtIndex(0).frame.size.height;
  const visibleTop = primaryScreenHeight - visibleFrame.origin.y - visibleFrame.size.height;

  const terminal = Application("Terminal");
  const tab = terminal.running() ? openInNewWindow(terminal, argv[0]) : openInLaunchWindow(terminal, argv[0]);
  tab.fontSize = tab.fontSize() * 2;
  tab.numberOfColumns = 80;
  tab.numberOfRows = 12;

  const window = terminal.windows[0];
  const bounds = window.bounds();
  window.bounds = {
    x: Math.round(visibleFrame.origin.x + (visibleFrame.size.width - bounds.width) / 2),
    y: Math.round(visibleTop + (visibleFrame.size.height - bounds.height) / 2),
    width: bounds.width,
    height: bounds.height,
  };
}
