# Balatro Recorder

A small Balatro mod that records the decisions you make while you play, so they can be used to teach an AI to
play Balatro the way people do. It's for an open hobby project training a Balatro bot. The bot learns most from
real games: which hands people play, what they buy, which packs they open and when they skip a blind.

The mod only reads the game. It never changes your game, saves, profile or settings, and it has no network code.
Nothing leaves your computer unless you send the files yourself.

## Install

You need **Steamodded** and **Lovely** installed. The recorder is tested with Steamodded 1.0.0-beta-1016c.

1. Download `BalatroRecorder.zip` from the [latest release](https://github.com/SeanBenner/balatro-recorder/releases/latest).
2. Unzip it into `%APPDATA%\Balatro\Mods\`. You should end up with `%APPDATA%\Balatro\Mods\BalatroRecorder\main.lua`.
3. Start Balatro. A **Recorder** entry shows up in the Mods menu, and the Lovely console shows a line starting with
   `[recorder] Balatro Recorder 0.3.0 loaded`.

Then play normally. Recording is on by default. To turn it off, open **Mods > Recorder > Config** and uncheck
**Record runs**. The change applies from your next run.

## What gets recorded

Each decision is one line of text:

- **What you did:** play, discard, buy, sell, reroll, use a consumable, pick from a pack, skip or select a
  blind, cash out.
- **What the game state was:** your hand, deck, jokers, consumables, money, the blind, the shop, and the run's
  seed, deck and stake.

Each run also stores:
- your **game profile name**: P1, P2, P3, or whatever you renamed it to in the game. If you renamed it to your real
  name, rename it back or tell me to ignore it.
- the **list of mods** you have installed, so runs with mods that change the rules can be set aside.

It doesn't read your Steam account or any other files.

Recordings go to `%APPDATA%\Balatro\recordings\<profile>\`, one file per run (`raw_<date>_<time>_<seed>.jsonl`).

## Sending your recordings

Zip your recordings folder (`%APPDATA%\Balatro\recordings`) and send it one of these ways:

- **GitHub:** attach the zip to the [recording submissions issue](https://github.com/SeanBenner/balatro-recorder/issues).
- **Discord:** send it to SeanBenner.

Every file is a complete run, so you can leave out any runs you'd rather not share. Please don't edit the files.

**Most useful:**
- Vanilla games: no mods that add jokers or change the rules.
- Whole runs, won or lost.
- Any deck or stake, though White Stake and Gold Stake runs are especially welcome right now.

## How your recordings are used

Your runs are used to train and test the bot. They aren't published as raw files. If you want your runs removed
later, ask and they'll be deleted.

## Notes

- Saturn's stack buttons (mass use, split, merge) aren't recorded. Use consumables one at a time while recording.
- A console window may flash briefly when a run starts. That's the recorder creating its folder.
- A run started with recording off stays unrecorded, even if you switch it on partway through.

## Uninstall

Delete the `BalatroRecorder` folder from `%APPDATA%\Balatro\Mods\`. Your recordings stay where they are unless you
delete them too.

## Troubleshooting

- **No Recorder entry and no console line.** Check that the folder is directly inside `Mods` (`Mods\BalatroRecorder\main.lua`),
  not one level deeper (`Mods\BalatroRecorder\BalatroRecorder\main.lua`).
- **A run is missing.** It was started with **Record runs** off.
- **Something else.** Open an [issue](https://github.com/SeanBenner/balatro-recorder/issues) and include the lines
  starting with `[recorder]` from the Lovely console.

## License

MIT. See [LICENSE](LICENSE).
