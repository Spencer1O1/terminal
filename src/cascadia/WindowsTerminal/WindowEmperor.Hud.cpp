// Licensed under the MIT license.
#include "pch.h"
#include "WindowEmperor.h"
#include "AppHost.h"

using Microsoft::Terminal::Hud::Request;
using ShortcutAction = winrt::Microsoft::Terminal::Settings::Model::ShortcutAction;

AppHost* WindowEmperor::GetHudWindow() const noexcept
{
    _assertIsMainThread();
    if (const auto host = _hudHost.lock(); host && host->Logic() && host->Logic().IsHudWindow())
    {
        return host.get();
    }
    return nullptr;
}

bool WindowEmperor::ClaimHudOwnership(AppHost& host)
{
    _assertIsMainThread();
    if (const auto existing = _hudHost.lock(); existing && existing.get() != &host)
    {
        return false;
    }
    if (!_hudOwnership.TryAcquire())
    {
        return false;
    }
    if (!_hudOwnership.Publish(_window.get(), host.GetWindow()->GetHandle()))
    {
        _hudOwnership.Release();
        return false;
    }
    if (_hudHost.expired())
    {
        ++_hudOwnershipEpoch;
    }
    _hudHost = host.shared_from_this();
    PostMessageW(_window.get(), WM_HUD_OWNERSHIP_CHANGED, 0, 0);
    return true;
}

void WindowEmperor::ReleaseHudOwnership(AppHost& host)
{
    _assertIsMainThread();
    if (_hudOwnership.Window() == host.GetWindow()->GetHandle())
    {
        _hudHost.reset();
        _hudOwnership.Release();
        ++_hudOwnershipEpoch;
        _pendingHudRequests.clear();
        PostMessageW(_window.get(), WM_HUD_OWNERSHIP_CHANGED, 0, 0);
    }
}

bool WindowEmperor::_forwardHudRequest(const Request request)
{
    if (const auto owner = _hudOwnership.FindOwner())
    {
        if (owner == _window.get())
        {
            _handleHudRequest(request);
        }
        else
        {
            LOG_LAST_ERROR_IF(!_hudOwnership.Send(owner, request));
        }
        // Discovery of an owner must never fall through to creating another HUD,
        // including if that owner's process is closing or not responding.
        return true;
    }
    return false;
}

void WindowEmperor::ActivateHudOwner()
{
    _assertIsMainThread();
    _forwardHudRequest(Request::Activate);
}

void WindowEmperor::RequestHudAction(const ShortcutAction action)
{
    _assertIsMainThread();
    Request request;
    switch (action)
    {
    case ShortcutAction::HudMode:
        request = Request::ToggleInteraction;
        break;
    case ShortcutAction::HudVisibility:
        request = Request::ToggleVisibility;
        break;
    default:
        return;
    }
    if (_forwardHudRequest(request) || request != Request::ToggleVisibility)
    {
        return;
    }
    _createNamedWindow(L"_hud");
}

void WindowEmperor::_handleHudRequest(const Request request)
{
    const auto host = _hudHost.lock();
    if (!_hudOwnership.IsOwner() || !host || !host->IsInitialized() || !host->Logic().IsHudWindow())
    {
        return;
    }
    if (host->IsChangingHudState())
    {
        _pendingHudRequests.emplace_back(_hudOwnershipEpoch, request);
        return;
    }
    if (request == Request::ToggleVisibility)
    {
        // Share Quake's actual summon defaults and monitor/activation behavior.
        static const auto quake = winrt::Microsoft::Terminal::Settings::Model::ActionAndArgs::Deserialize(LR"({"actions":["quakeMode"]})").GetAt(0).Args().as<winrt::Microsoft::Terminal::Settings::Model::GlobalSummonArgs>();
        host->HandleSummon(_makeSummonArgs(quake).SummonBehavior);
    }
    else
    {
        using Microsoft::Terminal::Hud::Action;
        host->ApplyHudAction(request == Request::ToggleInteraction ? Action::ToggleInteraction : Action::Activate);
    }
}

void WindowEmperor::_drainHudRequests()
{
    if (const auto host = _hudHost.lock(); host && host->IsChangingHudState())
    {
        return;
    }
    // Native presentation changes pump messages. Serialize requests received
    // during those changes and discard them when their ownership has ended.
    const auto pending = std::exchange(_pendingHudRequests, {});
    for (const auto& [epoch, request] : pending)
    {
        if (epoch == _hudOwnershipEpoch)
        {
            _handleHudRequest(request);
        }
    }
}
