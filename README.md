# Allain Automation — Keyless Scripts by Allain

Keyless automation scripts for Roblox. One loadstring works for every supported game: it detects which game you're in and loads the right script.

| Game | Version |
| --- | --- |
| Break and Steal an Egg | v3.3.2 |
| Steal a Balut | v0.2 (beta) |
| Run a Sari-Sari Store | v0.2 (beta) |
| Ride a Pet | v0.1 (beta) |

## How to run

Paste this into your executor and run it while in a supported game:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Allain-afk/Allain-Hub/main/loader.lua"))()
```

Press **RightShift** to show or hide the menu (you can change this in the **Config** tab).

## Break and Steal an Egg

### Features

**Automation**
- **Zone Auto-Farm**: runs to eggs in the zones you pick (one or several) and breaks them with the in-game Auto Swing. Filter by egg type, minimum luck (accepts K/M/B/T/Qa, e.g. `500B`) and priority (closest, highest luck, lowest HP).
- **Auto-Take Hatched Pets**: runs to a hatched pet's Steal prompt, takes it with E and carries it back to your plot. It ignores guards and retries every 2s until the pet is banked, then switches back to the pickaxe. Filter by pet, rarity and minimum Cash/s, or only take pets that earn more than the worst pet on your plot.
- **Guard avoidance** (egg farming): skips eggs near guards and backs off when a guard chases you.
- **Pickaxe guardrail**: switches back to your pickaxe (hotbar slot 1) if you're holding something else.
- **Auto-Progression**: equips your best pet, buys pickaxes and trails, and upgrades your plot and treadmill when you can afford them. It also turns on the in-game Auto Swing.

All movement uses your character's normal in-game speed. The script never changes WalkSpeed and never teleports.

**Eggs**
- **Auto-Merge Pets**: merges 3 of the same pet from your inventory at the Merge Machine (never touches pets placed on your plot), with species/rarity filters, protected traits, Keep Heaviest Per Species, Preview Merges (showing combined KG and estimated post-hatch Cash/s), and automatic placement of merged eggs on your plot.
- **Merge Eggs & Merged Egg List**: live list of every growing and ready merged egg on your plot (plus unplaced merge eggs in your inventory) with its species, `WeightKg`, **calculated post-hatch Cash/s** (calibrated live from your plot's `PlacedAnimals` to include your active Wealth Mastery, Index, Friend Boost, and Cash multipliers), countdown timer, total post-hatch Cash/s, and optional 3D overhead timers.
- **Special Eggs**: Interrupt Farm for Titanic Eggs (30x luck) and Prioritize Lucky Eggs.
- **Egg ESP**: highlight high-luck eggs through walls with rarity colors, minimum luck filter, and optional chams.

**Visuals**
- Player, pet, egg and guard ESP, with rarity colors and Cash/s filters.

**Alerts & Power**
- Anti-AFK (WASD mover) and auto-reconnect.
- Low Power mode (stops 3D rendering; FPS cap optional).
- FPS Boost: Unlock FPS, Potato Mode (plain materials), optional pet-texture removal, no shadows / effects / particles, lowest graphics quality. Everything is restored when turned off.
- Discord webhook alerts for rare pets (with a follow-up saying who took them), missed wanted pets (with the reason), progress reports and farm summaries (including your 5 most recent pets banked at your plot).

### Default keybinds

| Key | Toggles |
| --- | --- |
| RightShift | Menu |
| H | Zone Auto-Farm |
| Q | Anti-AFK mover |
| T | Player ESP |
| P | Pet ESP |
| G | Egg ESP |
| L | Low Power mode |

Change any keybind in the menu. Your settings are saved automatically.

## Steal a Balut

### Features

**Automation**
- **Egg Auto-Farm**: runs to baluts and breaks them with the in-game Auto Swing (or by clicking with your Asarol). Filter by zone, rarity and max HP; pick the closest, lowest HP or highest rarity egg first.
- **Auto-Steal Pets**: runs to wild pets, holds E on them and walks them home to your base. Filter by rarity and minimum income; pets that would despawn before you get there are skipped.
- **Always Take Pets I Hatch**: takes the pet from every egg the farm breaks, even with only Egg Auto-Farm on.
- **Auto Equip Best** after each pet reaches your base.
- **Auto Equip Best Asarol**: equips your strongest owned Asarol before farming, since your Asarol's power sets your egg damage. The first time, it equips each Asarol once to measure it, then remembers the results.
- **Guard avoidance**: skips eggs and pets near guards and backs off when a guard is alerted or chasing.
- Gets off the Trisikad before walking.

All movement uses your character's normal in-game speed. The script never changes WalkSpeed and never teleports.

**Visuals**
- Egg ESP (rarity, HP, zone) and wild pet ESP (rarity, income, mutation, time left), with a rarity filter.

**Alerts & Scan**
- Rare wild pet alerts (in-game and Discord), and an optional Discord message for each stored pet.
- Game Data Scan: sends the game's structure and a live capture of your actions to a Discord webhook as a .txt file.

### Default keybinds

| Key | Toggles |
| --- | --- |
| RightShift | Menu |
| H | Egg Auto-Farm |
| J | Auto-Steal |
| G | Egg ESP |
| P | Wild Pet ESP |

## Run a Sari-Sari Store

Beta. Store actions use the same prompts and buttons a player uses.

### Features

**Customers**
- **Auto Serve**: taps the shelves for each item the customer at your counter asks for.
- **Auto Checkout**: rings up finished orders and gives the exact change, and confirms KashG payments (optional).
- **Auto Answer Pay Later (beta)**: accepts or declines utang requests.

**Store**
- **Auto Open 24/7**: flips your sign back to Open whenever the store closes, including at night.
- **Auto Clean**: grabs the broom when there's dirt and sweeps every pile.
- **Auto Collect Piso WiFi** and **Return to Store When Idle**.
- **Auto Hit**: throws your weapon (Tsinelas, Kawali, ...) at your sleeping workers, and at thieves, runners and scammers near your store (beta).

**Stock**
- **Auto Pick Up Order Boxes** from your truck bay.
- **Auto Restock**: fills shelves below a set level from the boxes you carry.
- **Auto Order**: orders a box of each product that runs low, keeping a minimum balance. Counts shelves, carried boxes and waiting deliveries.
- **Auto Trash Empty Boxes (beta)**.

**Player**
- Walk speed, jump power, noclip and fly (WASD, Space up, Left Ctrl down).
- FPS Boost: Unlock FPS, Potato Mode, no shadows / effects / particles, lowest graphics quality. Everything is restored when turned off.
- Anti-AFK.

**Alerts & Scan**
- Discord webhook: store summaries, level-ups and shoplift alerts.
- Game Data Scan, Deep Scan and Live Capture for building new features.

Coming next: Auto E-Load, Auto Pay Electricity Bill, Auto New Branch, Auto Unlock Licenses, Auto Shelf / Buy Best Value.

### Default keybinds

| Key | Toggles |
| --- | --- |
| RightShift | Menu |
| H | Auto Serve |
| J | Auto Restock |
| F | Fly |

## Executor requirements

- `loadstring` and `game:HttpGet` are required.
- Simulated input (`VirtualInputManager`) is used for Auto-Take (holding E) and the pickaxe guardrail.
- `request` / `http_request` is needed for Discord webhooks.
- `queue_on_teleport` is needed for auto-reconnect.

## Credits

Script by Allain. The UI is built on the Obsidian / Alexandria UI library by deividcomsono (MIT license, see `LICENSE`; docs: https://docs.mspaint.cc/obsidian).

## Ride a Pet

Beta. Early version while the game is being mapped out.

### Features

- **Egg ESP**: shows every wild egg on the map through walls, even ones too far away to have loaded, with rarity colors, mutation, weight and distance. Filter by rarity, egg name or mutated only; the nearest 30 loaded eggs are highlighted. Max distance up to 20,000 studs.
- **Anti-AFK**: prevents the 20-minute idle kick.
- **Data Scan**: sends the game's structure to your Discord webhook for new features.
# Allain-Hub
