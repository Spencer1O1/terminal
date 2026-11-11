// Licensed under the MIT license.
#include "pch.h"
#include "AppHost.h"
#include "WindowEmperor.h"

void AppHost::_CaptureHudPlacement()
{
    WINDOWPLACEMENT placement{ sizeof(WINDOWPLACEMENT) };
    THROW_IF_WIN32_BOOL_FALSE(GetWindowPlacement(_window->GetHandle(), &placement));
    _hudNormalPlacement = placement;
}

void AppHost::_HudActionRequested(const winrt::Windows::Foundation::IInspectable&,
                                 const winrt::Microsoft::Terminal::Settings::Model::ShortcutAction action)
{
    _windowManager->RequestHudAction(action);
}

void AppHost::_ExitHudRequested(const winrt::Windows::Foundation::IInspectable&,
                                const winrt::Windows::Foundation::IInspectable&)
{
    _windowLogic.HudModeEnabled(false);
    if (_windowLogic.WindowProperties().WindowName() == L"_hud")
    {
        _windowLogic.WindowName(L"");
    }
}

void AppHost::_RememberHudForeground()
{
    auto foreground = GetForegroundWindow();
    if (_window && foreground == _window->GetHandle())
    {
        foreground = _window->PreviousForegroundWindow();
    }
    if (foreground && (!_window || foreground != _window->GetHandle()) &&
        IsWindowVisible(foreground) && !IsIconic(foreground))
    {
        _hudReturnFocus = foreground;
        _hudReturnFocusThread = GetWindowThreadProcessId(foreground, &_hudReturnFocusProcess);
    }
}

void AppHost::_RestoreHudForeground()
{
    DWORD process{};
    const auto thread = GetWindowThreadProcessId(_hudReturnFocus, &process);
    if (_hudReturnFocus && thread == _hudReturnFocusThread && process == _hudReturnFocusProcess &&
        IsWindowVisible(_hudReturnFocus) && !IsIconic(_hudReturnFocus))
    {
        if (SetForegroundWindow(_hudReturnFocus))
        {
            return;
        }
    }
    // The previous foreground may have closed, including a transient Settings
    // window. Give input to the next eligible window instead of recovering to
    // Active merely because the remembered destination no longer exists.
    EnumWindows([](HWND candidate, LPARAM data) -> BOOL {
        const auto hud = reinterpret_cast<HWND>(data);
        const auto styles = GetWindowLongPtrW(candidate, GWL_EXSTYLE);
        if (candidate != hud && GetAncestor(candidate, GA_ROOTOWNER) != hud &&
            IsWindowVisible(candidate) && IsWindowEnabled(candidate) && !IsIconic(candidate) &&
            !(styles & (WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW)) && SetForegroundWindow(candidate))
        {
            return FALSE;
        }
        return TRUE;
    }, reinterpret_cast<LPARAM>(_window->GetHandle()));
}

void AppHost::ApplyHudAction(const Microsoft::Terminal::Hud::Action action)
{
    using namespace Microsoft::Terminal::Hud;
    if (_changingHudState)
    {
        return;
    }
    _changingHudState = true;
    const auto resetGuard = wil::scope_exit([&] {
        _changingHudState = false;
        PostMessageW(_windowManager->GetMainWindow(), WindowEmperor::WM_HUD_OWNERSHIP_CHANGED, 0, 0);
    });
    const auto hwnd = _window->GetHandle();
    const auto ownedForeground = GetForegroundWindow() == hwnd;
    const auto state = _hudState.Apply(action);
    try
    {
        if (state == State::Active)
        {
            _RememberHudForeground();
            THROW_HR_IF(E_FAIL, !_hudInput.SetPassive(hwnd, false));
            _windowLogic.SetHudMode(true, false);
            // Keep this HUD on its existing monitor when it is summoned.
            winrt::TerminalApp::SummonWindowBehavior summon;
            summon.ToggleVisibility(false);
            summon.DropdownDuration(0);
            summon.ToMonitor(winrt::TerminalApp::MonitorBehavior::InPlace);
            _window->SummonWindow(summon);
            _windowLogic.WindowVisibilityChanged(true);
            if (GetForegroundWindow() != hwnd)
            {
                // Focus can be refused by Windows. Never leave an unfocused
                // fullscreen window intercepting pointer input in that case.
                _hudState.Apply(Action::Deactivate);
                THROW_HR_IF(E_FAIL, !_hudInput.SetPassive(hwnd, true));
                _windowLogic.SetHudMode(true, true);
            }
        }
        else
        {
            THROW_HR_IF(E_FAIL, !_hudInput.SetPassive(hwnd, true));
            _windowLogic.SetHudMode(true, true);
            if (state == State::Hidden)
            {
                ShowWindow(hwnd, SW_HIDE);
                _windowLogic.WindowVisibilityChanged(false);
            }
            else
            {
                ShowWindow(hwnd, SW_SHOWNOACTIVATE);
                _windowLogic.WindowVisibilityChanged(true);
            }
            // A focus-loss notification must never steal focus back.
            if (ownedForeground && action != Action::Deactivate)
            {
                _RestoreHudForeground();
                THROW_HR_IF(E_FAIL, GetForegroundWindow() == hwnd);
            }
        }
    }
    catch (...)
    {
        LOG_CAUGHT_EXCEPTION();
        _hudState.Apply(Action::Activate);
        LOG_HR_IF(E_FAIL, !_hudInput.SetPassive(hwnd, false));
        _windowLogic.SetHudMode(true, false);
        ShowWindow(hwnd, SW_SHOW);
        _windowLogic.WindowVisibilityChanged(true);
    }
}

void AppHost::_IsHudWindowChanged(const winrt::Windows::Foundation::IInspectable&,
                                  const winrt::Windows::Foundation::IInspectable&)
{
    ++_hudModeGeneration;
    const auto enabled = _windowLogic.IsHudWindow();
    if (enabled && !_windowManager->ClaimHudOwnership(*this))
    {
        // Another process won the role. Never apply HUD effects without the lease.
        _windowLogic.HudModeEnabled(false);
        _windowManager->ActivateHudOwner();
        return;
    }
    {
        const auto previousChanging = std::exchange(_changingHudState, true);
        const auto guard = wil::scope_exit([&] { _changingHudState = previousChanging; });
        if (enabled)
        {
            _CaptureHudPlacement();
            _RememberHudForeground();
            _hudState = {};
        }
        else
        {
            // Release HUD input before restoring the normal presentation.
            THROW_HR_IF(E_FAIL, !_hudInput.SetPassive(_window->GetHandle(), false));
            ShowWindow(_window->GetHandle(), SW_SHOW);
            _windowLogic.WindowVisibilityChanged(true);
        }
        _windowLogic.SetHudMode(enabled, false);
        _window->SetAlwaysOnTop(enabled || _windowLogic.AlwaysOnTop());
        _window->SetAutoHideWindow(!enabled && _windowLogic.AutoHideWindow());
        _window->SetShowTabsFullscreen(!enabled && _windowLogic.ShowTabsFullscreen());
        if (!enabled && _hudNormalPlacement)
        {
            const auto placement = *_hudNormalPlacement;
            _hudNormalPlacement.reset();
            LOG_IF_WIN32_BOOL_FALSE(SetWindowPlacement(_window->GetHandle(), &placement));
        }
    }
    if (enabled && _isWindowInitialized == WindowInitializedState::Initialized)
    {
        ApplyHudAction(Microsoft::Terminal::Hud::Action::Activate);
    }
    if (!enabled)
    {
        _windowManager->ReleaseHudOwnership(*this);
    }
    _updateTheme();
    PostMessageW(_windowManager->GetMainWindow(), WindowEmperor::WM_HUD_OWNERSHIP_CHANGED, 0, 0);
}
