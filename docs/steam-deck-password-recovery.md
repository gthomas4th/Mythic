# Steam Deck password recovery

The owner forgot the local `deck` password. The GRUB debug-shell attempt produced
continuous AMD graphics messages and repeated freezes. A normal boot restored Steam.
Do not repeat that method or substitute a ROM-transfer workaround for the requested
password reset.

## Recovery media

- Owner explicitly approved erasing the 30.75 GB SanDisk 3.2Gen1 USB labelled MSI BIOS.
- Its GIGABYTE.bin file (33.55 MB) was copied to a private project backup and SHA-256
  verified before writing. The backup location is kept outside Git.
- Image: Valve's steamdeck-repair-20250521.10-3.7.7.img.bz2, downloaded from its
  official image server. Expanded size is 7.74 GB; compressed-data integrity and
  the GPT header were checked. This is the manual recovery-desktop image.
- Writer: official balenaEtcher 2.1.6 for Apple Silicon; the vendor-published
  SHA-256 digest and app signature were checked.
- Writing and validation are in progress. Do not call the USB ready until Etcher
  confirms successful validation.

## Next live steps

1. Shut the Deck down normally and connect the verified recovery USB and keyboard.
2. Hold Volume Down, press Power, and release Volume Down at the chime. In the boot
   manager choose the USB's EFI entry. Do not change persistent boot configuration.
3. Wait for the recovery desktop. Do not select Wipe, Re-image, Erase User Data or
   an installation action; the objective is only the existing account's password.
4. Inspect the recovery tools and installed system before selecting a repair shell.
   Confirm the installed system/active partition set rather than guessing a disk or
   A/B slot. Reset `deck` inside the installed system, not the recovery USB's account.
5. The owner enters and confirms the new password locally. Never request it in chat.
6. Exit the repair session, shut down normally, remove the USB and boot internal
   SteamOS. Verify with `sudo -k` then `sudo -v` in Desktop Mode.
7. Resume the authorized ROM-transfer connection setup only after password recovery.

References: [Valve recovery images](https://steamdeck-images.steamos.cloud/recovery/),
[Valve installation and repair](https://help.steampowered.com/en/faqs/view/65B4-2AA3-5F37-4227),
[Etcher releases](https://github.com/balena-io/etcher/releases/tag/v2.1.6).
