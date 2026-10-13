-- Trading between players (module "trade", resource wasteland_trade).
-- Hold Left Alt on another player: "Trade". They get a popup to accept.
-- The window shows what you carry, your offer and theirs; both press
-- Accept, and any change to an offer takes both accepts back. The swap is
-- all or nothing: if something does not fit, nothing changes.
return {
    distance = 3.0,         -- metres: how close to ask
    cancelDistance = 8.0,   -- further apart than this ends the trade
    inviteSeconds = 30,     -- a request lasts this long
    maxItems = 40,          -- different stacks one side can offer
}
