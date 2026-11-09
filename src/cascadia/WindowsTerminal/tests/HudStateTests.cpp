// Licensed under the MIT license.
#include "../HudState.h"
#include <cassert>
#include <iostream>

using namespace Microsoft::Terminal::Hud;

int main()
{
    // Independent transition table, including both hidden memories.
    constexpr State states[] = { State::Active, State::Passive, State::Hidden, State::Hidden };
    constexpr State expected[][4] = {
        { State::Passive, State::Hidden, State::Active, State::Passive },
        { State::Active, State::Hidden, State::Active, State::Passive },
        { State::Active, State::Active, State::Active, State::Hidden },
        { State::Active, State::Passive, State::Active, State::Hidden },
    };
    constexpr Action actions[] = { Action::ToggleInteraction, Action::ToggleVisibility, Action::Activate, Action::Deactivate };
    for (int row = 0; row < 4; ++row)
    {
        for (int column = 0; column < 4; ++column)
        {
            StateMachine machine;
            if (row == 1 || row == 3)
            {
                machine.Apply(Action::ToggleInteraction);
            }
            if (row >= 2)
            {
                machine.Apply(Action::ToggleVisibility);
            }
            assert(machine.Current() == states[row]);
            assert(machine.Apply(actions[column]) == expected[row][column]);
        }
    }
    // Every sequence of eight actions must preserve valid hidden memory;
    // visibility pairs are reversible even after arbitrary state history.
    for (unsigned sequence = 0; sequence < 65536; ++sequence)
    {
        StateMachine machine;
        auto encoded = sequence;
        for (int step = 0; step < 8; ++step)
        {
            machine.Apply(actions[encoded & 3]);
            encoded >>= 2;
            assert(machine.Remembered() != State::Hidden);
            const auto before = machine.Current();
            machine.Apply(Action::ToggleVisibility);
            assert(machine.Apply(Action::ToggleVisibility) == before);
        }
    }
    std::cout << "HUD state: 16 transitions and 65,536 action sequences passed\n";
}
