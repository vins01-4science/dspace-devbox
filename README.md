# DSpace Dev Environment (devbox)

Fast, reproducible, small dev env for the two repos in this folder:
`DSpace/` (backend, Spring Boot) and `dspace-angular/` (UI, Angular).

- **No packaging.** The backend runs straight from `target/classes` dirs plus
  `.m2` jars on the classpath — no fat `server-boot` jar is ever built or copied.
- **Native infra.** Postgres 15, Solr 9.10.1, Mailpit and the Ministack S3
  emulator all run as **native** services via `devbox services`
  (process-compose) — no Docker anywhere in the stack. Ministack is installed
  from its PyPI wheel (Python/hypercorn, LocalStack-compatible) by `flake.nix`
  with versions pinned to upstream's exact requirements. The previous Floci
  (Quarkus JAR) emulator remains packaged in `flake.nix` as an **opt-in** — it
  is not installed by default (see “Choosing the S3 emulator”).
- **S3 via Ministack.** Bitstream storage goes to a Ministack `dspace-assets`
  bucket (path-style, creds `test`/`test`), so S3 works with zero cloud cost.
- **Hot reload.** UI: `ng serve` watch mode (always on). Backend: `mvn compile`
  + restart — see “Hot reload, backend” below.

## The repos are git submodules

`DSpace/` and `dspace-angular/` are **git submodules** of this template. Their
URLs and default branches are recorded in `.gitmodules`:

| Submodule      | Default remote                          | Default branch          |
| -------------- | --------------------------------------- | ----------------------- |
| `DSpace`       | `vins01-4science/DSpace` (fork)         | `task/main/hot-reload`  |
| `dspace-angular` | `DSpace/dspace-angular` (upstream)     | `main`                  |

### Clone

```bash
git clone --recursive <template-url> dspace-main
```

### Reconfigure remotes / branches (forks, customers, CI)

Every repo/branch pairing is driven by `repos.conf`. Edit it to point at any
fork / remote / branch, then re-apply:

```bash
# edit repos.conf
devbox run init-repos     # re-points origins, fetches, checks out, pulls
```

`bash scripts/init-repos.sh` is equivalent and works without devbox. It is
idempotent — safe to run any time after editing `repos.conf`.

> Note: as submodules, commits are tracked by the parent template, but
> `init-repos` checks out the configured branch tip, so a template copy tracks
> the live branch rather than a frozen commit.

## Quickstart

Everything is driven through `devbox` scripts (defined in `devbox.json`).

```bash
devbox run infra-up      # start postgres + solr + s3 + mailpit (native, fixed ports)
devbox run backend       # boot the backend (random free port, ~15 s)
devbox run ui            # boot the Angular dev server (random free port, watch mode)
```

or one shot — both processes together, ports paired automatically:

```bash
devbox run dev
```

`devbox run` with no arguments lists all available scripts.

## First run only

`devbox run setup` — `npm ci` in `dspace-angular` (once), resolves the
backend classpath, and — when the infra DB is reachable — applies the Flyway
migrations automatically (idempotent). To migrate manually instead:

```bash
devbox shell
bash scripts/dspace-cli.sh database migrate
```

and the administrator is created by:

```bash
bash scripts/dspace-cli.sh create-administrator -e admin@dspace.org -f Admin -l User -p admin123 -c en
```

> **Why `devbox shell` + the script, not `devbox run cli -- <args>`?**
> Args passed after `--` to a script declared in `devbox.json` are currently
> **dropped** by devbox (v0.18.0), so `ScriptLauncher` gets no command and only
> prints usage. The `dspace-cli.sh` wrapper forwards `"$@"` correctly, so run it
> from inside a `devbox shell` (or directly, if your host already matches the
> devbox toolchain).

## What is where

| Piece          | URL / how to find it                                      |
| -------------- | --------------------------------------------------------- |
| UI             | `http://localhost:<ui port>/home` (printed by `env`)      |
| Backend REST   | `http://localhost:<backend port>/server`                  |
| Mailpit inbox  | `http://localhost:8025` (fixed)                           |
| Solr admin     | `http://localhost:8983/solr` (fixed)                      |

Infra services use **default** host ports (`5432`, `8983`, `4566`, `1025`/`8025`)
overridable via `PG_PORT`, `SOLR_PORT`, `S3_PORT`, `SMTP_PORT`,
`MAILPIT_UI_PORT`. If a port is already taken, `scripts/infra.sh up` (and Solr
even under a bare `devbox services up`) auto-detects it and shifts to the first
free port in `base+1..+20` — no restart loops. The chosen ports persist in
`.devbox/ports.env` (plus `.devbox/solr-data/.port` for Solr) so the backend
and the readiness probes always follow the running services. The `floci` AWS
profile in `~/.aws/config` pins `endpoint_url` to `http://localhost:4566` with
creds `test`/`test` (path-style); it is **not** applied automatically — only
use it explicitly with `aws --profile floci ...`, so the devbox shell's `aws`
never touches your real AWS configuration. If you override `S3_PORT`, update
the profile's `endpoint_url` accordingly. Run `bash scripts/lib/env.sh` (or
`devbox run env`) to print the current values; the backend/UI ports are still
random per run.

Login: `admin@dspace.org` / `admin123`.

## How the ports model works

- **Infra (all native):** Postgres 15, Solr 9.10.1, Mailpit and Ministack S3
  (LocalStack-compatible) run as native processes managed by `devbox services`
  (process-compose) with **fixed** host ports (`5432`, `8983`, `4566`,
  `1025`/`8025`). All definitions live in `process-compose.yml`.
- **Busy-port auto-relocation:** `scripts/infra.sh up` probes every fixed port
  up front and relocates any that are taken, persisting the choices to
  `.devbox/ports.env` (reloaded by `env.sh` for every run script). Solr is
  additionally self-healing at the process level: if its port is busy when it
  starts (e.g. a system-wide Solr already listens on `8983`), `solr-native.sh`
  picks a free port, records it in `.devbox/solr-data/.port`, and the
  process-compose readiness/shutdown probes plus the backend wiring follow it —
  so even a bare `devbox services up` won't restart-loop. Ports stay stable
  across restarts once relocated.
- **Custom packages where nixpkgs lacks the exact version:** `flake.nix` builds
  Solr 9.10.1 from the Apache CDN (fetchurl) and installs Ministack from its
  PyPI wheel. All Ministack packages are pure-Python wheels (`py3-none-any`)
  installed as-is — nothing is compiled — with versions pinned to upstream's
  exact requirements (`botocore==1.43.63`, `graphql-core==3.2.12`, and
  `jsonata-python==0.7.0`, which nixpkgs does not ship). Postgres and Mailpit
  come from nixpkgs. Floci 2.0.1 (Maven/Quarkus) is still built as `.#floci` /
  `.#floci-native` — an opt-in alternative, not installed by default.
- **Footprints (lean on purpose):** the only JVM service left is Solr, capped
  via `SOLR_JAVA_MEM` in `process-compose.yml` (`-Xmx128m`, SerialGC). Ministack
  is Python — a single asyncio event loop, no JIT heap or off-heap buffers —
  measuring ~43 MB RSS idle (~57 MB under active S3 uploads), a fraction of a
  JVM's footprint. (For comparison, the old Floci wrapper capped its heap at
  `-Xmx256m` ~190 MB RSS, and the opt-in `.#floci-native` is ~80 MB.)
- **Floci native (optional alternative):** `flake.nix` also exposes
  `.#floci-native`, a GraalVM **native-image** build of Floci (no JVM at
  runtime, ~80 MB RSS, ~30 ms start). See "Choosing the S3 emulator" below for
  the switch recipe.
- **Backend / UI:** each run picks a random free OS port (`free_port()` in
  `env.sh`). `devbox run dev` allocates both in the same shell so the backend's
  advertised UI URL and the `ng serve` port always agree (CORS origin matches).
- **Per instance:** `INSTANCE=2 devbox run backend` starts a second instance on
  a different random port using the same shared database, Solr cores and bucket.

## Choosing the S3 emulator

**Ministack is the default and works out of the box** — `devbox.json` installs
it, and the `s3` service in `process-compose.yml` boots it. It speaks the
LocalStack API, so the same client-side `floci` profile, env exports and
`aws`/DSpace code work against it unchanged. No Docker, no JVM: ~43 MB RSS
idle (~57 MB under active S3 uploads).

Floci (the previous Quarkus-based emulator) is still built by `flake.nix` as
`.#floci` (JAR) and `.#floci-native` (GraalVM native-image), but it is **not
installed** by default — its binary is not on the devbox PATH. To use it
instead of Ministack:

1. Add it to `devbox.json` packages — `"path:.#floci": {}`, or
   `"path:.#floci-native": {}` for the native build — then re-run
   `devbox update`.
2. Point the `s3` service in `process-compose.yml` at it: swap
   `exec ministack` for `exec floci` and replace the `MINISTACK_*` env with
   the `FLOCI_*`/`QUARKUS_HTTP_HOST` block (both variants are documented in
   git history).

Caveat for `.#floci-native`: the build takes 2–5 min with GraalVM CE as a
build-only dep, and native binaries are not byte-reproducible, so the
fixed-output hash in `flake.nix` must be re-pinned when the derivation changes
(run `nix build .#floci-native` and paste the reported hash).

## Hot reload, backend

The UI hot-reloads automatically (`ng serve --watch`).

The backend hot-reloads with **real Spring Boot DevTools restarts**:
`spring-boot-devtools` is a dependency of `dspace/modules/server-boot`, and with
`DEVTOOLS_RESTART=true` the app boots under DevTools' restart classloader taking
the **full launch classpath** as its restart world, so the whole app (including
the DSpace kernel and its SPI) reloads in one coherent classloader. Edit Java
code, run `devbox run compile`, and the running backend restarts in seconds —
no manual relaunch.

```bash
DEVTOOLS_RESTART=true devbox run backend   # hot-reload loop (Ctrl-C to stop)
devbox run backend                         # plain boot (restart disabled)
devbox run compile                         # recompile -> triggers DevTools restart
```

Three small patches (in this repo, no upstream changes) make DevTools work with
DSpace's two-context architecture:

1. `dspace-server-webapp/src/main/resources/META-INF/spring-devtools.properties`
   — makes the restart world the **whole launch classpath** (all jars + all
   `target/classes` dirs), minus two JVM-global-static landmines:

   ```properties
   restart.include.all=.*
   restart.exclude.xmlapis=.*xml-apis[^/]*[.]jar   # hijacks JDK JAXP, crashes log4j2 init
   restart.exclude.tomcat=.*tomcat-embed[^/]*[.]jar # reload breaks URL.setURLStreamHandlerFactory
   ```

   Without `include.all`, third-party jars resolve in the base loader and
   XOAI filter loading crashes with `DSpace kernel cannot be null` (the kernel
   static exists only in the restart loader).
2. `DevToolsRestarterUrlSeeder` (an `EnvironmentPostProcessor`) — DevTools
   initializes its per-world `Restarter` from `getInitialUrls(thread)`, which
   returns null on the `restartedMain` thread, so by default every generation
   after the first has an empty restart world and no watcher. The seeder
   reflectively seeds the live `Restarter` with this world's classloader URLs
   in every generation. This is what actually enables generation 2+.
3. `DevToolsRootContextRegistrar` (an `ApplicationListener` for
   `ApplicationPreparedEvent`) — `Restarter.prepare()` only closes contexts
   **without a parent**; DSpace's web context has a parent (the kernel
   service-manager context), so on restart the old Tomcat never stops and
   generation 2 dies with `BindException`. The registrar reflectively registers
   the web context in `Restarter.rootContexts` so the old server is closed
   before the new one binds.

Verified end-to-end: edit a controller → `devbox run compile` → the log shows
a second `Started ServerBootApplication` ~20 s later, the previous Tomcat
stopped cleanly, and the new code answers requests on the same port.

## Storage (S3)

`assetstore.index.primary=1` routes bitstreams to S3, and
`assetstore.s3.endpoint=http://localhost:<s3 port>` targets Ministack. The
bucket `dspace-assets` is auto-created on first write.

```bash
aws --profile floci s3 ls     # 'floci' profile → client-side only (test/test, path-style); opt in explicitly
```

## Configuration

- Backend overrides are exported as env by `scripts/lib/env.sh` — `__P__` = `.`
  and `__D__` = `-`, e.g. `db__P__url`, `solr__P__multicorePrefix`,
  `assetstore__P__s3__P__endpoint`.
- UI: `dspace-angular/config/config.dev.yml` (dev defaults) + `DSPACE_*` env
  vars (`DSPACE_REST_PORT`, `DSPACE_UI_NAMESPACE=/home`, ...).
- Logs: `.devbox/backend-<i>.log`, `.devbox/ui-<i>.log`. Backend console logs
  are colored via `.devbox/log4j2-dev.xml`.

## Good to know

- Scripts are `scripts/{backend,ui,dev,infra,cli,setup,init}.sh` + `scripts/lib/*`
  + `scripts/{db-native,solr-native}.sh` (native service bootstrap).
- `devbox.json` pins all package versions explicitly (maven@3.9.16, mvnd@1.0.6,
  nodejs_22@22.23.2, jdk21@21, awscli@1.44.21, vim@9.2.0782,
  postgresql_15@15.19, mailpit@1.31.0, git@2.55.0) plus the custom Nix
  packages `solr` and `ministack` (via `flake.nix`). No global `AWS_PROFILE`
  is set in the devbox shell — the emulator profile is opt-in only
  (`aws --profile floci ...`). All versions are committed in `devbox.lock` —
  to update a package, run `devbox add <pkg>@<new-version>`.
- The `path:.#solr` and `path:.#ministack` flake refs are locked in
  `devbox.lock` with a relative path (`path:../../..`, resolved from the
  generated flake against the project root), so the committed lock is
  machine-independent — a fresh clone just works without re-locking, and no
  per-machine edits leak into `devbox.lock` diffs. `devbox` resolves the
  relative ref to each machine's absolute project path when it regenerates
  `.devbox/gen`. (Only a deliberate `devbox update`/`devbox add` rewrites the
  lock, and then only when the Nix packages actually change.)
- The backend is launched with `mvn -pl dspace/modules/server-boot
  spring-boot:run`; devtools + all module `target/classes` dirs are injected
  through `-Dspring-boot.run.additional-classpath-elements` (comma-separated),
  keeping fresh classes in front of the stale `.m2` reactor jars.
- **Local-only by design:** the infra binds well-known ports on localhost and
  dev Postgres accepts the `dspace` user via `trust` auth. Do not run this env
  on a shared/multiuser machine or bind it beyond `127.0.0.1` — if you must,
  secure the database auth (e.g. md5/scram passwords) first.