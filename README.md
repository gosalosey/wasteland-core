# Wasteland Core

An original, modular, standalone zombie-survival framework for FiveM, built without QBCore, Qbox, ESX, ox_* or any other gameplay framework.

> **Status: Milestone 1 of 12.** The kernel works: module registry, configuration and validation, lifecycle and admin status. There is **no gameplay yet**. See `PROJECT_STATUS.md`.

## Repository layout

```
resources/[wasteland]/
  wasteland_config/     your settings (config/*.lua), never overwritten by updates
  wasteland_core/       framework kernel + Module SDK
  wasteland_template/   example module; copy it to start a new one
docs/                   architecture, conventions, API, testing, in-game tests, known issues
tests/                  automated tests + simulated FiveM runtime
tools/                  test runner scripts
server.cfg.example      lines to add to your server.cfg
PROJECT_STATUS.md       milestone checklist and how to resume work
```

## Try it (Milestone 1)

1. Copy `resources/[wasteland]` into your FXServer `resources/` folder.
2. Add the lines from `server.cfg.example` to your server.cfg.
3. Start the server and run `wasteland status` in the console.
4. Follow `docs/IN_GAME_TESTS.md` (Milestone 1) to verify it.

## Run the automated tests

`tools\run_tests.bat` on Windows, or `./tools/run_tests.sh` elsewhere. Both need Lua 5.4; see `docs/TESTING.md`.

## Documentation

* `docs/ARCHITECTURE.md`: design, resource map, lifecycle, contracts, security
* `docs/MODULE_API.md`: SDK, config schema DSL, exports, events, admin command
* `docs/CONVENTIONS.md`: naming, versioning, error handling
* `docs/TESTING.md` and `docs/IN_GAME_TESTS.md`
* `docs/KNOWN_ISSUES.md`
