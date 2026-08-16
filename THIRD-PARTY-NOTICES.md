# Third-Party Notices

Tickerfish is released under the MIT License (see [LICENSE](LICENSE)). That licence covers
Tickerfish's own source code and artwork. The components listed below are the work of others and are
redistributed under their own terms. Full licence texts are in the [`licenses/`](licenses) folder
next to this file.

---

## Godot Engine

| | |
|---|---|
| **Used as** | Game engine; an executable exported from this project embeds the Godot runtime. |
| **Version** | 4.6.2 stable |
| **License** | MIT |
| **Copyright** | Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur. |
| **Full text** | [`licenses/Godot-Engine.LICENSE.txt`](licenses/Godot-Engine.LICENSE.txt) |
| **Source** | https://github.com/godotengine/godot |

The Godot runtime itself bundles further third-party components (FreeType, mbedTLS, zlib, Thorvg and
others), each under its own permissive licence. The complete component list with per-component
copyright notices is maintained upstream in Godot's
[`COPYRIGHT.txt`](https://github.com/godotengine/godot/blob/master/COPYRIGHT.txt).

## Noto Sans SC

| | |
|---|---|
| **Used as** | Bundled UI font for all text (`NotoSansSC.ttf`, variable weight). |
| **Version** | 2.004 |
| **License** | SIL Open Font License, Version 1.1 |
| **Copyright** | (c) 2014-2021 Adobe (http://www.adobe.com/), with Reserved Font Name 'Source'. |
| **Full text** | [`licenses/NotoSansSC.OFL.txt`](licenses/NotoSansSC.OFL.txt) |
| **Source** | https://github.com/notofonts/noto-cjk |

## JetBrains Mono

| | |
|---|---|
| **Used as** | Bundled monospace font for prices, percentages and other figures (`JetBrainsMono.ttf`). |
| **License** | SIL Open Font License, Version 1.1 |
| **Copyright** | Copyright 2020 The JetBrains Mono Project Authors (https://github.com/JetBrains/JetBrainsMono) |
| **Full text** | [`licenses/JetBrainsMono.OFL.txt`](licenses/JetBrainsMono.OFL.txt) |
| **Source** | https://github.com/JetBrains/JetBrainsMono |

---

## Artwork

The vector fish, the app icon and the taskbar animation were created for Tickerfish, contain no
third-party material, and are covered by the MIT License above.

The optional **Art** skin can render Elthen's *2D Pixel Art Fish Pack*.

> [!IMPORTANT]
> That pack is **not included in this repository, not redistributed with it, and not bundled in any
> build produced from it.** Tickerfish ships no third-party fish artwork at all; the default skin is
> the project's own vector fish and the application is fully usable without any third-party art.

A user who owns the pack may place its sprite sheet in a local `FishArt/` folder next to the
executable, and Tickerfish will read that file at runtime. The licence for that pack runs between the
artist and that user; Tickerfish is neither a party to it nor a distributor of the assets. The pack's
licence restricts blockchain and crypto-related use, and Tickerfish can display cryptocurrency prices
— users should read the licence and decide for themselves.

| | |
|---|---|
| **Pack** | [2D Pixel Art Fish Pack](https://elthen.itch.io/2d-pixel-art-fish-pack) |
| **Artist** | [Elthen](https://elthen.itch.io/) · [Patreon](https://www.patreon.com/elthen) |
| **License** | [Elthen's Common Sense License 1.0](https://www.patreon.com/posts/27430241) — held by the end user, not by this project |

Screenshots in this repository that show the Art skin depict the artwork in use within the
application. The sprite sheet itself is not present in the repository in any form.

Setup instructions for owners of the pack: [FISH-ART-GUIDE.md](FISH-ART-GUIDE.md)

> **A note from me, personally:**
>
> I lean towards using Elthen's fish myself. They genuinely bring the software to a different level
> visually, so I bought a copy of the pack for my own use. What stops me from shipping it with the
> source is the licensing, nothing else.
>
> If you would like the fish to look better, I recommend buying the pack yourself. Once you own it,
> the application will walk you through how to use it.
>
> — DCW

---

## Market data

Tickerfish ships with no API keys and stores none on any server. Each user registers their own key
and connects directly to the data provider; Tickerfish operates no intermediary service and
redistributes no market data.

| Market | Provider | Role |
|---|---|---|
| US stocks | [Finnhub](https://finnhub.io) | primary |
| Crypto | [Binance public market data](https://www.binance.com) | primary |
| Crypto | [CoinGecko](https://www.coingecko.com) | fallback |

Use of these APIs is governed by each provider's own terms of service. Attribution for the active
providers is shown in the application's About window.
