{
  pkgs,
  lib ? pkgs.lib,
}: rec {
  # Parse profile combinations
  # "backend+frontend" -> ["backend" "frontend"]
  # "all" -> all profile names

  # Built-in base profile - always available

  baseProfile = import ./base_profile.nix {inherit pkgs;};

  # Helper to source an external hooks file if it exists
  sourceHooksFile = path:
    if builtins.pathExists path
    then builtins.readFile path
    else "";

  # Parse profile combinations
  parseProfiles = profileDefinitions: str:
    if str == "all"
    then builtins.attrNames profileDefinitions
    else lib.splitString "-" str;

  # Merge profile definitions for a list of profile names
  mergeProfiles = profileDefinitions: profileNames: let
    selectedDefs = map (name: profileDefinitions.${name}) profileNames;

    # Merge packages
    allPackages = lib.lists.flatten (
      map (def: def.packages or []) selectedDefs
    );

    # Merge scripts
    allScripts =
      lib.foldl
      (acc: def: acc // (def.scripts or {}))
      {}
      selectedDefs;

    scriptsPackages = builtins.attrValues allScripts;

    # Combine shell hooks
    allHooks =
      lib.concatMapStringsSep "\n"
      (def: def.shellHook or "")
      selectedDefs;

    # Merge commands
    allCommands = lib.lists.flatten (
      map (def: def.commands or []) selectedDefs
    );
    # Convert commands to script packages
    commandPackages =
      map (
        cmd:
          pkgs.writeShellScriptBin cmd.name cmd.script
      )
      allCommands;

    # Merge environment variables
    allEnvVars =
      lib.foldl
      (acc: def: acc // (def.envVars or {}))
      {}
      selectedDefs;

    # Build environment variable exports for shell
    envVarExports =
      lib.concatStringsSep "\n"
      (lib.mapAttrsToList
        (name: value: "export ${name}=\"${value}\"")
        allEnvVars);

    # Build environment variable list for containers
    containerEnvList =
      lib.mapAttrsToList
      (name: value: "${name}=${value}")
      allEnvVars;

    # Merge container configs
    mergedContainerConfig = let
      allConfigs = map (def: def.containerConfig or {}) selectedDefs;

      allEnvs =
        containerEnvList
        ++ lib.lists.flatten (
          map (cfg: cfg.Env or []) allConfigs
        );

      allPorts =
        lib.foldl
        (acc: cfg: acc // (cfg.ExposedPorts or {}))
        {}
        allConfigs;

      finalCmd = let
        cmds =
          lib.filter (x: x != null)
          (map (cfg: cfg.Cmd or null) allConfigs);
      in
        if cmds == []
        then ["${pkgs.bash}/bin/bash"]
        else lib.last cmds;

      finalWorkingDir = let
        dirs =
          lib.filter (x: x != null)
          (map (cfg: cfg.WorkingDir or null) allConfigs);
      in
        if dirs == []
        then "/workspace"
        else lib.last dirs;
    in {
      Env = lib.lists.unique allEnvs;
      ExposedPorts = allPorts;
      Cmd = finalCmd;
      WorkingDir = finalWorkingDir;
    };
  in {
    packages = lib.lists.unique (allPackages ++ scriptsPackages ++ commandPackages);
    shellHook = allHooks;
    envVarExports = envVarExports;
    containerConfig = mergedContainerConfig;
    scripts = allScripts;
  };

  # Create a devShell from profile names
  mkDevShell = profileDefinitions: profileNames: hooksFile: let
    merged = mergeProfiles profileDefinitions profileNames;
    scriptNames = builtins.attrNames merged.scripts;
    externalHooks = sourceHooksFile hooksFile;
  in
    pkgs.mkShell {
      buildInputs = merged.packages;

      shellHook = ''
        echo "🚀 Development Environment"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "📦 Active profiles: ${toString profileNames}"
        echo ""

        # Export environment variables
        export FLK_FLAKE_REF=".#${lib.concatStringsSep "-" profileNames}"
        ${merged.envVarExports}

        # Run profile hooks
        ${merged.shellHook}

        ${lib.optionalString (scriptNames != []) ''
          echo ""
          echo "📜 Available scripts: ${toString scriptNames}"
        ''}

        echo ""
        echo "Available profiles: ${toString (builtins.attrNames profileDefinitions)}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        ${externalHooks}
      '';
    };

  # Create a container image from profile names
  mkContainerImage = profileDefinitions: name: profileNames: let
    merged = mergeProfiles profileDefinitions profileNames;
  in
    pkgs.dockerTools.buildLayeredImage {
      inherit name;
      tag = "latest";
      contents = merged.packages;
      config =
        merged.containerConfig
        // {
          Labels = {
            "dev.profiles" = toString profileNames;
            "dev.scripts" = toString (builtins.attrNames merged.scripts);
          };
        };
    };

  # Generate all devShells for given combinations
  mkDevShells = {
    profileDefinitions,
    combinations,
    hooksFile ? "./.flk/hooks.sh",
  }: let
    parser = parseProfiles profileDefinitions;

    generated = builtins.listToAttrs (
      map (combo: {
        name = combo;
        value = mkDevShell profileDefinitions (parser combo) hooksFile;
      })
      combinations
    );
  in
    generated
    // {
      default = mkDevShell profileDefinitions ["base"] hooksFile;
    };

  # Generate all container images for given combinations
  mkContainerImages = {
    profileDefinitions,
    combinations,
    containerFormats ? ["image" "docker" "podman"],
  }: let
    parser = parseProfiles profileDefinitions;

    # Generate images for each combination
    generateForCombo = combo: let
      baseImage = mkContainerImage profileDefinitions combo (parser combo);
    in
      builtins.listToAttrs (
        map (format: {
          name = "${format}-${combo}";
          value = baseImage;
        })
        containerFormats
      );

    # Generate for all combinations
    allGenerated =
      lib.foldl
      (acc: combo: acc // (generateForCombo combo))
      {}
      combinations;
  in
    allGenerated;

  mkProfileOutputs = {
    profileDefinitions,
    combinations ? null,
    hooksFile ? ./.flk/hooks.sh,
    defaultImage ? null,
    defaultShell ? null,
    maxCombinations ? 3,
    includeBaseInShells ? false,
    includeBaseInImages ? true,
  }: let
    shellProfileDefinitions =
      if includeBaseInShells
      then {base = baseProfile;} // profileDefinitions
      else profileDefinitions;

    imageProfileDefinitions =
      if includeBaseInImages
      then {base = baseProfile;} // profileDefinitions
      else profileDefinitions;

    shellProfileNames = builtins.attrNames shellProfileDefinitions;
    imageProfileNames = builtins.attrNames imageProfileDefinitions;

    generateAllCombinations = profiles: maxSize: let
      combinations = k: list:
        if k == 0
        then [[]]
        else if list == []
        then []
        else let
          head = builtins.head list;
          tail = builtins.tail list;
          withHead = map (c: [head] ++ c) (combinations (k - 1) tail);
          withoutHead = combinations k tail;
        in
          withHead ++ withoutHead;

      allSizes = lib.lists.range 1 (lib.trivial.min maxSize (builtins.length profiles));
      allCombos = lib.lists.concatMap (size: combinations size profiles) allSizes;
    in
      map (combo: lib.concatStringsSep "-" combo) allCombos;

    shellCombinations =
      if combinations != null
      then combinations
      else generateAllCombinations shellProfileNames maxCombinations;

    imageCombinations =
      if combinations != null
      then combinations
      else generateAllCombinations imageProfileNames maxCombinations;

    actualDefaultShell =
      if defaultShell != null
      then defaultShell
      else builtins.head shellCombinations;

    actualDefaultImage =
      if defaultImage != null
      then defaultImage
      else builtins.head imageCombinations;

    generatedPackages = mkContainerImages {
      profileDefinitions = imageProfileDefinitions;
      combinations = imageCombinations;
    };

    withDefaults =
      generatedPackages
      // {
        default = generatedPackages."image-${actualDefaultImage}";
      };
  in {
    devShells =
      mkDevShells {
        profileDefinitions = shellProfileDefinitions;
        inherit hooksFile;
        combinations = shellCombinations;
      }
      // {
        # Override default shell
        default = mkDevShell shellProfileDefinitions (parseProfiles shellProfileDefinitions actualDefaultShell) hooksFile;
      };

    packages = withDefaults;
  };
}
