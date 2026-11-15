# Credits

Zyde Forever is original work: its code is written for this addon and is not based on any other
addon. It is free software under the GNU General Public License v3.0 or later (see [LICENSE](LICENSE)).

## Third-party data

GearAdvisor's built-in boss loot table (`GearAdvisor/Data/BossLoot.lua`) is built from data in these
open-source projects. The file's header records exactly which versions were used.

| Project | Licence | What Zyde uses |
|---|---|---|
| [cMaNGOS classic-db](https://github.com/cmangos/classic-db) | GPL-3.0 | Classic boss drop chances, including the shared loot pools |
| [DungeonMaster](https://www.curseforge.com/wow/addons/dungeonmaster) by MalkDev | GPL-3.0 | Forever's new dungeons, their bosses and boss loot item IDs, and Forever items added to Classic bosses |
| SimGear Forever by Flavius and contributors | MIT (code); GPL-3.0-or-later (its item data, derived from cMaNGOS) | The first version of the loot table was extracted from its data files (dungeon and boss lists, drop chances and in-game sightings) |

`GearAdvisor/Data/DropRates.lua` holds a short list of drop chances for Forever's new boss items
that none of those sources has. The addon's author checked them by hand, one item at a time, on
Wowhead's WoW Forever item pages (2026-11-15); they are not copied in bulk.

**How Zyde differs:** these projects are loot databases or a gear advisor. Zyde takes only their loot
data and builds its own features on it: its own upgrade scoring, dungeon planner, unit frames,
nameplates, class reminders, quest tracker and levelling route planner.

World of Warcraft content is (c) Blizzard Entertainment.

## Works with (not included)

Zyde can use these addons when they're installed, through their public functions only; none of their
code is included: Questie, AHledger, Zygor Guides, TomTom, Baganator and NodeSight Sparkles.

## SimGear Forever licence notice

```
MIT License

Copyright (c) 2026 Flavius and SimGear Forever contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
