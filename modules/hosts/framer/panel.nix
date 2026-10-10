{ config, ... }:
{
  openclaw.skills.panel = ./skills/panel;
  openclaw.commands = [ config.kiosk.panelCommand ];
}
