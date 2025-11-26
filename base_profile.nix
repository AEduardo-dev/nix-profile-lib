{pkgs}: {
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
  ];

  envVars = {
    LANG = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
  };

  shellHook = ''
    echo "✓ Base tools loaded"
  '';

  containerConfig = {
    Cmd = ["${pkgs.bashInteractive}/bin/bash"];
    WorkingDir = "/workspace";
  };
}
