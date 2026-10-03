# Fightcade Record / Playback Dummy

Record what the P2 character does, then make P2 repeat it while you play P1. Great for practicing punishes.

Training mode only. Made for Fightcade's FBNeo.

## Install

1. Start a game in **training / offline mode**.
2. In the emulator window: **Game > Lua Scripting > New Lua Script Window**.
3. Click **Browse**, pick `fightcade_record_play.lua`, then click **Run**.

## How to use

1. Press **Record**. Your controls now move the **P2** character (and P1 guards).
2. Do the move you want to practice against.
3. Press **Record** again to stop.
4. Put the characters back in position, then press **Play**. P2 repeats your move and you control P1.
5. Press **Stop** when you're done.

## Main buttons

| Action | Keyboard | Controller |
|--------|----------|------------|
| Record / stop recording | **R** | Coin + A |
| Play | **P** | Coin + B |
| Stop | **T** | Coin + C |
| Loop on / off | **Y** | Coin + D |
| Mirror on / off | **M** | Coin + Start |

For controller combos, **hold the first button, then press the other one.** Coin is usually the Select / Back button. Press **Q** (or Start + D) any time to show all buttons on screen.

## More buttons

| Action | Keyboard | Controller |
|--------|----------|------------|
| Guard high / low | **G** | Coin + Down |
| Guard direction (flip) | **H** | Coin + Up |
| Next recording slot | **N** | Coin + Right |
| Previous recording slot | **B** | Coin + Left |
| Savestate reset on / off | **U** | Start + A |
| Playback delay (cycles off, 30, 60, random) | **V** | Start + B |
| Random slot on / off | **X** | Start + C |
| Show / hide help | **Q** | Start + D |

## Features

- **Guard while recording:** P1 holds back automatically so it blocks P2's attacks. Use **G** to switch between standing and crouching guard. If P1 walks toward P2 instead, press **H**.
- **5 recording slots:** choose a slot with **N / B** (while idle), then record into it. The slot list (with the frame count of each slot) is shown on screen.
- **Automatic saving:** recordings are saved to `record_play_<game>.txt` in the emulator's folder when you stop recording, and loaded again when you run the script.
- **Playback delay:** P2 waits a short time before starting, so you can't predict the timing. The delay repeats on every loop. Press **V** to cycle: off, 30 frames, 60 frames, random (0 to 90 frames).
- **Random slot:** with several slots recorded, P2 plays a random one each time. Great for practicing against mixups.
- **Savestate reset (optional, experimental):** press **U** to turn it on. Each recording remembers its starting position and **Play** puts the characters back there every time. It uses the emulator's save slots 5 to 9, so don't keep your own saves there.

- **On-screen text:** your settings and slot list stay on screen, and a colored line shows **REC** or **PLAY** while recording or playing. Press **Q** to also show the hotkey list. To move the text or hide it, change `TEXT_X`, `TEXT_Y` or `SHOW_TEXT` at the top of the script. For a quieter screen, set `ALWAYS_SHOW_DETAILS = false` and the settings will only appear for a few seconds after you change something. If the colors look wrong in your emulator, set `TEXT_COLORS = false`.

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
