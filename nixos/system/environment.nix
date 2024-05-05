{
  config,
  pkgs,
  inputs,
  ...
}: {
  environment = {variables = {EDITOR = "vim";};};
}
