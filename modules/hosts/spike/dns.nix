{
  services.cloudflare-dyndns = {
    enable = true;
    apiTokenFile = "/var/lib/secrets/cloudflare-dyndns-token";
    domains = [ "spike.cute.engineer" ];
  };
}
