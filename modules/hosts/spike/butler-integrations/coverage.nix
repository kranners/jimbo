# Which live checks of check.py cover each of butler's commands, or "none: <why>" for one with nothing outside
# spike to call; butler-integrations.nix fails the build for a command missing here, and the flake check
# butler-integrations fails for a check named here that check.py does not have.
{
  asset = "none: the asset store is files on spike, with no outside service";
  backlogic-ticket = [ "backlogic-instance" ];
  calendar = [
    "google-calendar"
    "work-calendar"
    "write-gates"
  ];
  call-say = "none: a local spool the daemon reads";
  change = [ "claude-accounts" ];
  chat = [
    "chat-cache"
    "slack-read"
    "messenger"
  ];
  context = "none: built on spike from memory, the board and pilot, each checked on its own";
  daily = "none: writes the daily dashboard from sources checked on their own";
  drive = [ "drive" ];
  feeds = [
    "feed-spotify"
    "feed-steam"
    "feed-paypal"
    "feed-letterboxd"
    "feed-goodreads"
    "feed-mail"
  ];
  garmin = [ "garmin" ];
  github-issue = [
    "github-issues-token"
    "github-backlogic-token"
  ];
  hevy = [
    "hevy"
    "write-gates"
  ];
  home = [
    "home-assistant"
    "write-gates"
  ];
  imagine = [ "openai-image" ];
  inbox = [ "inbox-monitor" ];
  integrations = "none: this check itself";
  jobs = "none: files in butler's cron folder";
  kanban = [ "kanban" ];
  land-queue = "none: the landing queue on spike, which butler-selfcheck checks";
  life = [
    "index-freshness"
    "exports-waiting"
  ];
  mac = [ "machines" ];
  mail = [
    "mail-fastmail"
    "mail-gmail"
    "mail-outlook"
    "work-mail"
  ];
  mail-send = [
    "mail-fastmail"
    "mail-gmail"
    "mail-outlook"
    "write-gates"
  ];
  maps = [ "maps" ];
  memory-note = [ "github" ];
  memory-save = [ "github" ];
  messenger-chats = [ "messenger" ];
  messenger-read = [ "messenger" ];
  messenger-send = [
    "messenger"
    "write-gates"
  ];
  mindbody = [ "mindbody" ];
  monitor = [
    "machines"
    "disk"
  ];
  note = [ "notes" ];
  notify = "none: a local spool the daemon reads";
  now = "none: the local clock";
  photos = [ "icloud-photos" ];
  remarkable = [ "remarkable" ];
  reminders = [
    "icloud-reminders"
    "write-gates"
  ];
  render = "none: an offline Chromium on spike";
  self-fix = [ "claude-accounts" ];
  shell = "none: runs Butler's own scripts on spike";
  slack = [ "slack-read" ];
  slack-send = [
    "slack-write"
    "write-gates"
  ];
  up = [ "up" ];
  voice-sample = [ "openai-voice" ];
  weather = [ "weather" ];
}
