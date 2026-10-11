-- wasteland_ui :: server/main.lua
-- Registers module "ui" so modules with screens can depend on it. The UI
-- itself runs on the client (client/main.lua + html/).

Wasteland.DefineModule({
    name = 'ui',
    version = '0.1.0',
    description = 'NUI shell, design system and screen manager',
    core = '^1.1.0',
})
