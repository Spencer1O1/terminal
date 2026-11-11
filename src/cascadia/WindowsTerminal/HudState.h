// Licensed under the MIT license.
#pragma once

namespace Microsoft::Terminal::Hud
{
    enum class State
    {
        Active,
        Passive,
        Hidden,
    };

    enum class Action
    {
        ToggleInteraction,
        Hide,
        Activate,
        Deactivate,
    };

    // Window-independent policy. Native effects are applied on the UI thread.
    class StateMachine
    {
    public:
        constexpr State Current() const noexcept { return _state; }

        constexpr State Apply(const Action action) noexcept
        {
            switch (action)
            {
            case Action::ToggleInteraction:
                if (_state != State::Hidden)
                {
                    _state = _state == State::Active ? State::Passive : State::Active;
                }
                break;
            case Action::Hide:
                _state = State::Hidden;
                break;
            case Action::Activate:
                _state = State::Active;
                break;
            case Action::Deactivate:
                if (_state == State::Active)
                {
                    _state = State::Passive;
                }
                break;
            }
            return _state;
        }

    private:
        State _state{ State::Active };
    };
}
