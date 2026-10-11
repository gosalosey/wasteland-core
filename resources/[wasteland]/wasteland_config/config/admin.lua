-- Wasteland Core :: admin (module "admin", resource wasteland_admin)
-- The admin panel opens with F10 or /admin (players can rebind the key).
-- Who is an admin is decided by this ACE in server.cfg, for example:
--     add_ace group.admin wasteland.admin allow
--     add_principal identifier.license:<their license> group.admin
-- Every action is checked on the server and written to the action log.
return {
    adminAce = 'wasteland.admin',
}
