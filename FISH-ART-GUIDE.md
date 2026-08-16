# The Art Skin — Setup Guide

[中文版](FISH-ART-GUIDE.zh-CN.md)

Tickerfish ships with the **Minimal** skin: three vector fish drawn for this project. The optional
**Art** skin replaces them with 12 pixel-art species from Elthen's *2D Pixel Art Fish Pack*.

<table>
<tr>
<td align="center" width="50%">
  <img src="Showcase/Tf1.png" alt="Minimal skin"><br>
  <sub><b>Minimal</b> — ships with the app</sub>
</td>
<td align="center" width="50%">
  <img src="Showcase/Tf2.png" alt="Art skin"><br>
  <sub><b>Art</b> — needs the pack</sub>
</td>
</tr>
</table>

That pack is a paid third-party product. It is not included with Tickerfish and this guide is not a
way to obtain it — it explains how to use a copy you have bought yourself.

> **A note from me, personally:**
>
> I lean towards using Elthen's fish myself. They genuinely bring the software to a different level
> visually, so I bought a copy of the pack for my own use. What stops me from shipping it with the
> app is the licensing, nothing else.
>
> If you would like the fish to look better, I recommend buying the pack yourself. Once you own it,
> the application will walk you through how to use it.
>
> — DCW

---

## Before you start

> [!IMPORTANT]
> The pack is **not included in this repository, not redistributed with it, and not bundled in any
> build produced from it.** Tickerfish ships no third-party fish artwork at all; the default skin is
> the project's own vector fish and the application is fully usable without any third-party art.

If you buy the pack, its licence runs between the artist and you. Tickerfish is neither a party to it
nor a distributor of the assets. The pack's licence restricts blockchain and crypto-related use, and
Tickerfish can display cryptocurrency prices — read the licence and decide for yourself.

| | |
|---|---|
| **Pack** | [2D Pixel Art Fish Pack](https://elthen.itch.io/2d-pixel-art-fish-pack) |
| **Artist** | [Elthen](https://elthen.itch.io/) · [Patreon](https://www.patreon.com/elthen) |
| **License** | [Elthen's Common Sense License 1.0](https://www.patreon.com/posts/27430241) — held by you, not by this project |

Do not commit the sprite sheet to a public repository, and do not ship it inside an `.exe` you
distribute. Both are redistribution. See [If you export your own exe](#if-you-export-your-own-exe).

---

## Step 1 — Buy the pack

Either go straight to the store page:

<https://elthen.itch.io/2d-pixel-art-fish-pack>

or let the application take you there: **right-click → Fish style → Art skin assets… → Buy from
Elthen**.

Download the pack and unzip it. The file Tickerfish needs is the sprite sheet:

```
Fishes Sprite Sheet.png        (512 x 768 pixels)
```

Some copies name it with underscores instead of spaces. Tickerfish accepts both:

```
Fishes Sprite Sheet.png
Fishes_Sprite_Sheet.png
```

Nothing else from the pack is used. The `.json` and `.aseprite` files are not read.

---

## Step 2 — Put the file in the right folder

Tickerfish looks for a folder named `FishArt`, and where that folder lives depends on how you run
the app:

| How you run it | Where `FishArt/` goes |
|---|---|
| From source in Godot | `<project folder>/FishArt/` |
| An exported `.exe` | `<folder holding the .exe>/FishArt/` |

The easiest way to get it right is to let the app open the folder for you: **right-click → Fish style
→ Art skin assets… → Open folder**.

That button creates the folder if it does not exist, writes a `.gdignore` marker inside it, and opens
it in Explorer. Drop the `.png` in there. The panel also prints the exact path in a read-only box, so
you can copy it.

> [!WARNING]
> Put the `.png` **directly** in `FishArt/` — not in a sub-folder, and not still inside the
> downloaded `.zip`.

---

## Step 3 — Turn it on

Back in the **Art skin assets…** panel, the status line updates itself:

| Status line | Button | What to do |
|---|---|---|
| *Not found yet — the Minimal skin stays in use.* | **Check again** | Press it after dropping the file in; you do not need to reopen the panel. |
| *Sprite sheet found.* | **Use Art skin** | Press it and the fish change over with a short fade. |
| Already on the Art skin | **In use** (greyed out) | Nothing to do. |

You can also switch from the menu once the file is in place: **right-click → Fish style → Art**.

No restart is needed, and Godot does not need to re-import anything. Tickerfish reads the `.png`
straight off disk at runtime, so the file takes effect the moment you press the button.

If you pick **Art** while the file is missing, Tickerfish does not switch. It opens this same panel
instead and stays on the Minimal skin.

---

## Choosing species

The 12 species only appear while the Art skin is active. On the Minimal skin the same menus offer the
three vector designs instead.

### For fish you already have

> [!NOTE]
> Every fish that existed before you switched shows up as **Anchovy** — the default.

Change them one at a time: **right-click a fish → Change species → pick one**. The current species
carries a checkmark. The choice is saved immediately, per fish.

### For new fish

**Right-click → Add → … → the "Species:" dropdown.**

The dropdown appears only in **Fish tank** display mode. The numeric list, rotating card and top
banner modes do not draw fish, so they do not offer it.

### The 12 species

| | | |
|---|---|---|
| Anchovy | Silver Salmon | Frontosa |
| Tuna | Alaska Pollock | Blue Tang |
| Shortfin Batfish | Red Parrot Fish | |
| Sailfish | Clown Fish | |
| Great Barracuda | Atlantic Cod | |

---

## If it is not picking the file up

The panel keeps saying *Not found yet*. Check these in order:

1. **The file name.** It must be exactly `Fishes Sprite Sheet.png` or `Fishes_Sprite_Sheet.png`.
   Renamed copies, `(1)` suffixes from a second download, and `.PNG` in capitals on a case-sensitive
   drive will all miss.
2. **The folder level.** The `.png` goes directly inside `FishArt/`, not in a sub-folder the unzip
   created. If unzipping produced `FishArt/2D Pixel Art Fish Pack/Fishes Sprite Sheet.png`, move the
   file up one level.
3. **Still zipped.** A `.zip` sitting in `FishArt/` does nothing. Extract it first.
4. **Wrong file type.** The pack also contains `.aseprite` and `.json` files. Tickerfish only reads
   the `.png`.
5. **Wrong `FishArt` folder.** If you run both from source and from an exported `.exe`, each has its
   own `FishArt/` folder. Use the **Open folder** button from the build you are actually running.

If the file is there and readable but the image is damaged, Tickerfish logs a warning and stays on
the Minimal skin rather than drawing garbage.

### If you remove the file later

The fish fall back to the Minimal skin. Your per-fish species choices are kept in the save file, so
putting the sheet back restores exactly what you had.

---

## If you export your own exe

Two things matter here, and both exist to keep the paid asset out of anything you hand to another
person.

### Do not delete `FishArt/.gdignore`

That empty file tells the Godot editor to skip the folder. Without it, Godot imports any `.png` you
drop in, the asset lands in `.godot/imported/`, and the export preset
(`export_filter="all_resources"`) packs it into your `.exe`. At that point you would be
redistributing Elthen's artwork.

### The folder goes next to the exe, not inside it

After exporting, create `FishArt/` in the same folder as `Tickerfish.exe` and put your copy of the
sprite sheet there — the same way `DataBridge/` and `api_config.json` live beside the executable.
Anyone you give the `.exe` to will see the Minimal skin unless they own the pack and supply their own
copy, which is exactly the intent.

`FishArt/*` is already in `.gitignore`, so the sheet will not be committed by accident.
