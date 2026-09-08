{
  description = "DSpace devbox native services";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs supportedSystems (system: f {
        pkgs = nixpkgs.legacyPackages.${system};
      });
    in
    {
      packages = forAllSystems ({ pkgs }:
        let
          solr = pkgs.stdenv.mkDerivation {
            pname = "solr";
            version = "9.10.1";

            src = pkgs.fetchurl {
              url = "https://dlcdn.apache.org/solr/solr/9.10.1/solr-9.10.1.tgz";
              sha512 = "sha512-I5FboMnrqB2e191Gvz36dIoc8Sz9HSvDw34wIok7jUWm1twHjueeM8A2cZHD5PLR3zxvVwUzHM/hPWsSh4EusA==";
            };

            installPhase = ''
              runHook preInstall
              mkdir -p $out
              cp -rp . "$out/"
              chmod +x "$out/bin/solr" "$out/bin/solr.cmd" 2>/dev/null || true
              runHook postInstall
            '';

            meta = with pkgs.lib; {
              description = "Apache Solr search platform";
              homepage = "https://solr.apache.org";
              license = licenses.asl20;
              platforms = platforms.unix;
            };
          };

          # Floci S3: Quarkus app built from source (see the Floci install guide:
          # `mvn clean package -DskipTests`). No standalone binary is published in
          # the GitHub releases, so we build the production Quarkus app ourselves.
          # Split into two derivations:
          #   1. flociJar — a fixed-output derivation (Maven needs Maven Central,
          #      which a plain sandbox build forbids; declaring it fixed-output
          #      opts it out of the sandbox's network ban, like fetchurl does).
          #      Its output is ONLY the quarkus-app dir: no wrapper, so no store
          #      path references (FODs must not reference other store paths).
          #   2. floci — a normal derivation wrapping the jar with a launcher
          #      that hardcodes JDK 25 (so it never interferes with the DSpace
          #      JDK 21). Normal derivations MAY reference store paths.
          flociJar = pkgs.stdenv.mkDerivation {
            pname = "floci-jar";
            version = "2.0.1";

            src = pkgs.fetchFromGitHub {
              owner = "floci-io";
              repo = "floci";
              rev = "2.0.1";
              sha256 = "sha256-2LORiBBj5sabwU1cQ2mi3W5k9Qg4AZ5AJqTVrNqfGh8=";
            };

            nativeBuildInputs = [ pkgs.openjdk25 pkgs.maven ];

            outputHashAlgo = "sha256";
            outputHashMode = "recursive";
            outputHash = "sha256-G7THEpONn75eomLOxAVvjM4TVmo8R3bXJtVdcH+Mftw=";

            dontConfigure = true;
            enableParallelBuilding = false;

            buildPhase = ''
              runHook preBuild
              export HOME="$TMPDIR"
              export JAVA_HOME="${pkgs.openjdk25}"
              # Reproducible jars: fix the timestamp Maven/Quarkus stamp into
              # archives, so the fixed-output hash is stable across builds/machines.
              export SOURCE_DATE_EPOCH=1
              mvn --batch-mode clean package -DskipTests -Dproject.build.outputTimestamp=1970-01-01T00:00:00Z
              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              mkdir -p "$out"
              cp -r target/quarkus-app "$out/quarkus-app"
              runHook postInstall
            '';
          };

          floci = pkgs.stdenv.mkDerivation {
            pname = "floci";
            version = "2.0.1";

            src = flociJar;
            dontUnpack = true;

            installPhase = ''
              runHook preInstall
              mkdir -p "$out/bin" "$out/lib"
              cp -r "$src/quarkus-app" "$out/lib/quarkus-app"
              cat > "$out/bin/floci" <<WRAP
              #!/usr/bin/env bash
              exec "${pkgs.openjdk25}/bin/java" -jar "$out/lib/quarkus-app/quarkus-run.jar" "\$@"
              WRAP
              chmod +x "$out/bin/floci"
              runHook postInstall
            '';

            meta = with pkgs.lib; {
              description = "Floci — free, open-source local AWS emulator (Quarkus JAR)";
              homepage = "https://floci.io";
              license = licenses.mit;
              platforms = platforms.unix;
            };
          };
        in
        {
          solr = solr;
          default = solr;
          floci = floci;
        });
    };
}
