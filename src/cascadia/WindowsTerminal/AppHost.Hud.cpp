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

void AppHost::_ToggleHudModeRequested(const winrt::Windows::Foundation::IInspectable&,
                                      const winrt::Windows::Foundation::IInspectable&)
{
    if (!_windowLogic.IsHudWindow())
    {
        if (const auto existing = _windowManager->GetHudWindow(); existing && existing != this)
        {
            // Retain one HUD per app instance. Activate that HUD instead of
            // unexpectedly changing the role of a second window.
            winrt::TerminalApp::SummonWindowBehavior summon;
            summon.ToggleVisibility(false);
            summon.ToMonitor(winrt::TerminalApp::MonitorBehavior::InPlace);
            existing->HandleSummon(summon);
            return;
        }
    }
    _windowLogic.HudModeEnabled(!_windowLogic.IsHudWindow());
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
        SetForegroundWindow(_hudReturnFocus);
    }
}

void AppHost::_ApplyHudState(const Microsoft::Terminal::Hud::Action action)
{
    using namespace Microsoft::Terminal::Hud;
    if (_changingHudState)
    {
        return;
    }
    _changingHudState = true;
    const auto resetGuard = wil::scope_exit([&] { _changingHudState = false; });
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
        _ApplyHudState(Microsoft::Terminal::Hud::Action::Activate);
    }
    _updateTheme();
    PostMessageW(_windowManager->GetMainWindow(), WindowEmperor::WM_UPDATE_NOTIFICATION_ICON, 0, 0);
}
