// Licensed under the MIT license.
#pragma once

#include <windows.h>

namespace Microsoft::Terminal::Hud
{
    // Owns only HUD input style bits. Never lowers the whole-window alpha:
    // the terminal renderer controls background alpha independently of text.
    class InputMode
    {
    public:
        bool SetPassive(HWND window, const bool passive) noexcept
        {
            constexpr LONG_PTR mask = WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE;
            if (passive)
            {
                if (!_window)
                {
                    _window = window;
                    _originalStyle = GetWindowLongPtrW(window, GWL_EXSTYLE);
                    _hadLayerAttributes = GetLayeredWindowAttributes(window, &_colorKey, &_alpha, &_layerFlags) != FALSE;
                }
                if (_window != window)
                {
                    return false;
                }
                const auto style = GetWindowLongPtrW(window, GWL_EXSTYLE) | mask;
                if (!_setStyle(window, style) || !SetLayeredWindowAttributes(window, 0, 255, LWA_ALPHA))
                {
                    SetPassive(window, false);
                    return false;
                }
            }
            else if (_window)
            {
                if (_window != window)
                {
                    return false;
                }
                const auto style = (GetWindowLongPtrW(window, GWL_EXSTYLE) & ~mask) | (_originalStyle & mask);
                if (!_setStyle(window, style))
                {
                    return false;
                }
                if ((_originalStyle & WS_EX_LAYERED) && _hadLayerAttributes &&
                    !SetLayeredWindowAttributes(window, _colorKey, _alpha, _layerFlags))
                {
                    return false;
                }
                _window = nullptr;
            }
            return true;
        }

    private:
        static bool _setStyle(HWND window, LONG_PTR style) noexcept
        {
            SetLastError(ERROR_SUCCESS);
            if (!SetWindowLongPtrW(window, GWL_EXSTYLE, style) && GetLastError() != ERROR_SUCCESS)
            {
                return false;
            }
            return SetWindowPos(window, nullptr, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED) != FALSE;
        }

        HWND _window{};
        LONG_PTR _originalStyle{};
        COLORREF _colorKey{};
        BYTE _alpha{ 255 };
        DWORD _layerFlags{};
        bool _hadLayerAttributes{};
    };
}
