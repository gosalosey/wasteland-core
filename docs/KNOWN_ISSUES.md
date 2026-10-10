# Known issues and limitations

| ID | Area | Description | Status |
|---|---|---|---|
| K-1 | Core / platform | Functions passed through exports arrive as FiveM function-reference *tables* (with `__call`), not Lua functions. The registry handles this. | **Verified at runtime 2026-10-10 (R1.1)** |
| K-2 | Core / platform | Runtime finding (R1.7, 0.1.0): `restart wasteland_core` makes FiveM stop dependent module resources, and they are **not** started again, so modules stayed down (`missing`). Fixed in 0.1.1: the core records which module resources were stopped by its own stop (server convar, current process only) and starts them again on boot. Resources an admin stopped earlier are left alone. Configurable: `framework.restartModulesAfterCoreRestart`. | Fixed in 0.1.1; re-run R1.7 |
| K-3 | Lifecycle | Graceful shutdown covers resource stops and txAdmin-announced restarts/shutdowns. A killed process (crash, closing the window, `taskkill`) runs no shutdown. From M2, persistence will not rely on shutdown alone. | By design (platform limitation) |
| K-4 | Config | Config changes to a running framework are validated by `config reload` but applied only on restart (except when recovering from config_error). Hot-apply for selected settings may come later. | By design for M1 |
| K-5 | Tests | The Windows branch of the static "dead file" check (`dir /s /b`) was written but has only run on Linux. If it cannot list files it skips the check instead of failing. | Open: verify on Windows |
| K-6 | Logging | Logs go to the server console (which txAdmin captures). There is no separate log file because FiveM's `SaveResourceFile` cannot append. | By design for M1 |
| K-7 | Admin | Player-issued commands show output in F8 only (no chat or UI yet). wasteland_ui/admin will add an in-game panel. | Planned M10 |
