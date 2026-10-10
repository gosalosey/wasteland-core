# In-game (runtime) test procedures

These steps need a real FXServer. Record the date, server build (artifact number) and result for each step in the milestone report. A step only counts as **passed** if someone actually ran it.

## Milestone 1: framework foundation

**Setup**

1. Copy `resources/[wasteland]` into your server's `resources/` folder.
2. Add these lines to server.cfg, after the default resources:
   ```
   ensure wasteland_config
   ensure wasteland_core
   ensure wasteland_template
   add_ace group.admin wasteland.admin allow
   ```
3. Make sure no other framework is started for this test (no qb-core, es_extended, ox_* and so on).

| # | Step | Expected result |
|---|---|---|
| R1.1 | Start the server and watch the console | `starting core v0.1.1 (api 1.0.0)`, then `module "template" ... -> running` and `Template module is running (framework Wasteland Core v0.1.1)`. No red SCRIPT ERROR lines. |
| R1.2 | Wait 30 s | A status table ending in `summary: running=2` |
| R1.3 | In the server console: `wasteland status` | The same table; `core` and `template` are running |
| R1.4 | `wasteland config validate` | `[ OK ]` for framework.lua, modules.lua, logging.lua and template.lua; then `All configuration files are valid.` |
| R1.5 | Edit `wasteland_config/config/template.lua` to `heartbeatSeconds = -5`, then run `wasteland config validate` | An error naming the file, `heartbeatSeconds` and the range 0–3600. The template keeps running. Revert the edit. |
| R1.6 | `restart wasteland_template` | `template module stopped (resource_stop)`, then it registers and runs again |
| R1.7 | `restart wasteland_core`, then `wasteland status` | `will restart 1 module resource(s)... wasteland_template`, `shutdown complete`, then `restarting module resource "wasteland_template"`. The status shows the template `running`. |
| R1.7b | `stop wasteland_template`, wait 5 s, `restart wasteland_core`, `wasteland status` | The template is **not** restarted (you stopped it on purpose). Run `ensure wasteland_template` afterwards. |
| R1.8 | Set `level = 'verbose'` in `logging.lua`, then `restart wasteland_core` | A precise error for `logging.lua`, `level`; the framework reports config_error and no module initialises. Fix the file, run `wasteland config reload`, and confirm `OK: configuration valid; startup resumed` and that the template is running. |
| R1.9 | Join the server as a player **without** the ACE and type `wasteland status` in F8 | `You are not authorised...` in F8; the server console logs `denied admin command` |
| R1.10 | Join **with** the ACE (or `add_ace identifier.license:<yours> wasteland.admin allow`) and run `wasteland status` in F8 | The status table is printed in F8 |
| R1.11 | Use txAdmin to schedule a restart (or "Restart server") | Before exit, `shutting down (server_shutdown)` and `shutdown complete` appear in the console |
