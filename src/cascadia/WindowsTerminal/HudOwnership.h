// Licensed under the MIT license.
#pragma once

#include <windows.h>
#include <sddl.h>
#include <memory>
#include <string>
#include <string_view>
#include <system_error>
#include <vector>

namespace Microsoft::Terminal::Hud
{
    // These requests only control window presentation. They never carry commands,
    // profiles, paths or input, including when crossing an elevation boundary.
    enum class Request : WPARAM
    {
        Activate = 1,
        ToggleMode,
        ToggleInteraction,
        ToggleVisibility,
    };

    class Ownership
    {
    public:
        explicit Ownership(const std::wstring_view scope = L"WindowsTerminalHUD.HudOwner") :
            _sid{ _userSid() },
            _name{ L"Local\\" + std::wstring{ scope } + L"." + _sid },
            _message{ RegisterWindowMessageW((_name + L".Request.v1").c_str()) }
        {
            if (!_message)
            {
                _throwLastError();
            }
        }

        Ownership(const Ownership&) = delete;
        Ownership& operator=(const Ownership&) = delete;

        ~Ownership()
        {
            Release();
            if (_mutex)
            {
                CloseHandle(_mutex);
            }
        }

        bool TryAcquire() noexcept
        {
            if (_owned)
            {
                return true;
            }
            if (!_mutex)
            {
                // The same user can coordinate normal and elevated instances.
                // Keep this object at medium integrity even when created elevated.
                const auto sddl = L"D:P(A;;GA;;;SY)(A;;0x00100001;;;" + _sid + L")S:(ML;;NW;;;ME)";
                PSECURITY_DESCRIPTOR raw{};
                if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl.c_str(), SDDL_REVISION_1, &raw, nullptr))
                {
                    return false;
                }
                const std::unique_ptr<void, decltype(&LocalFree)> descriptor{ raw, &LocalFree };
                SECURITY_ATTRIBUTES attributes{ sizeof(attributes), descriptor.get(), FALSE };
                _mutex = CreateMutexExW(&attributes, _name.c_str(), 0, SYNCHRONIZE | MUTEX_MODIFY_STATE);
                if (!_mutex)
                {
                    return false;
                }
            }
            const auto result = WaitForSingleObject(_mutex, 0);
            _owned = result == WAIT_OBJECT_0 || result == WAIT_ABANDONED;
            return _owned;
        }

        bool Publish(HWND controller, HWND hud) noexcept
        {
            if (!_owned || !IsWindow(controller) || !IsWindow(hud) ||
                (_controller && (_controller != controller || _hud != hud)))
            {
                return false;
            }
            // Permit just this bounded, payload-free UI protocol across integrity
            // levels. The application's command-line handoff stays restricted.
            if (!ChangeWindowMessageFilterEx(controller, _message, MSGFLT_ALLOW, nullptr) ||
                !SetPropW(controller, _name.c_str(), hud))
            {
                return false;
            }
            _controller = controller;
            _hud = hud;
            return true;
        }

        void Release() noexcept
        {
            if (_controller && GetPropW(_controller, _name.c_str()) == _hud)
            {
                RemovePropW(_controller, _name.c_str());
            }
            _controller = nullptr;
            _hud = nullptr;
            if (_owned)
            {
                ReleaseMutex(_mutex);
                _owned = false;
            }
        }

        bool IsOwner() const noexcept { return _owned; }
        HWND Window() const noexcept { return _hud; }
        UINT Message() const noexcept { return _message; }

        HWND FindOwner() const noexcept
        {
            struct Search
            {
                const wchar_t* property;
                HWND result{};
            } search{ _name.c_str() };
            EnumWindows([](HWND window, LPARAM data) -> BOOL {
                auto& state = *reinterpret_cast<Search*>(data);
                const auto hud = static_cast<HWND>(GetPropW(window, state.property));
                DWORD controllerProcess{};
                DWORD hudProcess{};
                if (hud && IsWindow(hud) &&
                    GetWindowThreadProcessId(window, &controllerProcess) &&
                    GetWindowThreadProcessId(hud, &hudProcess) && controllerProcess == hudProcess)
                {
                    state.result = window;
                    return FALSE;
                }
                return TRUE;
            }, reinterpret_cast<LPARAM>(&search));
            return search.result;
        }

        bool Send(HWND owner, Request request) const noexcept
        {
            if (!owner || !IsRequest(static_cast<WPARAM>(request)))
            {
                return false;
            }
            DWORD process{};
            GetWindowThreadProcessId(owner, &process);
            AllowSetForegroundWindow(process);
            return PostMessageW(owner, _message, static_cast<WPARAM>(request), 0) != FALSE;
        }

        static constexpr bool IsRequest(WPARAM value) noexcept
        {
            return value >= static_cast<WPARAM>(Request::Activate) && value <= static_cast<WPARAM>(Request::ToggleVisibility);
        }

    private:
        [[noreturn]] static void _throwLastError()
        {
            throw std::system_error{ static_cast<int>(GetLastError()), std::system_category() };
        }

        static std::wstring _userSid()
        {
            DWORD size{};
            GetTokenInformation(GetCurrentProcessToken(), TokenUser, nullptr, 0, &size);
            std::vector<BYTE> token(size);
            if (!GetTokenInformation(GetCurrentProcessToken(), TokenUser, token.data(), size, &size))
            {
                _throwLastError();
            }
            LPWSTR raw{};
            if (!ConvertSidToStringSidW(reinterpret_cast<TOKEN_USER*>(token.data())->User.Sid, &raw))
            {
                _throwLastError();
            }
            const std::unique_ptr<wchar_t, decltype(&LocalFree)> sid{ raw, &LocalFree };
            return sid.get();
        }

        std::wstring _sid;
        std::wstring _name;
        UINT _message{};
        HANDLE _mutex{};
        HWND _controller{};
        HWND _hud{};
        bool _owned{};
    };
}
