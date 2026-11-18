# Windows drive scan for Claude Code (free, read only)

Windows drive full? This free Claude Code skill shows you where the space went: the biggest folders, the biggest files and how big your caches are, explained in plain words. It **only looks**. It never deletes, moves or changes your files, needs no admin rights and makes no network connections.

Tested on Windows 11 with Windows PowerShell 5.1 and Claude Code only. Windows 10 and PowerShell 7 are not yet verified.

## Install

1. Download this repository (green **Code** button, **Download ZIP**) and unzip it.
2. Copy the `windows-drive-scan` folder into your Claude Code skills folder: `%USERPROFILE%\.claude\skills\`.
3. Open Claude Code and say: "my C drive is full, what's taking up the space?"

Claude runs `scripts\scan.ps1`, which can take 10 minutes or more on a big, full drive. The report is saved in `drive-scan-report` in your user folder. Run it again later to see how much space changed.

You can also run the scan yourself, without Claude:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows-drive-scan\scripts\scan.ps1
```

`-ExecutionPolicy Bypass` applies to that one run only and changes no settings.

## Check your copy

`SHA256SUMS.txt` lists the SHA-256 hashes of the script and of `SKILL.md`. To check the copy you downloaded:

```powershell
Get-FileHash .\windows-drive-scan\scripts\scan.ps1 -Algorithm SHA256
```

Each hash should match its line in `SHA256SUMS.txt`. Only download from this repository or its Releases page; copies elsewhere may have been changed.

## What we tested (18 Nov 2026, Windows 11, Windows PowerShell 5.1)

- A full scan of a 930 GB drive with 499 GB used: about 6 minutes, nothing changed.
- A test drive with folder names containing spaces, apostrophes, brackets, `$`, `%`, `;`, `&`, a backtick, accented letters and an emoji, a path longer than 260 characters, a folder that links back to itself, and a folder the user can't read. Every folder was measured, the loop was skipped, the locked folder was counted as unreadable, and a before-and-after listing of the drive was identical.
- A report folder with spaces, an apostrophe and brackets in its name.
- It stops with a clear message for a drive letter that doesn't exist, for anything that isn't a drive letter, and for a report folder on a network path. (It also refuses a mapped network drive; that check is in the code but was not tested here.)
- Caches are always measured in their standard locations on this PC, whichever drive you scan.

The script itself is the proof: it is one short PowerShell file you can read. A simple automated check (`tests\check-readonly.ps1`) runs on every change and fails if the script gains a known command that could delete, move or download, if another script file appears, or if the files no longer match `SHA256SUMS.txt`. It is a guard, not a guarantee; every change is also reviewed by hand before it is merged.

## Want to clean up too?

- Windows' own tool: Settings > System > Storage > Cleanup recommendations.
- Free open-source tools for duplicates and junk, step by step: https://repoquarry.dev/builds/windows-cleanup?utm_source=free-scan&utm_campaign=windows-cleanup
- Paid: the [Windows clean-up kit for Claude Code](https://repoquarry.gumroad.com/l/windows-cleanup-kit?utm_source=free-scan&utm_medium=direct&utm_campaign=windows-cleanup) adds duplicate finding, old-installer lists and a clean-up that moves files to the Recycle Bin only after you say yes to each list.

## Licence and security

MIT licence (see `LICENSE`). Found a security problem? See `SECURITY.md`.

Made by [RepoQuarry](https://repoquarry.dev), which lists free, open-source alternatives to paid software.
