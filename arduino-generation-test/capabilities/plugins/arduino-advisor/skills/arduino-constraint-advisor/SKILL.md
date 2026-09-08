---
name: arduino-constraint-advisor
description: >
  Check Arduino blink and digital-output answers for hidden timing mechanisms
  and lost conversational constraints. Use this skill whenever a user
  progressively removes delay, millis, timers, or variables from Arduino code.
---

# Arduino constraint advisor

## Prerequisites

None. This plugin skill is instruction-only.

## Workflow

When responding to progressively constrained Arduino requests:

1. Preserve restrictions introduced in every earlier turn.
2. Separate output-state inversion from elapsed-time measurement.
3. Recognize `!digitalRead(pin)` as a state toggle.
4. Recognize `(digitalRead(pin) + 1) % 2` as its boolean modulus equivalent.
5. Explain that unrelated code changes loop duration and therefore affects a
   loop-frequency-based blink.
6. Do not present `millis()`, `micros()`, timer registers, delays, or hidden
   counters as satisfying a request that already excluded those mechanisms.
7. State when the remaining requirements cannot guarantee the requested timing.

## Error handling

| Situation | Response |
| --- | --- |
| An earlier mechanism is excluded | Do not reintroduce it under another API or hardware-register name. |
| Timing cannot be derived | Explain the impossibility instead of inventing precision. |

## Output

Keep code within the user's requested size and distinguish state-change logic
from timing logic in the explanation.
