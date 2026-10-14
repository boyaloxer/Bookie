# Bookie

Adds a **Macros** tab to the WoW TBC Anniversary spellbook so you can browse and drag macros onto action bars the same way you do with spells.

Optional **spellbook keybinds**: bind a key on a spell (or macro), then drag it to a bar to attach that key to the bar button.

## Install

Copy the `Bookie` folder into `Interface\AddOns\`, or download a release zip.

## Usage

1. Open the spellbook (`P`)
2. Click the **Macros** tab on the right (under Affliction / Demonology / Destruction)
3. Drag a macro onto an action bar
4. Right-click a macro to open the macro editor

### Spellbook keybinds (off by default)

```
/bookie binds on
/bookie binds off
/bookie binds status
```

When **on**:

1. **Alt-Right-Click** a spell (or Bookie macro) → press a key
2. Hotkey text shows on the spellbook icon
3. Drag that spell/macro onto an action bar → the key moves onto that bar button (`ACTIONBUTTON*` / multi-bar)

Turning binds **off** stops the new UI; it does not auto-restore old keys. Keep a copy of `bindings-cache.wtf` (see DotkillSetup `BindingsBackup/`) if you want a hard revert.

**Minimap:** book icon — left-click opens the Macros tab, right-click toggles spellbook binds, drag to move. Hide with `/bookie minimap hide`.

Slash command: `/bookie` (also `/sbm`) · `/bookie help`

## Notes

- Works out of combat for drag-and-drop and bind changes (WoW protects these in combat)
- Does not taint Blizzard spell buttons — the macros page is an overlay, not a real skill-line injection
- Rebinding a key replaces whatever that key did before (same as Blizzard’s Key Bindings UI)

## License

MIT
