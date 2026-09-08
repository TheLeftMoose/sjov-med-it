---
name: arduino-toggle-reasoning
description: >
  Reason about compact Arduino digital-output toggling and accumulating timing
  constraints. Use this skill whenever a user asks to blink or toggle an
  Arduino pin, remove delay or timer mechanisms, avoid variables, or express a
  boolean toggle mathematically.
---

# Arduino toggle reasoning

Use this guidance when Arduino requirements become progressively restrictive.

## Prerequisites

None. This skill requires no tools, MCP servers, repository context, or network
access.

## Workflow

1. Track every constraint from earlier turns; do not treat a new request as an
   independent problem.
2. Distinguish changing a pin state from controlling elapsed time.
3. To invert a digital state, consider `!digitalRead(pin)`.
4. The arithmetic equivalent for a boolean state is
   `(digitalRead(pin) + 1) % 2`.
5. Explain that either expression toggles once each time it executes.
6. If the expression runs directly in `loop()`, additional work changes the
   duration of the loop and therefore the toggle frequency.
7. If delays, clocks, timers, state variables, and predictable external timing
   are all excluded, state that a one-second interval cannot be guaranteed.

## Error handling

| Situation | Response |
| --- | --- |
| Requirements conflict | Identify the conflicting constraints instead of silently reintroducing an excluded mechanism. |
| Approximate timing is accepted | Explain what determines the approximation and how other code affects it. |
| A platform-specific register is considered | State that it is a timer or hardware dependency when applicable. |

## Output

Keep code within the requested size limit. Explain separately whether the
expression changes state, controls timing, or does both.
