{pkgs, ...}: {
  packages = with pkgs; [
    bashInteractive
    coreutils
    findutils
    gnugrep
    gnused
    gawk
    git
    curl
    wget
    ncurses
    procps
    less
    util-linux
  ];

  envVars = {
    LANG = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
  };

  commands = [
  ];

  shellHook = ''
  '';

  containerConfig = {
    Cmd = ["${pkgs.bashInteractive}/bin/bash"];
    WorkingDir = "/workspace";
  };
}
