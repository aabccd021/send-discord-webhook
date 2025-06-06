{
  nixConfig.allow-import-from-derivation = false;

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.treefmt-nix.url = "github:numtide/treefmt-nix";
  inputs.bun2nix.url = "github:baileyluTCD/bun2nix";
  inputs.systemd-notify-fifo.url = "github:aabccd021/systemd-notify-fifo";

  outputs =
    { self, ... }@inputs:
    let

      overlays.default = (
        final: prev:
        import ./overlay.nix {
          pkgs = final;
          inputs = inputs;
        }
      );

      pkgs = import inputs.nixpkgs {
        system = "x86_64-linux";
        overlays = [
          inputs.systemd-notify-fifo.overlays.default
        ];
      };

      overlayPackages = import ./overlay.nix {
        pkgs = pkgs;
        inputs = inputs;
      };

      test = import ./test {
        pkgs = pkgs;
        discord-webhook-dispatcher = overlayPackages.discord-webhook-dispatcher;
      };

      treefmtEval = inputs.treefmt-nix.lib.evalModule pkgs {
        projectRootFile = "flake.nix";
        programs.prettier.enable = true;
        programs.nixfmt.enable = true;
        programs.biome.enable = true;
        programs.shfmt.enable = true;
        settings.formatter.prettier.priority = 1;
        settings.formatter.biome.priority = 2;
        settings.global.excludes = [ "LICENSE" ];
      };

      formatter = treefmtEval.config.build.wrapper;

      nodeModules = inputs.bun2nix.lib.x86_64-linux.mkBunNodeModules (import ./bun.nix);

      typeCheck = pkgs.runCommand "typeCheck" { } ''
        cp -Lr ${nodeModules}/node_modules ./node_modules
        cp -Lr ${./src} ./src
        cp -L ${./tsconfig.json} ./tsconfig.json
        ${pkgs.typescript}/bin/tsc
        touch $out
      '';

      lintCheck = pkgs.runCommand "lintCheck" { } ''
        cp -Lr ${nodeModules}/node_modules ./node_modules
        cp -Lr ${./src} ./src
        cp -L ${./biome.jsonc} ./biome.jsonc
        cp -L ${./tsconfig.json} ./tsconfig.json
        cp -L ${./package.json} ./package.json
        ${pkgs.biome}/bin/biome check --error-on-warnings
        touch $out
      '';

      inputPackages = {
        bun = pkgs.bun;
        biome = pkgs.biome;
        typescript = pkgs.typescript;
        typescript-language-server = pkgs.typescript-language-server;
        vscode-langservers-extracted = pkgs.vscode-langservers-extracted;
        bun2nix = inputs.bun2nix.packages.x86_64-linux.default;
        nixd = pkgs.nixd;
      };

      devShells.default = pkgs.mkShellNoCC {
        buildInputs = builtins.attrValues inputPackages;
      };

      scripts.fix = pkgs.writeShellApplication {
        name = "fix";
        runtimeInputs = [ pkgs.biome ];
        text = ''
          biome check --fix --unsafe
        '';
      };

      packages =
        devShells
        // test
        // scripts
        // inputPackages
        // overlayPackages
        // {
          tests = pkgs.linkFarm "tests" test;
          formatting = treefmtEval.config.build.check self;
          formatter = formatter;
          typeCheck = typeCheck;
          lintCheck = lintCheck;
        };

    in

    {

      packages.x86_64-linux = packages // {
        gcroot = pkgs.linkFarm "gcroot" packages;
      };

      checks.x86_64-linux = packages;
      formatter.x86_64-linux = formatter;
      devShells.x86_64-linux = devShells;

      overlays = overlays;

    };
}
