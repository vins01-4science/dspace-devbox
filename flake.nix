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
              hash = "sha512-I5FboMnrqB2e191Gvz36dIoc8Sz9HSvDw34wIok7jUWm1twHjueeM8A2cZHD5PLR3zxvVwUzHM/hPWsSh4EusA==";
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
              # Lean JVM: floci is a local AWS/S3 emulator (low throughput). Default
              # Quarkus ergonomic heap is ~25% of physical RAM (several hundred MB+
              # RSS via Netty direct buffers). Cap the heap explicitly; keep enough
              # headroom for Netty's native (off-heap) allocations. SerialGC is fine
              # for a single-socket emulator and matches Solr's tuning in
              # process-compose.yml.
              exec "${pkgs.openjdk25}/bin/java" \
                -Xms64m -Xmx256m \
                -XX:+UseSerialGC \
                -XX:TieredStopAtLevel=1 \
                -XX:MaxMetaspaceSize=128m \
                -XX:MaxDirectMemorySize=64m \
                -XX:ReservedCodeCacheSize=64m \
                -jar "$out/lib/quarkus-app/quarkus-run.jar" "\$@"
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

          # Floci native: GraalVM native-image build (no JVM at runtime). Single
          # self-contained `-runner` binary → a fraction of the JAR's memory
          # (no JIT heap / metaspace / code cache / Netty direct buffers), sub-100ms
          # startup. Trade-off: requires GraalVM CE as a build-only dep and a
          # 2–5 min native-image compile (vs seconds for the JAR), and native
          # binaries are not byte-reproducible across machines, so the FOD hash
          # must be re-pinned on the target machine if the store is shared.
          # Exposed as an opt-in `.#floci-native`; default `.#floci` stays the JAR.
          flociNativeRunner = pkgs.stdenv.mkDerivation {
            pname = "floci-native";
            version = "2.0.1";

            src = pkgs.fetchFromGitHub {
              owner = "floci-io";
              repo = "floci";
              rev = "2.0.1";
              sha256 = "sha256-2LORiBBj5sabwU1cQ2mi3W5k9Qg4AZ5AJqTVrNqfGh8=";
            };

            nativeBuildInputs =
              [ pkgs.graalvmPackages.graalvm-ce pkgs.maven pkgs.gcc pkgs.zlib ];
            buildInputs = [ pkgs.zlib ];

            outputHashAlgo = "sha256";
            outputHashMode = "recursive";
            outputHash = "sha256-70bSiEesC1ty5qUeLgkl0c9hxYugMN5FQB/XbF/zTWE=";

            dontConfigure = true;
            enableParallelBuilding = false;

            # native-image embeds the build-machine path into the binary; strip it
            # down where possible and set a stable build id.
            buildPhase = ''
              runHook preBuild
              export HOME="$TMPDIR"
              export JAVA_HOME="${pkgs.graalvmPackages.graalvm-ce}"
              export PATH="${pkgs.graalvmPackages.graalvm-ce}/bin:$PATH"
              export GRAALVM_HOME="${pkgs.graalvmPackages.graalvm-ce}"
              export SOURCE_DATE_EPOCH=1
              mvn --batch-mode clean package -Dnative -DskipTests -B
              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              mkdir -p "$out/bin"
              echo "[floci-native] cwd: $(pwd)"
              RUNNER="$(find . -type f -name '*runner' | head -1)"
              echo "[floci-native] runner: $RUNNER"
              [ -n "$RUNNER" ] && [ -f "$RUNNER" ] || {
                echo "[floci-native] ERROR: native runner not found" >&2
                exit 1
              }
              cp -v "$RUNNER" "$out/bin/floci"
              chmod +x "$out/bin/floci"
              runHook postInstall
            '';
          };

          flociNative = pkgs.stdenv.mkDerivation {
            pname = "floci-native";
            version = "2.0.1";

            src = flociNativeRunner;
            dontUnpack = true;

            installPhase = ''
              runHook preInstall
              mkdir -p "$out/bin"
              cp "$src/bin/floci" "$out/bin/floci"
              chmod +x "$out/bin/floci"
              runHook postInstall
            '';

            meta = with pkgs.lib; {
              description = "Floci — local AWS emulator, native-image build (no JVM)";
              homepage = "https://floci.io";
              license = licenses.mit;
              platforms = platforms.unix;
            };
          };

          # Ministack S3: Python (hypercorn/ASGI) LocalStack-compatible AWS
          # emulator, a drop-in alternative to Floci. All packages are pure-
          # Python wheels (py3-none-any) fetched from PyPI and installed as-is,
          # so nothing is compiled. Versions are pinned to upstream's exact
          # requirements: upstream requires botocore==1.43.63 and
          # graphql-core==3.2.12 (both exact pins), and jsonata-python is not
          # packaged in nixpkgs.
          jsonata-python = pkgs.python3.pkgs.buildPythonPackage {
            pname = "jsonata-python";
            version = "0.7.0";

            format = "wheel";
            src = pkgs.fetchurl {
              url = "https://files.pythonhosted.org/packages/03/30/17eaf4576916556875fc961002cb67d0b404abc3345ab2bb13f1496654a2/jsonata_python-0.7.0-py3-none-any.whl";
              sha256 = "85b8dd2adf9c17a67494892ef04bc191ba2156598daae4465eec30ffd1559238";
            };

            doCheck = false;
            dontCheckRuntimeDeps = true;

            meta = with pkgs.lib; {
              description = "JSONata query and transformation language for Python";
              homepage = "https://github.com/ministackorg/jsonata-python";
              license = licenses.mit;
              platforms = platforms.unix;
            };
          };

          botocore = pkgs.python3.pkgs.buildPythonPackage {
            pname = "botocore";
            version = "1.43.63";

            format = "wheel";
            src = pkgs.fetchurl {
              url = "https://files.pythonhosted.org/packages/23/ae/8ddbf97a12fba9b6ce50ac1c2209ebd2ab3b240229a1fbe5de66ffcbd05f/botocore-1.43.63-py3-none-any.whl";
              sha256 = "8deed86feacc8f8d2491f1d170562af191f8b33924052d834f4217d5d797e5a9";
            };

            propagatedBuildInputs = with pkgs.python3.pkgs; [
              jmespath
              python-dateutil
              urllib3
            ];

            doCheck = false;
            dontCheckRuntimeDeps = true;

            meta = with pkgs.lib; {
              description = "Low-level, core components of Python SDK 2.0";
              homepage = "https://github.com/boto/botocore";
              license = licenses.asl20;
              platforms = platforms.unix;
            };
          };

          graphql-core = pkgs.python3.pkgs.buildPythonPackage {
            pname = "graphql-core";
            version = "3.2.12";

            format = "wheel";
            src = pkgs.fetchurl {
              url = "https://files.pythonhosted.org/packages/4e/b6/304c572e79b9e82982dbd5091e26a89f5018e565868091d804c2142f6ba5/graphql_core-3.2.12-py3-none-any.whl";
              sha256 = "3d8f104532070485e13caa4092c1e71cda2ba6cffd96e98f285111ee10ed1e51";
            };

            doCheck = false;
            dontCheckRuntimeDeps = true;

            meta = with pkgs.lib; {
              description = "GraphQL implementation for Python";
              homepage = "https://github.com/graphql-python/graphql-core";
              license = licenses.mit;
              platforms = platforms.unix;
            };
          };

          ministack = pkgs.python3.pkgs.buildPythonApplication {
            pname = "ministack";
            version = "1.5.9";

            format = "wheel";
            src = pkgs.fetchurl {
              url = "https://files.pythonhosted.org/packages/6f/1c/c2dfd09e9a765e1db79379eaf9602fc3ec689abc7e32771f0b29f4e2e38a/ministack-1.5.9-py3-none-any.whl";
              sha256 = "6d73d224d5b0b124fbecb3911525a6c8cb34f511847872c5342e568e51d29a82";
            };

            propagatedBuildInputs = [
              pkgs.python3.pkgs.hypercorn
              pkgs.python3.pkgs.pyyaml
              pkgs.python3.pkgs.defusedxml
              botocore
              jsonata-python
              graphql-core
            ];

            doCheck = false;
            dontCheckRuntimeDeps = true;

            meta = with pkgs.lib; {
              description = "Ministack — LocalStack-compatible local AWS emulator (Python/hypercorn)";
              homepage = "https://github.com/ministackorg/ministack";
              license = licenses.mit;
              platforms = platforms.unix;
            };
          };

        in
        {
          solr = solr;
          default = ministack;
          floci = floci;
          floci-native = flociNative;
          ministack = ministack;
        });
    };
}
