{
  description = "feuille: open a PDF at once, arrange its pages, put text on them.";

  inputs = {
    self.submodules = true;
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.2605";
    git-hooks = {
      url = "https://flakehub.com/f/cachix/git-hooks.nix/0.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    git-hooks,
    ...
  }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    inherit (pkgs) lib;

    wgpu = pkgs.fetchurl {
      url = "https://github.com/gfx-rs/wgpu-native/releases/download/v29.0.1.1/wgpu-linux-x86_64-release.zip";
      sha256 = "95a4d90c071005a98d03eab348beaa6b07e16eb00d1dcdb9f8348f75eb97ec5a";
    };

    odin = pkgs.stdenv.mkDerivation {
      pname = "odin";
      version = "dev-2026-11a";
      src = pkgs.fetchurl {
        url = "https://github.com/odin-lang/Odin/releases/download/dev-2026-11a/odin-linux-amd64-dev-2026-11a.tar.gz";
        sha256 = "65c9f6e97d6f8a30930e151f270ce5aeaa98fe8b2ba49fe067394e2af04f7618";
      };
      nativeBuildInputs = [pkgs.makeWrapper pkgs.unzip];
      dontBuild = true;
      dontPatchELF = true;
      installPhase = ''
        mkdir -p $out/lib/odin $out/bin
        cp -r . $out/lib/odin
        dest=$out/lib/odin/vendor/wgpu/lib/wgpu-linux-x86_64-release
        mkdir -p $dest
        unzip -qo ${wgpu} -d $dest
        echo 29.0.1.1 > $dest/VERSION
        makeWrapper $out/lib/odin/odin $out/bin/odin --set-default ODIN_ROOT $out/lib/odin/ --prefix PATH : ${lib.makeBinPath [pkgs.clang pkgs.lld]}
      '';
    };

    runtime = with pkgs; [
      vulkan-loader
      mesa
      libxkbcommon
      wayland
      libx11
      libxcb
      libxcb-cursor
      fontconfig
      freetype
      dbus
      curl # (gt:http opens libcurl at run time)
    ];

    # APP_VERSION of src/main.odin
    version = let
      line = lib.findFirst (lib.hasPrefix "APP_VERSION ::") "" (lib.splitString "\n" (builtins.readFile ./src/main.odin));
    in
      builtins.head (builtins.match ''APP_VERSION +:: "([^"]+)".*'' line);

    # feuille, built from this tree as a release is: feuilletool build release.
    feuille = pkgs.stdenv.mkDerivation {
      pname = "feuille";
      inherit version;
      src = lib.fileset.toSource {
        root = ./.;
        fileset = lib.fileset.difference ./. (lib.fileset.maybeMissing ./build);
      };
      # the crates of the toolkit's native library (text, PDF), vendored: cargo makes no request
      cargoDeps = pkgs.rustPlatform.importCargoLock {lockFile = ./ext/gui_toolkit/native/gt/Cargo.lock;};

      nativeBuildInputs = [odin pkgs.cargo pkgs.rustc pkgs.clang pkgs.lld pkgs.autoPatchelfHook pkgs.copyDesktopItems];
      buildInputs = [pkgs.fontconfig pkgs.freetype pkgs.stdenv.cc.cc.lib];
      # what it opens with dlopen goes in its RUNPATH; the Vulkan driver is the system's
      runtimeDependencies = runtime;
      # Odin links a foreign library as -l:<absolute path> with -L/, which the purity check of the linker wrapper drops
      NIX_ENFORCE_PURITY = 0;

      configurePhase = ''
        runHook preConfigure
        export HOME="$TMPDIR"
        mkdir -p "$HOME/.cargo"
        cat > "$HOME/.cargo/config.toml" <<EOF
        [source.crates-io]
        replace-with = "vendored-sources"
        [source.vendored-sources]
        directory = "$cargoDeps"
        EOF
        export CARGO_NET_OFFLINE=true
        runHook postConfigure
      '';

      buildPhase = ''
        runHook preBuild
        mkdir -p build
        odin run tools/feuilletool -collection:gt=ext/gui_toolkit/src -out:build/feuilletool -- build release
        runHook postBuild
      '';

      desktopItems = [
        (pkgs.makeDesktopItem {
          name = "feuille";
          desktopName = "Feuille";
          genericName = "PDF Reader";
          comment = "Open a PDF at once, arrange its pages, put text on them.";
          exec = "feuille %f";
          icon = "feuille";
          categories = ["Office" "Viewer"];
          mimeTypes = ["application/pdf"];
          keywords = ["pdf" "reader" "pages" "form"];
          startupWMClass = "feuille";
        })
      ];

      installPhase = ''
        runHook preInstall
        install -Dm755 build/feuille $out/bin/feuille
        for size in 16 32 64 128 256; do
          install -Dm644 assets/logo_$size.png "$out/share/icons/hicolor/''${size}x''${size}/apps/feuille.png"
        done
        install -Dm644 -t $out/share/doc/feuille LICENSE README.md CHANGELOG.md THIRD-PARTY-NOTICES
        install -Dm644 ext/gui_toolkit/src/lucide/LICENSE.txt $out/share/doc/feuille/LUCIDE-LICENSE.txt
        runHook postInstall
      '';

      meta = {
        description = "Open a PDF at once, arrange its pages, put text on them.";
        license = lib.licenses.mit;
        platforms = [system];
        mainProgram = "feuille";
      };
    };

    preCommitCheck = git-hooks.lib.${system}.run {
      package = pkgs.prek;
      src = ./.;
      hooks = {
        alejandra.enable = true;
        deadnix.enable = true;
        statix.enable = true;
      };
    };
  in {
    packages.${system} = {
      inherit feuille odin;
      default = feuille;
    };
    apps.${system}.default = {
      type = "app";
      program = "${feuille}/bin/feuille";
    };
    checks.${system} = {
      pre-commit = preCommitCheck;
      inherit feuille;
    };
    formatter.${system} = pkgs.alejandra;

    devShells.${system}.default = pkgs.mkShell {
      # (cargo and rustc: the toolkit's native library)
      packages = [odin] ++ (with pkgs; [cargo rustc]) ++ preCommitCheck.enabledPackages;
      buildInputs = [pkgs.fontconfig];
      shellHook =
        preCommitCheck.shellHook
        + ''
          export LD_LIBRARY_PATH=${lib.makeLibraryPath runtime}
        '';
    };
  };
}
