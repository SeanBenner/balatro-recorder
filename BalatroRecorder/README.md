# Balatro Recorder

Records the decisions you make in Balatro (plays, discards, shop buys, pack picks, blind skips, and so on)
so they can be used to teach a bot to play like people do. It only reads the game. It never changes your
game, saves, profile, or settings.

## What gets recorded

Each committed decision is written as one line of text, with a snapshot of what you could see at that moment:
your hand, deck order, jokers, consumables, money, the blind, and the seed. Your profile name (P1, P2, P3,
or whatever you named it in the game) is stored with each run. The recorder doesn't read your Steam account
or other files, and it has no network code. Nothing leaves your computer unless you send the files yourself.

## Requirements

- Balatro with **Steamodded 1.0.0-beta-1016c** and **Lovely**. This is the version the recorder was tested with.
- The recorded runs so far were played with Blueprint, Brainstorm, JokerDisplay, and Saturn installed. Saturn's
  stack buttons (mass use, split, merge) are not recorded, so use consumables one at a time while recording.

## Install

1. Copy the `BalatroRecorder` folder into `%APPDATA%\Balatro\Mods\`. You should end up with
   `%APPDATA%\Balatro\Mods\BalatroRecorder\main.lua`.
2. Start Balatro. The Lovely console should show a line starting with `[recorder] Balatro Recorder 0.3.0 loaded`.
3. Recording is on by default. To turn it off, open **Mods > Recorder > Config** and uncheck **Record runs**.
   A change applies from the next run.

## Where recordings go

`%APPDATA%\Balatro\recordings\<profile>\raw_<date>_<time>_<seed>.jsonl`

One file per run. A run stays in the folder of the profile it was started on.

## Sending your recordings

Send the `raw_*.jsonl` files from the folder above. Don't edit them. Each file is a complete run, so you can
send only the runs you're happy to share and skip the rest.

## Uninstall

Delete the `BalatroRecorder` folder from `%APPDATA%\Balatro\Mods\`. Your recordings stay where they are
unless you delete them too.

## Troubleshooting

- **No console line.** Check that the folder is directly inside `Mods`, not one level deeper.
- **A console window flashes when a run starts.** That's the recorder creating its folder. It's harmless.
- **A run is missing.** It was started with **Record runs** off. Runs that start unrecorded stay unrecorded.
