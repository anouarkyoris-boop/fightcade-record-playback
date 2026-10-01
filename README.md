# Fightcade Record / Playback Dummy

A small Lua script for Fightcade's FBNeo emulator. Record your own (P1) inputs, then have the P2 dummy replay them on demand. Useful for practicing against setups, pressure strings, and tricky sequences in training mode.

## Install

1. Start a game in **training / offline mode**.
2. In the emulator window: **Game > Lua Scripting > New Lua Script Window**.
3. Click **Browse**, pick `fightcade_record_play.lua`, then click **Run**.

## How to use

1. Press **Record**. Your controls now move the **P2** character.
2. Do the move you want to practice against.
3. Press **Record** again to stop.
4. Put the characters back in position, then press **Play**. P2 repeats your move and you control P1.
5. Press **Stop** when you're done.

## Buttons

| Action | Keyboard | Controller |
|--------|----------|------------|
| Record / stop recording | **R** | Coin + A |
| Play | **P** | Coin + B |
| Stop | **T** | Coin + C |
| Loop on / off | **Y** | Coin + D |
| Mirror on / off | **M** | Coin + Start |

For controller combos, **hold Coin first, then press the other button.** Coin is usually the Select / Back button.

## Tips

- Loop is on by default, so P2 repeats your move until you press Stop.
- If P2 moves the wrong direction while you record, press **Mirror** (M) after starting the recording.
- If the controller combos don't work, your game may name its buttons differently. See "Change the buttons" below.

## Change the buttons (optional)

Open the script in any text editor. Near the top, the `HOTKEYS` list shows each action and its buttons. For example, this line means "R on the keyboard, or Coin + Button A on the controller":

```lua
rec = { {"R"}, {"P1 Coin", "P1 Button A"} },
```

To find your controller's button names, set `PRINT_BUTTONS = true` in the script, run it, press your buttons, and read the names printed in the Lua console. Set it back to `false` when you're done.
