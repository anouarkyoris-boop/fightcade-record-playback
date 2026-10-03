-- Record / Playback dummy for Fightcade (FBNeo Lua)
-- Record: your P1 controls drive P2. Play: P2 repeats it while you play P1.
-- Default keyboard: R record, P play, T stop, Y loop, M mirror, G guard high/low,
-- H guard direction, E guard on/off, N / B next / previous slot, U savestate on/off,
-- V playback delay, X random slot, Q on-screen help.
-- Controller combos are configured in HOTKEYS below.
-- Messages are logged to the Lua console with the prefix [rp].

---------------------------------------------------------------- settings
local NUM_SLOTS = 5               -- how many recordings you can keep
local AUTO_SAVE_TO_FILE = true    -- save slots to a file after each recording, load on start
local USE_SAVESTATE = false       -- start with savestate reset on/off (toggle with the state hotkey)
local STATE_SLOT_BASE = 5         -- recording slot 1 uses emulator state slot 5, slot 2 uses 6, ...
local BLOCK_P1_WHILE_RECORDING = true  -- freeze P1 while you control P2
local MIRROR_AT_RECORD_START = false   -- mirror forced when recording starts (false/true/nil)
-- While recording, P1 holds back so it guards P2's attacks.
local GUARD_ON_RECORD = true
local GUARD_DIRECTION = "Left"    -- P1's back direction: "Left" if P1 is on the left, "Right" if on the right
local GUARD_CROUCH = false        -- starting guard: false = standing (high), true = crouching (low)
local PRINT_BUTTONS = false       -- true = print pressed controller button names to the console
local DELAY_STEPS = { 0, 30, 60, "random" }  -- playback start delays in frames (cycle with the delay hotkey)
local RANDOM_DELAY_MAX = 90       -- the "random" delay picks 0 to this many frames

-- On-screen text: a colored REC / PLAY line while recording or playing, plus the
-- settings and slot list.
local SHOW_TEXT = true            -- false = hide all on-screen text
local ALWAYS_SHOW_DETAILS = true  -- true = settings always visible; false = only for a few seconds after a change
local TEXT_X, TEXT_Y = 4, 66      -- top-left corner of the text (just under the health bars)
local TEXT_COLORS = true          -- colored text on a dark backdrop (set false if it looks wrong)
local INFO_SECONDS = 3            -- when ALWAYS_SHOW_DETAILS is false: how long the details stay after a change

-- Hotkeys. Each action has a list of alternatives; any one of them triggers it.
-- An alternative is a list of inputs that must ALL be held at once (a chord).
-- Inputs can be keyboard keys ("R") or controller buttons ("P1 Coin").
-- For controller combos: hold the FIRST input, then press the others.
local HOTKEYS = {
  rec       = { {"R"}, {"P1 Coin", "P1 Button A"} },
  play      = { {"P"}, {"P1 Coin", "P1 Button B"} },
  stop      = { {"T"}, {"P1 Coin", "P1 Button C"} },
  loop      = { {"Y"}, {"P1 Coin", "P1 Button D"} },
  mirror    = { {"M"}, {"P1 Coin", "P1 Start"} },
  guard     = { {"G"}, {"P1 Coin", "P1 Down"} },
  side      = { {"H"}, {"P1 Coin", "P1 Up"} },
  guard_toggle = { {"E"}, {"P1 Start", "P1 Up"} },
  slot_next = { {"N"}, {"P1 Coin", "P1 Right"} },
  slot_prev = { {"B"}, {"P1 Coin", "P1 Left"} },
  state     = { {"U"}, {"P1 Start", "P1 Button A"} },
  delay     = { {"V"}, {"P1 Start", "P1 Button B"} },
  random    = { {"X"}, {"P1 Start", "P1 Button C"} },
  help      = { {"Q"}, {"P1 Start", "P1 Button D"} },
}

-- System buttons that are never recorded or copied to P2
local IGNORE = { "Coin", "Start", "Select", "Service", "Test", "Reset",
                 "Diagnostic", "Dip", "Region", "Fake" }

---------------------------------------------------------------- state
local IDLE, REC, PLAY = 0, 1, 2
local mode = IDLE
local pos = 0
local loop, mirror = true, false
local guard_dir = GUARD_DIRECTION
local guard_low = GUARD_CROUCH
local guard_on = GUARD_ON_RECORD  -- current: does P1 guard while recording?
local use_state = USE_SAVESTATE
local delay_i = 1           -- index into DELAY_STEPS
local random_slot = false   -- true = each playback pass picks a random non-empty slot
local show_help = false
local wait = 0              -- frames left before P2 starts the current pass
local play_slot = 1         -- slot currently being played
pcall(function() math.randomseed(os.time()) end)
local prev = {}
local logged = 0
local last_print = ""
local pad_now = {}      -- joypad.get() for the current frame
local chord_held = {}   -- inputs belonging to a hotkey that is currently held
local pending = {}      -- joypad overrides collected this frame, applied once at the end

local slots = {}
for i = 1, NUM_SLOTS do slots[i] = { frames = {}, has_state = false } end
local cur = 1

local function log(...) print("[rp]", ...) end

local frame_count = 0
local info_until = 6 * 60   -- show the details (with a hint) for the first 6 seconds
local hint_until = 6 * 60
local function flash() info_until = frame_count + INFO_SECONDS * 60 end

---------------------------------------------------------------- file saving
local function rom_name()
  local ok, n = pcall(function() return emu.romname() end)
  if ok and type(n) == "string" and n ~= "" then return (n:gsub("[^%w_%-]", "_")) end
  return "game"
end

local SAVE_FILE = "record_play_" .. rom_name() .. ".txt"

local function frame_key(f)
  local t = {}
  for b in pairs(f) do t[#t + 1] = b end
  table.sort(t)
  if #t == 0 then return "-" end
  return table.concat(t, "|")
end

local function save_file()
  local fh, err = io.open(SAVE_FILE, "w")
  if not fh then log("save failed:", err) return end
  fh:write("FRP1\n")
  for i = 1, NUM_SLOTS do
    local frames = slots[i].frames
    if #frames > 0 then
      fh:write("SLOT ", i, "\n")
      if slots[i].has_state then fh:write("STATE\n") end
      local run_key, run_n = nil, 0
      for _, f in ipairs(frames) do
        local k = frame_key(f)
        if k == run_key then
          run_n = run_n + 1
        else
          if run_key then fh:write(run_n, " ", run_key, "\n") end
          run_key, run_n = k, 1
        end
      end
      if run_key then fh:write(run_n, " ", run_key, "\n") end
      fh:write("END\n")
    end
  end
  fh:close()
  log("saved to", SAVE_FILE)
end

local function load_file()
  local fh = io.open(SAVE_FILE, "r")
  if not fh then return end
  local slot = nil
  for line in fh:lines() do
    local idx = line:match("^SLOT (%d+)")
    if idx then
      slot = tonumber(idx)
      if slot < 1 or slot > NUM_SLOTS then slot = nil else slots[slot].frames = {} end
    elseif line:match("^END") then
      slot = nil
    elseif slot and line:match("^STATE") then
      slots[slot].has_state = true
    elseif slot then
      local n, key = line:match("^(%d+) (.+)$")
      n = tonumber(n)
      if n and n <= 200000 then
        local frame = {}
        if key ~= "-" then
          for b in key:gmatch("[^|\r]+") do frame[b] = true end
        end
        local frames = slots[slot].frames
        for _ = 1, n do frames[#frames + 1] = frame end
      end
    end
  end
  fh:close()
end

local function autosave()
  if not AUTO_SAVE_TO_FILE then return end
  local ok, err = pcall(save_file)
  if not ok then log("save error:", err) end
end

---------------------------------------------------------------- savestates
local function state_slot(i) return STATE_SLOT_BASE + i - 1 end

local function do_save()
  if not use_state then return false end
  local st = savestate.create(state_slot(cur))
  savestate.save(st)
  return true
end

local function do_load(i)
  if use_state and slots[i].has_state then
    local st = savestate.create(state_slot(i))
    savestate.load(st)
  end
end

---------------------------------------------------------------- inputs / hotkeys
local function is_down(token, keys)
  return (keys[token] or pad_now[token]) and true or false
end

-- While the first input of a combo (e.g. Coin) is held, stop the other controller
-- buttons of that combo from reaching the game, so using a hotkey does not make
-- P1 perform the move bound to those buttons.
local function block_combo_buttons(keys)
  for _, alternatives in pairs(HOTKEYS) do
    for _, combo in ipairs(alternatives) do
      if #combo >= 2 and is_down(combo[1], keys) then
        for i = 2, #combo do
          if combo[i]:match("^P1 ") then pending[combo[i]] = false end
        end
      end
    end
  end
end

local function ignored(btn)
  for _, word in ipairs(IGNORE) do
    if btn:find(word) then return true end
  end
  return false
end

-- true only on the frame a hotkey becomes pressed
local function hot(name, keys)
  local active = false
  for _, combo in ipairs(HOTKEYS[name]) do
    local all = true
    for _, token in ipairs(combo) do
      if not is_down(token, keys) then all = false break end
    end
    if all then
      active = true
      for _, token in ipairs(combo) do chord_held[token] = true end
    end
  end
  local was = prev[name] or false
  prev[name] = active
  return active and not was
end

local function flip(btn)
  if not mirror then return btn end
  if btn == "Left" then return "Right" end
  if btn == "Right" then return "Left" end
  return btn
end

-- P1 buttons currently held (name without the "P1 " prefix)
local function read_p1()
  local held = {}
  for name, down in pairs(pad_now) do
    local btn = tostring(name):match("^P1 (.+)$")
    if btn and down and not ignored(btn) and not chord_held[name] then
      held[btn] = true
    end
  end
  return held
end

local function names(t)
  local n = {}
  for k in pairs(t) do n[#n + 1] = k end
  table.sort(n)
  return table.concat(n, ",")
end

---------------------------------------------------------------- record / play
-- Recording: P1 controller drives the P2 character.
-- The stored frame is exactly what was sent to P2 (already mirrored).
local function record_frame()
  local held = read_p1()
  local out, frame = {}, {}
  for btn in pairs(held) do
    local b = flip(btn)
    out["P2 " .. b] = true
    frame[b] = true
    if BLOCK_P1_WHILE_RECORDING then out["P1 " .. btn] = false end
  end
  if guard_on then
    out["P1 " .. guard_dir] = true
    if guard_low then out["P1 Down"] = true end
  end
  for k, v in pairs(out) do pending[k] = v end
  local frames = slots[cur].frames
  frames[#frames + 1] = frame
  if next(frame) and logged < 10 then
    logged = logged + 1
    log("rec frame", #frames, "P2 gets:", names(frame))
  end
end

local function play_frame(frame)
  for btn in pairs(frame) do pending["P2 " .. btn] = true end
  if next(frame) and logged < 10 then
    logged = logged + 1
    log("play frame", pos, "P2 set:", names(frame))
  end
end

local function finish_recording()
  local frames = slots[cur].frames
  local n = 0
  for _, f in ipairs(frames) do if next(f) then n = n + 1 end end
  log("record stop: slot", cur, ",", #frames, "frames,", n, "with inputs")
  autosave()
  flash()
end

local function delay_label()
  local d = DELAY_STEPS[delay_i]
  if d == "random" then return "random(0-" .. RANDOM_DELAY_MAX .. "f)" end
  if d == 0 then return "off" end
  return d .. "f"
end

local function pick_delay()
  local d = DELAY_STEPS[delay_i]
  if d == "random" then return math.random(0, RANDOM_DELAY_MAX) end
  return d
end

-- the slot to play: a random non-empty slot if random mode is on, otherwise the current one
local function choose_play_slot()
  if random_slot then
    local list = {}
    for i = 1, NUM_SLOTS do
      if #slots[i].frames > 0 then list[#list + 1] = i end
    end
    if #list > 0 then return list[math.random(#list)] end
  end
  return cur
end

-- start one pass of playback (first start or a loop restart)
local function begin_pass(idx)
  play_slot = idx or choose_play_slot()
  if idx and use_state and not slots[play_slot].has_state then
    log("note: no savestate stored for slot", play_slot, ", playing from the current position")
  end
  do_load(play_slot)
  pos, logged = 0, 0
  wait = pick_delay()
end

local function advance_playback()
  if wait > 0 then wait = wait - 1 return end
  pos = pos + 1
  if pos > #slots[play_slot].frames then
    if loop then
      begin_pass()
      if wait > 0 then wait = wait - 1 return end
      pos = 1
    else
      mode = IDLE
      log("play finished")
      flash()
      return
    end
  end
  play_frame(slots[play_slot].frames[pos])
end

local function tick()
  frame_count = frame_count + 1
  local keys = input.get()
  pad_now = joypad.get()
  chord_held = {}

  if PRINT_BUTTONS then
    local held = {}
    for name, down in pairs(pad_now) do
      if down and tostring(name):match("^P%d ") then held[#held + 1] = tostring(name) end
    end
    table.sort(held)
    local str = table.concat(held, ", ")
    if str ~= last_print then log("buttons:", str) last_print = str end
  end

  local r, p = hot("rec", keys), hot("play", keys)
  local s = hot("stop", keys)
  local l, m = hot("loop", keys), hot("mirror", keys)
  local g, h = hot("guard", keys), hot("side", keys)
  local ge = hot("guard_toggle", keys)
  local sn, sp, st = hot("slot_next", keys), hot("slot_prev", keys), hot("state", keys)
  local dl, rn, hp = hot("delay", keys), hot("random", keys), hot("help", keys)
  block_combo_buttons(keys)

  if l then loop = not loop log("loop", loop) flash() end
  if m then mirror = not mirror log("mirror", mirror) flash() end
  if ge then guard_on = not guard_on log("guard while recording", guard_on and "ON" or "OFF") flash() end
  if h then guard_dir = (guard_dir == "Left") and "Right" or "Left" log("guard direction", guard_dir) flash() end
  if g then guard_low = not guard_low log("guard", guard_low and "low (crouching)" or "high (standing)") flash() end
  if dl then delay_i = delay_i % #DELAY_STEPS + 1 log("playback delay", delay_label()) flash() end
  if rn then random_slot = not random_slot log("random slot", random_slot and "ON" or "OFF") flash() end
  if hp then show_help = not show_help end
  if st then
    flash()
    use_state = not use_state
    log("savestate reset", use_state and "ON (slots " .. STATE_SLOT_BASE .. "-" .. (STATE_SLOT_BASE + NUM_SLOTS - 1) .. ")" or "OFF")
  end

  if sn or sp then
    if mode ~= IDLE then
      log("press stop before changing slot")
    else
      cur = ((cur - 1 + (sn and 1 or -1)) % NUM_SLOTS) + 1
      log("slot", cur, "(" .. #slots[cur].frames .. " frames)")
      flash()
    end
  end

  if s then
    flash()  -- always show the details when stop is pressed
    if mode == REC then
      finish_recording()
      mode = IDLE
    elseif mode == PLAY then
      log("play stopped")
      mode = IDLE
    end
  end

  if r then
    if mode == REC then
      mode = IDLE
      finish_recording()
    else
      local sl = slots[cur]
      sl.frames = {}
      sl.has_state = do_save()
      pos, logged = 0, 0
      if MIRROR_AT_RECORD_START ~= nil then mirror = MIRROR_AT_RECORD_START end
      mode = REC
      log("record start: slot", cur, "- your controls now drive P2, mirror", mirror,
          use_state and "(state saved)" or "(no savestate)")
    end
  elseif p then
    local ps = choose_play_slot()
    if #slots[ps].frames == 0 then
      log("play refused: slot", ps, "is empty (record something first)")
    else
      mode = PLAY
      begin_pass(ps)
      log("play start: slot", play_slot, ",", #slots[play_slot].frames, "frames, delay", delay_label())
    end
  end

  if mode == REC then
    record_frame()
  elseif mode == PLAY then
    advance_playback()
  end
end

local function safe_tick()
  pending = {}
  local ok, err = pcall(tick)
  if not ok then log("ERROR:", err) end
  if next(pending) then joypad.set(pending) end
end

---------------------------------------------------------------- display
local function slot_summary()
  local t = {}
  for i = 1, NUM_SLOTS do
    local n = #slots[i].frames
    t[#t + 1] = string.format("%s%d:%s", i == cur and ">" or "", i, n > 0 and n or "-")
  end
  return table.concat(t, " ")
end

-- draw one line of text; falls back to plain text if this emulator rejects colors
local function draw_text(x, y, str, color)
  if TEXT_COLORS then
    if pcall(gui.text, x, y, str, color or "white", "#000000b0") then return end
  end
  gui.text(x, y, str)
end

local HELP = {
  "Keyboard: R rec  P play  T stop  Y loop  M mirror",
  "G guard high/low  H guard side  E guard on/off",
  "N/B slot  U savestate  V delay  X random slot  Q this list",
  "Pad, hold Coin then press: A rec  B play  C stop  D loop",
  "Start=mirror  Down=guard  Up=side  Right/Left=slot",
  "Pad, hold Start then press: A savestate  B delay",
  "C random slot  D this list  Up guard on/off",
}

emu.registerbefore(safe_tick)
gui.register(function()
  if not SHOW_TEXT then return end
  local y = TEXT_Y
  local function line(str, color)
    draw_text(TEXT_X, y, str, color)
    y = y + 10
  end

  -- always-on part: only while recording or playing
  if mode == REC then
    line("REC  slot " .. cur, "#ff6666")
  elseif mode == PLAY then
    local str = "PLAY  slot " .. play_slot
    if wait > 0 then str = str .. "  wait " .. wait end
    line(str, "#66ff66")
  end

  -- details: always (default), or briefly after a change, or while the help panel is open
  if show_help or ALWAYS_SHOW_DETAILS or frame_count < info_until then
    local grey = "#e0e0e0"
    line(string.format("loop:%s  mirror:%s  guard:%s",
      loop and "on" or "off", mirror and "on" or "off",
      guard_on and (guard_low and "low" or "high") .. "(" .. guard_dir .. ")" or "off"), grey)
    line(string.format("delay:%s  random:%s  savestate:%s",
      delay_label(), random_slot and "on" or "off", use_state and "on" or "off"), grey)
    line("slots  " .. slot_summary(), grey)
    if frame_count < hint_until then line("Q = hotkey list", grey) end
  end

  if show_help then
    for _, text in ipairs(HELP) do line(text, "#c8c8ff") end
  end
end)

if AUTO_SAVE_TO_FILE then
  local ok, err = pcall(load_file)
  if not ok then log("load error:", err) end
end

log("loaded. slots:", slot_summary(), "| file:", SAVE_FILE)
