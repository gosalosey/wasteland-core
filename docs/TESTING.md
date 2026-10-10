# Testing

Wasteland Core uses three kinds of verification. Reports always say which kind was used.

| Kind | What it proves | Where |
|---|---|---|
| **Static checks** | Manifests parse; every referenced file exists and compiles; no dead Lua files; no references to other gameplay frameworks; config files compile | `tests/static/` |
| **Simulated tests** | Real framework files run unmodified in a simulated FiveM server (`tests/mock/fivem.lua`) | `tests/unit/`, `tests/integration/` |
| **Runtime (in-game) tests** | Behaviour on a real FXServer with a real client | `docs/IN_GAME_TESTS.md`, run by a human |

**A simulated pass is not a runtime pass.** The mock models resource isolation, exports with copied arguments, function references (including invalidation when the owner stops), `GetInvokingResource`, events, dependency start/stop order, threads on a virtual clock, commands, ACEs and convars. It does **not** model networking, clients, NUI, real natives, real timing or msgpack edge cases.

## Running the automated tests

You need Lua 5.4. No FiveM server is required.

* **Linux, macOS or WSL:** run `./tools/run_tests.sh`. Install Lua with `sudo apt install lua5.4` or `brew install lua`.
* **Windows:** run `tools\run_tests.bat`. Get Lua 5.4 from LuaBinaries (`lua54.exe`) or with `scoop install lua`, and add it to PATH.
* **Directly:** run `lua5.4 tests/run.lua [filter]` from the repository root. `filter` matches suite file names, for example `registry`.
* **Debug output:** set `WL_TEST_ECHO=1` to print everything the simulated server prints.

The exit code is 0 when everything passes and 1 when anything fails.

## Writing tests

* Unit tests load core files into an isolated environment with `loadCoreFiles({...}, stubs)`.
* Integration tests build a simulated server with `newServer({ config = { ['file.lua'] = 'source' | false } })`. They add in-memory module resources (using the real SDK) with `addModule(server, 'resName', luaSource)`, inside which `track(x)` records calls for assertions. Read state through real exports: `server:export('wasteland_core', 'GetModuleStatus', 'x')`.
* Add new suite files to `tests/suites.lua`.
