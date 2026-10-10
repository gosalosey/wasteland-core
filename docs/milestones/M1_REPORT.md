# Milestone 1 report: architecture and project foundation

Date: 2026-10-10 · Core 0.1.1 · Core api 1.0.0

## Acceptance test

> The framework starts without unrelated gameplay frameworks, loads its configuration, reports module status and shuts down cleanly.

| Part | Simulated | Runtime (real FXServer) |
|---|---|---|
| Starts without other frameworks | **Pass** (static check: no references; boot with only wasteland_* resources) | Not run: R1.1 |
| Loads configuration | **Pass** (valid, invalid, missing and recovered configs) | Not run: R1.1, R1.4, R1.5, R1.8 |
| Reports module status | **Pass** (startup table, `wasteland status`, exports, events) | Not run: R1.2, R1.3, R1.10 |
| Shuts down cleanly | **Pass** (resource stop, txAdmin shutdown, failing module, idempotent) | Not run: R1.6, R1.7, R1.11 |

**Verdict:** passed in simulation; runtime acceptance pending. Nothing in this report was checked in-game. There was no FiveM server in the development environment.

## 1. Files created

```
README.md  PROJECT_STATUS.md  CHANGELOG.md  server.cfg.example  .gitignore
docs/ARCHITECTURE.md  docs/CONVENTIONS.md  docs/MODULE_API.md  docs/TESTING.md
docs/IN_GAME_TESTS.md  docs/KNOWN_ISSUES.md  docs/milestones/M1_REPORT.md
resources/[wasteland]/wasteland_config/  fxmanifest.lua, config/{framework,modules,logging,template}.lua
resources/[wasteland]/wasteland_core/    fxmanifest.lua
    shared/{util,semver,schema,logger}.lua
    server/{config_loader,registry,lifecycle,commands,exports,main}.lua
    client/main.lua   sdk/module.lua
resources/[wasteland]/wasteland_template/ fxmanifest.lua, server/main.lua
tests/run.lua  tests/suites.lua  tests/lib/harness.lua  tests/mock/fivem.lua
tests/static/manifests.lua
tests/unit/{semver,schema,logger,config_loader}.lua
tests/integration/{boot,registry,lifecycle,commands}.lua
tools/run_tests.sh  tools/run_tests.bat
```

## 2. Features implemented

* Module registry: validated definitions, semver module/api/core versions, hard and optional dependencies, dependency-ordered init, cycle detection, async modules with timeout, ownership checks, duplicate-name rejection, cascade shutdown and automatic re-init of dependents, per-module enable/disable.
* Configuration: separate config resource, sandboxed Lua config files, declarative schemas with defaults, schema self-check, precise errors (file, setting, expected value), typo warnings, `config_error` safe mode with `config reload` recovery.
* Lifecycle: boot, startup window with missing/stuck module reporting, readiness event, status table, ordered idempotent shutdown on core stop and txAdmin shutdown.
* Logging: levels, per-module overrides, colours, recent-issues ring buffer, module logs routed through the core.
* Admin: `wasteland status|module|config validate|config reload|issues|version`, ACE-gated, audit-logged, F8 output for players.
* Module SDK and a working template module.
* Configurable framework name and command name.

## 3. Automated tests: 107 passed, 0 failed

Command: `lua5.4 tests/run.lua` (Lua 5.4.6, Linux)

| Suite | Kind | Tests |
|---|---|---|
| static/manifests | static | 15 |
| unit/semver | unit | 6 |
| unit/schema | unit | 14 |
| unit/logger | unit | 5 |
| unit/config_loader | unit | 9 |
| integration/boot | simulated | 13 |
| integration/registry | simulated | 26 |
| integration/lifecycle | simulated | 11 |
| integration/commands | simulated | 8 |

All framework Lua files also pass `luac5.4 -p`.

**Defects found and fixed by the tests during this milestone:**
1. The registry checked whether `init` was callable on a schema-validated *copy*, which strips the metatable from FiveM function-reference tables, so every cross-resource module was rejected. It now checks the original value.
2. Optional sub-tables in schemas were materialised as `{}` and then failed their own required fields. Added `nullable` tables.
3. The core passed the shutdown reason `resource_stop` to modules when the *core* stopped, which was ambiguous. Renamed to `core_stopped`.

## 4. In-game tests (owner's server, txAdmin v8.1.1, CFX Default recipe, 2026-10-10)

| Step | Result |
|---|---|
| R1.1 start with only wasteland_* + CFX defaults | **Pass**: core 0.1.0 booted, config loaded, template registered from its own resource and ran; no script errors |
| R1.3 `wasteland status` | **Pass** |
| R1.7 `restart wasteland_core` | **Fail on 0.1.0**: clean shutdown and core reboot, but FiveM stopped wasteland_template and did not restart it (reported as `missing`). Fixed in 0.1.1 (K-2); **re-test pending** |
| R1.2, R1.4–R1.6, R1.7b, R1.8–R1.11 | Not yet run |

Unrelated console messages on the test server: `Couldn't find resource hardcap` (default cfg line) and `Argument count mismatch (passed 1, wanted 2)` (a server.cfg command with a missing argument). Neither comes from Wasteland.

## 5. Known issues and unresolved dependencies

See `docs/KNOWN_ISSUES.md` (K-1…K-7). Most important: K-1 and K-2 need runtime confirmation. Milestone 2 needs a decision on the database driver (oxmysql proposed, isolated behind an adapter).

## 6. Reproducing remaining failures

No automated failures remain. For runtime issues, follow the numbered steps in IN_GAME_TESTS.md and record the console output.

## 7. Regression

This is the first milestone, so there are no earlier tests to regress.
