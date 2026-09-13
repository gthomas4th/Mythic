# Copy your Steam Deck library without breaking existing games

The central library is prepared with `roms`, `bios`, `incoming`, and `save-backups`
folders. Its private NAS address is kept outside Git. No network share was added.
Use an existing USB drive that both the Deck and Mac can read; it needs enough free
space for the files you choose. Do not format a drive containing anything you need.

## First, bring just the game list

1. On the Deck, use **Steam → Power → Switch to Desktop**.
2. Close Steam, then open **Dolphin**, the file manager. Show hidden files with
   **Ctrl+H**. A keyboard is helpful; **Steam+X** opens the on-screen keyboard.
3. Open `~/.local/share/Steam/userdata`. Inside your account's numbered folder,
   open `config` and copy **shortcuts.vdf** to your USB drive. If there are multiple
   account folders, keep their files separate; use the account you play with.
4. Safely eject the drive and connect it to your Mac.
5. In the hub, open **Library → Steam Deck → Import shortcuts.vdf…** and choose
   that copied file. Keep the original on the Deck.

This imports names and device-specific references. A recognized EmuDeck ROM path
shows **Files on Steam Deck**. An unknown mapping shows **Target not resolved**.
Neither is treated as a purchased Steam app or a playable Mac installation.

## Then copy the games, when ready

1. In Dolphin, locate your **Emulation/roms** folder. It may be in your home folder
   or on the SD card. Use the location already used by EmuDeck, rather than guessing
   the SD card's mount name.
2. **Copy**, rather than move, the `roms` folder to the USB drive. Keep system
   subfolders and all files belonging to each disc set together. Large libraries can
   be copied one system at a time.
3. If needed, copy your own BIOS files separately. Keep saves and save states
   separate; they need their own backup and compatibility checks.
4. Bring the drive to the Mac. The engineer can transfer the copy to the prepared
   NAS directory through existing authorized access, check file counts/sizes and
   hashes, and report any failures before anything is used.

Keep the Deck originals and its existing shortcuts. The NAS is the master copy;
local working copies allow play without the NAS mounted. No automatic save merging
or file deletion is part of this transfer.

References: [EmuDeck file management](https://github.com/EmuDeck/emudeck.github.io/blob/main/docs/file-management/steamos/file-management.md)
and [Steam ROM Manager](https://github.com/EmuDeck/emudeck.github.io/blob/main/docs/tools/steamos/steam-rom-manager.md).
