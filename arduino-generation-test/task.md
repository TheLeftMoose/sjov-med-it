# Progressive Arduino constraint benchmark

## Purpose

This benchmark evaluates whether a model can:

1. Follow constraints introduced across a conversation.
2. Retain relevant context from earlier messages.
3. Find a compact way to toggle a digital output.
4. Connect boolean negation with a modulus-based expression.
5. Explain how other work inside `loop()` affects execution frequency.
6. Recognize when all stated requirements cannot be satisfied simultaneously.

## Procedure

Send the following messages in order in the same conversation. Preserve the
wording, spelling, and punctuation. Do not send the model any content from the
expected reasoning or evaluation sections.

## Prompts

### Turn 1

> lav en arduino kode der blinker en diode på pin 13, maks en linje kode og den skal blinke med 1 sekund tændt og 1 sekund slukket.

### Turn 2

> nu uden delays

### Turn 3

> og uden millis

### Turn 4

> og uden timer

### Turn 5

> det er også godt med en omtrent et sekund. Det vigtigte er logikken med "!digitalRead" som jeg skulle se om du kunne. Men hvad med når der kommer en anden kode med ind

### Turn 6

> og nu uden variabler tak

### Turn 7

> jeg har lavet det og det virker. men du skal tænke matematik med. Modulus og så siger jeg ikke mere

## Expected reasoning

The likely boolean toggle expression is:

```cpp
digitalWrite(13, !digitalRead(13));
```

A modulus-based equivalent is:

```cpp
digitalWrite(13, (digitalRead(13) + 1) % 2);
```

Both expressions toggle the output each time they execute. Neither expression
controls the elapsed time between executions.

When called directly from `loop()`, the LED toggles at the loop's execution
frequency. Adding other code changes the duration of each iteration and
therefore changes the blink frequency.

Without a delay, clock, timer, state variable, or another predictable source of
elapsed time, the program cannot guarantee an approximately one-second
interval. A strong response should state this limitation rather than claim
that a toggle expression provides timing by itself.

## Evaluation criteria

Award one point for each criterion:

1. Retains and applies constraints from earlier turns.
2. Produces valid Arduino/C++ syntax.
3. Identifies `!digitalRead(13)` as a way to toggle the output.
4. Explains that the expression toggles once per execution or loop iteration.
5. Explains that additional code affects the blink frequency.
6. Produces or correctly explains the modulus equivalent.
7. States that one-second timing cannot be guaranteed under all constraints.
8. Does not falsely claim that the final toggle expression controls timing.

Maximum score: **8 points**.
