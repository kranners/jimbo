{
  # Seconds without a word from butler after which spike's `mac` ends a control session as idle and the overlay on
  # the Mac fades out by itself, so a crashed or interrupted turn, or a restart of butler, never leaves it on screen.
  idle = 90;
  # Seconds after spike's overlay relay last said butler is working within which `mac`'s `hide` leaves him on screen;
  # the relay says so every few seconds while any turn runs, and `rest` once none does.
  busy = 30;
}
