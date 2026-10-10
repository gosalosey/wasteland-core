# Testing

Wasteland Core uses three kinds of verification. Reports always say which kind was used.

| Kind | What it proves | Where |
|---|---|---|
| **Static checks** | Manifests parse; every referenced file exists and compiles; no dead Lua files; no references to other gameplay frameworks; config files compile | `tests/static/` |
| **Simulated tests** | Real framework files run unmodified in a simulated FiveM server (`tests/mock/fivem.lua`) with a simulated oxmysql (`tests/lib/fake_oxmysql.lua`) and an in-memory database (`tests/lib/memorydb.lua`) | `tests/unit/`, `tests/integration/` |
| **Real-database tests** | The framework's migrations and SQL run on a real MariaDB/MySQL (the simulated server sends every statement through the `mariadb` client) | `tests/db/` |
| **Runtime (in-game) tests** | Behaviour on a real FXServer with a real client | `docs/IN_GAME_TESTS.md`, run by a human |

**A simulated pass is not a runtime pass.** The mock models resource isolation, exports with copied arguments, function references (including invalidation when the owner stops), `GetInvokingResource`, events, dependency start/stop order, threads on a virtual clock, promises and `Citizen.Await`, commands, ACEs, convars, players (connection deferrals, joining, dropping, identifiers, state bags, ped coordinates) and client→server net events. It does **not** model networking, real clients, NUI, real natives, real timing or msgpack edge cases.

The in-memory database does not parse SQL. It implements exactly the statements listed in the resources' `sql.lua` files and fails on anything else. The real-database suite proves those statements are valid SQL.

## Running the automated tests

You need Lua 5.4. No FiveM server is required.

* **Linux, macOS or WSL:** run `./tools/run_tests.sh`. Install Lua with `sudo apt install lua5.4` or `brew install lua`.
* **Windows:** run `tools\run_tests.bat`. Get Lua 5.4 from LuaBinaries (`lua54.exe`) or with `scoop install lua`, and add it to PATH.
* **Directly:** run `lua5.4 tests/run.lua [filter]` from the repository root. `filter` matches suite file names, for example `registry`.
* **Debug output:** set `WL_TEST_ECHO=1` to print everything the simulated server prints.

### Real-database suite

Without configuration it is reported as `skip`. To run it, create a database user with rights on a database whose name contains `test`. **The suite drops and recreates that database.**

```sql
CREATE USER 'wasteland_test'@'127.0.0.1' IDENTIFIED BY '...';
GRANT ALL PRIVILEGES ON wasteland_test.* TO 'wasteland_test'@'127.0.0.1';
```

Then create `tests/db.env` (gitignored), or set the same names as environment variables:

```
WL_TEST_DB_CLIENT=C:/Program Files/MariaDB 11.6/bin/mariadb.exe
WL_TEST_DB_USER=wasteland_test
WL_TEST_DB_PASSWORD=...
WL_TEST_DB_NAME=wasteland_test
```

Optional: `WL_TEST_DB_HOST` (default 127.0.0.1) and `WL_TEST_DB_PORT` (3306). Each statement starts a client process, so the suite takes a few seconds.

The exit code is 0 when everything passes and 1 when anything fails.

## Writing tests

* Unit tests load core files into an isolated environment with `loadCoreFiles({...}, stubs)`.
* Integration tests build a simulated server with `newServer({ config = { ['file.lua'] = 'source' | false } })`. They add in-memory module resources (using the real SDK) with `addModule(server, 'resName', luaSource)`, inside which `track(x)` records calls for assertions. Read state through real exports: `server:export('wasteland_core', 'GetModuleStatus', 'x')`.
* Add new suite files to `tests/suites.lua`.
