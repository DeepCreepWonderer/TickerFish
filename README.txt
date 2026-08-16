===============================================================================
  TICKERFISH
===============================================================================

A desktop ticker that swims. Your watchlist lives in a transparent, always-on-top
window -- as fish that change colour with the market, a numeric list, rotating
cards, or a banner across the top of the screen.

Godot 4.6 / GDScript. Windows.

Chinese version: README.zh-CN.txt


  NOT INVESTMENT ADVICE. Entertainment-only visualization. Prices are delayed
  and may differ from your broker. See DATA NOTES below.


  ABOUT THIS PROJECT

  I just wanted to make software of my own. I'm not a professional programmer,
  and of course I used AI to assist me throughout the entire development of this
  program. My original intention in creating it was simply to make something to
  play with myself, and to accomplish a personal goal. I had fun developing this
  software for the past few months and got exposed to experience the life of a
  programmer.

  I have not tracked development versions the way professional programmers do,
  so the current version is positioned as v0.99 so this is never an official
  release. This is also very likely the last version. Compared with professional
  developers and professional programmers, I have never used GITHUB, so I have
  not yet decided on any follow-up development plan or update plan. Feel free to
  fork, modify, and use it however you like. I may casually add a feature or fix
  a bug in my own version and upload it, but please do not expect ongoing
  maintenance, bug fixes, or technical support. Enjoy.

  All the best,
  DCW


-------------------------------------------------------------------------------
  DISPLAY MODES
-------------------------------------------------------------------------------

  Fish tank       Each ticker is a fish. Colour tracks the daily change; fish
                  sleep when the market is closed.

  Numeric list    A scrollable list grouped by market, with intraday candles.

  Rotating card   Large cards that page through a named set of tickers.

  Top banner      A full-width strip along the top of the screen. Drag cards to
                  reorder; drop one into another group to move it.


-------------------------------------------------------------------------------
  GETTING STARTED
-------------------------------------------------------------------------------

Run from source with Godot 4.6 (GL Compatibility renderer -- the transparent
always-on-top window depends on it):

    godot --path /path/to/Tickerfish

Want a standalone .exe? Open the project in Godot, install the export templates
when prompted, then Project -> Export -> Windows Desktop -> Export Project. The
preset is in the repo. Put the result in a folder you can write to -- Tickerfish
saves DataBridge/ and api_config.json next to the executable.

CRYPTO WORKS IMMEDIATELY. BTC, ETH and anything else on Binance needs no API key.

US STOCKS NEED A FREE FINNHUB KEY:

  1. Register at https://finnhub.io/register
  2. Confirm the verification email.
  3. Sign in -- you land on the Dashboard.
  4. Copy the API Key from the box at the top (not Webhook, not Security).
  5. In Tickerfish: right-click -> Settings -> API Key settings -> paste -> Save.

The key is checked on save. It is stored in api_config.json beside the executable
and is never uploaded anywhere. api_config.example.json is a blank template.

Finnhub's free tier is for personal use; check their terms if you plan to use it
commercially.


-------------------------------------------------------------------------------
  ALSO IN THE BOX
-------------------------------------------------------------------------------

  * Named tanks -- up to 10, switched from the right-click menu.

  * Price alerts -- one notification per threshold step the daily change
    crosses. Set 5% and you hear about 5%, 10%, 15%; up and down are tracked
    separately and reset each trading day.

  * Price recording -- prices sampled to CSV every 15, 30 or 60 minutes.

  * English / Chinese, three colour themes.


-------------------------------------------------------------------------------
  FISH SKINS
-------------------------------------------------------------------------------

The default MINIMAL skin -- three vector fish -- ships with the app and needs
nothing extra.

The optional ART skin can render Elthen's 2D Pixel Art Fish Pack:
https://elthen.itch.io/2d-pixel-art-fish-pack

That pack is paid and not redistributable, so no third-party fish art ships with
Tickerfish. If you own it, right-click -> Fish style -> Art skin assets... opens
a panel with the exact folder, a button to open it, and a detect button -- drop
"Fishes Sprite Sheet.png" in and it picks the file up immediately.

The pack is licensed to you by Elthen, not by Tickerfish. Read the licence first:
https://www.patreon.com/posts/27430241
It restricts blockchain and crypto-related use, and Tickerfish can display
cryptocurrency prices.

Step-by-step setup, species selection and troubleshooting: FISH-ART-GUIDE.txt

Art by Elthen -- https://elthen.itch.io/


A note from me, personally:

I lean towards using Elthen's fish myself. They genuinely bring the software to a
different level visually, so I bought a copy of the pack for my own use. What
stops me from shipping it with the app is the licensing, nothing else.

If you would like the fish to look better, I recommend buying the pack yourself.
Once you own it, the application will walk you through how to use it.

-- DCW


-------------------------------------------------------------------------------
  LIMITS
-------------------------------------------------------------------------------

  Unique tickers, all tanks and lists combined ........... 50
  Tickers per tank ...................................... 20
  Tanks ................................................. 10
  Numeric list entries .................................. 30

The 50-ticker cap keeps polling inside Finnhub's free allowance of 60 requests
per minute.


-------------------------------------------------------------------------------
  DATA NOTES
-------------------------------------------------------------------------------

  * Stock prices refresh every 60 seconds (min_interval_seconds in
    api_config.json) -- NOT REAL TIME. Free-tier APIs commonly delay US stock
    data by 15-20 minutes.

  * Market open and closed follow the exchange status reported by Finnhub.
    Without an API key the app falls back to a built-in NYSE calendar, which may
    differ from the exchange's actual schedule.

  * Pre-market and after-hours trades are not shown. After the 4:00 PM ET close,
    the regular-session close price is used.

  * Market hours are US Eastern and follow US daylight saving, whatever the local
    time zone.

  * Crypto comes from Binance public data mirrors, 24/7, with CoinGecko as a
    fallback.


-------------------------------------------------------------------------------
  DEVELOPMENT
-------------------------------------------------------------------------------

Open the project folder in Godot 4.6. All GDScript lives in scripts/; scenes,
project.godot and the autoload registration sit at the repository root. All UI
text is in i18n/strings.json, "en" and "zh".

Regression suite:

    godot --headless --path . res://tests/regression_test.tscn

Exit code 0 on success; each assertion prints PASS or FAIL. THE SUITE RUNS
AGAINST THE REAL SAVE FILE -- it backs up user://save.json,
user://bars_cache.json and the DataBridge JSON files, restores them at the end
and verifies each restore by md5. Close any running instance first.

Things that are not obvious from the source:

  * Under the GL Compatibility renderer a borderless OPAQUE sub-window renders
    black. That is why secondary windows use system borders; only the
    transparent main window and toast popups are borderless.

  * All rendering for the main window happens in fish_tank_window._draw().
    Child Control nodes with show_behind_parent draw blank there.

  * Secondary window sizes come from tide_dialog_window.gd. Change the constants
    there, not per dialog.

  * CJK fonts are embedded. Do not fall back to SystemFont -- a clean Windows
    install has no Chinese font and text renders as tofu.

  * api.binance.com returns HTTP 451 in some regions and must not be used; the
    two public data mirrors are the only crypto endpoints.

  * The Art skin sprite sheet is a paid third-party asset and must never enter
    the repository. It loads at runtime from FishArt/, outside res:// and
    outside Godot's import pipeline. Everything under assets/ is original to the
    project.


-------------------------------------------------------------------------------
  LICENSE
-------------------------------------------------------------------------------

MIT -- see the LICENSE file. Copyright (c) 2026 DeepCreepWonderer

Third-party components and their licences: THIRD-PARTY-NOTICES.txt
