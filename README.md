# Zyde Forever

A quality-of-life addon for **World of Warcraft: Forever**: the classic world on the modern game client (Interface 16001). It cleans up the interface, adds reminders for warriors and hunters, makes questing and gearing smoother, and includes **GearAdvisor**, a gear upgrade scorer for your class and spec.

Every feature can be turned on or off on its own. Type `/zyde` in game to open the options window.

## Installing

1. Download this repository (Code → Download ZIP) and unzip it.
2. Rename the folder to `Zyde_Forever` if it isn't already, and put it in
   `World of Warcraft\_forever_\Interface\AddOns\`.
3. Restart the game (not just `/reload`: the game only picks up new files on a full restart).
4. Type `/zyde` to choose which features you want.

### Works with (optional)

| Addon | What it adds |
|---|---|
| [Questie](https://www.curseforge.com/wow/addons/questie) | Needed for Questie drop chances and quest mobs nearby; also improves the quest tracker and quest object alert |
| AHledger | Needed for vendor / auction advice; adds auction prices to the scrap list |
| Zygor Guides | Needed for the Zygor target keybind |
| NodeSight Sparkles | Sparkles on quest objects and nodes |
| LootTriage | When enabled, it replaces Zyde's scrap list |

## Features

### Interface
- **Unit frames**: flat, clean player, target, pet, party and raid frames.
  - Buffs and debuffs like the game's own frames: the target's debuffs (yours first) and buffs, your debuffs and buffs, with time left. (Can be turned off in `/zyde`.)
  - Party frames show each member's mana, rage or energy.
  - Optional target of target frame (on in the `/zyde` window).
  - Shift-drag any frame to move it (out of combat).
  - The target's cast bar.
  - Hunters get a pet frame with a happiness face, the pet's buffs and an XP bar.
- **XP readout**: a small, draggable XP % in place of the XP bar, showing rested XP and time to level. Hunters also see their arrow or bullet count here.
- **Reminder icons**: icons to the right of your character. Shift-drag any icon to move the column.
  - **Warrior:** Battle Shout missing or running out, Overpower / Execute / Revenge / Victory Rush ready, Thunder Clap missing on your target, wrong stance, Sunder stacks while tanking.
  - **Hunter:**
    - no Aspect, or Cheetah / Pack on in combat
    - Hunter's Mark missing (solo only)
    - target **too far or too close** to shoot
    - Mongoose Bite ready, Mend Pet needed
  - **Shaman:**
    - weapon imbue missing or under a minute left
    - Lightning Shield missing or on its last charge (in combat, or with an enemy targeted)
    - Earth Shock ready while your target casts something you can interrupt
    - a totem out of range (you no longer have its buff)
    - no Ankh when you can Reincarnate
  - **Everyone:** Well-Rested running low, gear needing repair, low on food or water.
- **Hide Blizzard bar art**: removes the action bar art, bag bar and micro menu.
- **Tidy action bars**:
  - Short keybind labels: `a-1` becomes `A1`, Mouse Button 4 becomes `M4`.
  - Empty slots are hidden, and show again while you drag a spell or item.
- **Character screen gear**:
  - Rarity borders and item levels on your gear.
  - A green arrow on a slot when your bags hold an upgrade for it.
  - Empty slots stay a quiet gray unless your bags can fill them.
  - Your average item level in the window's header.

### Hunter
- **Ammo**:
  - Arrows / bullets left and how long they'll last.
  - A warning when you leave town low.
  - A **Fill quiver** button at ammo vendors.
  - A waypoint to the nearest ammo vendor (click the Arrows line, or `/zyde ammovendor`).
- **Pet care**:
  - Keys to feed your pet the right food from your bags, and to call or revive it.
  - Reminders when it's hungry or missing.
  - A Growl autocast reminder: off in a group, on when solo.

### Groups
- **Group finder helper**: puts groups with room for your role first, with one-click whisper to the leader.
- **Guild member list**: class-colored names, each member's level colored by how close it is to yours, and their zone on hover.
- **Marker wheels**: hold a key for a wheel of target markers (or world markers), then click the one you want. The centre clears.

### Questing & leveling
- **Quest tracker**: replaces the game's tracker.
  - Quests ready to turn in come first, then this zone's quests nearest first. Other zones are folded away and finished objectives hidden.
  - Click a quest to track it on the map; right-click opens the quest log.
  - Questie's own quest tracker is turned off while this one is on, and comes back if you turn this off.
  - A long list scrolls with the mouse wheel once it reaches the bottom of the screen (`/zyde questheight <pixels>` caps it lower).
  - Text size slider in the `/zyde` window.
- **Quest object alert**: a glow, a bobbing **!** and a ping on nearby objects you need to pick up for a quest. Loot from mobs you kill for a quest isn't marked.
- **Icons over nearby objects**: the game's interact icons over herbs, ore and chests, spotted from further away.
- **Quest mobs nearby** (Questie): a gold edge on quest mobs' nameplates, a count of them near you, and a key to target one.
- **Questie drop chances** (Questie): the drop % and your odds of getting the item on your next kill, under Questie's nameplate icon.
- **Zygor target keybind** (Zygor): one key targets the current Zygor step's enemy or NPC.

### Bags & vendors
- **Scrap list**: when your bags are full, the three cheapest items to throw away. Right-click one to keep it.
- **Vendor / auction advice** (AHledger): "Vendor it", "Auction it" or "Keep" in item tooltips, at merchants and at the auction house. Hold Shift for the details.

### Travel & gathering
- **Flight master shortcut**: flight masters open the flight map directly. Hold Shift to talk to them instead.
- **Keep tracking after death**: turns Find Minerals, Find Herbs and similar tracking back on after you die.
- **One Button Fishing**: the same key casts and reels in.

### GearAdvisor (`/ga`)
Scores gear for your class and spec.
- **Planner window** (`/ga` or the minimap button):
  - **My Gear:** what you wear, each slot's value and its best known upgrade.
  - **Dungeons:** which dungeon at your level to run next, and its chance of dropping an upgrade per run. Upgrades are listed under each boss with their drop chance; items you can't wear yet show the level they need.
  - **By Slot:** the best upgrades known for each slot, from your bags and from dungeons.
  - Boss loot is built in (from the cMaNGOS classic database and drops seen on Forever), including Forever's new dungeons; no loot addon needed.
- A short verdict in item tooltips: upgrade %, or "can't wear until level N".
- Upgrade marks on quest rewards and on items in your bags. While quest marks are on, Zygor's own quest reward arrow is turned off, and comes back if you turn them off (`/ga quest`).
- Advice on loot rolls.
- A popup when you loot an upgrade.
- At the auction house: upgrade % on listings, and an Upgrades panel that opens when a search finds upgrades.

## Keybindings

Set these under **Game Menu → Options → Keybindings → AddOns → Zyde Forever**:

| Binding | What it does |
|---|---|
| One Button Fishing | Casts, and reels in when a fish bites |
| Target Zygor Step NPC | Targets the current Zygor step's enemy or NPC |
| Target nearest quest mob | Targets a nearby mob you need for a quest |
| Feed pet (best food in bags) | Feeds your pet food it likes |
| Call or revive pet | Calls your pet, or revives it if it's dead |
| Marker wheel (hold) | Target marker wheel |
| World marker wheel (hold) | World marker wheel |

## Commands

`/zyde` on its own opens the options window. `/zyde help` lists everything.

| Command | What it does |
|---|---|
| `/zyde unlock` / `lock` | Unlock the unit frames to drag them, empty ones included (Shift-drag works without unlocking), then lock them again (they also lock when combat starts) |
| `/zyde resetframes` | Put the unit frames back in their default spots |
| `/zyde resetxp` | Move the XP readout back to the top of the screen |
| `/zyde resetquests` | Move the quest tracker back to its default spot |
| `/zyde resetmobs` | Move the quest mob count back to its default spot |
| `/zyde resetreminders` | Move the reminder icons back beside your character |
| `/zyde questheight <pixels>` | The tallest the quest tracker gets before it scrolls (0 = down to the bottom of the screen) |
| `/zyde questalert` | Turn the quest object alert on or off |
| `/zyde questicons` | Turn the icons over nearby objects on or off |
| `/zyde questrange <yards>` | How far away quest objects are spotted (default 30) |
| `/zyde scrap` | Turn the scrap list on or off |
| `/zyde scraptest` | Preview the scrap list now |
| `/zyde scrapreset` | Let items you marked to keep be suggested again |
| `/zyde vendor` | Turn the vendor / auction advice on or off |
| `/zyde ammovendor` | Hunters: waypoint to the nearest ammo vendor |
| `/zyde ammowarn <number>` | Hunters: warn when leaving town with less ammo than this (default 600, 0 = off) |
| `/zyde test` | Preview the reminder icons |
| `/zyde errors` | Show the last Lua errors from any addon, even with error pop-ups turned off |
| `/zyde zygor` | Show what the Zygor target key will do on this step |

Troubleshooting:

| Command | What it shows |
|---|---|
| `/zyde petdebug` | Your pet's mood, buffs and food, as the game reports them |
| `/zyde rangedebug` | Your target's range readings (Auto Shot, Wing Clip, ~10 yd) |
| `/zyde auradebug` | Your target's debuffs as the game reports them (name, spell ID, stacks) |
| `/zyde mobsdebug` | Nearby nameplates, and why each is or isn't counted as a quest mob |
| `/zyde questdebug` | Why the quest object you're facing is or isn't detected |

GearAdvisor:

| Command | What it does |
|---|---|
| `/ga` or `/ga plan` | Open the planner window (also the minimap button) |
| `/ga help` | List GearAdvisor's commands |
| `/ga minimap` | Show or hide the minimap button |
| `/ga summary` | Your gear summary |
| `/ga score <item>` | Score an item: Shift-click one in, or hover it |
| `/ga bags` | Upgrades in your bags |
| `/ga spec <spec>` | Set the spec gear is scored for (for example `arms`, `bm`, or `auto` to detect it) |
| `/ga tooltip` | Turn tooltip lines on or off |
| `/ga quest` | Turn quest reward marks on or off |
| `/ga arrows` | Turn bag upgrade arrows on or off |
| `/ga rolls` | Turn loot roll advice on or off |
| `/ga toast` | Turn the upgrade popup on or off |
| `/ga ah` | An auction house upgrades report |

## Notes

- Built for the WoW Forever client. Some game information is hidden from addons in combat ("secret" values), so a few features pause or fall back to the last known value during fights.
- Settings are saved per account in `ZydeForeverDB` (and `GearAdvisorDB`).
- Found a problem? `/zyde errors` shows recent errors to include in a bug report.

## Licence

Zyde Forever is free software, released under the [GNU General Public License v3.0 or later](LICENSE). You may use, change and share it, as long as anything you share that's built from it is under the same licence.

World of Warcraft and its content are © Blizzard Entertainment.
