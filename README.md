# DSpace Dev Environment (devbox)

Fast, reproducible, small dev env for the two repos in this folder:
`DSpace/` (backend, Spring Boot) and `dspace-angular/` (UI, Angular).

- **No packaging.** The backend runs straight from `target/classes` dirs plus
  `.m2` jars on the classpath — no fat `server-boot` jar is ever built or copied.
- **Native infra.** Postgres 15, Solr 9.10.1, Mailpit and the Floci S3 emulator all
  run as **native** services via `devbox services` (process-compose) — no Docker
  anywhere in the stack. Floci is built from source (Quarkus JAR) by `flake.nix`.
- **S3 via Floci.** Bitstream storage goes to a Floci `dspace-assets` bucket
  (path-style, creds `test`/`test`), so S3 works with zero cloud cost.
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
devbox run infra-up      # start postgres + solr + floci + mailpit (native, fixed ports)
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

Infra services run on **fixed** host ports: Postgres `5432`, Solr `8983`, Floci
`4566`, Mailpit SMTP `1025` / UI `8025` (override via `PG_PORT`, `SOLR_PORT`,
`S3_PORT`, `SMTP_PORT`, `MAILPIT_UI_PORT`). Note: the `floci` AWS profile in
`~/.aws/config` pins `endpoint_url` to `http://localhost:4566` — if you override
`S3_PORT`, update it accordingly. Run `bash scripts/lib/env.sh` (or
`devbox run env`) to print the current values; the backend/UI ports are still
random per run.

Login: `admin@dspace.org` / `admin123`.

## How the ports model works

- **Infra (all native):** Postgres 15, Solr 9.10.1, Mailpit and Floci S3 run as
  native processes managed by `devbox services` (process-compose) with **fixed**
  host ports (`5432`, `8983`, `4566`, `1025`/`8025`). All definitions live in
  `process-compose.yml`.
- **Custom packages where nixpkgs lacks the exact version:** `flake.nix` builds
  Solr 9.10.1 from the Apache CDN (fetchurl) and Floci 2.0.1 from source
  (Maven/Quarkus; it publishes no standalone binary). Postgres and Mailpit come
  from nixpkgs.
- **Backend / UI:** each run picks a random free OS port (`free_port()` in
  `env.sh`). `devbox run dev` allocates both in the same shell so the backend's
  advertised UI URL and the `ng serve` port always agree (CORS origin matches).
- **Per instance:** `INSTANCE=2 devbox run backend` starts a second instance on
  a different random port using the same shared database, Solr cores and bucket.

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
`assetstore.s3.endpoint=http://localhost:<floci port>` targets Floci. The
bucket `dspace-assets` is auto-created on first write.

```bash
aws --profile floci s3 ls     # floci profile configured in ~/.aws (test/test, path-style)
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
- `devbox.json` provides jdk21, maven, nodejs_22, git, postgresql_15, mailpit,
  solr + floci (via `flake.nix`) and `AWS_PROFILE=floci`.
- The backend is launched with `mvn -pl dspace/modules/server-boot
  spring-boot:run`; devtools + all module `target/classes` dirs are injected
  through `-Dspring-boot.run.additional-classpath-elements` (comma-separated),
  keeping fresh classes in front of the stale `.m2` reactor jars.