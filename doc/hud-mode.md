# HUD mode

This fork adds optional HUD mode to Windows Terminal stable **v1.25.2733.0**
(`dc8ae365847d41f62d1ebca93815bb00959bc12f`). It is independent of the
TerminalHUD repository. Ordinary Terminal startup, profile appearance, tabs,
and shell sessions retain their normal behavior.

## Use

Launch the built fork's `WindowsTerminal.exe`. Press Win+Ctrl+Backtick in the
focused window to enter HUD on its current monitor. Press it again to restore
its previous window placement, focus/fullscreen presentation and topmost policy.
The window retains its name and sessions. Opening Settings or selecting a tab
with nonterminal content exits HUD, keeping opaque UI out of Passive overlays.
Select a terminal-only tab before entering HUD again. The mode toggle does not
select or create tabs. Quake windows keep their separate mode;
renaming a HUD to `_quake` leaves HUD before applying Quake sizing.

| Default shortcut | Scope | Action |
| --- | --- | --- |
| Win+Ctrl+Backtick | Focused Terminal | `toggleHudMode` / `Terminal.ToggleHudMode` |
| Win+Backtick | Global | `hudMode` / `Terminal.HudMode`: Active/Passive |
| Win+Shift+Backtick | Global | `hudVisibility` / `Terminal.HudVisibility`: hide/restore |
| Alt+Backtick | Global | `quakeMode` / `Terminal.QuakeMode` |

Backtick bindings use physical scan code 41. Configure them in Settings > Actions
or `keybindings` in `settings.json`. Explicit user bindings override defaults.
A shortcut registered by another application is unavailable until released.

| State | Background | Input |
| --- | --- | --- |
| Active | Configurable, 35% opaque by default | Terminal receives keyboard/pointer input |
| Passive | Transparent; normal glyph opacity retained | Underlying application receives input |
| Hidden | Window hidden | Underlying application receives input |

Focus loss makes Active become Passive. The interaction action activates a
Passive/Hidden HUD. Visibility restores the state remembered when hiding.
Both global actions work while another application has focus. The local mode
toggle needs Terminal focus; activate the HUD first. Escape passes through.

There is one HUD per app instance. If another window is already the HUD, the
mode toggle activates that window. Global HUD actions do nothing when HUD
mode is disabled. Explicit `WindowsTerminal.exe -w _hud` creates a HUD on the
primary monitor when that window name is unused. Reusing an existing name
retains that window's current mode. Ordinary command-line window reuse excludes HUD windows;
explicit names and IDs can still target them. Renaming does not change mode.
Generic `globalSummon` activation of the HUD retains ordinary summon semantics.

## Appearance

Set **Settings > Appearance > HUD Active opacity (%)**, from 0 (transparent) to
100 (opaque). Its top-level JSON setting is:

```json
"hudActiveOpacity": 35
```

Settings reload updates the current HUD and new/attached panes. Passive
backgrounds remain transparent. HUD suppresses acrylic, Mica and background
images without rewriting profile appearance. Leaving HUD restores normal
profile/runtime opacity. Ordinary opacity shortcuts leave that hidden runtime
value untouched while HUD is enabled; use the dedicated HUD setting instead.
HUD retains its fullscreen/focus presentation until its mode is disabled. HUD does not lower whole-window alpha.

## Implementation

- `WindowsTerminal/HudState.h` contains the window-independent transition policy.
- `WindowsTerminal/HudInput.h` owns only layered, transparent and no-activate
  window styles, preserving unrelated styles and previous layered attributes.
- `WindowsTerminal/AppHost.Hud.cpp` applies native effects on the UI thread,
  remembers foreground identity, restores window placement and retains recovery
  through the notification icon. A failed focus release recovers to interactive
  mode. Queued HUD requests are discarded after leaving HUD mode.
- `TerminalPage` retains the ordinary presentation and propagates HUD appearance
  to controls. `ControlCore` overrides background opacity in memory. Unchanged
  HUD appearance does not rebuild control brushes.
- HUD interaction/visibility use the existing global-hotkey/summon transport.
  The registered action determines interaction toggling; a window name alone
  does not convert an ordinary summon into a HUD toggle.

The notification icon remains available while a HUD exists. Hiding retains
connections and scrollback. Closing the HUD closes its sessions normally.
There is no background service: closing every Terminal window ends the process
and unregisters its global shortcuts. Prompt-aware Escape is not implemented.

## Build and preview

Follow this checkout's [prerequisites](../README.md#prerequisites) and
[build guide](building.md). Native validation used Visual Studio 2026 18.11.3,
Windows SDK 10.0.26100.9457, PowerShell 7 and the .NET Framework 4.7.2 targeting
pack. Restore `build/packages.config` and `dep/nuget/packages.config` into
`packages`, then build the WindowsTerminal application target. WSL tests alone
cannot validate Windows windowing/input behavior.

A prepared unpackaged runtime can be copied into an isolated preview:

```powershell
pwsh -NoProfile -File .\tools\New-HudPreview.ps1 `
  -RuntimeDirectory .\bin\x64\Debug\WindowsTerminal `
  -DestinationDirectory C:\Dev\wt-preview -UseTemporaryHudKeys
```

The destination must be new and outside the input runtime directory. Settings are copied; saved workspace state is not.
The single `Start-Terminal.lnk` shortcut launches the GUI executable directly
in ordinary mode. `-UseTemporaryHudKeys` substitutes Ctrl+Alt+F9/F10 for global
HUD actions so stock Terminal can retain Win+Backtick. Installed settings and OS
defaults are unchanged. This Debug preview requires the local debug runtime.

## Validation

Run standalone native policy/input tests:

```powershell
pwsh -NoProfile -File .\tools\Test-HudMode.ps1
```

The transition test also runs portably:

```bash
g++ -std=c++17 -Wall -Wextra -Werror -pedantic \
  src/cascadia/WindowsTerminal/tests/HudStateTests.cpp -o /tmp/wt-hud-state-tests
/tmp/wt-hud-state-tests
```

Build and run the Control and Settings Model suites using the upstream TAEF
instructions. Use an isolated `te.exe` next to each suite, as configured in
`tools/tests.xml`. Tests cover HUD appearance, ordinary opacity restoration,
action parsing/serialization and settings persistence.

The desktop driver creates private runtime copies/settings, owned background
windows, and guarded keyboard/mouse input. It stops only its own processes and
retains logs/captures in its new artifact directory:

```powershell
pwsh -NoProfile -Sta -File .\tools\Test-HudModeDesktop.ps1 `
  -RuntimeDirectory .\bin\x64\Debug\WindowsTerminal
```

It exercises fresh HUD launch, ordinary-window conversion, real click-through,
foreground restoration, hide/show memory, Escape, shell survival, exact window
restoration, opacity rendering/live reload, and the real Appearance save path.
It selects a secondary monitor when one is exposed. Test global shortcuts are
Ctrl+Alt+F5/F6/F7/F8/F11/F12; occupied chords abort the fixture before input injection.

Before a release, verify secondary-monitor and mixed-DPI restoration, minimized
and maximized windows, tab/pane attachment, settings reload with images/acrylic,
tray recovery, virtual desktops, interactive terminal applications, and installation/default-host
registration. The hand-prepared preview omits some packaged profile icon assets;
the final package must include and validate upstream's resource content.

Build a release from the package project/clean build layout, not the personal
preview directory: previews contain copied user settings and local test data.
The reviewed source and native checks do not replace installer/resource,
multimonitor, signing and default-host validation before distribution.

## Fork releases

`stable` tracks the upstream stable tag. HUD implementation/review commits live
on `feature/hudmode-stable`; `release/hud-1.25` merges that branch and carries the
fork's packaging identity. No public PR is required for this local workflow.

Build the fork package from a native Visual Studio developer shell after
restoring the two package manifests described above. Visual Studio's packaging
target also needs a .NET SDK discoverable by MSBuild:

```powershell
msbuild OpenConsole.slnx /t:Terminal\CascadiaPackage `
  /p:Configuration=Release /p:Platform=x64 /p:WindowsTerminalBranding=HUD `
  /p:AppxPackageSigningEnabled=false /p:AppxBundle=Never `
  /p:AppxSymbolPackageEnabled=false /m
```

The first fork package version is **1.25.2733.1**, with display name
**Windows Terminal HUD**, package name `Spencer1O1.WindowsTerminalHUD`, and
publisher `CN=Spencer1O1`. The `HUD` branding uses upstream's stable feature flags,
keeps the normal terminal icon, includes fonts/profile icons and the fork's JSON
schema, and registers separate terminal/console/Explorer COM classes. Stock
Terminal and upstream Dev builds retain their identities. The command alias is
`wthud.exe`; changing the system's default terminal is a separate installation step.
On first installed launch, settings are copied from stock stable Terminal when
available, using upstream's existing first-run migration. Subsequent settings
are isolated in the fork's own package data. HUD does not use Microsoft's Store
update checker; feedback opens this fork's issue tracker.

An unsigned MSIX is a build artifact, not an installable signed release. Sign
with a certificate whose subject matches the manifest publisher. A local test
certificate must be trusted explicitly before installing; keep its private key
out of the repository and distribution. Ship the public certificate only when
it is needed for a personal test installation. Public distribution requires an
appropriate signing/trust strategy.

Validate the MSIX with `build/scripts/Test-WindowsTerminalPackage.ps1`, inspect
its manifest/resources, then use `build/scripts/New-UnpackagedTerminalDistribution.ps1`
to produce a clean portable runtime for desktop regression. Never package the
personal preview or its copied settings. Record the source revision, SDK/build
versions, checksums, test evidence, and remaining hardware/installation checks
alongside the candidate. Tagging/publishing follows candidate validation.
