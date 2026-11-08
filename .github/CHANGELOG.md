# Changelog

All notable changes to **GGSocialState** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - Unreleased

### Added
- **Multi-Version & WoW Forever Compatibility (`GGSocialState.toc`)**: Added full support for Retail (`12.0+`), MoP Classic (`5.5`), Cata Classic (`4.4`), Wrath Classic (`3.4`), TBC Anniversary (`2.5`), Classic Forever (`16001`), and Classic Era (`1.15`).
- **Modern Battle.net (`C_BattleNet`) & Friends (`C_FriendList`) APIs**: Replaced removed legacy `BNGetFriendInfo`/`BNGetFriendToonInfo`/`GetFriendInfo`/`ShowFriends` calls with cross-expansion `C_BattleNet` and `C_FriendList` wrappers while preserving legacy fallbacks.
- **Retail 12.0 (Midnight) Secret-Value Protection**: Added `issecretvalue` guards (`SafeStr`, `SafeNum`, `SafeBool`) for all Battle.net, Friend, and Guild roster fields.
- **Minimap Button & Addon Compartment**: Added `LibDBIcon-1.0` minimap button (toggleable in options) and `GGSocialState_OnAddonCompartmentClick` / `Enter` / `Leave` handlers.
- **Complete Localization (`enUS`, `deDE`)**: Populated all missing English and German locale strings in `Locales/enUS.lua` and `Locales/deDE.lua`.
- **Standardized CI/CD & Packaging**: Added `.github/workflows/quality.yml`, `.github/workflows/release.yml`, `.github/FUNDING.yml`, `.pkgmeta` (GitHub upstreams), `.gitignore`, and `.gitattributes`.
- **Brand Assets (`assets/`)**: Added `logo.png`, `logo.jpg`, `social-banner.png`, and `social-banner.jpg`.

### Changed
- **Modern Dark-Gold `LibQTip` Tooltip Design (`GGSocialState.lua`, `libs/LibQTip-1.0/LibQTip-1.0.lua`)**:
  - Redesigned the `GGSocialState` tooltip to match `Factionizer`'s Modern Dark-Gold UI: added a top title banner with icon, version badge, and live Friends/Guild online counters, gold separator lines, shaded section and column headers (`Lvl`, `Name`, `RealID`, `Zone`, `Realm`, `Note`), alternating zebra row backgrounds, and compact single-line Guild MOTD formatting.
  - Replaced pure black `(0, 0, 0, 1)` backdrop override with `LibQTip-1.0`'s Dark-Slate & Gold border/backdrop (`0.07, 0.08, 0.11, 0.97` / `ElvUI` `Transparent` template).

### Fixed
- **Hint Text Truncation & Sub-Span Column Widths (`libs/LibQTip-1.0/LibQTip-1.0.lua` Minor 52, `GGSocialState.lua`)**:
  - Updated `LibQTip-1.0:Layout()` to calculate and distribute width deficits across any multi-column sub-span (`colSpan > 1`, such as columns `1..4` and `5..7` in the Hint footer), preventing right-hand hint lines (`Shift-Klick...`, `Strg-Rechtsklick...`, `Mittelklick...`, `Rechtsklick...`) from being truncated with `...`.
- **Top Bar Overlap & Anchor Positioning (`GGSocialState.lua`, `libs/LibQTip-1.0/LibQTip-1.0.lua` Minor 52)**:
  - Called `tooltip:SmartAnchorTo(self)` and `tooltip:SetAutoHideDelay(...)` **after** populating all tooltip rows and elevated `tooltip:SetFrameStrata("TOOLTIP")` / `SetFrameLevel(100)`, plus normalized effective scale in `SmartAnchorTo` with an `8px` vertical offset so the tooltip never overlaps the top LDB/ElvUI info bar.
- **ElvUI & AddOnSkins Tooltip Skinning (`GGSocialState.lua`, `GGSocialState.toc`)**:
  - Preserved `AddOnSkins` / `ElvUI` `Transparent` tooltip styling on `LibQTip:Acquire("GGSocialState")` instead of overwriting `tooltip:SetBackdropColor(0, 0, 0, 1)` with opaque black, and automatically applied `tooltip:SetTemplate("Transparent")` when ElvUI is loaded standalone.
- **GuildGreet / GuildGreet-Extended Integration**: Added nil-guards when looking up `GLDG_DataChar[toonName]` or `GuildGreetDB.players[toonName]` so unindexed guild members never trigger a Lua error.
- **Tooltip Backdrop Crash**: Guarded `tooltip:SetBackdropColor` with `pcall` for modern `LibQTip-1.0` frames.
