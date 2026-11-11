// Licensed under the MIT license.
#include "../HudOwnership.h"
#include <shellapi.h>
#include <objbase.h>
#include <cassert>
#include <iostream>

using Microsoft::Terminal::Hud::Ownership;
using Microsoft::Terminal::Hud::Request;

static UINT requestMessage;
static unsigned requests;
static HANDLE acknowledgement;
static bool elevatedWorker;

static LRESULT CALLBACK windowProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam)
{
    if (message == requestMessage && lparam == 0 && Ownership::IsRequest(wparam))
    {
        ++requests;
        if (acknowledgement) { SetEvent(acknowledgement); }
        if (elevatedWorker && wparam == static_cast<WPARAM>(Request::ToggleVisibility)) { PostQuitMessage(0); }
        return 0;
    }
    return DefWindowProcW(window, message, wparam, lparam);
}

static HWND makeWindow()
{
    WNDCLASSW type{};
    type.lpfnWndProc = windowProc;
    type.hInstance = GetModuleHandleW(nullptr);
    type.lpszClassName = L"HudOwnershipTestWindow";
    RegisterClassW(&type);
    const auto window = CreateWindowExW(0, type.lpszClassName, L"HUD ownership test", WS_POPUP,
                                       0, 0, 10, 10, nullptr, nullptr, type.hInstance, nullptr);
    assert(window);
    return window;
}

static PROCESS_INFORMATION startChild(const std::wstring& mode, const std::wstring& scope)
{
    std::wstring executable(32768, L'\0');
    const auto length = GetModuleFileNameW(nullptr, executable.data(), static_cast<DWORD>(executable.size()));
    assert(length && length < executable.size());
    executable.resize(length);
    auto command = L"\"" + executable + L"\" " + mode + L" " + scope;
    STARTUPINFOW startup{ sizeof(startup) };
    PROCESS_INFORMATION process{};
    assert(CreateProcessW(executable.c_str(), command.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW,
                          nullptr, nullptr, &startup, &process));
    return process;
}

static void waitChild(PROCESS_INFORMATION& process)
{
    const auto deadline = GetTickCount64() + 10000;
    while (WaitForSingleObject(process.hProcess, 10) == WAIT_TIMEOUT)
    {
        assert(GetTickCount64() < deadline);
        MSG message{};
        while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE))
        {
            TranslateMessage(&message);
            DispatchMessageW(&message);
        }
    }
    DWORD result{};
    assert(GetExitCodeProcess(process.hProcess, &result) && result == 0);
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
}

// Explicit opt-in integration check: the UAC prompt is requested only when
// this mode is selected. All windows stay hidden and no input is generated.
static int crossElevation(const std::wstring& scope)
{
    TOKEN_ELEVATION elevation{};
    DWORD size{};
    assert(GetTokenInformation(GetCurrentProcessToken(), TokenElevation, &elevation, sizeof(elevation), &size));
    assert(!elevation.TokenIsElevated); // This side must actually run at normal integrity.
    assert(SUCCEEDED(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED)));
    Ownership observer{ scope };
    const auto ready = CreateEventW(nullptr, TRUE, FALSE, (L"Local\\" + scope + L".Ready").c_str());
    const auto ack = CreateEventW(nullptr, TRUE, FALSE, (L"Local\\" + scope + L".Ack").c_str());
    assert(ready && ack);
    std::wstring executable(32768, L'\0');
    const auto length = GetModuleFileNameW(nullptr, executable.data(), static_cast<DWORD>(executable.size()));
    assert(length && length < executable.size());
    executable.resize(length);
    const auto parameters = L"elevated-owner " + scope;
    SHELLEXECUTEINFOW launch{ sizeof(launch) };
    launch.fMask = SEE_MASK_NOCLOSEPROCESS;
    launch.lpVerb = L"runas";
    launch.lpFile = executable.c_str();
    launch.lpParameters = parameters.c_str();
    launch.nShow = SW_HIDE;
    assert(ShellExecuteExW(&launch));
    assert(WaitForSingleObject(ready, 30000) == WAIT_OBJECT_0);
    SetLastError(ERROR_SUCCESS);
    assert(!observer.TryAcquire());
    assert(GetLastError() != ERROR_ACCESS_DENIED);
    const auto controller = observer.FindOwner();
    assert(controller);
    assert(observer.Send(controller, Request::Activate));
    assert(WaitForSingleObject(ack, 10000) == WAIT_OBJECT_0);
    assert(observer.Send(controller, Request::ToggleVisibility));
    assert(WaitForSingleObject(launch.hProcess, 10000) == WAIT_OBJECT_0);
    DWORD result{};
    assert(GetExitCodeProcess(launch.hProcess, &result) && result == 0);
    assert(observer.TryAcquire());
    observer.Release();
    CloseHandle(launch.hProcess);
    CloseHandle(ack);
    CloseHandle(ready);
    CoUninitialize();
    std::cout << "HUD ownership: normal/elevated exclusion and window-only forwarding passed\n";
    return 0;
}

int wmain(int argc, wchar_t** argv)
{
    // Only hidden disposable windows and an isolated mutex namespace. No global
    // shortcuts, focus changes, input injection or existing Terminal instances.
    const std::wstring scope = argc > 2 ? argv[2] :
        L"WindowsTerminalHUD.Test." + std::to_wstring(GetCurrentProcessId()) + L"." + std::to_wstring(GetTickCount64());
    if (argc > 1 && std::wstring_view{ argv[1] } == L"cross-elevation")
    {
        return crossElevation(scope);
    }
    Ownership owner{ scope };
    requestMessage = owner.Message();
    if (argc > 1)
    {
        const std::wstring_view mode{ argv[1] };
        if (mode == L"contend")
        {
            assert(!owner.TryAcquire());
            const auto controller = owner.FindOwner();
            assert(controller);
            assert(owner.Send(controller, Request::Activate));
            assert(!owner.Send(controller, static_cast<Request>(99)));
            return 0;
        }
        assert(owner.TryAcquire());
        const auto window = makeWindow();
        assert(owner.Publish(window, window));
        if (mode == L"elevated-owner")
        {
            TOKEN_ELEVATION elevation{};
            DWORD size{};
            assert(GetTokenInformation(GetCurrentProcessToken(), TokenElevation, &elevation, sizeof(elevation), &size));
            assert(elevation.TokenIsElevated);
            elevatedWorker = true;
            acknowledgement = OpenEventW(EVENT_MODIFY_STATE, FALSE, (L"Local\\" + scope + L".Ack").c_str());
            const auto ready = OpenEventW(EVENT_MODIFY_STATE, FALSE, (L"Local\\" + scope + L".Ready").c_str());
            assert(acknowledgement && ready && SetEvent(ready));
            MSG message{};
            while (GetMessageW(&message, nullptr, 0, 0) > 0) { DispatchMessageW(&message); }
            CloseHandle(acknowledgement);
            CloseHandle(ready);
        }
        if (mode == L"crash-owner")
        {
            const auto ready = OpenEventW(EVENT_MODIFY_STATE, FALSE, (L"Local\\" + scope + L".Ready").c_str());
            assert(ready && SetEvent(ready));
            CloseHandle(ready);
            Sleep(INFINITE); // Parent terminates only this test child.
        }
        owner.Release();
        assert(!owner.FindOwner());
        DestroyWindow(window);
        return 0;
    }

    assert(!owner.IsOwner() && !owner.FindOwner());
    // The retired mode-conversion request must not enter the v2 protocol.
    assert(!Ownership::IsRequest(0) && !Ownership::IsRequest(2) && !Ownership::IsRequest(99));
    assert(owner.TryAcquire());
    const auto window = makeWindow();
    assert(owner.Publish(window, window));
    assert(owner.IsOwner() && owner.FindOwner() == window);
    auto contender = startChild(L"contend", scope);
    waitChild(contender);
    MSG message{};
    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE))
    {
        DispatchMessageW(&message);
    }
    assert(requests == 1);
    owner.Release();
    assert(!owner.IsOwner() && !owner.FindOwner());
    auto successor = startChild(L"take", scope);
    waitChild(successor);

    const auto ready = CreateEventW(nullptr, TRUE, FALSE, (L"Local\\" + scope + L".Ready").c_str());
    assert(ready);
    auto crashed = startChild(L"crash-owner", scope);
    assert(WaitForSingleObject(ready, 10000) == WAIT_OBJECT_0);
    assert(!owner.TryAcquire() && owner.FindOwner());
    assert(TerminateProcess(crashed.hProcess, 0));
    waitChild(crashed);
    CloseHandle(ready);
    assert(owner.TryAcquire()); // WAIT_ABANDONED is a valid new ownership grant.
    assert(!owner.FindOwner());
    assert(owner.Publish(window, window));
    owner.Release();
    DestroyWindow(window);
    std::cout << "HUD ownership: cross-process exclusion, forwarding, release and crash recovery passed\n";
}
