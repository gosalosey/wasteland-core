-- Wasteland Core :: database (module "database", resource wasteland_database)
--
-- The connection itself (host, user, password, database name) is NOT set
-- here. oxmysql reads it from server.cfg, which keeps the password out of
-- files you share:
--     set mysql_connection_string "mysql://wasteland:PASSWORD@127.0.0.1/wasteland?charset=utf8mb4"
-- and the start order in server.cfg must be:
--     ensure oxmysql
--     ensure wasteland_database
return {
    -- Database driver. Only 'oxmysql' is supported.
    driver = 'oxmysql',

    -- Name of the driver resource folder.
    driverResource = 'oxmysql',

    -- Seconds to wait for a connection at startup before the module fails
    -- with an explanation. Keep this below framework.startupTimeoutSeconds.
    -- 1 - 300.
    connectTimeoutSeconds = 20,

    -- A query that gets no answer within this many milliseconds fails, and
    -- an immediate health check runs. 500 - 120000.
    queryTimeoutMs = 10000,

    -- Queries slower than this (ms) are logged as warnings. 1 - 60000.
    slowQueryWarningMs = 250,

    -- Seconds between health checks. 1 - 600.
    healthCheckSeconds = 15,
}
