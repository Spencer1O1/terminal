// Licensed under the MIT license.
#include "../HudState.h"
#include <cassert>
#include <iostream>

using namespace Microsoft::Terminal::Hud;

int main()
{
    // Summon activates; interaction only changes a visible HUD. Hide has no
    // remembered interaction state, so a subsequent summon always starts Active.
    constexpr State states[] = { State::Active, State::Passive, State::Hidden };
    constexpr State expected[][4] = {
        { State::Passive, State::Hidden, State::Active, State::Passive },
        { State::Active, State::Hidden, State::Active, State::Passive },
        { State::Hidden, State::Hidden, State::Active, State::Hidden },
    };
    constexpr Action actions[] = { Action::ToggleInteraction, Action::Hide, Action::Activate, Action::Deactivate };
    for (int row = 0; row < 3; ++row)
    {
        for (int column = 0; column < 4; ++column)
        {
            StateMachine machine;
            if (row == 1) { machine.Apply(Action::Deactivate); }
            if (row == 2) { machine.Apply(Action::Hide); }
            assert(machine.Current() == states[row]);
            assert(machine.Apply(actions[column]) == expected[row][column]);
        }
    }
    for (unsigned sequence = 0; sequence < 65536; ++sequence)
    {
        StateMachine machine;
        auto reference = State::Active;
        auto encoded = sequence;
        for (int step = 0; step < 8; ++step)
        {
            const auto column = encoded & 3;
            reference = expected[static_cast<int>(reference)][column];
            assert(machine.Apply(actions[column]) == reference);
            encoded >>= 2;
        }
    }
    std::cout << "HUD state: 12 transitions and 65,536 action sequences passed\n";
}
