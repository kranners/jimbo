# The public half of spike's remote-desk gateway key, from `sudo remote-desk key` on spike, which each machine
# authorizes only to tunnel to its own VNC server and to print whether its screen is locked. Until it is set here no
# machine accepts the gateway, and setting it back to null withdraws it from every Mac and the jimbo PC's NixOS.
{
  publicKey = null;
  comment = "remote-desk@spike";
}
