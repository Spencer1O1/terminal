# HUD mode in this fork

HUD mode is implemented inside Windows Terminal. It has no dependency on the
TerminalHUD repository, its Rust binaries, generated profile fragments, or its
IPC bridge. The fork is based on stable release **v1.25.2733.0**, commit
`dc8ae365847d41f62d1ebca93815bb00959bc12f`. The earlier prototype based on
upstream `main` is retained on branch `feature/hudmode`.

## Launch and shortcuts

Run the **built fork's executable**, rather than the installed Store `wt.exe`:

```powershell
.\WindowsTerminal.exe
```

This opens an ordinary Terminal window using normal profile appearance and
startup settings. HUD is opt-in: press Win+Ctrl+Backtick in the focused window
to enter HUD on its current monitor; press it again to restore the previous
presentation. There is no HUD-specific change to ordinary window opacity,
fonts or colors.

For explicit HUD startup during testing, use:

```powershell
.\WindowsTerminal.exe -w _hud
```

For a portable preview that starts with your existing stock Terminal settings:

```powershell
pwsh -NoProfile -File .\tools\New-HudPreview.ps1 `
  -RuntimeDirectory .\bin\x64\Debug\WindowsTerminal `
  -DestinationDirectory C:\Dev\wt-preview -UseTemporaryHudKeys
```

The destination must be new. This copies settings and binaries into a private
portable directory; saved workspace state is not copied. Run its single
`Start-Terminal.lnk` shortcut to open normally, then toggle HUD when needed.
`-UseTemporaryHudKeys` substitutes Ctrl+Alt+F9/F10 for HUD interaction/visibility
so stock Terminal can keep Win+Backtick during testing.

The reserved window name `_hud` starts a fullscreen, topmost HUD on the primary
monitor. It uses normal Terminal profile resolution; `-p` can select a profile.
Creation requests focus. If Windows refuses activation, the window releases
pointer input and becomes Passive.

The fork supplies these default shortcuts while Terminal is running:

| Shortcut | Scope | Action |
| --- | --- | --- |
| Win+Ctrl+Backtick | Focused Terminal window | `toggleHudMode` (`Terminal.ToggleHudMode`): normal ↔ HUD |
| Win+Backtick | Global | `hudMode` (`Terminal.HudMode`): toggle interaction |
| Win+Shift+Backtick | Global | `hudVisibility` (`Terminal.HudVisibility`): hide/show |
| Alt+Backtick | Global | `quakeMode` (`Terminal.QuakeMode`): summon Quake |

All four use scan code 41, the physical backtick key on a US keyboard. They
remain configurable through Settings > Actions or the `keybindings` array in
`settings.json`. Existing user bindings override the inbox defaults; remove or
reassign an explicit old Quake binding if it still uses Win+Backtick. The HUD
implementation does not edit user settings files.

`toggleHudMode` converts the focused ordinary Terminal window into an Active
HUD covering that window's current monitor. The same action restores its prior
window placement, fullscreen/focus presentation and topmost policy, retaining
its name, tabs and shell sessions. It does not convert Quake windows. There is
one HUD per app instance; if another window is already the HUD, the action
activates it. Entering via the reserved `_hud` name still starts on the primary
monitor.

Interaction and visibility shortcuts work while another application has focus,
including when the HUD is Passive or Hidden. Ordinary typing goes to the
foreground application. The mode toggle is local: first use the global
interaction shortcut to activate a Passive or Hidden HUD, then toggle its mode.
A shortcut already registered by another application is unavailable until that
application releases or reassigns it.

| Action | Active | Passive | Hidden | No HUD window |
| --- | --- | --- | --- | --- |
| `hudMode` | Passive | Active | Active | Create Active |
| `hudVisibility` | Hidden, remember Active | Hidden, remember Passive | Restore remembered state | Create Active |

| State | Background | Text | Keyboard and pointer |
| --- | --- | --- | --- |
| Active | Configurable; 35% opaque by default | Retains normal glyph opacity | HUD receives input |
| Passive | Transparent | Retains normal glyph opacity | Underlying app receives input |
| Hidden | Window hidden | Hidden | Underlying app receives input |

Focus loss makes Active become Passive. Explicit interaction/visibility actions
attempt to restore the foreground window saved before activation. A failed focus
release recovers to an interactive window rather than claiming successful Passive
state. Window handle, process and thread identity are checked before focus restore.

Hiding and showing retain the terminal connection and scrollback. Closing the HUD
closes its sessions normally; if another Terminal window keeps the process alive,
the next HUD shortcut creates a new window. This prototype does not keep the
process alive after all Terminal windows close.

The notification icon is retained while a HUD window exists. Its window submenu
can activate the HUD if global shortcuts are unavailable. Renaming a window
preserves its current mode; use `toggleHudMode` to restore ordinary input,
appearance and window presentation.

## Appearance and boundaries

HUD appearance overrides are applied in memory to every terminal pane, including
new and attached panes. Settings reload preserves those overrides. Acrylic,
Mica and background images are suppressed in HUD mode. Profiles, defaults and
ordinary runtime appearance are not rewritten. Set **Settings > Appearance > HUD Active opacity (%)** to choose an Active
background opacity from 0 (transparent) to 100 (opaque). The default is 35.
The JSON equivalent is the top-level setting `"hudActiveOpacity": 35`.
Saving or reloading settings updates an existing HUD, including new panes;
Passive backgrounds remain fully transparent and glyph opacity stays unchanged.
Leaving HUD restores the normal profile opacity and runtime appearance.

Ordinary command-line window reuse excludes the HUD. Explicitly naming `_hud`
or its numeric window ID still targets it. Both HUD actions use the existing
global-hotkey/summon transport. Native window effects are in
`src/cascadia/WindowsTerminal/AppHost.Hud.cpp`; window-independent transition
policy is in `HudState.h`, and input-style ownership is in `HudInput.h`.

Escape is forwarded normally. Prompt-aware Escape requires a separate shell
integration and is not implemented in this prototype. This avoids intercepting
Escape in interactive programs. There is no separate autostart service or
TerminalHUD-style shell-preserving Quit operation in this fork.

## Building and validation

Follow the [upstream prerequisites](../README.md#prerequisites) and
[build guide](building.md). Use the prerequisites documented by this stable checkout. Native validation uses
Visual Studio 2026 18.11.3, Windows SDK 10.0.26100.9457, the C++ desktop and
Windows UI workloads, PowerShell 7, and the .NET Framework 4.7.2 targeting pack
for tests. Restore both `build/packages.config` and `dep/nuget/packages.config`
into `packages` before building the native application target.
The upstream `.config/configuration.winget` and `.vsconfig` supply installation
configuration. Build on a Windows filesystem if a tool rejects the WSL UNC path;
the authoritative checkout remains `~/wt`.

Run the standalone native helper tests from Windows PowerShell 7:

```powershell
.\tools\Test-HudMode.ps1
```

They compile into an isolated temporary directory, run without displaying test
windows, and remove their own build directory. They require a C++ toolchain but
do not require XAML or the complete Terminal build environment.

The policy test also runs on Linux:

```bash
g++ -std=c++17 -Wall -Wextra -Werror -pedantic \
  src/cascadia/WindowsTerminal/tests/HudStateTests.cpp -o /tmp/wt-hud-state-tests
/tmp/wt-hud-state-tests
```

The existing Settings Model and Control native suites include new HUD hotkey
parsing/serialization and appearance/reload regression tests. Run these suites
using the upstream TAEF test instructions after building.

The desktop regression driver creates fresh copies of a prepared unpackaged
runtime and private settings. Run from Windows PowerShell 7 on an interactive
desktop (the driver sends guarded keyboard input and one click to its own test
window per fixture):

```powershell
pwsh -NoProfile -Sta -File .\tools\Test-HudModeDesktop.ps1 `
  -RuntimeDirectory .\bin\x64\Debug\WindowsTerminal
```

The driver retains logs, captures and isolated runtime copies in a new temporary
artifact directory, and stops only the processes it launches. It checks fresh
HUD launch and conversion of an existing named window, global actions while an
owned background application has focus, Escape pass-through and normal-mode
restoration. It chooses a secondary display for conversion when one is exposed.

Additional manual acceptance coverage on Windows should include:

1. Start `_hud` on a secondary-monitor desktop setup. Check primary-monitor
   fullscreen placement, topmost behavior, 35% background and opaque text.
2. Toggle interaction. Check that the same shell survives, the background becomes
   transparent, text remains visible, and a real click reaches an owned test
   window underneath. Check keyboard input goes to the underlying foreground app.
3. Toggle back to Active. Check focus and input, including after ordinary focus
   loss and after the previous foreground window has closed.
4. Check Active/Hidden/Active and Passive/Hidden/Passive. Verify restoring Passive
   does not activate it or flash an opaque background.
5. Add a tab and split a pane. Reload settings with acrylic, a background image
   and a different opacity. Check HUD overrides persist while normal windows
   retain their settings.
6. Exercise both hotkeys, the tray recovery path, close/relaunch, and renaming
   windows. Check ordinary launch/window reuse does not select the HUD.
7. Move an ordinary Terminal to a secondary monitor. Use Win+Ctrl+Backtick to
   enter HUD on that monitor, exercise the global HUD actions with another app
   focused, then leave HUD. Verify exact previous bounds, topmost policy, name,
   appearance and shell survival. Repeat with maximized/fullscreen windows and
   confirm a fresh `_hud` can also return to ordinary window mode.
8. Check Neovim, `less`, `fzf` and SSH still receive Escape.

### Earlier development-branch evidence

The runs below validated the earlier `main`-based prototype. The stable port
requires its own native build and desktop validation before replacing the preview.

On Windows 11, the standalone tests compiled with MSVC 19.29 and SDK 10.0.19041:

- 16 transition-table cases and all 65,536 sequences of eight actions passed.
- Native style application, repeated transitions, preservation of unrelated
  extended styles, whole-window alpha 255, and restoration of pre-existing
  layered-window attributes passed.
- The policy test also passed under GCC on Linux.

The full Debug x64 application now builds with Visual Studio 2026 18.11.3
and Windows SDK 10.0.26100.9457. The Control suite passed all 30 tests; the
Settings Model suite passed all 159 tests using its isolated `te.exe` runner
(the `isolatedTaef` requirement is recorded in `tools/tests.xml`).

A real Windows 11 desktop run with a private portable profile passed primary
fullscreen placement, topmost state, Active focus and background opacity,
Passive transparency with opaque text, one guarded physical click routed to an
owned background window, focus restoration, both remembered hide/show cycles,
shell survival and Escape pass-through. Active background sampled RGB
(26,104,143) over an owned RGB (40,160,220) background; Passive sampled the
background unchanged, with 45,917 opaque-white text samples.

The normal/HUD extension also passed the full native build and both suites
(189 tests total). The checked-in desktop driver passed both fresh `_hud`
startup and conversion of an existing named Terminal. It exercised the actual
default Win+Ctrl+Backtick shortcut, both global HUD actions with the background
app focused, exact restoration of normal window bounds and topmost policy,
shell survival, and a second HUD/normal round trip. The desktop session exposed
one monitor; placement on a different monitor and mixed-DPI restoration remain
unverified.

Raw build/test logs and captures are preserved locally under
`%LOCALAPPDATA%\wt-hud-build`. `mode-desktop-output-3.txt` and
`mode-desktop-review3` record the passing mode-conversion runs;
`mode-regression-output.txt` records both complete suites. Stock Terminal was
left running; the fixture used Ctrl+Alt+F9/F10 for global actions in the initial runs instead of
claiming its existing Win+Backtick registration. Installed/default-terminal
selection and a production package have not been exercised.

The configurable-opacity update passed the native Debug x64 build and all
190 unit tests (30 Control, 160 Settings Model). The desktop driver passed
35% and 65% Active rendering, live changes in both directions, Passive input
behavior, restoration of a normal profile's 65% opacity, exact bounds/topmost
restoration, and saving 47% through the real Appearance settings control.
`opacity-build-output-2.txt`, `opacity-regression-output.txt`, and
`opacity-desktop-output-3.txt` under the same local build directory record this
revision. The fixture uses Ctrl+Alt+F11/F12 to leave the user's temporary
Ctrl+Alt+F9/F10 bindings available.

The updated preview's `Start-Terminal.cmd` was exercised directly. Its window
opened with ordinary window styles and bounds, the copied stock profile
settings, and the PowerShell 7 executable, with no startup error. The old
`Start-HUD.cmd` alias was removed. `normal-preview-output-2.txt` records this
check; installed Terminal and OS default-terminal selection were unchanged.

The preview shortcut launches the GUI executable directly. A batch-file launcher
is unsuitable for this GUI app because opening the batch file can create a
visible console host before starting Terminal. Preview preparation now creates
`Start-Terminal.lnk`; it does not create a command-shell wrapper.

The earlier Workspaces button came from upstream `main` commit `1282d56a3`,
not the HUD feature. Porting onto the stable tag removes that development-branch
UI change instead of hiding it with a preview-only theme override.

### Stable release validation

The v1.25.2733.0 port passed a fresh native Debug x64 application build and all
175 tests in its Control and Settings Model suites (30 and 145 respectively).
Both desktop fixtures passed: fresh HUD launch and conversion of an ordinary
window, global interaction/visibility actions with another app focused, physical
click-through, remembered hide/show state, Escape, shell survival, exact window
restoration, 35%/65% Active opacity and live reload, restoration of the normal
profile's 65% opacity, and saving opacity through stable's Appearance UI.

The portable preview was replaced with this tested build, retaining the user's
current settings. The earlier development preview was preserved under
`%LOCALAPPDATA%\wt-hud-build\preview-main-backup-*`. The preview has one direct
`Start-Terminal.lnk` entry point. Its actual normal launch passed window-style,
placement, PowerShell 7 executable and error-free startup checks. Installed
Terminal and OS defaults were unchanged. The session exposed one monitor;
secondary-monitor and mixed-DPI restoration still need live validation.

Evidence in the same local build directory: `stable-build-output-3.txt`,
`stable-regression-output.txt`, `stable-desktop-output-1.txt`, and
`stable-preview-output.txt`. The canonical code matches the native build source,
and preview binaries/resources match that tested build.
