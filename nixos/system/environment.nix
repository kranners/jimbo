{ config
, pkgs
, inputs
, ...
}: {
  environment = { variables = { EDITOR = "nvim"; }; };
}
