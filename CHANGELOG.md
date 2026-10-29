# Changelog

## Survivors (new module: wasteland_survivors)

- Friendly NPC survivors wander the map near players (config/survivors.lua). They carry a gun or a blade, which they never drop.
- They leave players alone. Hurt one and it fights back, and the survivors within 40 m turn on you too.
- Survivors and zombies fight each other. Zombies now chase and hit survivors as well as players (wasteland_zombies: new `wasteland:zombies:server:hitPed`, server event `wasteland:zombies:hitPed`).
- Helping: kill 2 zombies within 30 m of a survivor. They thank you, and Talk (Left Alt) gives a reward, once per survivor.
- Trade (Left Alt): each survivor has 3 item-for-item swaps of their own from a configurable list, each usable a few times.
- Voice: the game's own voice lines (shouting for help when zombies are on them, thanks, hello, insults), with the words shown above their head.
- Admin: `/survivors count | clear | spawn`. Exports: GetSurvivorCount, SpawnSurvivor, IsSurvivor.
- Add `ensure wasteland_survivors` after `ensure wasteland_hunting` (the updater adds it).

## Gates tougher

- Gate doors and gate frames now have 3000 health (was 700).

## HUD: a grey silhouette instead of the character picture

- The Body style HUD shows a plain grey body silhouette (the image the owner picked), sized to fill the space beside the rings. Bleeding (pulsing red), infection (green) and low health (red flush) tint it, shaped to its outline.
- The character picture is gone, and with it /hudphoto, client/portrait.lua and the screenshot-basic resource: nothing touches the camera any more. If server.cfg has `ensure screenshot-basic`, delete that line.

## HUD character picture: only when you ask (/hudphoto)

- The HUD no longer takes the picture by itself (it kept doing it and cut the camera away mid-game). It is taken only when the player types `/hudphoto`, and the last picture keeps showing until the next one, also after changing clothes.

## HUD character picture: cropped to the character (bigger)

- The picture was cropped around everything that changed between the two shots, drifting clouds included, so the character came out small at the bottom. The crop now finds the character itself (the solid block of change) and clears specks elsewhere, so the character fills the space. Pictures taken before are dropped and taken again once (one short flash).

## HUD: noise ring, voice speaker, new ring colours

- The separate noise panel is gone: the small speaker ring at the top of the HUD now shows the noise, how far zombies can hear you (fill and colour from white "QUIET" to red "DEAFENING", the word under it). /noise still brings the old panel back if wanted.
- Voice chat: a small speaker ring in the bottom row next to pee and poop shows your voice range and glows green while you talk (only with voice chat running; "When it matters" mode shows it only while talking).
- Ring colours: health red, stamina dark blue, food brown, water deep blue (low still turns amber, critical red).

## HUD character picture: /hudphoto and clear reasons

- `/hudphoto` takes the picture of your character at once, or says on screen why it cannot (screenshot-basic not running, in a vehicle, moving, fighting, a menu open, ...). Failures of the automatic picture are shown the same way and printed in F8, instead of the HUD silently keeping the figure.
- If screenshot-basic does not answer within 3 s, the camera comes back anyway. A picture can be taken again for the same clothes.

## HUD: your own character instead of the figure

- The Body style HUD shows a picture of your actual character, real clothes and all, where the grey figure was. Bleeding (pulsing red), infection (green) and low health (red) show on the picture.
- How: when your character or clothes change and you stand still on foot, out of a fight, a copy of your character is put high in the sky above you with a light on it; a camera looks at it for a moment (a short flash on your screen) and takes two shots, one with the copy and one without. The HUD keeps only what differs (your character) and stores the picture on your PC, so it is taken again only when your clothes change. Without screenshot-basic the figure stays.
- New resource `screenshot-basic` (the official CitizenFX one, MIT, shipped already built in resources\[wasteland]\screenshot-basic). server.cfg needs `ensure screenshot-basic`; the updater offers to add it.
- New client file wasteland_survival/client/portrait.lua.

## HUD: new "Body" style (now the default)

- A body figure with rings in an arc beside it: health, stamina, food and drink, each with its percentage. Top left, two small rings: armour (outer ring the vest, gold inner ring the plates in it) and voice (your range: whisper, normal, shout; lights up green while you talk, needs pma-voice for the range). Small rings for temperature, pee and poop and the bleeding / infection tags below. The body pulses red while bleeding, has a green tint while infected and a red flush when health is low. Preview: docs/images/hud/body_style.png.
- /hud has a new Style choice: Body or Classic (the old plates and dials, still there). Size, position and "Always / When it matters / Off" work for both. Everyone starts on Body; a saved position and size are kept.
- In the Body style stamina is a ring, so the stamina bar at the bottom of the screen only shows in Classic.

## Vehicles: more wrecks, and motorbikes

- Up to 40 wrecks in the world (was 30), with 20 new spawn points: Sandy Shores junkyard, YouTool, Stab City, Grapeseed, O'Neil ranch, Paleto (sawmill, sheriff, north gas station), Harmony, Route 1 at Zancudo, and in Los Santos Mission Row, Grove Street, Little Seoul, La Mesa, El Burro Heights, Burton, Vespucci Beach, Mirror Park, Pillbox Hill and Del Perro pier. VERIFY IN-GAME: picked from the map; the spot check moves a wreck to the nearest clear spot.
- Motorbikes: about 1 in 4 new wrecks is a dirt bike or motorcycle (`bikes`, `bikeChance` in vehicles.lua). They need the same parts as a car, but two wheels: wheel fitting, tyre wear and bursts, "Check vehicle" (Front / Rear) and the HUD (two tyres) all follow. Their storage is small saddlebags (6 x 4, 25 kg).

## Quests: /quest screen and a better tracker

- `/quest` (or J) opens a quest screen: your current story step (Patient Zero) at the top, then every job you have taken in full: what it is, each objective with its progress and how to do it, the camps to hand it in at and how far they are, the reward and when you took it, and under "Done recently" when finished jobs can be taken again. "Hide tracker" / "Show tracker" turns the on-screen tracker off and on.
- The on-screen job tracker shows how long ago each job was taken, a "how to" line under the objective you are on (where to find the item, what to search, where to go), and when a job is done, the camp to hand it in at with the distance (updates as you move).
- New export `wasteland_story` `GetStoryView(source)`; the job board shows the how-to lines too.
- Retired ammo leftovers fixed: the "Thin the herd" job, event loot and zombie bodies gave 9mm; they give 12 gauge now. A test checks every config file for retired weapons and ammo.

## Vehicles: lock the doors from the inside (L)

- Sitting in any seat, press L to lock or unlock the doors; no key needed. The server checks you are really in that vehicle.
- A vehicle with a lock fitted stays locked after you get out (its key or a lockpick opens it, as before). A vehicle with no lock fitted unlocks itself once everyone is out, so you cannot lock yourself out of it; it is also never left locked after a restart.
- L can be changed in Settings > Key Bindings > FiveM ("Vehicle: lock / unlock the doors from inside").

## Standard weapons retired: the scrap weapons replace them

- Loot, supply drops, story rewards, the Survivor's Cache and traders' stock now give the closest scrap weapon instead of a standard one (see the swap table in docs/scrapweapons.md). 9mm, 5.56 and 7.62 ammo became 12 gauge, .44 and .308. The recipes and blueprints of the standard guns and melee weapons are removed.
- Kept: the knife and hatchet as tools (skinning, trees, starting knife), and molotovs, grenades and sticky bombs. The scrap axe and maul chop trees, the scrap machete and axe skin, the pipe club, axe and maul break down wood piles.
- Standard weapons players already own keep working, and traders still buy them.
- The ten scrap items are now in inventory.lua, so every system knows them from the start; `ensure wasteland_scrapweapons` moves right after `ensure wasteland_inventory`. Loot and supply drops warn instead of refusing to start when a listed item is missing. The spiked bat recipe takes a wood plank instead of a baseball bat. Improvised double-barrel marked approved.
- Config files changed: inventory.lua, crafting.lua, loot.lua, camps.lua, supplydrops.lua, story.lua, hunting.lua.

## Fix: script errors from wasteland_scrapweapons at server start

- On start, wasteland_scrapweapons registered its items while the inventory module was still loading its settings, so `RegisterItem` crashed (`attempt to index a nil value (field 'cfg')`) once per weapon. Items still got registered a moment later, but the console filled with errors.
- `wasteland_inventory` `RegisterItem` / `RegisterUsable` now answer "inventory module is not running yet" instead of crashing.
- `wasteland_scrapweapons` now registers only with modules that are running (core `IsModuleRunning`); each module's "running" event registers them as soon as it is ready. The start line is printed once everything is in.

## Improvised double-barrel: new look from the second reference picture

- Rebuilt after the second reference: two thick barrels in mottled tan and green camo paint with a coupling collar, a long receiver in chipped red paint with a ribbed side panel and two spring hammers on top, a bent-rod trigger guard, and a brown stock with a red-painted wrist and wide white bandage wraps. Gameplay unchanged.

## Improvised double-barrel: look, third pass

- The stock is now wood wound in separate overlapping rag strips (red, green, grey, tan) instead of a flat camo pattern, and runs right up to the breech, bolted on with steel side plates (the plain bar is gone). The breech is a pipe coupling round each barrel end instead of a box; the trigger guard is a bent rod. Barrels and the brass shell unchanged.

## Improvised double-barrel: new look

- Rebuilt to match the reference picture: thick barrels painted teal-green and worn through to rust, a chunky breech block with bolts and a spare brass shell wired on top, a long stock wound in strips of red, green and grey rag, rubber pad. Gameplay unchanged; now 5 x 2 in the inventory.

## Scrap weapons 10: Improvised double-barrel (awaiting in-game test)

- New weapon `scrap_double_barrel`: two pipes side by side with a welded rib and clamps, a wooden forend, a breech plate with twin nail firing pins and two bent-bolt hammers, two triggers, a sawn-down stock with an inner-tube pad. Two 12 gauge shells, the barrels swing open to reload (the sawed-off). Recipe: 10 scrap metal + 1 metal sheet + 2 wood planks + 4 nails + 2 duct tape.
- Heavy scrap maul marked approved.

## Scrap weapons 9: Heavy scrap maul (awaiting in-game test)

- New weapon `scrap_maul`: a head cut from steel I-beam, welded to a thick pipe handle with gusset plates, rebar studs on both striking faces, chain wrapped round the neck, a taped and rag-wrapped grip. Two-handed (the bat's swings), 1.7x the damage, 500 hits durability. Recipe: 10 scrap metal + 2 metal sheet + 2 duct tape + 1 rag.
- Scrap lever rifle marked approved.

## Scrap weapons 8: Scrap lever rifle (awaiting in-game test)

- New weapon `scrap_lever_rifle`: an octagonal barrel over a tube magazine, a receiver with tarnished brass side plates and a loading gate, a closed loop lever, an exposed hammer, a saddle ring, buckhorn sights and a wooden stock and forend studded with brass tacks. 7 rounds of .44, 65 damage, a shot a second. The game has no lever-action animation: it handles like the precision rifle and the lever itself does not move. Recipe: 12 scrap metal + 2 metal sheet + 3 wood planks + 6 nails + 1 duct tape.
- Scrap machete marked approved.

## Scrap weapons 7: Scrap machete (awaiting in-game test)

- New weapon `scrap_machete`: a blade cut from rusty steel plate with a ground edge, saw teeth hacked into the spine, old bolt holes, a bent-bar guard, a cord-wrapped wooden handle and a hex nut pommel. Swings like the machete, 1.25x the damage. Recipe: 1 metal sheet + 3 scrap metal + 1 wood planks + 1 rag + 1 duct tape.
- Pipe club marked approved.

## Scrap weapons 6: Pipe club (awaiting in-game test)

- New weapon `scrap_pipe_club`: a steel pipe with a cast-iron tee screwed on as a hammer head (hex caps, a bolt hammered in as a spike), bolts through a coupling, a ribbed bike grip and cord. One-handed (the crowbar's swings), 1.3x the damage, 450 hits durability. Recipe: 5 scrap metal + 1 duct tape + 1 rag.
- Scrap bolt rifle marked approved.

## Scrap weapons 5: Scrap bolt rifle (awaiting in-game test)

- New weapon `scrap_bolt_rifle`: long pipe barrel strapped to a full wooden stock, a pipe receiver with a working bolt, a tin box magazine, washer-and-bolt sights, a cracked stock patched with a steel plate. Handles like the game's precision rifle (bolt worked between shots), 5 rounds of .308. Recipe: 12 scrap metal + 1 metal sheet + 3 wood planks + 4 nails + 2 duct tape.
- Scrap pump shotgun marked approved.

## Scrap weapons 4: Scrap pump shotgun (awaiting in-game test)

- New weapon `scrap_pump_shotgun`: pipe barrel over a pipe magazine tube, a welded sheet-steel receiver with rivets and an ejection port, a pump made from wood wrapped in old inner tube on two steel rods, a plank stock with a taped wrist, tyre-rubber butt pad and spare shells strapped on. Real pump action (the game's pump shotgun), holds 4 shells of 12 gauge. Recipe: 10 scrap metal + 2 metal sheet + 2 wood planks + 4 nails + 2 duct tape.

## Target: fix the cursor taking all input (Alt release lost)

- Root cause of the target getting stuck or flashing: "keep game input while the screen has the mouse" only applies to the resource that owns the screen, and our screens live in wasteland_ui, but wasteland_target was the one asking for it. So it never applied, and letting go of Alt never reached the game. `wasteland_ui` `SetFocus(name, focus, cursor, keepInput)` now takes it (other callers unchanged).
- Like the reference behaviour: while the cursor is up the target keeps being checked, and if you lose it the cursor goes away; Scrap axe marked approved.

## Target: works the usual FiveM way

- Hold Left Alt: an eye in the middle. Look at something usable: the eye turns green and its options show beside it. Left-click: the mouse cursor comes up and the camera holds still. Click an option to use it. Let go of Alt to close; right-click puts the cursor away so you can look around again. Scroll + E is gone.

## Scrap weapons 3: Scrap-made axe (awaiting in-game test)

- New weapon `scrap_axe`: a head cut from rusty steel plate with a ground edge, bolted through a rough branch handle with cheek plates, lashed with wire and a rag, a rebar spike on the back, taped grip. Swings like the hatchet, hits 1.2x as hard. Recipe: 4 scrap metal + 1 log + 2 nails + 1 rag + 1 duct tape.
- Pipe shotgun marked approved.

## Scrap weapons 2: Pipe shotgun, new look

- Rebuilt the pipe shotgun model after the in-game look test: a long dark rusty pipe barrel held by clamp rings, a heavy coupling breech with a nail hammer, a ring trigger guard and a wooden rifle stock wrapped in grey duct tape over red cloth. Gameplay is unchanged. It is now 4 x 2 in the inventory.

## Scrap weapons 2: Pipe shotgun (awaiting in-game test)

- New weapon `scrap_pipe_shotgun`: galvanised pipe barrel on a door hinge, nail firing pin, 2x4 grip, duct-tape forend. One 12 gauge shell; the barrel swings open to reload. Handles, sounds and hits like the sawed-off. Recipe: 6 scrap metal + 1 wood planks + 4 nails + 2 duct tape.
- Spiked bat marked approved.
- Build tools: shared `common.py`, parts on more than one bone, `make_meta.py` reads DLC files and takes setting overrides (ClipSize=1).

## Target: fix the menu flashing and not being clickable

- Holding Alt made the target menu flash on and off. When the mouse cursor came up, the game lost sight of Alt being held, closed the menu and opened it again. Now, while the cursor is up, the menu itself watches for Alt being let go (or Esc), and handles E and the scroll wheel too.

## Scrap weapons 1: Spiked baseball bat (awaiting in-game test)

- New weapon `scrap_spiked_bat` in `wasteland_scrapweapons`: its own model (nails through the barrel, wire, duct-tape grip, old blood), icon, recipe (baseball bat + 10 nails + scrap metal + duct tape) and game weapon `WEAPON_WL_SPIKEDBAT`. Swings like the bat, hits 1.35x as hard. Holding, wear and repairs come from wasteland_weapons.
- `wasteland_images`: icon `scrap_spiked_bat`.
- Build tools in `tools/scrapweapons/`; renders in `docs/images/scrapweapons/`.

## Scrap weapons: foundation (no weapons yet)

- New resource `wasteland_scrapweapons` (add `ensure wasteland_scrapweapons`; the updater offers to). Its weapon list is empty for now: weapons are added one at a time, see docs/scrapweapons.md.
- New exports so a resource can bring its own weapons and recipes without touching your config files: `wasteland_weapons` `RegisterWeapon(item, def)` and `wasteland_crafting` `RegisterRecipe(name, def)`. Entries of the same name in weapons.lua / crafting.lua win. Registrations go away when the registering resource stops.
- `wasteland_inventory` `RegisterItem`: the resource that registered an item may now register it again (after a restart).

## Crafting: track recipes

- Each recipe on the crafting screen (K) has a Track button. Tracked recipes (up to 3) show in the top-right corner with every item they need and how many you have, e.g. Scrap 1 / 2. Counts update as your inventory changes and turn green once you have enough. Click Tracked again to remove one. The list is saved with the character.

## Target: click an option with the mouse

- While Left Alt is held and options are showing, the mouse cursor comes up and the camera holds still. Click an option to use it (hovering highlights it). Scroll + E still works. Let go of Alt (or press Esc) to close.

## Unreleased: zone trees and stumps sit lower

- Zone trees are now placed 0.7 m into the ground (was 0.3) and stumps 0.6 m (was 0.3), so they no longer float on slopes. Rocks are unchanged.

## Character creator: the camera never ends up inside a wall

- The creator camera stands 3 m in front of the character. At the new creator spot it looked into a wall, so the character could not be seen. Now the creator tries the character's facing and then every 45 degrees, and turns the character to the first direction with clear space for the camera.

## Character creator moved to 318.27, -584.21, 43.28

- New characters are made at 318.27, -584.21, 43.28 (a safe zone) instead of the Sandy Shores airfield hangar; they pick their starting camp afterwards as before. `players.lua` `defaultSpawn`.

## Character creator: no zombies, no damage

- Zombies could hit (bleeding, infection) players in the character creator: the login placement switched protection off when its 15-second watch ended, even with the creator open. The creator now holds protection (and full health) the whole time it is open.
- Players who are protected (making a character, choosing their starting camp) have a 60 m zombie-free bubble: no zombies spawn there, and any that are there or wander in are removed.

## 5 characters per player

- `players.lua` `maxCharacters = 5` (was 3): every account can make up to 5 characters on the character select screen.

## Story: hand-placed NPCs stay put; the others get the reachability check

- NPCs with `exact = true` in story.lua (spots placed by hand: Hollis) stand exactly at their coordinates. Every other story NPC (Tomas, Crane, Rook) and every story item gets the safety check: a spot inside a building interior, without ground, or far from the given height is moved to the nearest road edge, so players can always reach it.

## Story: NPCs stand where they are placed again

- The "easy to reach" safety net moved story NPCs and items away when anything was above them (an awning, a stall canopy, a tree), so Hollis appeared up to 75 m away from his marker. Now a spot is only moved when there is no ground there, the ground is far from the given height (a roof or a pit), or it is inside a building interior. Chosen spots are used as given.

## Story: Act II "The Company"; easy-to-reach places; tracker goes when done

- **Act II: The Company** (9 steps) starts after Act I's ending card and reacts to what you chose there: a company convoy stopped at the Yellow Jack Inn, its turned guards, the convoy manifest (a weaponised strain, LAZARUS-10, and a relay at the El Gordo lighthouse aimed at Sandy Shores), Rook the deserter at the Fort Zancudo gate (patch his leg with 3 bandages, or just take the codes), holding the lighthouse while the relay is shut down, Crane's orders, and the ending: warn every camp (supplies, $800) or take the company stash ($2500, a pump shotgun, armour).
- story.lua now holds a list of `acts` played in order; choices (flags) carry over between acts. Old saves keep their Act I progress. The journal shows every act with its ending.
- Easy to reach: every story NPC and item stands on open ground next to a road. As a safety net the game moves one whose spot is inside a building, under a roof or without ground to the nearest road edge (within 75 m); the server accepts the moved spot.
- The story tracker leaves the screen once every act is done.
- New item: Convoy document case.

## Story: "Patient Zero", Act I (new module wasteland_story)

- A quest chain with a story: 12 steps across the map, three characters (Hollis the radio operator at Sandy Shores, Tomas Reyes at the old Grapeseed ranch, Mr. Crane), notes and recordings to find, and choices that change what happens and how it ends.
  - Hollis hears a looped radio message; the crashed courier plane at the Sandy airfield; the sealed LAZARUS case and the pilot's log; the infected clinic in Paleto Bay and Dr. Ward's notes; Tomas, bitten, with her keycard (ease his fever with antibiotics, or take the card and watch him turn); holding the Humane Labs gate while the reader boots (zombies come in waves); the last LAZARUS sample and Dr. Ward's final recording; then the choice: give the vial to the camp medic (3 Lazarus serums, $500) or sell it to Crane ($3000, a carbine and ammo).
  - Two endings; Hollis remembers what you did to Tomas.
- How it plays: hold Left Alt on a story character to talk (cinematic dialogue with typed lines and numbered choices); story items and notes appear in the world only for you, with a marker; the current objective is on the map; a tracker on the right; "Journal updated" banners; `/journal` tells the story so far as diary entries.
- Solo or with your group: group members close by on the same step share kills and defending.
- New items: Sealed steel case, Dr. Ward's keycard, LAZARUS sample, Lazarus serum (use: clears infection).
- Everything is in `wasteland_config/config/story.lua` (text, places, choices, rewards); more acts can be written there. Admins: `/story reset [id]`, `/story skip [id]`.
- **server.cfg: add `ensure wasteland_story` after `ensure wasteland_quests`.** It is in modules.lua as `story = true`.
- VERIFY IN-GAME: the NPC and item positions (picked from the map), the NPC models and the dialogue screen.

## No gap when walls are stacked

- Walls, half walls, doorways, window frames and frames have a 20 cm skirt below their bottom edge. An upper-floor wall stands on the floor piece's edge, 20 cm above the top of the wall below (the floor sits beside that wall, not on it); the skirt fills that strip. On a foundation the skirt is hidden inside it. Model change only: same collision and snapping, existing bases are fixed too.

## Vehicle parts: condition on the HUD, repair or replace one part

- Engine parts, the battery and each of the four tyres have a condition (%). The vehicle HUD shows them: ENG PARTS and BATTERY chips and four tyre spots laid out like the car (front left, front right, rear left, rear right), green / yellow / red, blinking at 0%, grey when missing.
- Parts wear: by distance driven (`vehicles.lua` `wear`), engine parts also in crashes (from the engine damage), and a tyre that bursts is flat (0%). Engine parts or battery at 0%: the engine will not start ("worn out" / "dead battery"). A flat tyre stays flat.
- Fix one part (Left Alt on the vehicle):
  - with a toolkit: "Repair engine parts", "Recondition battery", "Patch this tyre" (the tyre nearest to you): +40%, never above 80% (`partRepair`);
  - with a new part: "Replace engine parts", "Replace battery", "Replace this wheel": 100% (the old part is scrap).
- Wrecks start with parts at 25-85% (`wreck.condition`). Old saved vehicles count their fitted parts as 100%. "Check vehicle" lists every part's %. A full vehicle repair makes every part 100%.

## Moonshine still: copper still on a fire, smoke while it cooks

- New still model (`wl_moonshine_still`, made in Blender): a hammered copper pot with green patina and soot on a stone fire ring with logs and embers, a copper cap and lyne arm to a copper thumper keg on a stump, then a wooden worm barrel with iron hoops, a copper coil, a spout and a mason jar catching the drip. Same collision as before. Preview: `docs/images/scrap/moonshine_still.jpg`.
- While a still is brewing (and you are within 60 m): small flames under the pot, smoke rising from the cap and the firebox, and a flickering orange firelight. They stop when the batch is done.
- VERIFY IN-GAME: the fire and smoke effects (game particle names; the first one the game has is used) and their positions on the still.

## Rain catcher: scrap-built drum and tarp

- New rain catcher model (`wl_farm_raincatcher`, made in Blender): a sun-faded blue 55-gallon drum with a tap, under an old olive tarp sagging into a funnel, tied with rope to four crooked 2x4 posts with crossbars and braces. Same collision as before (the drum). Preview: `docs/images/scrap/raincatcher.jpg`.

## No gap between storeys

- Floor / ceiling pieces (wood, stone, metal) have a solid rim the full 20 cm round their edge, so the strip between a lower wall and the wall above is closed (it showed the outside before).
- Metal sheets and wood planks on walls now reach the top edge exactly (they stopped a few cm short).
- Same model names and collision; existing bases change look only.

## The scrap barricade look is now the default

- The 45 Blender-made models (building pieces in wood, stone and metal, doors, gates, window bars, tool cupboard, storage, generator, lamps, weapon locker, bed) replace the old ones in **wasteland_buildprops**. Every base on the server shows the new look; nothing else changes (same model names, same collision).
- The separate wasteland_buildprops_scrap resource is gone. If you added `ensure wasteland_buildprops_scrap` to server.cfg, remove that line (otherwise the server only warns that it cannot find it).
- The old models are in the git history if ever wanted back.

## Scrap building look: gaps closed, doorway patch, new props

- Floors (wood and metal ceilings / foundations) run edge to edge, so there are no bright lines between pieces; a backing board under wood floors and behind wood walls means nothing shows through the plank gaps.
- Patches (rust sheets, the yellow plate) stay inside their panel and never hang over a doorway or window.
- The metal (diamond plate) floors are darker and much less orange.
- New detailed models in the scrap pack: small and large storage (plank crates with battens, iron corners, rope handles), generator (tube frame, engine with fins, round fuel tank, exhaust, wheels), hanging lamp (cord and cone shade), work light (tripod, twin floodlights), weapon locker (green steel, louvres, hasp), camp bed (frame, canvas, blanket). 45 models in all, each with the original collision (checked).

## Scrap barricade building look: all 38 pieces (optional)

- **wasteland_buildprops_scrap** now has the whole set, made in Blender: foundations, walls, doorways, window frames, half walls, ceilings, frames, stairs, ramps and hatches in all three tiers, plus wood and metal doors, the garage door, gate frame and gate door, wood and metal window bars, and the tool cupboard.
  - Wood: crooked scrap planks with gaps, posts and braces, nailed cross-boards, rusty patches.
  - Stone: cinder blocks between concrete pillars and caps, patched blocks.
  - Metal: rusty corrugated sheets (some faded blue / red) on angle iron, welded patch plates, diamond-plate floors.
  - Spray paint (X, tally marks, "no entry" circles) and blood smears on outside faces; grime and mud everywhere.
- Every model keeps the exact collision of the original (checked by re-importing all 38). About 20,700 triangles for the whole set, one 1024 texture each (about 14 MB of downloads for players, once).
- Stairs, ramps, hatches and the tool cupboard keep their shape with the new textures.
- Still **not started by default**: add `ensure wasteland_buildprops_scrap` after `ensure wasteland_buildprops`. Previews: `docs/images/scrap/`.
- VERIFY IN-GAME: look by day and night, collision, which side faces out, doors opening, snapping.

## Scrap barricade building look (test: wood wall)

- New optional resource **wasteland_buildprops_scrap**: a new "scrap barricade" look made in Blender (Sollumz). First piece: the wood wall, with crooked weathered planks with gaps, a nailed cross-board, a rusty corrugated patch, a red spray-painted X, grime and mud. 964 triangles, one 1024 texture, the same size and collision as the old wall.
- **Not started by default.** To try it, add `ensure wasteland_buildprops_scrap` after `ensure wasteland_buildprops` in server.cfg; remove it to go back. Every existing wood wall changes look; nothing else changes.
- Build scripts in `tools/buildprops/scrap` (textures from ambientCG, CC0).
- VERIFY IN-GAME before more pieces are made: the look by day and night, collision, which side faces out, and snapping next to the old pieces.

## Survivor's Cache: a very rare find from chopping and mining

- Every tree chopped and every rock mined has a 1 in 1000 chance (`rareChance = 0.001` in treeZones / rockZones) of a **Survivor's Cache** (`survivor_cache`), on top of the wood or stone. The player is told; a full pocket leaves it at the tree / rock (that opens).
- Use it from the inventory: a box opens with a carbine rifle, 150 5.56 rounds, an armor vest, a hiking backpack, 3 antibiotics, 15 bandages, 4 MREs and 4 water bottles. The contents are in `loot.lua` `survivorCache.contents`.
- Other resources can react to `wasteland:loot:rareFound` (source, item, kind).

## Chop / mine minigame: a circle, and you can fail

- The minigame is now a circle in the middle of the screen (the screen around it darkens, over the swinging player): a needle sweeps round a ring, press **E** (or Space) when it is in the green arc. Each hit cracks the log end / the stone, with chips flying and a thunk; the last hit breaks it ("Timber!").
- **One miss fails**: "The axe slips" / "The pickaxe glances off", nothing is given, and the player has to start chopping / mining again (the tree or rock stays).
- Kept easy: the green arc is a fifth of the circle, the needle takes over two seconds a turn, a little faster after each hit. Trees need 3 hits, rocks 4.
- X / Esc stops. Taking damage still stops it.
- loot.lua `minigame = { enabled, hits, zone (part of the circle), speed (turns a second), speedStep }`.
- Without wasteland_ui the old bar is used (a miss fails there too).

## No building in safe zones; tool cupboards can be broken

- Nothing can be built inside a safe zone: camps and tree / rock zones ("You cannot build inside a safe zone"; nothing is paid). Admin build mode still can. `basebuilding.lua` `placement.noBuildInSafeZones` (default true).
- Other players can break a tool cupboard with melee weapons (bat, crowbar, hatchet...): 10 damage a hit, so 50 hits for a 500-health cupboard (`raid.melee.cupboardDamage`). Explosives already damaged cupboards. The owner and players with access cannot hurt their own.
- The owner is told "Your tool cupboard is under attack!" (at most every 3 minutes; offline: when they next join), and when it is destroyed. A destroyed cupboard loses its supplies and the land is no longer claimed; the pieces stay.

## Tree and rock zones are safe from zombies

- Tree zones and rock zones count as safe zones, like camps: no zombies spawn inside, hordes avoid them, zombies that wander in are removed, and zombies stop chasing players inside (and cannot hurt them there).
- Per zone kind in loot.lua: `safe = true` (set `safe = false` for dangerous gathering).
- New exports `IsInGatherZone(coords)` on wasteland_loot (server and client); wasteland_zombies checks it next to camps and bases.

## Chopping and mining minigame

- Chopping a tree or mining a rock is now a small timing game: a marker slides along a bar at the bottom of the screen; press **E** while it is in the green zone. 4 good hits fell a tree, 5 break a rock. A miss flashes red and locks E for 0.4 s; nothing is lost. X, moving or taking damage still stops it.
- Settings per zone kind in loot.lua: `minigame = { enabled, hits, zone (green width), speed }`. `enabled = false` goes back to the plain timer.
- The server only checks it was not impossibly fast (0.35 s per hit).

## Faster chopping and mining, more from each

- Chopping a tree: 6 s (was 10). Each tree gives two picks: mostly logs (2-3 each), sometimes firewood, so usually 4-6 logs (was 2-3).
- Mining a rock: 7 s (was 12). Two picks: stone (5-7 each) and now **scrap metal** (1-3), so usually 10-14 stone, or stone plus scrap.

## Starter tools: cheap hatchet and pickaxe

- **Hatchet**: 2 scrap metal + 1 rag, 5 s, no blueprint needed any more (was 3 scrap metal + 2 duct tape and the hatchet blueprint).
- **Pickaxe**: 3 scrap metal + 1 rag, 5 s, no blueprint (was 4 scrap metal, 2 wood planks, 1 duct tape).
- The hatchet blueprint no longer drops as loot (it would teach nothing). Blueprints already in inventories stay, but are useless.

## Tree / rock zones: no trees or rocks on roads or buildings

- Before a tree or rock spawns, the client checks its spot once (when the player is within 120 m, so the ground and buildings are loaded): on or right next to a road, inside an interior, against a wall, against a prop or base piece, or on a roof (a flat spot with a drop of more than 3 m next to it). Such spots are left empty. Hillsides are fine (walls face sideways, slopes face up).
- Only the client decides; nothing changes on the server, and a skipped spot never blocks anything.
- `/zonecheck` shows how many spots near you spawned and how many were skipped (and why).
- A zone with many roads or buildings now has fewer trees / rocks; raise its `trees` in loot.lua (or `/treezone add ... <trees>`) if it feels thin.

## Rock zones: mine big rocks with a pickaxe for stone

- New tool **Pickaxe** (`pickaxe`): craft it (4 scrap metal, 2 wood planks, 1 duct tape; no blueprint) or buy it at the camp trader ($60).
- **Rock zones** (`loot.lua` `rockZones`), the same as tree zones: the server places big rocks (one per 2 m of radius, at least 9 m apart). 4 zones ship: Davis Quartz quarry (100 m), Grand Senora desert rocks (80 m), Mount Chiliad summit (70 m) and Mount Gordo cliffs (70 m).
- An orange arrow and ring mark minable rocks within 35 m; zones are on the map ("Mining: ...").
- Target "Mine rock" with a pickaxe: the player turns to the rock and swings (12 s). X, moving, or taking any damage stops it. Gives 5-9 stone (the `rock` table). A mined rock is gone for everyone and comes back after 60 minutes.
- Admins: `/rockzone add <radius 50-100> [rocks] [name]`, `/rockzone remove`, `/rockzone list`.
- Tree zones and rock zones now share one system; nothing changes for tree zones.
- VERIFY IN-GAME: the 4 rock zone spots, the rock models (`prop_rock_4_big`, `prop_rock_4_big2`, `prop_rock_4_c`, `prop_rock_1_a`), and the pickaxe in the hand.

## Tree zones: planted trees to chop

- **Tree zones** (`loot.lua` `treeZones`): the server plants choppable trees in each zone (one per 2 m of radius, or `trees = n`), at least 6 m apart, the same spots every restart. 7 zones ship: your 4 spots plus Paleto Forest, Raton Canyon woods and the Mount Chiliad trail (radius 70-100 m, 35-50 trees each).
- Easy to spot: a green arrow over each choppable tree and a ring at its foot (within 35 m), and every zone is on the map ("Lumber: ...").
- Target "Chop tree" with a hatchet or battle axe: the player turns to the tree and swings a hatchet (10 s). **X, moving, or taking any damage (health or armour) stops it**; nothing is given.
- One player per tree at a time. A chopped tree becomes a stump for everyone and grows back after **60 minutes** (`respawnMinutes`). Wood goes straight into the inventory (the `tree` loot table: logs, sometimes firewood).
- Admins place zones in game: `/treezone add <radius 50-100> [trees] [name]` at your position, `/treezone remove` (nearest placed zone), `/treezone list`. Placed zones are kept across restarts.
- Chopped state is kept in memory: a server restart grows every tree back.
- VERIFY IN-GAME: the extra 3 zone spots, that trees sit on the ground (not on roads or roofs), and the hatchet in the hand (position/rotation may need a tweak).

## Getting wood: chop trees, break down wooden junk, saw logs

- **Chop trees** with a hatchet or battle axe (look at a tree: "Chop tree", 8 s): 2-3 logs (sometimes firewood). Each tree can be chopped again after 30 minutes.
- **Log piles** on the map: take 2-4 logs (no tool).
- **Break down wooden junk** (pallets, wood piles, cable spools, wooden fences, loose planks) with a hammer, crowbar, hatchet or battle axe: 3-6 planks, 5 s, again after 30 minutes.
- New item **Log** (`wood_log`). Crafting: saw 1 log into 4 wood planks, or 5 logs into 20.
- Wood goes straight into the inventory (what does not fit stays there and opens).
- Removing your own base pieces gives back 75% of the cost (was 50%; `basebuilding.lua` `refund`).
- Camp trader: wood planks $8 (was $12), stock 120 (was 40), restocks 30 at a time (was 10). Also sells logs ($25) and buys them ($10).
- loot.lua containers can now have `tools` (one of these items is needed), `action` / `verb` (the option and progress text), `direct` (straight into the inventory) and the animations `chop` and `hammer`.
- VERIFY IN-GAME: which tree, pallet and fence models are on your map. A model that does not exist is simply never matched; ones that are missing can be added in the loot admin panel.

## Base building: slivers close themselves when snapping

- When a piece snaps, short rays check each side and the bottom against the real neighbouring pieces. A gap of up to 15 cm (a sliver) is closed by moving the piece onto its neighbour. A piece with a gap on both sides (between two pieces) is left alone on that axis.
- Optional `placement.autoFillGap` in basebuilding.lua (metres, default 0.15; 0 turns it off). Ctrl+arrows still fine-tune after that.

## Base building: move pieces with the arrow keys

- Reverted the ceiling alignment change from "Ceilings line up with the foundations": it made the gaps bigger.
- While placing, the arrow keys move the piece left / right / away / toward you (as the camera looks). Hold Ctrl for fine moves: a tap moves 1 cm, holding creeps slowly. Works on top of snapping, so a snapped piece can be pushed into the gap.
- Turning freely is now Shift + Left/Right; slow raise/lower is Shift + Up/Down (Shift + wheel still changes height).

## Ceilings line up with the foundations

- Ceilings snapped onto a wall were placed from the middle of the wall instead of the foundation edge it stands on, so they were shifted by half a wall's thickness. Ceilings snapped from opposite walls left gaps between each other and at the walls. They now line up with the foundation grid. Ceilings already built keep their place: remove and place them again to close the gaps.

## New login spawn system

- All placing of the player (login, "last known position / camp" choice, /stuck, rescues) now goes through one routine in `wasteland_players` (export `PlaceAt`). Before, three scripts moved the ped at the same time.
- The screen stays dark and the player held until, in order: the look is applied (a model change replaces the ped; the old code kept moving the deleted one), the world and collision load, the building loads, and the floor under the saved spot is found.
- Base floors are found with a ray that sees objects (the old ground check could not see them, so players ended up inside the floor).
- With the login spawn choice on, the player is no longer first placed at the saved spot and then moved again: the client waits for the choice (players export `HoldPlacement`; after 2 minutes without a choice, the saved spot is used).
- Fixed: dying within a minute of logging in pulled you back to your login spot after the respawn.
- After placing, the first 15 seconds are watched: falling through the world tries once more from the highest ground there, then a safe camp.

## Armor plate picture

- Armor plates use the `iron` picture (the drawn `armor_insert` picture is removed).

## Armor vests with plate slots

- The worn armor is now the **Armor vest** (item `armor_plate`, same item, renamed). It has 3 slots for **Armor plates** (new item `armor_insert`), shown in the inventory under the worn items.
- Damage goes to the plates first (in order), then the vest, then the player. A plate loses 0.5 durability per point (`survival.lua` `armor.plateWearPerDamage`): about 200 damage each.
- A used-up plate breaks and is gone (cannot be repaired). The vest can still be repaired with an armor repair kit.
- HUD: a gold Plates bar above the Armor bar (full = 3 new plates).
- Plates: crafted with the armor blueprint (4 scrap metal, 1 duct tape), sold by the trader that sells vests, found where vests are found.
- Inventory: containers can be limited to some items (`container.accepts`); such a container may be worn as armor and may go in a bag.

## Fix: logging in on a base floor put you inside it

- Players who logged out standing on a base floor or foundation are held until it appears (up to 12 s), then put on it; before, they were put on the ground under it and ended up stuck in the floor.

## Zombie aggro and combat feel

- Anyone within 10 m is noticed whatever they do (`detection.proximity`). Hearing and sight are shorter: walking 15 m, sprinting 25 m, sight 45 m (25 at night). Engines carry 45 m; horns 80 m (new noise).
- Zombies give up when their target is more than 60 m away (`ai.memory.loseDistance`).
- Walkers shamble about but run at you once they have you (`chaseSpeed` 2.2).
- Zombie attack animations (4, picked at random; `attack.anims`).
- A hit can knock the player down (15%; brute 45%).
- Zombies hit players in vehicles through the door: the engine takes damage, and 20% of hits (brute 40%) drag the player out.

## Wandering zombie hordes; more zombies around

- Wandering hordes (`zombies.lua` `hordes`): up to 2 groups of 12-20 zombies (18-28 at night) roam the map, drifting through where players are. Far away a horde is only a moving point; its zombies appear when a player is within 170 m and walk on together.
- Players within 120 m get a warning with the distance and direction (once per horde every 3 minutes).
- Admins: `/zombies horde` starts one heading for you.
- More zombies everywhere: 12 per player by day (was 8), 18 at night; world cap 90 (was 60). Hordes come on top.

## Zombies use GTA's own models again

- The add-on zombie model packs are removed (from the repository and its history): every zombie kind uses the GTA models in `zombies.lua`. `wasteland_zombiemodels` stays as the place for your own models (see its README).
- `/zcheck [model ...]` checks any model names (default `u_m_y_zombie_01`).

## GTA interiors: bob74_ipl

- The recipe installs bob74_ipl 2.7.1 (MIT) into `resources/[standalone]` and `server.cfg` ensures it: GTA's hidden interiors (story houses, online apartments, bunkers, offices) are loaded. If you add a Pillbox interior map (such as `hospital_map`), set `PillboxHospital.Enable(false)` in `bob74_ipl/client.lua`.

## Undead zombie pack removed (crashed the game); Walking Dead zombies in use

- `ywr_zombies` crashed players' games (build 3570) as soon as one appeared: removed from `stream` and `peds.meta`.
- Walkers and runners (and the special infected) use the 6 Walking Dead zombies (`wlz_twd_*`).

## Custom zombie models taken out of spawns (game crashes)

- `zombies.lua` is back to GTA models for every zombie type while the crash is tracked down. The model files stay streamed; `/zmodel` still spawns one to test.

## Updater: private repository, settings you never edited, zombie models

- `tools/update.ps1` works with a private repository: it asks once for a GitHub token and saves it in `github_token.txt` (not in git).
- Settings files you never edited are now updated (before, every settings file that differed from the new version was kept, so new settings never arrived). Edited ones are still kept, with `<name>.lua.new` next to them.
- `peds.meta`: the new version's zombie models are added to yours.

## Zombie model files in the repo

- `wasteland_zombiemodels/stream`: The Undead pack (`ywr_zombies`, 23 looks) and 6 Walking Dead zombies (`wlz_twd_*`), so servers installed from git get them.
- `/zcheck` (F8): shows whether this game has the custom zombie models.

## Fix: every zombie look showed as the same zombie

- The look of a multi-look ped (`ywr_zombies:5`) is now applied by every player's game (it was set on the server, where it did not stick).

## Custom zombie models for every zombie type

- Model entries can pick one look of a multi-look ped: `'ywr_zombies:5:2'` (look 5, 2 textures).
- Walkers, runners and each special infected have their own models in `zombies.lua` (The Undead pack + Walking Dead peds; files stay on the server, not in git).
- `peds.meta` registers `ywr_zombies` and `wlz_twd_01`-`05`, `wlz_twd_woman`.
- Admin command `/zmodel <model[:look]>` spawns a zombie with that look in front of you.

## Special infected can have their own models

- `zombies.lua` `ai.specials.<name>.models = { ... }`: that special spawns with one of these models (missing ones fall back to the kind/general list).

## Fix: HUD missing after choosing a character (owner)
* Survival now double-checks: once a character is in the world, the client waits for its stats (which bring the HUD) and, if none arrive within 4 seconds, asks the server every 3 seconds for up to a minute. The server loads the character into survival if it was missed (and logs a warning naming the player, to find the cause) or just sends the stats again.

## Explosives for raiding: molotovs, grenades, sticky bombs (owner)
* New thrown weapons. Hold one like any weapon (hotbar or Use) and attack to throw; every throw uses one, and the next stack is picked up automatically. Sticky bombs stick where they land and go off when you press G (also after the last one is thrown).
* Base damage (basebuilding.lua raid.explosionDamage, unchanged): molotov burns wood (100); grenade hurts wood and stone (30); sticky bomb breaks wood (250), stone (200) and metal (200).
* Crafting: molotov (1 whiskey + 1 rag, no blueprint); grenade (4 gunpowder, 2 scrap metal, 1 duct tape) and sticky bomb (10 gunpowder, 2 gun parts, 2 duct tape, 2 scrap metal) need the new Blueprint: explosives.
* Loot: molotovs in crates, bandit stashes, survivor caches and supply drops; grenades in heli crashes, military loot, supply drops and bandit stashes; sticky bombs and the explosives blueprint in heli crashes and military loot (sticky bombs also in supply drops).
* Raid fixes: one blast is counted once per piece (before, every nearby player reported it and it did damage once per player), and only blasts from explosives a player really threw nearby count, so a cheated report does nothing (raid.requireThrow, thrown, throwRange, throwSeconds, stickySeconds).

## Fix: sometimes no HUD and no control after a server restart (owner)
* Right after joining, a screen's script could fail to load once. The page dropped the screen but the game still thought it was open: the HUD never appeared (updates went to a screen that did not exist), and a focused screen kept the mouse and keyboard. Screen scripts are now tried up to 5 times; if one still fails, the page tells the game, which forgets the screen and gives focus back, and its owner opens it again (the HUD on its next update, the character screen by asking for the list again).
* The character list counted as received even when the UI was not running yet, so the character screen could never appear (frozen, nothing on screen). It now keeps asking until a screen shows it.

## Fix: wide trunks spilled past their panel (owner)
* The looting column was capped at 460 px, so a wide grid (an 18-wide truck trunk) ran past the panel background. The column now grows with its grid; cells shrink a little more when looting so it still fits the screen.

## Inventory layout (owner)
* The open backpack now sits under Pockets instead of beside them. The ground drop zone and the Health panel moved to the left column, under the hotbar. The right side is left for whatever is being looted (stashes, trunks, crates). Cell size is worked out for the new stacked layout.

## Double carry weight (owner)
* Pockets now hold 200 kg (was 100), the small backpack 400 kg (was 200), the hiking backpack 750 kg (was 375). Backpacks already in the world get the new limit when loaded. Storage (stashes, trunks, base boxes) is unchanged.

## Bigger stacks (owner)
* Every stackable item now stacks to 250 (was 5 to 200 depending on the item; the default for items without a size is now 250 too), so pockets and storage do not fill with many small stacks. Items that never stack (weapons, tools with durability, clothing, backpacks, placeables) are unchanged; cash still stacks to 1,000,000. Weight still counts per unit.

## Moonshine: 2 jars fill the Zombie Blind meter; drunk ends with it (owner)
* A jar now adds 50 to the meter, so any 2 jars fill it. While zombies cannot smell you, being drunk does not wear off; the moment the meter drops below the line (about 6 minutes) you are sober again. Without a full meter, drunk wears off on its own and is gone when the meter empties.

## Moonshine: brew several runs at once (owner)
* The still screen has a - / + picker per flavour: brew 1 to 10 runs at once. Each run takes a full set of ingredients and gives 2 jars; each extra run adds half a run's time (1 run 2 min, 2 runs 3 min, 10 runs 11 min). The ingredient list and time update as you pick; + stops at what you can afford. Settings: moonshine.lua maxBatch, batchSecondsFactor.

## Sugar easier to find (owner)
* Sugar now also turns up in trash, crates, survivor caches and supply drops (as well as fridges), and the General trader at every camp sells it ($8, 20 in stock).

## Moonshine still: rounder, more realistic model (owner)
* The still is rebuilt from smooth round shapes instead of boxes: a bellied copper pot with a rolled flange, rivets and an onion-head cap; a curved copper lyne arm; a bulging wooden thump keg and condenser barrel with iron hoops; a real coiled copper worm; a mason jar with a lid. Smooth shading on the round parts. The copper is darker and weathered (also on electric fence wires). The generator now supports per-corner normals (round parts) alongside the flat boxes.

## Moonshine (owner)
* New module wasteland_moonshine. A moonshine still (our own model: a brick firebox under a copper pot still with a cap and lyne arm, a thump keg and a condenser barrel with copper coils, and a jar under the spout) is crafted (6 metal sheets, 10 scrap metal, 4 wood planks) and placed anywhere. Saved (wl_moonshine_stills); the brewing time left survives a restart.
* Seven flavours from farmed crops: corn, strawberry, cucumber, blueberry, cranberry, potato, watermelon. Each takes 2 sugar, 1 water bottle, 1 firewood plus its crop; a 2-minute run gives 2 jars. New items: sugar (food loot, General trader), moonshine still, 7 moonshine jars.
* Drinking a jar heals 3, takes 3 off the infection, gives 4 thirst, and adds to being drunk (drunk walk, blur, camera sway; wears off) and to the Zombie Blind meter. With the meter full zombies ignore you (state bag wlMasked, checked wherever zombies pick a target, bite or spit) until it drains below 40%. The meter on screen shows SAFE (green) or NOT SAFE (red). Export IsMasked(source).
* Settings: moonshine.lua (brewSeconds, jarsPerRun, base ingredients, flavours, drink effects, how fast drunk and the meter wear off, unmaskBelow).

## Fix: plants left behind after harvesting / picking up a plot (owner)
* Redrawing a plot's plants waits for models to load; a second update meanwhile drew a second set that was never tracked (ghost plants). Each redraw is now numbered: an older one that finds a newer one started (or the plot gone) places nothing.

## Fix: repaired vehicles still looked damaged (owner)
* A repair back to full body health now also fixes the looks (SetVehicleFixed: glass, lights, doors, bumpers) as well as the dents. A partial repair leaves the damage showing.

## Rain catcher (owner)
* New craftable item (8 wood planks, 4 scrap metal, 3 rags), placed outdoors only (the server refuses a spot under a roof): a metal drum under a tarp funnel on four posts. It fills only while it rains: 0.35 L a minute, up to 10 L. Left Alt > Collect water turns it into water bottles (0.5 L each, so a full catcher gives 20); Check water; Pick up (owner, group, admins). Saved (wl_farm_catchers). Settings: farming.lua rainCatcher (capacityLitres, litresPerMinute, litresPerBottle, maxPerPlayer).

## Farming (owner)
* New module wasteland_farming. Farm plots in three sizes (small 1 spot, medium 4, large 9) are crafted (wood planks, scrap metal) and placed anywhere, inside or outside, with a see-through preview. Our own models: wooden planter boxes of soil, and plants that grow visibly (sprout, young, grown, ripe with fruit in the crop's colour).
* 16 crops, each with its own seed, growing time, yield and food: lettuce, strawberries, carrots, cucumbers, onions, tomatoes, bell peppers, bananas, blueberries, cranberries, beetroot, corn, potatoes, cabbage, watermelon, pumpkin. New food items with their own hunger/thirst values (survival.lua). Seeds in loot (food, survivor caches) and at the General trader; harvests sometimes give seeds back.
* Plants grow only while the plot has water: water bottles add water (more for small plots); a plot outdoors (no roof built over it) is watered by rain. Left Alt on a plot opens it: each spot's crop, progress, time left until harvest, the water left, and Plant / Water / Harvest / Pull up / Pick up plot.
* Saved in wl_farm_plots. Settings: config/farming.lua. Base building gained an IsRoofed(coords) export.

## Fix: head at the pillow end in bed (owner)
* bed.lie.turn is now 270 (was 90): you lie with your head on the pillow.

## Admin Generator (owner)
* New Power piece for admins only (the same people as the F10 admin panel): free, needs no fuel (unlimited), silent, powers 60 m, very tough (100000 health). Hidden from the build menu for everyone else, and the server refuses it for them. Piece fields: adminOnly, generator.unlimited.

## Fix: lying in bed (owner)
* The sleeping animation had its own offset (you sank into the mattress, across the bed). Now a flat lying-on-your-back animation, placed on the mattress top, held still while resting, head at the pillow end. bed.lie (x, y, up, turn) in basebuilding.lua tunes it.

## Beds (owner)
* New Furniture section with a Bed (8 wood planks, 4 rags): two pallets, a stained mattress, a pillow and a blanket. Left Alt > Lie down and rest: your character lies on it; every 10 seconds you get 2 health back and the zombie infection drops by 1.5. Moving, X, or being hurt gets you up. Only those with access to the base can use it, one person per bed. Settings: bed.tickSeconds, health, infection in basebuilding.lua.

## Generator: show its power range (owner)
* Left Alt on a generator > Show / hide power range: a ring on the ground at its power radius (green while running, grey while off) and a label. Lights and electric fences inside it get power.

## Fix: rain stayed off after leaving the base (owner)
* Clearing the indoor overcast did not bring the rain back. wasteland_world now re-applies the server's weather when you step out (exports ReapplyWeather, GetWeather), and the roof check follows the server's weather while you are inside (rain starting or stopping).

## Fix: the roof check for rain (owner)
* The upward ray did not see the ceiling (its result was read before it finished). Shelter is now worked out from the pieces themselves: standing inside a roof piece's footprint, below it.

## Fix: rain inside bases (owner)
* Hiding the rain drops was not enough (ripples and wet floors stayed). Under your own roof while it rains, your game now shows an overcast sky instead (only for you, only while you are inside), so no drops, ripples or wet floor; outside the server's weather comes straight back. F8 logs when you go under a roof or back out.

## No rain inside your base (owner)
* Under a roof you built (a ceiling, a ladder hatch, the floor above, stairs) rain stops for you, you dry off, and survival counts it as shelter (no rain chill, at least 15 C) like vehicles and buildings. Outside it rains as before. Export IsSheltered().

## Electric fence (owner)
* New defense: Electric Fence (4 metal sheet, 8 scrap metal): 4 m sections of steel posts and rails with six copper wires on ceramic insulators and a junction box. Sections chain like the external wall.
* Live only while a running generator is in range (its powerRadius). Touching it then shocks: 15 damage, sparks, a short stagger for players; zombies are thrown back. Without power it is just a fence.

## Power: generator and lights (owner)
* New Power section in the build menu. Generator (6 metal sheet, 10 scrap metal): Left Alt > Add fuel takes fuel from your fullest jerry can (20 L tank), Turn on / off, Check fuel. It burns 2 L an hour (a full tank lasts 10 hours) and stops when empty. It is loud: while it runs, zombies within 30 m come to look.
* Work Light (a floodlight on a tripod) and Hanging Lamp (for ceilings) light up for real while a running generator is within 40 m.
* Fuel is saved (migration 6 adds a fuel column). IsPowered(coords) export, ready for electric fences.

## High external wall with barbed wire (owner)
* New defense: High External Wall (8 metal sheet, 6 scrap metal; 2500 health): 4 m sections of overlapping rusty corrugated sheets on steel posts, 3.6 m tall, with three strands of barbed wire on leaning arms on top. Sections chain into a perimeter and stand on the ground.
* The barbed wire hurts anyone who touches it (12 a second, 30% chance a player starts bleeding): only its strip along the top, so standing next to or leaning on the wall is safe; climbing over it is not. Zombies too. The server checks a player is really up at the wire. Settings: wireDamage, wireBleed, wireFrom, wireTo, wireReach in basebuilding.lua.

## Foundations reach into the ground (owner)
* Foundations (wood, stone, metal) now extend 4 m below their base: sides, corner posts and collision. On slopes, or when snapped out from higher ground, there is no gap under them; on flat ground the extra part is buried. Snapping only uses the top and sides, so it is unchanged.

## /adminbuild (owner)
* Admins (wasteland.admin) type /adminbuild to build, upgrade and repair for free: no materials needed, the build menu opens without a Building plan. No refunds while it is on (no farming materials). Claim rules stay. /adminbuild again turns it off; it also ends when the admin leaves.

## Move the tool cupboard; doors swing through people (owner)
* Left Alt on your tool cupboard > Move (owner only). It claims the land, so every piece it covers must stay within its reach, and it cannot go onto someone else's land or too close to another cupboard.
* Wooden and metal doors swing through players and vehicles like gates (passThrough), instead of pushing you.

## Items weigh half as much (owner)
* Every item weight in inventory.lua is halved (for example a water bottle 0.6 -> 0.3 kg, scrap metal 1 -> 0.5 kg). Pocket and bag limits are unchanged, so players carry about twice as much.

## Fix: stone stairs (owner)
* Stone steps were solid blocks down to the ground (a huge mass, the upper flight a block in mid air, flickering where the blocks met). Steps are now treads on risers that meet exactly (no overlap, every material), with a sloped slab under each flight (thick concrete for stone).

## Fix: flickering where pieces meet (owner)
* Z-fighting: snapped pieces were pulled 0.15 m into each other (needed by the sinor models, not ours), so floors, walls and ceilings shared surfaces. snapOverlap is now 0, and every piece is drawn a tiny fixed amount off its spot (under 1 cm, from its id), so already built bases stop flickering too. Inside the models: metal floor seams, stone trim and gate bands no longer sit exactly on other faces.

## Fix: floating over ramps (owner)
* Ramp collision was the last triangle mesh (that kind misbehaved before: bullets went through walls); it is now one tilted solid box like the stairs, with the same size for snapping.

## Upper floors, stairs fit, moving placed pieces (owner)
* Walls, doorways, window frames, half walls and frames snap along ceiling edges too, so upper floors build like the ground floor.
* Stairs fit inside the walls (walls take 0.2 m of each square's edge; the stairs clipped into them), with a top step onto the next floor.
* Move: Left Alt on a placed piece (not the cupboard) > Move: it goes see-through and follows your aim (same snapping and keys), E puts it down. It keeps its id, so storage keeps what is in it; building rules apply at the new spot.

## Fix: stairs collision, ceilings snapping on walls (owner)
* Stairs had no collision: a paper-thin helper box (thinner than the physics margin) made the game drop it. The flights are now tilted solid boxes (as GTA's own props), the landing and rail boxes.
* Ceilings on walls: the snap spot was only on one side of a wall (the side assumed to be the room); walls turned the other way put it outside. There is now a spot on each side; the closer one wins.

## More floors: stairs and ladder hatches (owner)
* Stairs: U-shaped stairs that fill one 4 m square and go one floor up (3.2 m), with a landing, steps, stringers and handrails; walkable slopes under the steps. They stand on a foundation or on a ceiling (snap), so floors stack. Leave the square above them open; the top comes out at the front edge onto the next floor.
* Ladder hatch: a ceiling with an opening in one corner and a ladder down to the floor below; it snaps like a ceiling. E at the foot of the ladder climbs up, E at the opening climbs down.
* Both in wood, upgrading to stone and metal like the other pieces (basebuilding.lua stairs, hatch and their tiers; `ladder = true` marks a hatch).

## Ceilings snap again (owner)
* A ceiling's snap point is its middle, about 2 m from where you aim (a wall top or the floor), so it never came within the 2 m snap distance. Ceilings now snap when you aim anywhere under the spot they would cover (measured flat; the nearest storey wins).

## Storage boxes place again (owner)
* The large storage container used v_res_tre_storagebox, an interior prop the game will not spawn ("model ... is not in the game"). All three storage pieces now use our own models: wl_bp_stash_small (a wooden crate), wl_bp_stash_large (a corrugated metal box with a lid and padlock) and wl_bp_weaponlocker (a tall steel cabinet), with collision.

## Base building switched to our own props (owner)
* Approved in game (solid, bullets hit them, weathered look): basebuilding.lua uses wasteland_buildprops again; existing bases switch on the next restart.

## Free building props of our own: base building no longer needs a paid pack (owner)
* New resource wasteland_buildprops: 32 original models made for Wasteland: foundation, wall, half wall, doorway, window frame, ceiling, garage frame and ramp in wood, stone and metal; wooden and metal doors, a garage door, a gate frame and gate, wooden and metal window bars, and the tool cupboard. Each has its own collision (with wood, stone or metal surface sounds and bullet effects) and uses four textures painted by code (weathered planks, rusty corrugated metal, stone blocks, dark metal). Grid 4 m, walls 3 m tall; doors pivot on their hinges.
* basebuilding.lua now uses them (propsResource = 'wasteland_buildprops'); the paid sinor-buildingProps-v2 pack still works if you set it back. server.cfg ensures wasteland_buildprops before wasteland_basebuilding.
* tools/buildprops rebuilds the models from a script (no Blender, no GTA V needed): gen_buildprops.py writes them, a small converter on CodeWalker.Core (MIT) turns them into GTA files.

## Our building props: bullets hit thin pieces, realistic textures (owner)
* Collision is now solid boxes per part (as GTA's own thin props), with a small margin: bullets stop on walls, doorways and doors, not only on foundations.
* New textures: weathered grey planks with knots, nail rust and mould; dark cracked beams; galvanised corrugated metal with rust patches and streaks; dirty concrete blocks with water stains and moss; chipped painted steel. Blood is dark and faded, spray paint faded with overspray; no more cartoon colours. Every texture now has a normal map (real bumps in the game's light).

## Our building props: collision fixed (owner)
* The props had no collision because their archetypes did not name a physics dictionary: each now names itself (and flags 32), so the game uses the collision inside the model. Test walls removed. Base building still uses sinor until our props are approved in game.

## Base building back on the sinor props; generated props set aside (owner)
* The generated wasteland_buildprops looked poor in game and had no working collision (you walked through them and could not remove them). Base building uses sinor-buildingProps-v2 again (config, server.cfg and docs as before); wasteland_buildprops stays in the repo as an experiment, not ensured.
* Built pieces now always use the model the config sets for their piece (not the one saved when built), so switching props packs updates existing bases; the pieces placed with the generated props are sinor pieces again: solid and removable.

## Building props: a zombie-survival look (owner)
* Every wasteland_buildprops piece was rebuilt with detail: wood walls of uneven, slightly crooked planks (some missing) on studs with a cross brace; metal walls of overlapping rusty corrugated sheets on a frame, bolted, with patch plates; stone walls with a chipped capstone row, a footing and blocks sticking out; trim posts and sills round doorways and windows. Foundations: plank decks on posts, welded floor plates on corrugated sides, or paving slabs. Braced wooden doors with iron hinges, a barred metal door with a peep hole, a strapped garage door, crossed boards or rebar window bars, a gate frame with corner braces and spikes, a braced corrugated gate, a padlocked cupboard.
* Textures: a new dark beam wood, and old blood splatters and spray-painted marks on wood, metal and stone.
* Only the looks changed: collision and sizes are the same as before (looks and collision are now separate), so snapping and already built bases are unaffected. Preview: docs/images/buildprops.png.

## Free building props of our own: base building no longer needs a paid pack (owner)
* New resource wasteland_buildprops: 32 original models made for Wasteland: foundation, wall, half wall, doorway, window frame, ceiling, garage frame and ramp in wood, stone and metal; wooden and metal doors, a garage door, a gate frame and gate, wooden and metal window bars, and the tool cupboard. Each has its own collision (with wood, stone or metal surface sounds and bullet effects) and uses four textures painted by code (weathered planks, rusty corrugated metal, stone blocks, dark metal). Grid 4 m, walls 3 m tall; doors pivot on their hinges.
* basebuilding.lua now uses them (propsResource = 'wasteland_buildprops'); the paid sinor-buildingProps-v2 pack still works if you set it back. server.cfg ensures wasteland_buildprops before wasteland_basebuilding.
* tools/buildprops rebuilds the models from a script (no Blender, no GTA V needed): gen_buildprops.py writes them, a small converter on CodeWalker.Core (MIT) turns them into GTA files.

## HUD and toilet tweaks (owner)
* The id, name and cash line is bigger and bolder; the armour bar is as long as the health bar and taller.
* Pee and poop fill half as fast (bladderPerHour 25, bowelPerHour 12; drinking and eating add half as much).

## Fix: frozen after logging in, then falling through the map again and again (owner)
* Putting a character back on its spot after the base server's own spawn left it frozen with no collision; placing now always lets go of the ped.
* The fall-through safety net only remembers spots where you really stood on ground (never while frozen or in noclip), and if it happens again within 30 seconds you are sent to a safe camp instead of looping.

## Fix: falling through the map (owner)
* A safety net any time, not only after logging in: when you fall and there is ground above you but none below (the world or a map pack's collision did not load in time), you are put back on the last spot where you stood on ground (the screen fades while it loads).

## Fix: /propplacer refused admins (owner)
* The admin check only accepted true; FXServer answers 1 on some servers (the admin panel already accepted both).

## Prop placer for admins (owner)
* New module wasteland_props: /propplacer (admins, wasteland.admin) opens a panel to search presets (barricades, wrecks, junk, camp gear, structures) or type any prop model. A see-through copy follows where you look: mouse wheel turns (Shift fine), Up/Down raise and lower, Left/Right tilt, Z/X roll, R resets, G snaps to the ground, F toggles collision, Enter or left click places (keep placing copies), Delete removes the prop you aim at, Backspace or right click stops.
* Every prop is saved (wl_props, migration 1) and comes back after restarts; players' games spawn them nearby only (not networked, no entity cost). The panel lists nearby props to move, visit or delete. Settings: config/props.lua (presets, maxProps, streamDistance, maxPlaceDistance). The server checks admin rights, the model name and the distance for every change.

## Survival HUD: a zombie-survival look (owner)
* Health is a blood-red bar on a riveted, rusted plate (armour a steel bar under it); food, drink, temperature, pee and poop are round iron dials with a ring that drains, each in its own colour. Low glows amber, critical pulses red. Bleeding and infection tags restyled. Same data, modes and /hud layout as before.

## Fix: /hud edit toolbar flashing (owner)
* Removed the fade-in on opening screens: pieces that redraw often (the /hud edit toolbar) replayed it and flashed.

## Noise meter (owner)
* A new meter on screen shows how far zombies can hear you right now, using the zombies' own hearing rules (crouched, walking, running, engine) and, for gunshots, the exact reach the server used (suppressor, night, repeated fire). It shows a level from Quiet to Deafening, the reach in feet, what is making the noise, and how many zombies are within earshot. Move and resize it in /hud; /noise hides or shows it.

## Inventory: a smaller Worn panel (owner)
* The worn-item slots are much smaller and sit three to a row, so the Worn panel takes less than half the space it did.

## Inventory shows the vicinity (owner)
* Opening the inventory (TAB) now shows what lies on the ground within reach: dropped items, loot and body bags, nearest first (up to vicinityMax = 4, within reachDistance, in config/inventory.lua). Drag items straight in or out. Something dropped while the inventory is open shows there too.

## Backpacks show on the body (owner)
* A worn backpack now shows on your character (the bag clothing slot), for everyone to see. /backpack hides or shows it (remembered on your computer). The look per backpack is bagLooks in config/inventory.lua.

## Hotbar: 8 slots (owner)
* The hotbar has 8 slots on keys 1 - 8 (was 5). In the inventory they sit in two rows of four; the bar on screen is one row. Saved hotbars carry over.

## UI: removed the black box behind screens (owner)
* The background blur drew a solid black box in FiveM (the game cannot be blurred from a screen), so it is gone; the dark backdrop behind the inventory is gone too.

## Total Apocalypse is the standard map (owner)
* The txAdmin recipe now downloads the free Total Apocalypse map pack (SparksScripts, GPL-3.0) into resources/[maps], and server.cfg ensures pack1, pack2, pack3 and postapo-interior. It is downloaded from its own repository, not bundled (about 470 MB). Comment the four ensure lines out to use the normal GTA map.

## A cleaner, more finished look for every screen (owner)
* The shared design system (wasteland_ui/html/style.css) was refined, so every screen gets it: glass-like panels with soft depth, rounded corners and a thin glowing accent line along the top; buttons with depth that lift on hover and press on click (main buttons glow); inputs and tabs with clear focus and active states; slim dark scrollbars everywhere; section titles with an accent marker; screens fade in when they open.
* Inventory: a soft dark backdrop; panels, grids, slots, the hotbar, menus and the hover box restyled; item tiles with a sheen and a glow on hover; item pictures with a shadow; smoother health bars. The body figure's column is wider so it no longer crowds the bars.
* Skills, Survivor's guide, traders, crafting and the camp jobs board: rows and cards with depth, glowing progress bars.
* Looks only: no screen's layout, behaviour or code paths changed.

## Base building with your own props (owner)
* Base building no longer has to use the paid sinor-buildingProps-v2 pack: basebuilding.lua `propsResource` names the resource with your props ('' for GTA's own props), and each piece's `model` can be any model. Snapping measures each model, so any sensible sizes work. How-to: docs/INSTALL.md "Using your own building props".
* The start-up warning and the "model is not in the game" message no longer assume the sinor pack.

## Barricade without a tool cupboard (owner)
* Walls, doors, garage doors and defenses can now be built anywhere nobody has claimed, without a tool cupboard - to barricade an old building for a night. Storage still needs a cupboard.
* Such pieces belong to whoever built them (and their group): only they open the doors, repair, upgrade or remove them. No upkeep, no zombie-free zone - zombies will try to break through.
* They are gone after 12 hours, unless a tool cupboard placed later claims them (then they stay like any other piece). basebuilding.lua `freeBuild`: on/off, which categories, how many hours.
* Database: wl_bb_props gets an owner_id column (migration 5, applied by itself on start).

## Fix: zombie kills were never credited (owner report)
* The server noted a zombie's starting health the moment it created it - before any game had reported the new ped, so it read 0. Every kill report then failed the "is it really hurt?" check (0 is not below 0) and was thrown away, and the zombie was marked dead with no killer. A zombie now counts as 200 health when that first reading is 0. Kill milestones, combat XP and quest kill counts work from now on (kills before this fix were not recorded anywhere, so they cannot be counted back).
* The test server can now behave like a real one here (spawnHealth), with a test that fails without this fix.

## Weapon attachments (owner)
* Five attachments, found in military and heli-crash loot, supply drops, bandit stashes and (rarely) crates: Suppressor, Weapon flashlight, Scope, Grip, Extended magazine. Each fits only the guns we use that GTA has that attachment for (pistol, pump shotgun, micro SMG, SMG, carbine, assault rifle; suppressor on the hunting rifle too; the revolver and sawed-off take none).
* Right-click an attachment -> "Attach to <gun>", or right-click a gun -> "Attach <attachment>"; one per slot. Right-click the gun -> "Remove attachments" gives them back. The gun shows its attachments in your hands (GTA components) and in its menu title.
* A suppressed shot is heard only half as far by zombies (weapons.lua `suppressorNoise`).
* Which GTA component each gun uses per slot: the gun's `attachments` in inventory.lua.

## Calls for help: /help, /accepthelp, /cancelhelp (owner)
* /help [what is wrong] sends an announcement to everyone (a pop-up with a sound, and the chat): who needs help, roughly where (the area name) and the message.
* /accepthelp puts a red blip with a GPS route on your map to whoever called (or /accepthelp <id> for a particular player); it follows them every 10 s while the call is open and goes when you reach them. The caller is told who is coming.
* /cancelhelp ends the call (helpers are told); a call ends after 10 minutes or when the caller leaves. One call every 3 minutes.
* groups.lua `help`: on/off, cooldown, how long a call lasts.

## Fix: "Awaiting scripts" and a hazy, unloaded world after choosing a character (owner report)
* Blocking spawnmanager's random spawns (the previous fix) also blocked its first spawn when joining - and that first spawn is what ends GTA's loading screen. The game stayed at "Awaiting scripts" behind the character screen, so the world never finished loading. Wasteland now does that first spawn itself, at a fixed holding spot (the default spawn), ends the loading screen, and then the character screen opens.

## /stuck: back to the nearest safe camp (owner)
* Any player can type /stuck: a window shows the nearest safe camp and how far it is. Press Teleport and stand still for 10 seconds (moving, getting hurt or getting into a vehicle cancels it) and you are taken there. Once every 30 minutes, so it is no free fast travel or escape from a fight.
* Checked by the server (the wait, that you stood still, the cooldown). camps.lua `stuck`: on/off, the command, the wait, the cooldown.

## Fix: after choosing a character, stuck in the air over a half-loaded world (owner report)
* Placing the character now makes the game load the world at the saved spot first (a load scene - otherwise streaming follows wherever the camera was), then the building, then the ground under the spot, while the screen stays dark and the character is held. Up to about 30 s on a slow PC.
* No ground there: the highest ground at that spot is used; still none, or the character falls more than 25 m in the first 15 s, or is still hidden: the server sends them to a safe camp.

## Fix: a random spawn after waiting at character select (owner report)
* The base server's basic-gamemode turns spawnmanager's auto spawn back on and forces a spawn at a random map spawn point when the map has loaded - which could be after Wasteland had turned it off (for example while a player sat at character select), and that random spot could then be saved as the last position. Auto spawn is now kept off (also right after the map loads, and every few seconds).
* A returning character with no usable last position (none, or the map origin) wakes up at a random safe camp instead of wherever the game put them.

## Melee feels better: zombies react to hits (owner)
* Every melee hit (fists or a weapon) stuns the zombie for a moment: it stops in its tracks and the swing it was winding up never lands, so you can beat it back instead of trading blows.
* A hit can knock it off balance (a short stagger): sometimes with fists and knives, half the time with heavy weapons (bat, hatchet, battle axe, hammer, wrench, crowbar, machete).
* zombies.lua `hitReaction`: stun time, stagger chances and length, which weapons count as heavy; `enabled = false` turns it off.

## New survivors start with a knife and a Full vehicle repair (owner)
* Starting items now include a knife and a Full vehicle repair. Hold Left Alt on any wreck and choose "Full vehicle repair": after 15 s every part is fitted (battery, engine, four wheels), engine and body are like new and the tank has at least half its fuel. One use.
* Items can now have a `limit` (inventory.lua): the Full vehicle repair has limit 1, so a player can only carry one - picking up, being given, Take all and trading a second one are refused.
* Fix: new characters got their starting items while their pockets were still the bare 3 x 3 (before the creator's clothes were on), so bigger starting items could be lost. They now get them right after the creator, once the outfit (and the bigger pockets) is on.

## Fix: zombie kills often not counted; other guide milestones (owner report)
* Kill credit was lost in a race: the server noticed a zombie at 0 health (its once-a-second check) before the kill report from the game running it arrived, and marked it dead with no killer. It now waits up to 3 s for that report. Fixes "Kill your first zombie" / kill milestones, combat XP and quest kill counts.
* Running a zombie over now counts for the driver; when the game names no killer, the nearest player who hurt it gets the kill.
* A finished search that found nothing now counts as a search (guide, scavenging XP).
* Characters older than the guide get credit from their skills: kills (combat XP), searches, crafts, harvests, wounds treated and their best skill level - checked when they log in.

## Cheaper traders, cheaper upkeep, Take all (owner)
* Trader prices lowered: food and basics about 40 % less, gear about half, big-ticket items about a third (pistol 1500 -> 520, pump shotgun 3000 -> 1050, engine parts 600 -> 210, armor plate 750 -> 260, small backpack 400 -> 140). Traders never pay more than half their own price, so nothing can be bought and sold back at a profit.
* Base upkeep is a quarter of before: 0.25 of a material per piece per day (a 40-piece base: 10 planks a day). basebuilding.lua `upkeep.perPieceCostPerDay`.
* Looting: a Take all button on whatever you are looting (bodies, containers, trunks, stashes, the ground), or press E. Everything goes into your pockets, then your backpack; stackable items join stacks you already have, everything else keeps its condition. What does not fit stays, and you are told how many.

## Fix: supply drops were often empty (owner report)
* They used the ordinary crate loot table, which is empty half the time. They now have their own table (loot.lua `supplydrop`): never empty, 4 - 6 good finds (ammo, medical, food, armor, repair kits, gun parts, cash, sometimes a gun, a hiking backpack or a blueprint).
* A crate that still rolled nothing falls back to supplydrops.lua `items`; the crate is bigger (10 x 8) so a full drop always fits.

## Bases: a one-hour safe zone, window bars, barbed wire, spikes, sandbags (owner)
* The zombie-free zone round a tool cupboard now lasts one real hour after the cupboard is placed (basebuilding.lua `cupboard.safeMinutes`, 0 = for ever). Placing one shows a pop-up; a green ring marks the protected area and a countdown shows how long is left while you are near. When it drops the owner is told, and zombies can come in and attack walls, doors, gates, bars and sandbags. Cupboards placed before this update have had their hour.
* Window bars (wood, upgrade to metal) snap into window frames; zombies can break them.
* New Defenses category: Barbed Wire (hurts and slows zombies that walk into it), Wooden Spikes (hurt more), Sandbag Wall (a tough wall they must break). Wire and spikes wear down with every zombie that touches them; repair them like other pieces.
* Defense models are GTA's own; each has fallbacks (`altModels`) used when a game lacks the first - check in-game which one shows (R46.x).

## Zombie sounds included; Chiliad camp; respawn at the safe zones (owner)
* The zombie sound files are now part of Wasteland Core: `resources/[wasteland]/wasteland_zombiesounds` (Zombie Sound Pack, Free Version, by Catastic, plus a few extra clips). The recipe and the updater install them; `ensure wasteland_zombiesounds` is in the txAdmin server.cfg (the updater offers to add it). A server that had the folder outside `[wasteland]` should delete that copy.
* New camp: Chiliad Mountain Camp (general trader, medic, gunsmith).
* After dying you respawn at one of the safe zones: Sandy Shores, Paleto Bay, Pillbox, Chiliad.

## Survivor's guide (F2 or /guide)
* Progress: 22 milestones that tick off by themselves as you play (search a container, eat, first kill, craft, treat a wound, trade, blueprint, campfire, hunt, cook, group, vehicle, 25 kills, a camp job, tool cupboard, supply drop, a player trade, skill level 5, two hours without dying, a world event, 250 kills, a maxed skill). Counted milestones show progress (7 / 25). A message and a sound when one is done.
* "Try next": the next three unfinished milestones, each with a hint on how.
* Stats: time alive this life, longest life, best skill level, zombies killed, places searched, things crafted, animals harvested, meat cooked, wounds treated, trades, jobs, supply drops, blueprints, deaths.
* How to: pages on controls, staying alive, the dead, looting and crafting, camps and groups, vehicles, hunting, building, skills.
* guide.lua: the key, every milestone (label, hint, stat, count) and every page - edit them freely. Saved with the character; no tables of its own.
* New events other scripts can use: wasteland:basebuilding:cupboardPlaced, wasteland:hunting:fireLit, wasteland:hunting:cooked, wasteland:survival:consumed. Export AddStat(source, stat, amount) for your own milestones.
* Tests: the old zombie hit tests now use plain zombies (a random special infected made them fail now and then).

## Skills: level up by doing (/skills or F9)
* Six skills, levels 1 - 10, saved with the character: Scavenging (searching), Crafting, Medicine (bandages, medkits, antibiotics), Hunting (harvesting), Fitness (sprinting), Combat (zombie kills).
* Each level makes you a little better; level 1 has no bonus, level 10 the full one: searches 30 % faster and a 25 % chance of an extra find; crafting 30 % faster and a 20 % chance to get a material back; healing items heal 50 % more; 50 % more meat; stamina lasts longer; 20 % more melee damage and weapons wear 30 % slower.
* A level-up message and sound. The skills screen shows every skill, its XP bar and what it gives you now.
* Dying costs 10 % of the progress into each skill's current level - never a level (skills.lua `deathPenalty`: none / some / all).
* skills.lua: XP per action, the bonuses, the level curve, an XP multiplier (double XP weekends). Exports for other scripts: GetBonus, GetLevel, GetSkills, AddXP.
* Loot, crafting, hunting, survival and weapons ask for the bonus only when wasteland_skills is running; without it everything works as before.

## Zombie sounds
* Zombies groan (now and then when calm, more often when coming at you), make a sound when they swing, when they are hit (with a thud) and when they fall dead; screamers and howlers call (heard up to 90 m). Sleepers are quiet.
* Every player hears the zombies near them, louder when closer and from the side they are on.
* The sound files are a separate resource, `resources/wasteland_zombiesounds` (Zombie Sound Pack, Free Version, by Catastic, plus the zombey clips), kept on the server and not in the public repository: copy the folder to another server yourself and add `ensure wasteland_zombiesounds` to its server.cfg. Without it zombies are silent as before.
* zombies.lua `sounds`: on/off, volume, range, how often they groan (every file list: wasteland_zombies/client/sounds.lua).

## Zombies break through base walls, doors and gates
* A zombie whose target hides behind base walls (it stops getting closer), or inside a base's safe zone, attacks the nearest wall, doorway, window frame, half wall, door, gate or garage door in the way instead of giving up. When the piece breaks it goes after the player again; after 60 s it gives up.
* Damage per hit: wood 4, stone 2, metal 1 (basebuilding.lua `raid.zombies`; 0 = zombies cannot hurt that material). Open doors are left alone. Repairs work as usual.
* The owner gets "Zombies are attacking your base!" (at most every 3 minutes).
* Every hit is checked by the server like a player hit: the game reporting it runs the zombie, the zombie stands at the piece, not faster than its swing.
* Pieces inside the 12 m zombie-free zone round a tool cupboard stay out of reach (zombies cannot enter it); walls at its edge and outside it can be attacked.
* Off: zombies.lua `ai.barricades.enabled = false`, or basebuilding.lua `raid.zombies.enabled = false`.

## Zombie AI upgrade (zombies.lua `ai`; `ai.enabled = false` restores the old zombies)
* Personalities (share by day / night, configurable): wanderers, stalkers (follow from a distance, circle round, charge later, may back off and come again), ambushers (wait still, jump anyone close; optional `ambushPoints`), sprinters (slow until alerted, then sprint bursts with cooldowns), sleepers (lie down until you come close or make noise), pack hunters (surround you from different sides, no stacking).
* Senses: a view cone (less to the sides), still players are harder to see and runners easier, nothing through walls, engines heard (idling less), a short reaction time per personality. Memory: zombies go to where they last saw you and search around, then go back to what they were doing; a chase ends after 2 minutes or 160 m.
* Special infected (they keep their normal model): screamer, brute, howler, spitter (telegraphed, checked by the server), hunter (goes for players on their own), crawler (off). Bosses juggernaut, alpha, butcher and night terror are off until given a chance.
* Horde layer: the nearest zombies answer a noise (max 15), each to its own spot around it; repeated gunfire in one place brings more from further out; explosions and car crashes are noises; a cooldown per sound and spot; optional building `entryPoints`. Only existing zombies: nothing new spawns.
* Day / night: dawn, day, dusk and night change sight, chase speed, horde size and the personality mix; zombies change gradually, only when calm.
* Nothing else changed: spawning, population, models, loot, safe zones and every other system are as they were; no database change. In-game checks: docs/IN_GAME_TESTS.md R43.

## Smaller backpacks (they covered most of the screen)
* Small backpack: 8 x 8 (was 10 x 10). Hiking backpack: 12 x 10 (was 15 x 15). Weight limits unchanged (100 and 175 kg).
* A bag that holds more than fits in its new size keeps everything: stacks move into the smaller grid, and a bag that really cannot fit them stays just big enough until it is emptied a bit.

## Inventory: Sort button
* Every grid (pockets, the open backpack, storage, trunks, the ground) has a Sort button.
* Part stacks of the same item merge (same condition and metadata only); then everything is packed from the top left, grouped by category (weapons, ammo, medical, food, drinks, tools, materials, clothing, armor, bags, other), biggest first.
* Hotbar slots follow a stack that was merged into another. One saved step; if it would not all fit, nothing changes.

## A small zombie-free zone around every tool cupboard
* Within 12 m of a tool cupboard, zombies act as they do in camps: none spawn there, they stop chasing players inside, they cannot hit them, and ones that wander in are removed. You can build in peace.
* basebuilding.lua `cupboard.safeRadius` (0 turns it off). Exports: `IsInBaseZone(coords)` on the server and on the client.

## Fix: the garage door swung sideways like a normal door (owner report)
* Garage doors now roll up into their frame when opened (about a second) and back down when closed, and they stay up or down after a restart and for players who come near later.
* How far they go up: the door's own height less 0.3 m, or the piece's `openLift` in basebuilding.lua.

## Fix: gaps at wall corners; ramp distance when turned round (owner report)
* Walls, doorways, window frames and half walls snapped to the outside of the foundation edge, so two walls on neighbouring edges left a gap the thickness of a wall at the corner.
  * They now stand on the edge, their outer face flush with it; at a corner they overlap instead.
  * basebuilding.lua `placement.wallsInset = true` (false: the old way).
  * Pieces already built stay where they are.
* Ramps:
  * Turned round (R), the distance was measured from the wrong end of the ramp; fixed.
  * "On top of the foundation" (Q) now lies on the foundation, flush with its edge, instead of hanging off the outside.

## Base building: ramp up/down, gap tuning that is kept (owner report)
* Ramps snap four ways:
  * R turns them up or down.
  * Q puts them beside the foundation (top level with it: walk up onto it) or on top of the foundation.
  * The help line shows which.
* Gaps between snapped pieces: Ctrl+wheel while placing (Ctrl+Shift+wheel for big steps) is now remembered per piece on that computer, not only for one placement.
* /bbsnap lists the values (and prints a line to paste into basebuilding.lua `placement.overlap` for everyone); /bbsnap reset clears them.

## Base building (new module wasteland_basebuilding, ported from sbb-basebuilding)
* **Ported from sbb-basebuilding** (QBCore / ox) to Wasteland Core:
  * Wasteland characters, inventory (items and stash grids), target (Left Alt), UI screens, the lockpick minigame and the database (migrations).
  * Nothing from QBCore or ox is needed.
* **Needs the "sinor-buildingProps-v2" props pack.** It is NOT part of Wasteland Core: it is a Cfx escrow asset pack, licensed to the account that owns it. Install it on the server and `ensure` it before wasteland_basebuilding; the module warns if it is missing.
* **Tool cupboards** claim 40 m.
  * The owner, players they authorize (by player id), and the owner's group (/group) may build, open doors and storage, repair and remove there.
  * The cupboard screen shows upkeep per material, who has access, Supplies, Repair all and Remove.
* **Building:** use a Building plan (craft: rag + duct tape, or buy one) to open the build menu.
  * Pieces: foundation, wall, doorway, window frame, half wall, ceiling, frame, ramp, gate frame, doors, gate door, garage door, storage (3 sizes).
  * Pieces snap to foundations and to each other.
  * Controls: E place, wheel turn, arrows turn freely, Shift+wheel height, Tab snapping, Backspace cancel.
* **Upgrades** wood → stone → metal, repairs, and doors with E.
* **Raids:** explosives damage pieces, wood also takes melee hits.
  * Doors and storage can be lockpicked (the minigame; a failed try breaks the pick).
  * Owners are told when their base is lockpicked, also later if they were offline.
* **Upkeep** comes from the cupboard's supplies (wood planks, stone, metal sheets): 1 a day per piece of each material. Short of a material, its pieces decay.
  * Fix from the original: the cost was rounded up on every 5-minute tick (about 288 a day per piece); the fraction now carries over.
* **Items and recipes:**
  * New items: building plan, stone.
  * Wood planks are back in loot and at the trader and weigh 0.5 kg.
  * Metal sheets can be crafted again (no station).
* Tables `wl_bb_cupboards`, `wl_bb_auth`, `wl_bb_props`, `wl_bb_notices`. Config: basebuilding.lua.

## Update notice: the console says when GitHub has a newer Wasteland Core
* 15 s after the server starts, and every 6 hours, the core compares the installed version with GitHub. The installed version is `wasteland_core/VERSION.txt`, written by the updater (a resource may only read its own files); a fresh install records the newest version on its first start.
* If there are updates, a yellow banner in the console shows how many, the installed and newest versions, the titles of up to 10 changes, and how to update (run update_wasteland.bat).
* Admins (wasteland.admin) get a line in chat when they join while updates wait.
* framework.lua: `updateCheck = { enabled, repo, branch, everyHours }`.

## Bigger vehicle trunks
* Trunks are now 15 x 12 cells and hold 300 kg (were 6 x 5, 80 kg). Pickups and vans (Bison, Sadler, Rebel, Rat-Loader, Bodhi, Duneloader, Surfer, Rumpo, Youga) are 18 x 14 and hold 450 kg.
* vehicles.lua: `trunk = { width, height, maxWeight, models = { <model> = { width, height, maxWeight } } }`.
* A stash that is already loaded takes a new size from the settings straight away (never smaller than what is in it), so existing trunks grow without a restart.

## Inventory: the backpack opens on demand
* Opening the inventory shows the pockets only. To use the worn backpack, right-click it in the Back slot and choose Open backpack (or double-click it). Its grid then shows next to the pockets, with a Close button.
* With the backpack open and nothing else open, double-click (or Shift+click) moves items between the pockets and the backpack. Dragging works as before.
* Each time the inventory opens, the backpack starts closed. Items you buy, loot through Take all, or harvest still go into the backpack when the pockets are full.

## Fix: armor plates wore down every login or server restart (owner report)
* While a plate is worn, the game keeps GTA's armour full and reports what it loses as hits on the plate. A new ped (logging in, a server restart, respawning, a new look) starts with 0 armour, and that was counted as a 100-point hit: about 25% of the plate each time.
* Now only armour lost after it was full on the same ped counts, and not while the screen is faded out (teleports). The server also ignores armour reports for 15 s after a character loads.
* Clothing: only zombie hits wear it, and not while a player is protected (creating a character, choosing where to wake up).

## Fix: "Last known position" put you on the roof; no more idle camera (owner reports)
* After spawning, the ground was looked for from 5 m above the point, and inside a building the first thing found is the roof.
  * "Last known position" now puts you exactly where you were, after the building's interior has loaded.
  * Camp spawns look for the ground from just above the point.
* GTA's idle camera (it starts slowly panning when you stand still) is switched off: world.lua `idleCamera = false`.

## Fix: the cooking window fell back to the list after the first piece (owner report)
* The server sent "pieces done" as `done`, and the window read any number above 0 as "finished". After the first piece, the window showed the list again while the server was still cooking, and Cook did nothing.
* The end of cooking is now its own flag (`finished`). The window keeps showing "Cooking 3 of 5" until the last piece, and Cook works again right after.

## Fix: campfires stopped working after a while (owner report)
* The game deletes server-made props it thinks nobody needs, and the fire was one: the server then no longer knew the fire, so Cook did nothing. Fires are now kept (orphan mode 2), and a lost fire prop is made again in the same place.
* A fire now burns as long as anyone is within 30 m. Left alone for 15 minutes (`idleMinutes` in hunting.lua; it replaces `burnMinutes`), it goes out and goes back to its owner.
* If a fire cannot be placed, the match and firewood are given back too.

## Fix: supply crates landing on roofs, and "too far away" when you reach them (owner report)
* The crate looked for the ground from 50 m above its point, so it could land on a roof over the point. It now looks just above the point, so it lands on the ground there.
* Opening checks the distance along the ground (3.5 m) and allows 4 m up or down, for slopes and steps. Someone on a roof high above still cannot open it.

## Hunting, campfires and cooking (new module wasteland_hunting)
* **Animals:** deer, boars, rabbits and coyotes wander near every player.
  * Three per player, 40 on the map at most.
  * They spawn 90-200 m away, not on roads, in water or in camps.
  * They are removed when nobody is within 350 m; a carcass lasts 10 minutes.
* **Harvesting:** hold Left Alt on a dead animal and choose Harvest. It needs a blade: knife, switchblade, machete, hatchet or battle axe.
  * It takes 6 seconds of kneeling; moving or X cancels.
  * Yield: raw meat (deer 2-4, boar 2-3, coyote 1-2, rabbit 1, any other animal 1-2), and an animal pelt from deer, boars and coyotes (traders pay 15).
  * Any animal can be harvested, also ones this module did not spawn.
* **Campfire:**
  * Craft it from 3 scrap metal, or buy it.
  * Use it from the inventory: it is placed in front of you. Lighting it takes 1 match and 2 firewood.
  * It burns 30 minutes and warms you within 5 m.
  * Anyone can cook on it. The player who made it can put it out and pick it up again. When it burns out, it goes back to its owner.
* **Cooking:** Left Alt on the fire and choose Cook. Pick how many raw meat (up to what you carry, with - / + / All).
  * Each piece takes 5 seconds; the window shows "Cooking 2 of 5" and has a Stop button.
  * Walking away stops it.
* **Eating:**
  * Cooked meat: food +45 and a little health.
  * Raw meat: food +10, but infection +5.
* **New items:** raw meat, cooked meat, animal pelt, matches, firewood, campfire.
  * Matches and firewood are found in trash, tool sheds and crates, and sold by the general trader.
* Config: hunting.lua.

## Trading between players (new module wasteland_trade)
* Hold Left Alt on another player: **Trade**. They get a popup (Trade / No thanks); the request lasts 30 seconds.
* One window with three lists side by side:
  * your items (Offer);
  * your offer (change the amount, remove);
  * their offer.
* Each list scrolls on its own, so any number of items fits without overlapping. Up to 40 different stacks per side.
* Both press Accept. Any change to either offer takes both accepts back, so nobody can swap something at the last second.
* The swap is all or nothing:
  * whole stacks keep their condition (and a bag keeps its contents);
  * part of a stack splits off;
  * cash trades like any item;
  * if anything does not fit (room or weight), nothing changes and the trade stays open.
* Moving more than 8 m apart, dying or leaving cancels the trade. Traded items leave the giver's hotbar.
* Inventory exports: `GetTradeable(source)` and `Trade(a, offerA, b, offerB)`. Config: trade.lua.

## Inventory: a hover box with the item's name and amount
* Hovering over an item shows a box to the bottom right of the cursor, in large text (18 and 16 px):
  * the item's name;
  * the amount in the stack (dollars for cash) and its condition if it wears;
  * its description.
* The box stays on screen near the edges and hides while dragging. It replaces the browser's small, slow tooltip.

## Traders buy anything you carry
* Every trader buys every item except cash, not only what is on its list. The sell list shows whatever you carry.
* Price:
  * A shop's own `sell` price wins.
  * Otherwise: the item's price in `buyAnything.prices` (guns 60 to 220, gun parts, car parts, kits...), `blueprints` (25) for blueprints, or the item's category (food 4, drink 3, medical 6, material 2, tool 10, clothing 4, armor 30, bags 40, melee weapons 15, ammo 1 a round, other 3).
* What a trader pays is capped at half the lowest price any trader sells the item for, so nobody can buy at one trader and sell dearer at another.
* camps.lua: `buyAnything = { enabled, default, blueprints, categories, prices, except }`.

## Voice chat (pma-voice) and group radio
* Proximity voice with [pma-voice](https://github.com/AvarianKnight/pma-voice) v6.6.2: players near you hear you.
  * F11 cycles whisper, normal and shout.
  * Push-to-talk is the FiveM voice key, N by default.
* Group radio: everyone in your group (/group) is on the group's own radio channel. Hold Caps Lock to talk to them anywhere on the map. You join it when you join, log in, or the group is made; you leave it when you leave, are removed, or the group is disbanded.
* The radio key is Caps Lock, not pma-voice's default Left Alt, which is the interaction key.
* Installing it:
  * The txAdmin recipe downloads pma-voice.
  * The updater offers to install it and add its server.cfg lines.
  * server.cfg.example and the txAdmin server.cfg have the lines: `setr voice_*` and `ensure pma-voice` after oxmysql.
* groups.lua: `radio = { enabled, channelBase, keyName }`.

## Fix: hands up (X and the emote menu) did nothing (owner report)
* The animation dictionary was misspelled (`missminuteman_1ink` instead of `missminuteman_1ig_2`), so the game never found the animation.

## Fix: an "invisible block" when hitting zombies in melee (owner report)
* Zombies were in a relationship group the game treats as neutral toward players. That means no melee lock-on or hit assist, and running or swinging into one plays the bystander "bump", which felt like an invisible wall.
* Zombies and players are now enemies (as bandits already were), set on every player's game. Zombies also no longer block or dodge melee (combat ability 0).
* Not confirmed in-game yet.

## Fix: inventory grid lines did not match the items (owner report)
* The grid lines were always drawn 50 px apart, while the cells now shrink to fit big grids, so they drifted away from the items. The lines now use the same size as the cells, and the border no longer eats into the last row and column.
* The health panel no longer gets pushed off the right edge: the grids leave room for it and it takes the space that is left.

## Choose where you wake up (owner report: random spawn after waiting at character select)
* Returning characters now choose on login: their last known position, or one of the safe camps. The screen stays dark and they stay protected until they arrive. The choice puts them exactly there, whatever happened while they waited at the character screen.
* New characters still pick a camp after the creator. Not after a resource restart, and not while dead (the respawn screen handles that).
* spawnmanager's auto-spawn is now switched off as soon as the client starts, not only after a character is loaded. That was what moved players who waited at the character screen.
* camps.lua: `chooseSpawnOnLogin = true`. Players export `GetSavedPosition(source)`.

## Pockets grow with clothing; bigger backpacks
* Pockets start at 3x3. A worn top adds 2x2, pants 2x2 and an armor plate 2x2: 5x5, then 7x7, then 9x9. The most is 10x10.
* The pockets hold 55 kg. This is set in `inventory.lua` → `pockets` (`bonus` per worn slot, `maxWidth` and `maxHeight`).
* Taking something off is refused while the smaller pockets could not hold what is in them ("make room in them first"). Otherwise stacks outside the smaller grid move inside.
* Nothing is ever lost:
  * Old characters whose items do not fit keep pockets just big enough for them, until they make room.
  * On death, the clothes go into the body bag, and kept hotbar items that no longer fit go in with them.
* Backpacks:
  * Small backpack: 10x10, 100 kg.
  * Hiking backpack: 15x15, 175 kg.
* The inventory screen shows the pockets and backpack side by side, and makes the cells smaller when big grids would not fit on the screen.

## Crafting: rags from any clothing, weapon and ammo blueprints
* Tear up pants (3 rags), shoes (2) or a hat (1), as well as tops. These are known from the start.
* New melee weapons: hammer, pipe wrench, battle axe, brass knuckles and switchblade. Each has its own blueprint, and so does the baseball bat.
* Gun blueprints: pistol, heavy revolver, sawed-off shotgun, pump shotgun, micro SMG, SMG, hunting rifle, carbine and assault rifle.
* Ammo blueprints:
  * Pistol ammo (9mm and .44).
  * Shotgun shells.
  * Rifle ammo (5.56, 7.62 and .308).
* New materials:
  * Gun parts: crates, tool sheds, wrecks, crash sites, military and bandit loot.
  * Gunpowder: crates, crash sites, military and bandit loot, survivor caches.
* The best blueprints are the rarest: rifles at crash sites and military events, the SMG at crash sites.
* Change any of it in crafting.lua, loot.lua and inventory.lua.

## Base building switched off (owner decision)
* The props did not look good enough. `bases = false` in modules.lua, and `ensure wasteland_bases` is removed from the server.cfg templates.
* The code stays in `wasteland_bases`, along with the unit tests for its grid math.
* The building materials are out of loot, crafting and the trader: wood planks, nails, metal sheets and the base flag.
* The item definitions stay, so items players already have remain valid.
* The survival and crafting hooks stay; they are general: warmth sources, respawn points, crafting stations.

## Base building (new module wasteland_bases)
* **Claim:** craft a Base flag (4 wood planks, 2 rags, 2 scrap metal) and use it from the inventory. A preview shows where it goes (E / Q turn, left click place). You claim a 30 m circle.
  * Not within 150 m of a camp's edge or another base.
  * One base per group, or per player who is not in a group. Everyone in the owner's group builds and uses it.
* **Build:** /base or F7 opens the base screen: the pieces, what they cost and what you have. Pick one and place it.
  * The preview stays on so you can keep placing; right click stops.
  * Walls, doors and gates snap to a 3 m grid laid out from the flag.
  * The other pieces go anywhere in the claim.
* **Pieces:**
  * Scrap, metal and fortified walls. Build a better wall over an old one to upgrade it in place.
  * Scrap and metal doors, and a gate wide enough for vehicles. They open and close for the group only.
  * Storage crate and metal locker (shared storage).
  * Workbench: crafting recipes can need a station; metal sheets are made at a workbench.
  * Campfire: warms you within 6 m.
  * Sleeping bag: your group respawns there after dying, with a 5 minute cooldown.
  * Rain collector: makes a bottle of water every 30 minutes, up to 4.
* **Interacting:** hold Left Alt on a piece to open, use or demolish it. Demolishing asks twice and gives back half the materials. Storage must be empty first.
* **Upkeep:** keep scrap metal in the flag's upkeep box.
  * The cost is 1 a day plus 1 per started 10 pieces. A new base is paid for 3 days.
  * Unpaid, the base lasts 72 more hours, then it is removed with everything in it (the owner is warned).
* **How walls are made:** each wall is built from game props for the scavenged look, plus hidden solid panels that fill it exactly, so it blocks players whatever the props look like.
  * Admins: `/baseadmin preview` shows every piece in a row, named, so the props can be tuned in bases.lua.
  * `/baseadmin remove` removes the nearest base.
* **New items:**
  * Wood planks: trash, sheds, crates, the trader.
  * Nails: craft 20 from 1 scrap metal, or buy them.
  * Metal sheet: workbench.
  * Base flag.
* **Other modules:**
  * Survival: `RegisterWarmthSource(name, fn)` and `RegisterRespawnPoint(name, fn)`.
  * Crafting: recipes take `station`, plus `RegisterStation(name, label, fn)`.
* Tables `wl_bases` and `wl_base_pieces`. Config: `bases.lua`.

## More food and drink
* 18 new items, each with its own picture:
  * Food: canned tuna, canned salmon, chicken soup, country stew, MREs (beef and chicken), chips, peanut butter, bread, apple, banana, orange.
  * Drinks: Sprunk, coffee, milk, grape juice, beer, whiskey.
* They differ in what they do. Soup, stew, coffee and whiskey warm you up. Fruit gives a bit of water as well as food. Salty food (chips, tuna, peanut butter) makes you thirstier. MREs are a full meal. Whiskey warms you but dries you out.
* Found in fridges, vending machines, trash and crates. Most of them are also sold by the general trader.
* Change the effects in survival.lua (consumables), the items in inventory.lua, where they drop in loot.lua and prices in camps.lua.

## Groups (new module wasteland_groups)
* /group or F6: make a named group (3-24 characters, unique), invite players by id or from a "near you" list, accept or decline invites (they expire after 2 minutes).
* Members see each other on the map: blue for members, yellow for the leader, red when down. Updated every 2 seconds.
* The leader can remove members, make someone else leader, rename the group, and disband it. Members can leave; a leader must hand over first (if they are the only member, leaving disbands the group).
* Groups are saved in the database (wl_groups, wl_group_members) and last across restarts until the leader disbands them.
* Config: groups.lua (maxMembers 8, name length, invite time, marker update rate, command). Exports for other modules: GetGroupOf(characterId), SameGroup(a, b).
* Tests: 726.

## Updater: works wherever it is saved (owner report)
* update_wasteland.bat finds update_wasteland.ps1 or update.ps1 next to it (and says where to get it if neither is there).
* The updater finds the server folder itself when it is not in it: it looks in its own folder, its parent folders and their sub-folders (e.g. txData\MyServer.base) and asks which one if there are several.


## Fix: zombies only hurt you when the swing lands (owner report)
* Before, damage was sent the moment a zombie within 2.6 m started its attack animation, so being near one hurt even when it never touched you.
* Now a zombie within 2.2 m starts a swing; 0.45 s later it lands and hits only if you are still within 1.7 m, in front of it (about 60 degrees either side), with nothing in between and not in a vehicle. Step back or sideways in time and it misses. The server refuses hit reports from further than reach + 1 m. zombies.lua `attack = { range, hitReach, windupMs, cooldownMs }`.
* Tests: 709.


## Updater for other servers
* tools/update.ps1 (+ update_wasteland.bat): stop the server, double-click, start it. Shows what is new since the installed version (VERSION.txt), backs up the database (mysqldump / mariadb-dump, from the server.cfg connection string) and the old resources, installs the newest version from GitHub keeping the server's settings and zombie models (differing settings files get a .lua.new next to them), adds new settings files, offers to add missing ensure lines to server.cfg, updates itself.
* The txAdmin recipe (1.0.3) puts the updater into the server folder.
* Tested on an outdated server folder: settings kept, new settings file added, missing ensure lines added, database and files backed up, custom zombie models kept.


## New players: protected, $50, choose where to start (owner request)
* Protection: while choosing or making a character and until a new character has arrived at their camp, a player is protected (player state `wlProtected`): no damage from the server (survival Damage refuses), zombies do not notice or hit them, bandits ignore them. (Before, a zombie could kill you in the character creator.)
* New characters start with $50 cash (inventory.lua startingItems).
* Choose where to start: after making a new character, a "Where do you start?" screen lists the safe camps (traders shown); the character is taken there, protected for a few more seconds. camps.lua: optional `spawn = { x, y, z, heading }` per camp (default: its centre). Server event wasteland:camps:spawnChosen(source, campId).
* Tests: 707.


## Milestone 11: txAdmin recipe
* The repository is on GitHub: https://github.com/gosalosey/wasteland-core (credits for the item pictures in the README).
* txAdmin recipe (txadmin/recipe.yaml): installs FiveM's base resources, oxmysql (latest release), Wasteland Core, a ready server.cfg (build 3570, OneSync, start order, admins, server icon) and creates the database. Recipe URL: https://raw.githubusercontent.com/gosalosey/wasteland-core/main/txadmin/recipe.yaml
* Clean-install test: the published recipe was run into an empty folder and an FXServer started from it: all modules running, the database tables created.
* docs/INSTALL.md.


## World events (owner request)
* New resource wasteland_events (module "events", config events.lua; added to server.cfg). Every 35 minutes (with players online) an event starts at one of 10 points (never in a camp): a message for everyone and a red marker.
  * Helicopter crash: a burning crashed helicopter, 16 zombies and 4 bandits with pistols; the wreckage holds military loot.
  * Ambushed convoy: wrecked trucks and crates, 6 bandits with pistols and micro SMGs, 8 zombies; convoy cargo.
  * Bandit hideout: tents, a campfire, 7 bandits with pistols and sawed-offs; their stash.
  * Horde: 32 zombies at a wrecked car; a survivor cache.
* The danger appears when a player comes within 150 m. Bandits shoot players, take cover, stay near their spot and leave zombies alone; each drops a small bag (pistol ammo, cash, sometimes medicine). The loot stays locked ("Too dangerous: 2 bandits and 5 zombies are still here.") until every bandit and event zombie is dead; then everyone is told, the marker turns green and the loot (shared) opens. The event ends 15 minutes later.
* New loot tables: helicrash, military, bandit_stash, survivor_cache.
* Admins: /event (list), /event <type>, /event <type> here, /event end.
* Exports GetEvents, StartEvent, EndEvent; server events wasteland:events:started / cleared / looted / banditKilled.
* camps.lua: the owner's move of the Legion Square camp to Pillbox Hospital taken into the repository.
* Tests: 704.


## Testing with two games on one PC
* players.lua `duplicateSession = 'test_second_account'` (testing only): a second FiveM game on the same Rockstar account (started with -cl2) joins as a separate account ("...:test2") with its own characters, instead of kicking the first. Switched on in the owner's live config while the server is private; the shipped default stays 'kick_old'.
* Tests: 688.


## Zombie sync: same zombies for everyone, and a check (owner request)
* Audit: zombies and vehicles are networked entities created by the server (OneSync sends them to every player near them); ground bags, supply crates, traders, tailors and loot containers are drawn by every player's game from what the server sends to everyone. Nothing deletes zombies on one player's side.
* Fixed: a zombie's blood and stagger were only applied by the game that runs it, so other players could see a clean zombie walking normally. Every game now applies them to every zombie it shows.
* New: /zombies sync (admins, or the server console). Every player's game lists the zombies it shows within 150 m and the server compares that with the zombies it has there: "sees 4 of the 4 zombies near them", or MISSING / shown but not on the server / no answer. Output in F8 (or the console).
* Tests: 687.


## Zombies: more aggressive, custom kinds and models (owner request)
* More aggressive: they see 70 m by day / 40 m at night (was 35 / 18), hear running 45 m, walking 18 m, crouching 6 m, keep chasing 25 s without seeing you (was 10), hit every 1.1 s (was 1.5), walkers a little faster, more runners (25 % by day, 45 % at night). New: a zombie that spots a player brings the others within 25 m (`detection.alertRadius`).
* Any number of zombie kinds (zombies.lua `kinds`; walker required): each with its chance, speed, damage, infection, bleeding, `shamble` and its own `models`. A commented "brute" example is in the config.
* Custom models: new resource wasteland_zombiemodels (put files in its stream folder; add-on peds also in its peds.meta; added to server.cfg). Players' games report models they do not have; those are skipped with a console warning, so a bad model never makes invisible zombies.
* Tests: 684.


## Repair kits ask what to repair (owner request)
* Using a sewing kit or an armor repair kit ("Use (choose what to repair)…" in its right-click menu, or its hotbar key) opens a list of the damaged pieces it can fix, worn and carried, most worn first ("Pants · 42% (worn)"); pick one, or Cancel. Nothing is used until you pick. From the hotbar the inventory opens with the list.
* Right-clicking a damaged piece still offers "Repair with ..." directly.
* Tests: 674.


## Milestone 10B: SDK guide and example module
* docs/SDK_GUIDE.md: recipes for adding items, food and medicine, weapons, loot (files and in-game), recipes and blueprints, camps, traders and shops, jobs, zombie kinds, vehicles, emotes, tailors and supply drops; a step-by-step walk-through of writing a module; how to test it.
* New resource wasteland_supplydrops (module "supplydrops", config supplydrops.lua; added to server.cfg): the SDK example and a real feature. Every 45 minutes (with players online) a military crate comes down at one of 8 points: map blip and area, a message for everyone, red smoke. The first player to open it fills it (loot table "crate", or its own item list); everyone shares what is inside; gone after 20 minutes. Drops are recorded in `wl_supply_drops`. Admins: /supplydrop, /supplydrop here.
* It shows every part of the SDK: config schema, async init with a migration, a token-stopped thread, guarded net events with server-side checks, optional dependencies, inventory stashes, target, blips and props, an admin command, exports and server events, unit, integration and real-MariaDB tests.
* Tests: 672 (including the real MariaDB suite).


## Fix: sometimes spawning at a random spot after choosing a character
* Cause: the base server's spawnmanager (with the default map spawn points) could spawn the player after we placed them at their saved spot, and the server could sample the position before the move arrived, saving that spawn point.
* Now: the server only records positions after the client reports the character was placed (or after a minute if a client never does); autospawn is turned off as soon as a character loads; if spawnmanager still spawns the player in the first minute, they are put back at their saved spot.
* Tests: 658.


## Tailor camera controls (owner request)
* At the tailor: drag anywhere outside the panel to look around (left/right circles your character, up/down raises or lowers the camera), scroll to zoom in and out, and quick views: Full body, Face, Top, Pants, Shoes. "Turn around" now swings the camera to your back instead of turning the character.
* Turn the character too: "⟲ Left" / "Right ⟳" (45°), "Half turn", or Q / E (15°); the camera stays put. The character faces the way it did when you leave.


## Tailors (owner request)
* New resource wasteland_tailor (module "tailor", config tailor.lua; added to server.cfg). Tailor NPCs at Paleto Bay, Sandy Shores and Legion Square, with map blips. Left Alt on one: "Restyle my clothes ($25 a piece)".
* The screen lists only the pieces you wear (hat, glasses, top with undershirt and arms, pants, shoes): style and colour arrows per part, every change shown on your character at once (a camera looks at you; "Turn around"), "Undo all", "Pay $X (N pieces)". Nothing can be added or removed: only what is worn gets a new look. The server checks you stand at the tailor, that each piece is worn clothing, sane values, and takes the cash first.
* Inventory: worn clothes are put on again when an item's look changes (not only when items change); client exports `ApplyClothing()`, `GetClothingInfo()`; server export `GetClothingParts()`.
* Tests: 656.


## Fahrenheit, craft several at once (owner request)
* Inventory health panel: body temperature in °F with how it feels: Freezing / Cold / Comfortable / Hot / Overheating (coloured). The Cold/Hot advice shows °F too.
* Crafting: choose how many (−, number, +, Max; "can make N"), then "Craft xN". They are made one after another (each one timed, "Making bandage (2 of 5)"); moving or X cancels the rest; it stops early if the materials run out ("Made 2 of 3 x Bandage: out of materials."). Up to 50 at once.
* Tests: 646.


## Hotbar on screen, hands up, emotes (owner request)
* Hotbar on screen (bottom middle): the five hotbar slots with picture, key, count and condition. /hotbar shows or hides it (remembered on the player's computer). Hidden in vehicles, while the inventory is open and while dead.
* New resource wasteland_emotes (ensure it after wasteland_ui; added to server.cfg):
  * X: hands up, X again: down. No shooting or punching with your hands up. Ignored while a progress bar or the lockpick game is open (X cancels those).
  * F4: emote menu (search, categories: Gestures, Survival, Sit & lie, Work, Moods, Fitness); 46 emotes. /e <name> plays one, /e c stops, /e alone opens the menu. Whole-body emotes stop when you walk; upper-body ones (wave, salute...) keep playing while you walk. No emotes in vehicles, while dead, swimming or falling.
  * The list is wasteland_emotes/shared/emotes.lua (name, label, category, scenario or animation).
* Tests: 643.


## Named loot props (owner request)
* A prop an admin made lootable and named shows that name to players: the target says "Search Old barrel", the bar "Searching Old barrel", and the container opens as "Old barrel". Names can now have spaces (letters, digits, space, _ - . ' ( ), up to 40); the field is called "Name players see". Unnamed props still show their category.
* Tests: 635.


## Wrecks spawn on clear ground (owner request)
* Before a vehicle first appears, the nearest player's game checks its spot: no prop within 3.2 m, no other vehicle within 4.5 m, nothing solid across a car-sized box (walls, poles, fences, props), no steep ground. If blocked it is moved to the nearest clear spot within 12 m; a new wreck with no room at all goes to another spawn point. Checked once per vehicle (new column `wl_vehicles.spot_checked`, migration 3); vehicles players parked are only ever nudged, never sent elsewhere. If no player answers within 8 s, it appears where it is.
* vehicles.lua: `spotCheck = { enabled, radius, clearance }`. Vehicles admins spawn are placed as they are.
* Tests: 633.


## Admin loot target, health panel in the inventory (owner request)
* Admins: Left Alt on any prop, "Admin: loot container…": a small window to make that prop (every copy of its model) a loot container of a chosen category, with an optional prop name; Change / Remove for props added before. Only admins see the option (the client asks the server once a minute); the server still checks every request.
* Inventory: a Health panel (right column, under anything being looted) with a body outline (colour by health, green tint when infected, blood drops when bleeding, blue/orange edge when cold/hot, a plate when wearing armor), bars for health, food, water and armor, body temperature, and a list of what is wrong with how to fix it (the items that help come from survival.lua consumables).
* Survival client export `GetVitals()`; survival stats carry `cures` and `limits`.
* Tests: 630.


## Admin: prop names, own loot categories (owner request)
* "Looking at" shows a name where one is known: vehicles (their game name), props listed in loot.lua, and props you named when adding them (new optional "Prop name" box). GTA cannot turn a prop's model number back into its name, so other props show "(name unknown)".
* New Loot tab: make your own loot categories. Name, search time, refill time, size, chance it is empty, how many items per search, and the items it can hold (item, least, most, chance weight). Edit and delete them; deleting one stops its props being searchable. They show up in the Coords tab's "Loot as" list. Kept in wasteland_loot's KVP (loot.lua is not changed).
* Loot exports: `SaveLootCategory(id, def)`, `DeleteLootCategory(id)`; `AddContainerModel(hash, type, name?)`. Admin actions `lootTypeSave`, `lootTypeDelete`.
* Tests: 627.


## Admin: make any prop lootable (owner request)
* Admin panel, Coords tab, "Make it lootable": look at a prop, pick a loot container type (Dumpster / Trash can / Fridge / Vending machine / Tool chest / Crate / Mailbox / Wrecked vehicle, each with its loot table) and press "Add to loot". Every prop of that model on the map can then be searched by everyone, right away (no restart). "Change" and "Remove" for props added this way; a list of all of them. Props loot.lua already lists show "Already searchable".
* Kept in wasteland_loot's server KVP (survives restarts; loot.lua is not changed). Loot exports: `GetLootAdminData()`, `AddContainerModel(hash, type)`, `RemoveContainerModel(hash)`. Admin actions `lootAdd`, `lootRemove` (in the action log).
* Model hashes are handled signed and unsigned (target matching, loot lookup).
* Tests: 621.


## Loot in wrecked vehicles (owner request)
* New loot container "Wrecked vehicle": the rusted car, van, truck and bus wreck props on the map (prop_rub_carwreck_*, prop_rub_buswreck_*, prop_rub_trukwreck_*, ...). Left Alt on one: "Search wrecked vehicle" (6 s), shared, refills after 60 min. Loot table `wreck`: mostly scrap metal; rags, duct tape, wheels, jerry cans, engine parts, batteries, siphon hoses, lockpicks, a little cash and ammo.
* Containers can set `reach` (metres from the prop's middle; wrecks: 7) because big props are searched from their side. Stashes take the same `reach` option (inventory OpenStash).
* Admin panel, Coords tab: "Looking at" shows the model hash of the prop or vehicle in front of the camera (to find props that should be lootable).
* Tests: 615.


## Armor plates (owner request)
* New Armor slot in the inventory (Worn) and new items: Armor plate, Armor repair kit, Blueprint: armor plate.
* While a worn plate holds, all incoming damage is stopped: zombie hits (and they cannot cause bleeding; infection still can) and gunshots/blows from players (the client keeps GTA armour full and reports what the game took). The plate loses 0.25 durability per point of damage it stops (`survival.lua` armor.wearPerDamage): a new plate stops about 400 damage. At 0 it breaks ("Your armor plate broke...") and stops nothing until repaired. Falls and other damage the game does not put on armour still hurt.
* HUD: a shield icon shows the plate's condition while one is worn.
* Repair: Armor repair kit (+40%, used up): right-click the plate, "Repair with Armor repair kit", or use the kit (repairs the worn plate first). Sewing kits do not repair plates.
* Get them: crates (plate, kit, blueprint), tool loot (kit); gunsmith sells plates ($750) and kits ($150); craft plates with the blueprint (6 scrap metal, 2 duct tape, 2 rags), kits from the start (2 scrap metal, 1 duct tape).
* New item category `armor`; survival `Damage` export returns `ok, absorbed`.
* Tests: 613.


## Clothing durability and mending (owner request)
* Tops, pants, shoes, hats and glasses have durability (100). Every zombie hit wears out one worn piece (4-10, `survival.lua` clothing.hitWear). The inventory shows a condition bar (red at 25% or less), "Condition 64%" on hover and in the right-click menu; a ruined piece is greyed out and marked RUINED.
* Worn-out clothing keeps you less warm: full warmth when new, at least half while worn, none when ruined (until mended).
* New item: Sewing kit. Right-click a damaged piece: "Repair with Sewing kit" (or just use the kit: it mends the most worn piece you wear, then what you carry). One kit mends 50% (`clothing.repairItems`) and is used up. Found in trash and crates, sold by the general trader ($70), craftable from the start (2 rags + 1 scrap metal).
* Clothing from before this update counts as new.
* Inventory (for every module): item setting `repairs = '<category>'` makes the screen offer "Repair with ..." on damaged items of that category; usable handlers get the chosen item as a 4th argument (`targetUid`). `GetWornItems` now also returns uid, label, category and max durability.
* Tests: 606.


## Vehicle HUD: move and resize (owner request)
* /hud now also edits the vehicle HUD (shown with example values when you are not in a vehicle): drag it anywhere; resize it with the mouse wheel or the - / + buttons above it (60% to 180%); Reset puts it back at the bottom middle, normal size. Saving the HUD keeps it (stored on the player's computer, like the main HUD); Esc / cancel puts it back.
* survival sends the local event `wasteland:hud:editing(on, saved)` so other HUD pieces can join the edit mode.
* Tests: 599.


## Siphoning fuel (owner request)
* New item: Siphon hose (own picture). Left Alt on any vehicle with fuel: "Siphon fuel (hose)" drains the tank into a jerry can that is not full (up to the can's 20 L) in 10 seconds (`seconds.siphon`). The hose is kept. Works on locked cars too (the fuel cap has no lock).
* Found in garage/vehicle loot, sold by the general trader ($60, sells for $15).
* A driver sitting in a siphoned car sees the lower level at once.
* Trader positions at Sandy Shores taken from the live server config (moved by the owner).
* Tests: 598.


## Admin coords, removing your own car lock, lockpick minigame (owner request)
* Admin panel, new "Coords" tab: your position live (X, Y, Z, heading) with Copy buttons for `vector3(x, y, z)`, `vector4(x, y, z, heading)` and the heading alone; the last copied lines stay listed to copy again.
* Car locks: "Take the lock off" (Left Alt on the car) for the survivor who fitted it, and only them (stored per character, new column `wl_vehicles.lock_owner`, migration 2). The lock goes back into your pockets; the old key fits nothing any more. Locks fitted before this update: whoever holds the key can take them off.
* Picking a lock needs a lockpick and a minigame: a pick turns around the lock; press E, Space or click while it is in the green zone to set a pin. Set all 4 pins to open the car; one miss fails the try (the pick may snap, 50%). Each pin: a new zone, the other direction, faster. Esc gives up. Settings in vehicles.lua `lockpick` (`pins`, `zoneDegrees`, `speed`, `speedStep`, `breakChance`, `noise`); the old `chance` setting is gone. The server times the game (results faster than `minSecondsPerPin` per pin are rejected) and checks distance, lockpick and lock again.
* Tests: 595.


## Milestone 10A: admin tools
* New "Live" tab: players online, zombies alive, vehicles (in the world / out right now), gas pumps refilling, containers searched, uptime, module health and the latest warnings and errors; refreshes every 5 seconds while open.
* Server & world tab, world tools: spawn 1-20 zombies around you, clear all zombies, spawn a wreck or a working car in front of you, fix the car you sit in (or the nearest within 8 m), refill every gas pump, teleport to your map waypoint.
* Debug overlays (only for the admin who turns them on): zombie AI (kind and what it is doing), vehicles and wreck spawn points, camp borders, loot containers around you.
* Player tools: spectate, give and take cash, the player's jobs (drop one, reset cooldowns), recipes (teach or forget a blueprint recipe), send to the nearest camp.
* New exports: zombies `SpawnNear`, `GetZombieMode` (client); vehicles `GetVehicleStats`, `FixVehicle`, `SpawnWorking`, `RefillPumps`, `GetSpawnPoints`; loot `GetLootStats`, `GetContainerModels`; quests `GetQuestSummary`, `DropQuest`, `ResetCooldowns`; crafting `GetRecipeSummary`, `ForgetRecipe`.
* Tests: 587.


## Loading screen (owner request)
* wasteland_loadscreen 0.1.0: WASTELAND title and tagline, what the server offers (the dead, survival, scavenging, crafting, weapons, camps, vehicles, jobs), rotating survival tips, a typed-out survivor's log, outbreak counters, and an animated scene (ruined skyline, moon, fog, falling ash, zombies shambling along the bottom). The loading bar follows FiveM's real progress. One self-contained page: nothing to download, works offline.


## Gas pumps: level shown, full again after 2 hours (owner request)
* Standing next to a gas pump shows above it: "Fuel: 35 / 80 L" and "Full again in 1 h 24 min" (or "Full").
* Refill rule changed: a pump is full again 2 hours (real time) after fuel was first taken from it; taking more meanwhile does not restart the clock (`pump.refillMinutes = 120`; the 20 L every 15 minutes rule is gone).
* Tests: 571.


## Gas pumps: refuel at the pump, limited fuel (owner request)
* Park within 8 m of a gas pump, hold Left Alt on the pump: "Refuel vehicle" fills the nearest vehicle straight from the pump (4 L a second; no jerry can needed). "Fill jerry can" is still there.
* Every pump holds 80 L, shared by everyone (vehicles and jerry cans), and gets 20 L back every 15 minutes up to full. A dry pump says when it refills; a pump with little left gives what it has. All numbers in vehicles.lua (`pump`). Pump levels are kept in memory (full again after a restart).
* Fix: vehicle database writes after an action (parts, refuelling, locks, repairs) waited for the database inside a network event and failed; they only reached the database with the next 30-second save. Every vehicle write now runs in its own thread, and the tests fail on any handler error.
* Tests: 570 (new: pump refuel, dry pumps, refills, distance checks, pump rules).


## Vehicle HUD (owner request)
* While in a vehicle (any seat), bottom middle: speed in mph, fuel gauge with litres, engine and body condition (green, yellow at 35% or less, red at 15% or less), Locked / Unlocked for vehicles with a lock, and the reason a car will not run ("There is no battery.", "The tank is empty.").
* Tests: 566.


## Vehicles: never lose a car on relog or restart (owner request)
* Players already come back where they left (their position is checked every 10 s, saved every 60 s and when they leave). Vehicles are now saved as reliably:
  * when the driver gets out (position, damage, the last fuel used), right away;
  * when a player leaves the server (every vehicle that is out);
  * on a server stop or txAdmin restart: one final save that the database finishes on its own (before, the final save waited for the database, which a stopping resource cannot do, so it could be lost; then only the 30-second save counted).
* Tests: 564.


## Milestone 9: persistent vehicles

### wasteland_vehicles 0.1.0 (new)
* 30 abandoned wrecks at 22 spots around the map (Sandy Shores, Grapeseed, Route 68, Paleto Bay, Los Santos, Senora). Nobody owns a vehicle. Each is stored in the database (wl_vehicles) and stays where it was left; the car appears when a player is within 250 m.
* A vehicle needs engine parts, a battery, four wheels, fuel and an engine that is not wrecked. Wrecks miss parts by chance and have little fuel.
* Hold Left Alt on a vehicle: Check vehicle, Open trunk, Install battery, Fit engine parts, Mount a wheel, Refuel (jerry can), Repair (toolkit), Fit a lock, Lock / unlock (key), Pick the lock. Each takes a few seconds (moving cancels); the server checks and does it.
* Fuel: 50 L tank, used while driving (idle and per km); jerry cans (20 L) are filled at gas pumps (Left Alt, "Fill jerry can").
* Trunk: every vehicle has a 6x5 trunk that stays with it.
* Locks (owner request): a car lock locks the vehicle and makes the only key; whoever carries the key can lock, unlock and open the trunk. Without it, a lockpick opens the lock 30% of the time (and breaks it off), snaps half of the times it fails, and the noise draws zombies.
* Destroyed vehicles are gone (record and trunk); new wrecks appear over time.

### Other
* Items: car battery, engine parts, wheel, jerry can, toolkit, car lock, car key, lockpick (pictures from the pack). Sold by the general traders, found in tool chests, crates and trash; lockpicks can be crafted from scrap (known from the start).
* Inventory: `FindItems(source, name)`; stashes that move (trunks) take their current position when opened.
* Zombies: react to any `wasteland:noise(coords, radius)` (lock picking), not only weapons.
* Tests: 560 simulated + 24 on real MariaDB (new: vehicle rules, wrecks, spawning, saving, parts, fuel, repairs, locks, keys, lock picking, trunks, destruction, restarts).


## Milestone 8: quests

### wasteland_quests 0.1.0 (new)
* Jobs from camp traders: hold Left Alt on a trader, "Jobs". The board shows the camp's jobs: what to do, the reward, and New / In progress / Ready to hand in / Done (again in N min).
* Objectives: bring items (counted live, taken at hand-in), kill zombies (anywhere or near a place; only your own kills), go to a place (checked by the server), search loot containers of a type, craft something.
* Up to 3 jobs at once; repeatable after a cooldown. Hand-in at a camp that offers the job: the reward must fit first, then the items are taken; cash and items as rewards.
* Tracker on the right of the screen with each job's progress; job places are marked on the map with a route to the first one.
* 8 jobs: Scrap run, Food drive, Thin the herd, Field dressings, Crate scavenger (every camp); Check the airfield (Sandy Shores), Check the sawmill (Paleto Bay), Clear Pillbox Hospital (Legion Square).
* Exports `GetActiveQuests`, `AddProgress`; event `wasteland:quests:completed`.

### Other
* Zombies: the client reports who killed a zombie (checked: a player near the body); `wasteland:zombies:died` now also passes the killer and the position.
* Camps: `GetCamps` includes the traders' positions.
* Tests: 535 (new: quest rules, every objective type, hand-in, rewards, cooldowns, limits, persistence, board; a test that boots every module with the shipped config files).


## Milestone 7B: crafting

### wasteland_crafting 0.1.0 (new)
* Craft anywhere: key K (or /craft, or the "Crafting (K)" button in the inventory). The screen lists every recipe you know, what it needs (red when you lack it) and how many recipes are left to learn.
* Crafting takes a few seconds with an animation and a progress bar; moving, getting hurt, dying or X cancels. The server takes the materials and gives the result in one go (everything back if the result does not fit).
* Known from the start: rags (tear a top) and bandages (from rags). Learned from blueprints found while looting (rare): weapon repair kit, knife, hatchet, machete, crowbar. Use a blueprint in the inventory to learn its recipe for good (stored with the character).
* Exports `KnowsRecipe`, `TeachRecipe`; events `wasteland:crafting:learned`, `wasteland:crafting:crafted`.

### Other
* Inventory: 5 blueprint items (pictures from the pack); blueprints added to the trash, tools, crate and zombie loot tables; Crafting button in the inventory screen.
* Tests: 514 (new: recipe rules, learning, crafting, materials, timing, no room, persistence, screen).


## Milestone 7A: camps, safe zones, traders

### wasteland_camps 0.1.0 (new)
* Three camps: Sandy Shores, Paleto Bay, Legion Square. Each is a safe zone shown on the map (green circle + marker); entering shows "<camp> - safe zone", leaving "Leaving <camp>".
* Zombies never spawn inside a camp, ones that wander in are removed, they stop chasing players who are inside, and cannot hurt them there.
* Traders (NPCs, hold Left Alt, "Trade"): general trader and medic in every camp, a gunsmith in Sandy Shores. Buy and sell for cash; each item has a stock that refills every 10 minutes; selling to a trader raises its stock. Every trade is checked by the server (at the trader, stock, cash, room in the inventory; money back when the items do not fit).
* Exports `IsInSafeZone`, `GetCampAt`, `GetCamps` (server; `IsInSafeZone` also on the client); event `wasteland:camps:traded`.

### Fixes
* Zombies: `/zombies spawn` checked the spots against the normal 70-140 m ring and refused them all; it now uses the 15-35 m ring it asked for.
* Tests: 497 (new: camp zones and trade rules, trading, safe zones with zombies, trade screen).


## Inventory: carry more, double-click to take (owner request)
* Weight limits raised: pockets 35 kg (was 12), small backpack 35 kg (was 15), hiking backpack 60 kg (was 30).
* Double-click an item in a searched container (or a bag on the ground, a stash) to take it into your inventory: it tops up a matching stack first (ammo onto ammo), then uses free space in your pockets, then your backpack. Double-click one of yours to put it back into the open container. Shift-click still works.


## Milestone 6: looting

### wasteland_loot 0.1.0 (new)
* Every dumpster, trash can, recycling bin, fridge, vending machine, tool chest, wooden crate and mailbox on the map can be searched (hold Left Alt, "Search ..."). Dead zombies are searched the same way ("Search body"), instead of dropping a loot bag.
* Searching takes 3-5 seconds with an animation and a progress bar; moving, getting hurt, dying or X cancels. Then the container opens next to the inventory and you take what you want.
* Containers are shared: what one player takes is gone for everyone. A container refills only once it is empty and its time has passed (40-90 minutes). A body's loot is gone with the body.
* Scarce loot: many containers are empty; mostly junk; food and medicine uncommon; guns rare (crates, bodies). Every table, chance and time is in `loot.lua`.
* Export `RollTable(name)` for other modules (quests, rewards); event `wasteland:loot:searched(source, type, stash)`.

### Other
* wasteland_inventory: `EnsureStash`, `DeleteStash`, `OpenStash` option `open` (shows the screen).
* wasteland_zombies: zombies have a unique id (`wlZombie.uid`), export `GetZombieInfo`, event `wasteland:zombies:removed`; no loot bag while wasteland_loot runs.
* Tests: 475 (new: loot rules, searching, sharing, refills, bodies, abuse).


## Target system, admin item list, zombie reach (owner requests)

### wasteland_target 0.1.0 (new)
* Hold Left Alt: an eye appears in the middle of the screen. Look at something with options: they appear beside the eye; scroll to choose, click or E to use. Rebindable in the GTA key settings (FiveM section).
* For other resources (client exports): `AddModel`, `AddEntity`, `AddNetId`, `AddGlobal('ped'|'vehicle'|'object'|'player')`, `AddSphere`, `AddBox`, `Remove`, `IsTargeting`. Options: `label`, `icon`, `distance` (default 2.5 m), `canInteract(entity, distance, coords)`, and `onSelect(data)`, `event` or `serverEvent`. Registrations disappear with the resource that made them.
* Bags on the ground and body bags are searched through the target ("Search ..."); without wasteland_target the "Press E" prompt still works.

### Other
* Admin panel: the item picker is a dropdown listing every item on the server by category, with pictures and a search box.
* Zombies reach further: attack range 2.6 m (was 1.7 m).
* Tests: 453 (new: target matching and screen, item grouping).


## Milestone 5B: zombies

### wasteland_zombies 0.1.0 (new)
* The server keeps zombies around every living player (8 by day, 12 at night; at most 60 in the world), 70-140 m away, topping up every 6 seconds. The player's game finds spots on the ground; the server checks every spot (ring around the player, not next to anyone) and creates the zombie itself.
* Walkers (drunk shuffle) and runners (15% by day, 30% at night). GTA ambient models (tramps, meth heads, GTA's own zombie) with blood and dirt; silent.
* AI runs on the client that owns each zombie: wander; notice players by sight (35 m by day, 18 m at night, needs a clear line) and sound (sprinting 25 m, walking 9 m, crouching 3 m; vehicles are loud); chase; attack; give up after 10 s without seeing or hearing them.
* Gunshots: every zombie within the weapon's noise radius (pistol 120 m, rifles 250 m...) walks to the shot.
* Hits are decided by the server (zombie owned by the reporting client, alive, close, cooldown): 6-10 damage (runners 5-8), a 25% chance of infection, a 15% chance of bleeding (survival).
* Dead zombies lie 90 seconds; 25% leave "Zombie remains" with a little loot (cash, ammo, bandage, food, scrap). Zombies far from everyone disappear.
* `/zombies count | clear | spawn <n>` (admin). Exports `GetZombieCount`, `SpawnZombie`, `ClearZombies`; events `wasteland:zombies:died`, `wasteland:zombies:hit`.

### Other
* wasteland_inventory: `CreateLootDrop(coords, items, opts)`. wasteland_survival: `Damage(source, amount)`.
* Tests: 441 simulated (new: zombie rules, population, hits, noise, loot, despawning, admin, abuse); the mock simulates server-created entities.


## Cash, HUD info line, stamina bar (owner request)
* Cash is an item (`cash`, weightless, stacks to 1,000,000, picture `cashroll`) and the only money: no bank. It is carried in pockets or a worn bag, can be dropped, handed over and looted, and goes into the body bag on death like other items (unless on the hotbar). Inventory exports `GetCash`, `AddCash`, `RemoveCash`; config `cashItem` in inventory.lua. Tiles show cash as `$1,250`. Inventory and admin limits for one action raised to 1,000,000 for cash.
* HUD: a line with the player's server id, character name and cash above the icons (moves with the HUD).
* Stamina: a small bar at the bottom middle of the screen, only while stamina is used; it fades out when full.
* GTA's green/blue health and armour bars under the minimap are hidden.

## HUD redesign (owner request)
* The survival HUD is now four green outlined icons in the bottom-right corner that drain like a liquid level: health (drop), food (tray with fork and knife), drink (bottle), temperature (thermometer, 33-39 °C). They turn amber at 35% or below (or cold/hot) and red and pulsing at 15% or below. Bleeding and infection show as small badges under the icons. Stamina is no longer shown (GTA shows its own).
* `/hud` opens edit mode: drag the HUD anywhere, choose Always / When it matters / Off, Row or Column, size S/M/L; Save keeps it on the player's PC (each player their own), Cancel or Esc keeps the old one, Reset returns to the bottom-right corner.

## Item pictures (owner request)

### wasteland_images 0.1.0 (new)
* All 3,474 pictures of the community MK-Items pack (3,485 files; same-name files kept with a folder suffix), converted to WebP and scaled down where oversized (187.7 MB of PNG -> 19.3 MB, empty borders trimmed so long items fill their tiles). `tools/import_images.py` re-imports a pack.
* Inventory: tiles show the item's picture (it turns with rotated items); items can pick a picture with `image = '...'`, otherwise the picture named like the item is used. 22 items mapped to pictures; most weapons, water and bandages match by name. Admin panel shows the chosen item's picture.


## Milestone 5A: weapons

### wasteland_weapons 0.1.0 (new)
* Weapon items: use (hotbar key) to draw, use again to put away. Knife, baseball bat, crowbar, hatchet, machete, pistol, heavy revolver, sawed-off and pump shotgun, micro SMG, SMG, carbine, assault rifle, hunting rifle.
* Ammo comes from the inventory: 9mm, .44, 12 gauge, 5.56, 7.62, .308. Every shot uses a round; picking up or dropping ammo updates the gun at once.
* Durability: every shot or melee hit wears the weapon; a broken weapon cannot be used until it is fixed with a weapon repair kit (40% per kit).
* GTA's own weapon switching (wheel, scroll, weapon-slot keys) is off; weapons come only from the inventory.
* Gunshots and hits announce their noise (`wasteland:weapons:used`) for the zombies in 5B.

### Other
* wasteland_inventory: `FindItem`, `SetItemMetadata`, server event `wasteland:inventory:playerUpdated`; the crowbar is now a melee weapon.
* Fixes: worn clothing that carries no look (given or looted) shows a plain outfit instead of nothing; searching a drop with E no longer freezes the game.
* Stacks (owner request): items stack to 50 by default; bandages, painkillers, rags, energy bars and scrap metal to 100; 9mm, 5.56 and 7.62 rounds to 250, other ammo to 100. Weapons, tools with durability, backpacks and clothing still never stack (each carries its own wear, contents or look). Weight limits still apply.
* Tests: 403 simulated (new: weapons, stack defaults).


## World and admin (owner requests, brought forward from Milestones 7 and 10)

### wasteland_world 0.1.0 (new)
* One server clock (48-minute day by default) and one weather for everyone (dynamic, weighted, transitions), with exports to control them.
* Empty world: no pedestrians, traffic, parked cars, police, trains or boats (OneSync population off for bucket 0, plus client density).
* Silence: no ambience, music or radio, police scanner, distant sirens or music emitters. Gameplay sounds are kept. Everything is switchable in `world.lua`.

### wasteland_admin 0.1.0 (new)
* Admin panel (F10 or `/admin`) with Players, Bans, Server & world, and Action log tabs. Every action is checked on the server and logged to `wl_admin_log`.
* Players: teleport to, bring, heal, revive, freeze, kick, ban, set survival stats, give items, open or clear inventory.
* Bans by player or license, timed or permanent, stored in `wl_bans`, checked on connect, can be lifted.
* Server: module status, recent warnings and errors, announcements, time and weather, noclip and invisibility.

### Other
* wasteland_players: `RegisterAdmissionCheck` (other modules can refuse connections; a broken check never locks players out).
* wasteland_survival: `Heal`, `Revive`. wasteland_inventory: `OpenForAdmin`, `ClearInventory`, `GetItemList`, and a client "open" event.
* Tests: 383 simulated + 22 on real MariaDB (bans, action log).

## Milestone 4: survival, HUD, death and respawn

### wasteland_survival 0.1.0 (new)
* Server-owned hunger, thirst, bleeding (3 levels, from hard hits, clotting), infection (grows, treatable, lethal at 100) and body temperature (weather, time, altitude, wet, clothing warmth). The rules are pure functions in `shared/model.lua`. Moderate pace by default: food 2 h, water 1.5 h.
* Consumables from config (food, drink, bandage, rag, painkillers, antibiotics), used through the inventory, with eat, drink and treat animations. Items that would do nothing are refused and kept.
* Death: everything except hotbar items goes into a body bag (map marker for the owner, 2 h lifetime). There is a "You died" screen with a countdown, and respawn happens at a random configured point with reset stats. spawnmanager autospawn is off.
* HUD (bottom left): compact, only when it matters, or off (`/hud`, remembered per player).
* Exports: GetStats, AddInfection, AddBleeding, ModifyStats, IsDead. Events: wasteland:survival:died and respawned.

### wasteland_inventory
* DeathDrop export (body bags), GetWornItems, the item field `warmth`, and migration 3 (drop owner, label and expiry). New survival items in config.

### Tests
* 341 passing: survival rules (unit), survival server (integration), body bags, HUD logic (Node), and body bags on real MariaDB.

## Milestone 3B: inventory and item API

### wasteland_inventory 0.1.0 (new)
* Tetris-style grids: items have a size and can be rotated; weights; stacks; durability; metadata.
* Pockets (6x4, 12 kg), worn items (head, eyes, torso, back, legs, feet), backpacks that add their own grid when worn (never nested).
* Operations: move, rotate, merge, split, wear (with swap), take off, drop, use, hotbar (keys 1-5). All decided by the server, atomic, saved as one transaction each in an ordered write queue; refused while the database is down.
* Items on the ground (stored, visible as bags, E to search, expire after 60 minutes) and stashes for modules (`OpenStash`).
* Clothing as items: the starting outfit from the creator becomes worn clothing; empty slots show configurable "naked" parts.
* Exports: AddItem/RemoveItem (all or nothing), GetItemCount, RegisterItem, RegisterUsable, OpenStash, GetInventory, GetItemDefinition, IsLoaded. Admin `/give`.
* Inventory screen (key TAB): drag and drop with placement preview, R to rotate, right-click menu, shift-click quick move.

### Other
* wasteland_appearance: fires `wasteland:appearance:saved` (server) and `wasteland:appearance:client:applied` (client); client export `IsEditing()`.
* Tests: 302 (grid unit tests, 30 inventory integration tests incl. duplication, races, forged requests, disconnects and database failures, 6 Node tests for the screen, inventory SQL on real MariaDB).

## Milestone 3A: UI shell, character select, character creator

### wasteland_ui 0.1.0 (new)
* NUI shell with a screen manager: modules open screens whose scripts live in their own resource; actions come back as `wasteland:ui:client:action`; NUI focus handled per screen; screens of stopped resources close automatically; screen errors are printed in F8.
* Design system (`style.css`) and DOM helpers (`h`, `button`, `slider`, `picker`, `tabs`).

### wasteland_players 0.2.0
* Character select screen (create, play, delete with name confirmation) using wasteland_ui; the chat command remains as a fallback.
* The player is held (frozen, invisible, no collision) until a character is loaded (K-15).
* A new character is played immediately after it is created.
* The character state bag is replicated to the player's own client; `requestCharacters` from the screen no longer sends chat lines; the create result includes the slot and character id; client export `IsReady()`.

### wasteland_appearance 0.1.0 (new)
* Character creator: male/female freemode, heritage, 20 face features, hair and colours, eye colour, 13 overlays (beard, eyebrows, makeup, ageing, ...), starter clothing (top, undershirt, arms, legs, shoes, hat, glasses), live preview, fixed camera with rotation.
* Opens automatically for characters without a look; admin command `/appearance <id>` reopens it (cancellable).
* Server-side validation (schema, allowed slots, `blockedClothing`), write-through save, applied on load and after every respawn.

### Tests
* `tests/integration/appearance.lua` (18) and `tests/js/ui.test.js` (14, Node) run from `tests/run.lua`. 248 tests pass.

## wasteland_players 0.1.1 (runtime fix, 2026-10-10)

### Fixed
* Every connection was refused with "Unknown error" (runtime test R2.5): the players module called `deferrals.done(nil)` to accept, which FiveM treats as a rejection. It now calls `done()` with no argument. The test mock reproduces FiveM's behaviour (K-16).

## Milestone 2: database and player persistence (2026-10-10)

### wasteland_core 0.2.0 (core api 1.1.0)
* **Added** module health: `ReportModuleHealth` export and `M.setHealth()` in the SDK. Running modules can report `degraded` with a detail, which shows as `DEGRADED: ...` in `wasteland status` and `wasteland module <name>`. New event `wasteland:core:moduleHealth`.
* **Added** the net-event guard `M.netEvent(name, { args, rateLimit }, handler)`. It checks the sender, that the module is running, a per-player and per-event rate limit, and validates each argument against a schema. Rejections are logged (throttled) and reported as `wasteland:core:netViolation`.
* **Added** `server/security.lua`: counts guard violations and kicks after `framework.security.kickAfterViolations` (default 0 = never) within `violationWindowSeconds`.
* **Changed** the dependent-restart fix from 0.1.1 now applies to every module resource, not only the core: restarting `wasteland_database` brings `wasteland_players` back.

### wasteland_database 0.1.0 (new)
* oxmysql driver (verified against oxmysql v2.14.3 source), request layer with timeouts, slow-query warnings, fail-fast while down, and safe callbacks.
* Startup fails with a precise reason when the driver is missing, not started or not connected. Runtime health checks mark it degraded and broadcast `wasteland:database:health`.
* Per-module, numbered, checksummed, forward-only migrations (`wl_migrations`).
* `lib/db.lua`: await-style `WDB.query/single/scalar/insert/update/transaction/migrate/isUp` for module resources.

### wasteland_players 0.1.0 (new)
* Accounts per Rockstar license (no IPs stored), sessions with admission checks (license, database, duplicate sessions: `kick_old` or `reject_new`).
* Multiple character slots (`maxCharacters`, default 3): create with validated names, select, switch, soft delete with name confirmation.
* Per-character module data (`Get/SetCharacterData`, JSON, size limit) and `SaveCharacter` for write-through.
* Saves: periodic, final save on unload/drop/switch/stop/txAdmin shutdown. The account stays locked until the final save succeeds, and failed saves are retried.
* Restores sessions and characters after `restart wasteland_players` (via player state bags), without moving the player.
* Interim chat command `/character list|create|select|delete` and guarded net events for the future UI.

### wasteland_config
* New `database.lua` and `players.lua`. `framework.lua` gains a `security` section.

### Tests and tools
* Mock: promises/`Citizen.Await`, players with connection deferrals, state bags, net events, JSON, a simulated oxmysql and an in-memory database.
* New suites: netguard, database, players, and the real-database suite (`tests/db/mariadb.lua`, runs the real SQL on MariaDB when `tests/db.env` is configured). 206 tests pass (192 simulated + 14 on MariaDB 11.6).
* `tools/backup_database.ps1`, `docs/DATABASE.md`, `.luarc.json` (FiveM globals for the Lua language server).

## 0.1.1 (core), runtime fix from in-game testing

### Fixed
* `restart wasteland_core` left every module resource stopped, because FiveM stops dependents but does not restart them (found in runtime test R1.7). The core now restarts exactly the module resources its own stop took down. Controlled by the new `framework.restartModulesAfterCoreRestart` setting (default `true`).

## 0.1.0 (Milestone 1: architecture and foundation)

### Added
* `wasteland_core` 0.1.0 (core api 1.0.0): module registry with semver dependency resolution, optional dependencies, cycle detection, async modules, cascade stop and re-init; sandboxed configuration loading with schema validation and precise errors; levelled logging with a recent-issues buffer; startup window and status report; ordered, idempotent shutdown (resource stop and txAdmin shutdown); `wasteland` admin command with ACE check and audit logging; Module SDK.
* `wasteland_config` 0.1.0: framework.lua, modules.lua, logging.lua, template.lua.
* `wasteland_template` 1.0.0: example and template module.
* Automated test suite (static, unit and simulated integration) with a multi-resource FiveM mock.
* Documentation: architecture, conventions, module API, testing, in-game test procedure, known issues, project status.
