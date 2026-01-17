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
  ];

  envVars = {
    LANG = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
  };

  commands = [
    {
      name = "refresh";
      script = ''
        echo "Refreshing environment..."
        exec nix develop "$FLK_FLAKE_REF" --impure
        exit 0
      '';
    }
    {
      name = "switch";
      script = ''
        if [ -z "$1" ]; then
          echo "Usage: switch <profile-name>"
          exit 1
        fi
        echo "Switching to profile: $1"
        exec nix develop ".#$1" --impure
        exit 0
      '';
    }
  ];

  shellHook = ''
    echo "✓ Base tools loaded"
  '';

  containerConfig = {
    Cmd = ["${pkgs.bashInteractive}/bin/bash"];
    WorkingDir = "/workspace";
  };
}
