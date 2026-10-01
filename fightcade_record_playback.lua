-- Record / Playback dummy for Fightcade (FBNeo Lua)
-- Default keyboard: R = record (your controls drive P2), P = play, T = stop,
-- Y = loop, M = mirror. Controller combos are configured in HOTKEYS below.
-- Messages are logged to the Lua console with the prefix [rp].

local USE_SAVESTATE = false   -- experimental; uses savestate SLOT
local SLOT = 1
local BLOCK_P1_WHILE_RECORDING = true  -- freeze P1 while you control P2
-- Mirror state forced each time recording starts: false = off, true = on, nil = leave as is
local MIRROR_AT_RECORD_START = false

-- Hotkeys. Each action has a list of alternatives; any one of them triggers it.
-- An alternative is a list of inputs that must ALL be held at once (a chord).
-- Inputs can be keyboard keys ("R") or controller buttons ("P1 Coin").
-- To find your controller's button names, run diag.lua and press buttons.
local HOTKEYS = {
  rec    = { {"R"}, {"P1 Coin", "P1 Button A"} },
  play   = { {"P"}, {"P1 Coin", "P1 Button B"} },
  stop   = { {"T"}, {"P1 Coin", "P1 Button C"} },
  loop   = { {"Y"}, {"P1 Coin", "P1 Button D"} },
  mirror = { {"M"}, {"P1 Coin", "P1 Start"} },
}

-- System buttons that are never recorded or copied to P2
local IGNORE = { "Coin", "Start", "Select", "Service", "Test", "Reset",
                 "Diagnostic", "Dip", "Region", "Fake" }

local IDLE, REC, PLAY = 0, 1, 2
local mode = IDLE
local buffer, pos = {}, 0
local loop, mirror = true, false
local start_state = nil
local prev = {}
local logged = 0

local function log(...) print("[rp]", ...) end

local function do_save()
  if not USE_SAVESTATE then return end
  start_state = savestate.create(SLOT)
  savestate.save(start_state)
end

local function do_load()
  if USE_SAVESTATE and start_state then savestate.load(start_state) end
end

local pad_now = {}      -- joypad.get() for the current frame
local chord_held = {}  -- inputs belonging to a hotkey that is currently held
local pending = {}     -- joypad overrides collected this frame, applied once at the end

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
  for k, v in pairs(out) do pending[k] = v end
  buffer[#buffer + 1] = frame
  if next(frame) and logged < 10 then
    logged = logged + 1
    log("rec frame", #buffer, "P2 gets:", names(frame))
  end
end

local function play_frame(frame)
  local out = {}
  for btn in pairs(frame) do out["P2 " .. btn] = true end
  for k, v in pairs(out) do pending[k] = v end
  if next(frame) and logged < 10 then
    logged = logged + 1
    log("play frame", pos, "P2 set:", names(frame))
  end
end

local function tick()
  local keys = input.get()
  pad_now = joypad.get()
  chord_held = {}
  local r, p = hot("rec", keys), hot("play", keys)
  local s = hot("stop", keys)
  local l, m = hot("loop", keys), hot("mirror", keys)
  block_combo_buttons(keys)

  if l then loop = not loop log("loop", loop) end
  if m then mirror = not mirror log("mirror", mirror) end

  if s and mode ~= IDLE then
    log(mode == REC and "record stopped" or "play stopped")
    mode = IDLE
  end

  if r then
    if mode == REC then
      mode = IDLE
      local n = 0
      for _, f in ipairs(buffer) do if next(f) then n = n + 1 end end
      log("record stop:", #buffer, "frames,", n, "with inputs")
    else
      do_save()
      buffer, pos, logged = {}, 0, 0
      if MIRROR_AT_RECORD_START ~= nil then mirror = MIRROR_AT_RECORD_START end
      mode = REC
      log("record start: your controls now drive P2, mirror", mirror)
    end
  elseif p then
    if #buffer == 0 then
      log("play refused: buffer empty (record something first)")
    elseif USE_SAVESTATE and not start_state then
      log("play refused: no saved state")
    else
      do_load()
      pos, logged = 0, 0
      mode = PLAY
      log("play start,", #buffer, "frames")
    end
  end

  if mode == REC then
    record_frame()
  elseif mode == PLAY then
    pos = pos + 1
    if pos > #buffer then
      if loop then
        do_load()
        pos, logged = 1, 0
      else
        mode = IDLE
        log("play finished")
        return
      end
    end
    play_frame(buffer[pos])
  end
end

local function safe_tick()
  pending = {}
  local ok, err = pcall(tick)
  if not ok then log("ERROR:", err) end
  if next(pending) then joypad.set(pending) end
end

local LABEL = { [IDLE] = "IDLE", [REC] = "REC (controlling P2)", [PLAY] = "PLAY" }

emu.registerbefore(safe_tick)
gui.register(function()
  gui.text(4, 4, string.format("%s frames:%d pos:%d loop:%s mirror:%s",
    LABEL[mode], #buffer, pos, loop and "on" or "off", mirror and "on" or "off"))
end)

log("loaded. R=record (control P2), P=play, T=stop, Y=loop, M=mirror")
