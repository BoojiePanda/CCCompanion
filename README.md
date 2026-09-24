# CC Companion

CC Companion is a standalone World of Warcraft Retail companion addon for Class
Codex. It preserves selected Class Codex interface and browsing preferences
across characters while keeping class- and specialization-dependent choices
separate.

## Features

- Shares general Class Codex panel state across characters
- Remembers floating or docked mode, panel position, open or minimized state,
  active tab, escape-close preference, and supported collapsed-section state
- Stores specialization-dependent preferences under the character's class token
  and numeric specialization ID
- Keeps Compendium class, specialization, source, content, and hero-talent
  selections separate for each player specialization
- Shares supported per-specialization stat, rotation, gear, trinket, crafting,
  U.GG, and talent-pane preferences
- Deep-copies saved tables to prevent shared-reference mutation
- Excludes runtime caches, inspection state, loadout IDs, and pending talent
  application data
- Requires no external libraries and does not modify Class Codex files

## Requirements

- World of Warcraft Retail
- Class Codex enabled

## Commands

- `/ccom status` — show the current specialization profile and profile count
- `/ccom sync` — immediately capture and restore the current profile
- `/ccom reset` — request deletion of CC Companion's shared data
- `/ccom reset confirm` — confirm the reset within 30 seconds

Resetting CC Companion does not delete Class Codex's own character data.

## Installation

1. Download or clone this repository.
2. Place the `cccompanion` folder inside:

   `World of Warcraft/_retail_/Interface/AddOns/`

3. Ensure Class Codex and CC Companion are enabled in the AddOns menu.
4. Restart World of Warcraft or type `/reload`.

## Author

Created by **BoojiePanda (SilverRavyn)**.

## License

Licensed under the zlib License. See [LICENSE](LICENSE).
