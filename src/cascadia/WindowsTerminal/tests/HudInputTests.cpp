// Licensed under the MIT license.
#include "../HudInput.h"
#include <cassert>
#include <iostream>

using Microsoft::Terminal::Hud::InputMode;

int main()
{
    // Hidden, disposable windows. This test does not steal focus, inject input,
    // register global hotkeys, or change any existing Terminal window.
    const auto window = CreateWindowExW(0, L"STATIC", L"HUD style test", WS_POPUP, 0, 0, 100, 100, nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
    assert(window);
    const auto original = GetWindowLongPtrW(window, GWL_EXSTYLE);
    InputMode input;
    assert(input.SetPassive(window, true));
    const auto passive = GetWindowLongPtrW(window, GWL_EXSTYLE);
    assert(passive & WS_EX_LAYERED);
    assert(passive & WS_EX_TRANSPARENT);
    assert(passive & WS_EX_NOACTIVATE);
    COLORREF color{};
    BYTE alpha{};
    DWORD flags{};
    assert(GetLayeredWindowAttributes(window, &color, &alpha, &flags));
    assert(alpha == 255 && flags == LWA_ALPHA);
    assert(input.SetPassive(window, true)); // idempotent
    const auto other = CreateWindowExW(0, L"STATIC", L"HUD unrelated window", WS_POPUP, 0, 0, 100, 100, nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
    assert(other);
    const auto otherStyle = GetWindowLongPtrW(other, GWL_EXSTYLE);
    assert(!input.SetPassive(other, true));
    assert(!input.SetPassive(other, false));
    assert(GetWindowLongPtrW(other, GWL_EXSTYLE) == otherStyle);
    assert(GetWindowLongPtrW(window, GWL_EXSTYLE) == passive);
    DestroyWindow(other);
    // Unrelated native style changes must survive releasing HUD input mode.
    SetWindowLongPtrW(window, GWL_EXSTYLE, passive | WS_EX_TOOLWINDOW);
    assert(input.SetPassive(window, false));
    assert(GetWindowLongPtrW(window, GWL_EXSTYLE) == (original | WS_EX_TOOLWINDOW));
    assert(input.SetPassive(window, false));
    DestroyWindow(window);

    const auto layered = CreateWindowExW(WS_EX_LAYERED, L"STATIC", L"HUD existing alpha test", WS_POPUP, 0, 0, 100, 100, nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
    assert(layered);
    assert(SetLayeredWindowAttributes(layered, RGB(1, 2, 3), 173, LWA_ALPHA | LWA_COLORKEY));
    assert(input.SetPassive(layered, true));
    assert(input.SetPassive(layered, false));
    assert(GetWindowLongPtrW(layered, GWL_EXSTYLE) & WS_EX_LAYERED);
    assert(GetLayeredWindowAttributes(layered, &color, &alpha, &flags));
    assert(color == RGB(1, 2, 3) && alpha == 173 && flags == (LWA_ALPHA | LWA_COLORKEY));
    DestroyWindow(layered);
    std::cout << "HUD input: native style ownership and alpha restoration passed\n";
}
