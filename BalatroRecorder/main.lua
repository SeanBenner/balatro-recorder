--[[
Balatro Recorder (balatro_bot project)

Appends one JSON line per committed decision to
    <BALATRO_RECORDER_DIR>/<player>/raw_<date>_<seed>.jsonl
in the shape of docs/state_action_schema.md §5 (header / decision / outcome).
tools/recorder/convert.py turns the raw file into a schema v0.4 recording
(computed fields, validation against jackdaw's SchemaSim.load).

How it works: it wraps the button handlers a click goes through
(G.FUNCS.play_cards_from_highlighted, buy_from_shop, use_card, ...). Each
wrapper snapshots the visible state *before* the click takes effect, writes
it with the action, then calls the original handler unchanged. Selecting and
deselecting cards isn't logged. Joker reordering has no handler; the
snapshots carry the order and the converter turns changes into
rearrange_jokers actions.

Read-only: it never changes game state, saves, profile or settings, and it
writes only to its own output directory. All writes are wrapped in pcall, so
a recorder error can never interrupt the game.

Settings (Mods > Recorder > Config): an on/off switch. Recordings go in a sub-folder named
after the game profile being played (P1, P2, P3 unless renamed in the game), so everyone who
plays on the machine keeps their own games apart. A run keeps the folder it started in.

Environment (optional overrides):
    BALATRO_RECORDER_DIR     output root (default: <save dir>/recordings)
    BALATRO_RECORDER_PLAYER  sub-folder name (overrides the profile name)
]]

local MOD = SMODS.current_mod
local REC = { version = "0.3.0", t = 0, file = nil, seed = nil, done = false, last = nil, skip_seed = nil }

local function cfg()
  local c = MOD and MOD.config or {}
  if c.enabled == nil then c.enabled = true end
  return c
end

-- the game profile being played: its name ("P1".."P3" unless renamed), safe for a folder name
local function player_name()
  local env = os.getenv('BALATRO_RECORDER_PLAYER')
  if env and env ~= '' then return env end
  local ok, name = pcall(function()
    local n = G.SETTINGS and G.SETTINGS.profile or 1
    local p = G.PROFILES and G.PROFILES[n]
    return (p and p.name) or ('P' .. tostring(n))
  end)
  name = ok and tostring(name) or 'P1'
  name = name:gsub('[^%w%-_ ]', '_'):gsub('^%s+', ''):gsub('%s+$', '')
  return name ~= '' and name or 'P1'
end

-- ------------------------------------------------------------------ JSON
local function esc(s)
  return (s:gsub('[%c"\\]', function(c)
    local map = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
    return map[c] or string.format('\\u%04x', c:byte())
  end))
end

local function is_array(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= 'number' then return false end
    n = n + 1
  end
  return n == #t
end

local encode
encode = function(v, depth)
  depth = depth or 0
  local tv = type(v)
  if tv == 'nil' then return 'null'
  elseif tv == 'boolean' then return v and 'true' or 'false'
  elseif tv == 'number' then
    if v ~= v or v == math.huge or v == -math.huge then return 'null' end
    if v == math.floor(v) and math.abs(v) < 1e15 then return string.format('%d', v) end
    return string.format('%.10g', v)
  elseif tv == 'string' then return '"' .. esc(v) .. '"'
  elseif tv == 'table' then
    if depth > 6 or getmetatable(v) ~= nil then return 'null' end   -- game objects: skip
    local parts = {}
    if is_array(v) then
      for i = 1, #v do parts[#parts + 1] = encode(v[i], depth + 1) end
      return '[' .. table.concat(parts, ',') .. ']'
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    for _, k in ipairs(keys) do
      local x = v[k]
      if x == nil then x = v[tonumber(k)] end
      local tx = type(x)
      if tx ~= 'function' and tx ~= 'userdata' and tx ~= 'thread' then
        parts[#parts + 1] = '"' .. esc(k) .. '":' .. encode(x, depth + 1)
      end
    end
    return '{' .. table.concat(parts, ',') .. '}'
  end
  return 'null'
end

-- ------------------------------------------------------------------ state
local SUIT = { Hearts = 'H', Diamonds = 'D', Clubs = 'C', Spades = 'S' }
local RANK = { ['2'] = '2', ['3'] = '3', ['4'] = '4', ['5'] = '5', ['6'] = '6', ['7'] = '7', ['8'] = '8',
  ['9'] = '9', ['10'] = 'T', Jack = 'J', Queen = 'Q', King = 'K', Ace = 'A' }
local SKIP_ABILITY = { name = true, set = true, effect = true, order = true }

local function center_key(c)
  return (c.config and c.config.center and c.config.center.key) or c.config and c.config.center_key
end

local function edition_key(c)
  if not c.edition then return nil end
  for _, k in ipairs({ 'foil', 'holo', 'polychrome', 'negative' }) do
    if c.edition[k] then return 'e_' .. k end
  end
  return c.edition.key or c.edition.type
end

local function plain(t, depth)
  -- copy of a table with only JSON-friendly values (numbers, strings, bools, plain tables)
  if type(t) ~= 'table' or getmetatable(t) ~= nil or depth > 4 then return nil end
  local out = {}
  for k, v in pairs(t) do
    local tv = type(v)
    if tv == 'number' or tv == 'string' or tv == 'boolean' then out[k] = v
    elseif tv == 'table' then out[k] = plain(v, depth + 1) end
  end
  return out
end

local function entity(c, location, position)
  local ab = c.ability or {}
  local key = center_key(c)
  local e = {
    id = c.sort_id, key = key, set = ab.set, rank = nil, suit = nil, enhancement = nil,
    edition = edition_key(c), seal = c.seal,
    stickers = { eternal = ab.eternal and true or false,
      perishable_rounds = ab.perishable and (ab.perish_tally or 0) or nil,
      rental = ab.rental and true or false },
    debuffed = c.debuff and true or false,
    face_down = (c.facing == 'back'),
    cost = { buy = c.cost, sell = c.sell_cost },
    location = location, position = position,
  }
  local is_playing = c.base and c.base.suit and (ab.set == 'Default' or ab.set == 'Enhanced')
  if is_playing then
    e.rank = RANK[c.base.value]
    e.suit = SUIT[c.base.suit]
    e.key = (e.suit or '?') .. '_' .. (e.rank or '?')
    if key and key ~= 'c_base' then e.enhancement = key end
    e.set = e.enhancement and 'Enhanced' or 'Default'
    e.played_this_ante = ab.played_this_ante and true or false
    if (ab.perma_bonus or 0) ~= 0 then e.ability = { perma_bonus = ab.perma_bonus } end
    e.forced_selection = ab.forced_selection and true or nil
  else
    local a = {}
    for k, v in pairs(ab) do
      if not SKIP_ABILITY[k] then
        local tv = type(v)
        if tv == 'number' or tv == 'string' or tv == 'boolean' then a[k] = v
        elseif tv == 'table' then a[k] = plain(v, 1) end
      end
    end
    e.ability = a
  end
  return e
end

local function area(a, location)
  local out = {}
  if a and a.cards then
    for i, c in ipairs(a.cards) do out[#out + 1] = entity(c, location, i - 1) end
  end
  return out
end

local function ids(cards)
  local out = {}
  for _, c in ipairs(cards or {}) do out[#out + 1] = c.sort_id end
  return out
end

local function in_hand_order(cards)
  -- the game plays/discards highlighted cards in their left-to-right hand order
  local pos = {}
  for i, c in ipairs(G.hand and G.hand.cards or {}) do pos[c] = i end
  local list = {}
  for _, c in ipairs(cards or {}) do list[#list + 1] = c end
  table.sort(list, function(a, b) return (pos[a] or 0) < (pos[b] or 0) end)
  return ids(list)
end

local function state_name()
  for k, v in pairs(G.STATES or {}) do
    if v == G.STATE then return k end
  end
  return tostring(G.STATE)
end

local function bosses_used(g)
  -- vanilla / older Steamodded: {key = count}; newer Steamodded nests it as bosses_used.boss
  local bu = g.bosses_used
  if type(bu) ~= 'table' then return nil end
  local src = type(rawget(bu, 'boss')) == 'table' and rawget(bu, 'boss') or bu
  local out = {}
  for k, v in pairs(src) do
    if type(k) == 'string' and type(v) == 'number' then out[k] = v end
  end
  return out
end

local function snapshot()
  local g = G.GAME or {}
  local rr = g.round_resets or {}
  local cr = g.current_round or {}
  local blind = g.blind
  local hands = {}
  for name, h in pairs(g.hands or {}) do
    hands[name] = { level = h.level, chips = h.chips, mult = h.mult, times_played_run = h.played,
      played_this_round = h.played_this_round, visible = h.visible }
  end
  local tags = {}
  for _, t in ipairs(g.tags or {}) do tags[#tags + 1] = t.key end
  local vouchers = {}
  for k, v in pairs(g.used_vouchers or {}) do if v then vouchers[#vouchers + 1] = k end end
  table.sort(vouchers)
  local deck = {}
  for _, e in ipairs(area(G.deck, 'draw_pile')) do e.position = nil; deck[#deck + 1] = e end
  for _, e in ipairs(area(G.discard, 'discard')) do deck[#deck + 1] = e end
  local snap = {
    state = state_name(),
    run = {
      seed = g.pseudorandom and g.pseudorandom.seed, deck = g.selected_back and g.selected_back.effect
          and g.selected_back.effect.center and g.selected_back.effect.center.key,
      stake = g.stake, ante = rr.ante, round_num = g.round, money = g.dollars,
      interest_cap = g.interest_cap, hand_size = G.hand and G.hand.config and G.hand.config.card_limit,
      joker_slots = G.jokers and G.jokers.config and G.jokers.config.card_limit,
      consumable_slots = G.consumeables and G.consumeables.config and G.consumeables.config.card_limit,
      base_hands = rr.hands, base_discards = rr.discards, reroll_cost = cr.reroll_cost,
      free_rerolls = cr.free_rerolls or 0, win_ante = g.win_ante,
    },
    round = {
      hands_left = cr.hands_left, discards_left = cr.discards_left, hands_played = cr.hands_played,
      discards_used = cr.discards_used, chips_scored = g.chips,
      targets = {
        idol_card = cr.idol_card and { rank = cr.idol_card.rank, suit = cr.idol_card.suit } or nil,
        mail_rank = cr.mail_card and cr.mail_card.rank, ancient_suit = cr.ancient_card and cr.ancient_card.suit,
        castle_suit = cr.castle_card and cr.castle_card.suit,
      },
    },
    blind = blind and blind.config and blind.config.blind and {
      key = blind.config.blind.key, chips = blind.chips, disabled = blind.disabled and true or false,
      boss = blind.boss and true or false, only_hand = blind.only_hand,
      hands_used = plain(blind.hands, 1),
    } or nil,
    blind_on_deck = g.blind_on_deck,
    blind_choices = plain(rr.blind_choices, 1), blind_states = plain(rr.blind_states, 1),
    blind_tags = plain(rr.blind_tags, 1),
    hand_levels = hands,
    hand = area(G.hand, 'hand'),
    jokers = area(G.jokers, 'jokers'),
    consumables = area(G.consumeables, 'consumables'),
    deck = deck,
    shop = (G.shop_jokers or G.shop_vouchers or G.shop_booster) and {
      items = area(G.shop_jokers, 'shop'), vouchers = area(G.shop_vouchers, 'shop'),
      packs = area(G.shop_booster, 'shop'), reroll_cost = cr.reroll_cost,
    } or nil,
    pack = G.pack_cards and G.pack_cards.cards and {
      cards = area(G.pack_cards, 'pack'), choices_remaining = g.pack_choices,
    } or nil,
    vouchers_owned = vouchers, tags_held = tags,
    bosses_used = bosses_used(g),            -- {boss key: times seen}; seen bosses don't return early
  }
  return snap
end

-- ------------------------------------------------------------------ output
local function out_dir()
  local root = os.getenv('BALATRO_RECORDER_DIR')
  if not root or root == '' then
    root = love.filesystem.getSaveDirectory() .. '/recordings'
  end
  return root .. '/' .. player_name()
end

local function mkdirs(path)
  -- love.filesystem can only create inside the save dir; use the shell for absolute paths
  if package.config:sub(1, 1) == '\\' then
    os.execute('mkdir "' .. path:gsub('/', '\\') .. '" 2>nul')
  else
    os.execute('mkdir -p "' .. path .. '"')
  end
end

local function write(obj)
  if not REC.file then return end
  REC.file:write(encode(obj), '\n')
  REC.file:flush()
end

local function mods_list()
  local mods = {}
  if SMODS and SMODS.Mods then
    for id, m in pairs(SMODS.Mods) do
      if m.can_load ~= false and not m.disabled then mods[#mods + 1] = { name = id, version = m.version } end
    end
  end
  table.sort(mods, function(a, b) return a.name < b.name end)
  return mods
end

local function ensure_run()
  local g = G.GAME
  local seed = g and g.pseudorandom and g.pseudorandom.seed
  if not seed then return false end
  if REC.file and REC.seed == seed then return true end          -- same run (endless after a win too)
  if REC.skip_seed == seed then return false end                 -- this run started with recording off
  if REC.file then REC.file:close(); REC.file = nil end
  if not cfg().enabled then
    REC.skip_seed = seed
    print('[recorder] recording is off; this run is not recorded')
    return false
  end
  REC.skip_seed = nil
  local dir = out_dir()
  mkdirs(dir)
  local path = dir .. '/raw_' .. os.date('%Y%m%d_%H%M%S') .. '_' .. seed .. '.jsonl'
  REC.file = io.open(path, 'a')
  REC.seed, REC.t, REC.done, REC.path = seed, 0, false, path
  write({ kind = 'header', schema_version = '0.4', recorder_version = REC.version,
    game_version = G.VERSION, mods = mods_list(), seed = seed,
    seeded = g.seeded and true or false,
    deck = g.selected_back and g.selected_back.effect and g.selected_back.effect.center
        and g.selected_back.effect.center.key,
    stake = g.stake, player = player_name(), consent = true,
    started = os.date('!%Y-%m-%dT%H:%M:%SZ') })
  return true
end

-- a decision is captured before the click is handled (the snapshot is the state the player saw)
-- and written after, unless the game refused it (buy_from_shop returns false with no room)
local function capture(action)
  local ok, rec = pcall(function()
    if not ensure_run() then return nil end
    return { kind = 'decision', wall = os.date('!%Y-%m-%dT%H:%M:%SZ'), snapshot = snapshot(), action = action }
  end)
  if not ok then print('[recorder] ' .. tostring(rec)) return nil end
  return rec
end

local function commit(rec)
  local ok, err = pcall(function()
    local now = love.timer.getTime()
    rec.t = REC.t
    rec.think_ms = REC.last and math.floor((now - REC.last) * 1000) or nil
    write(rec)
    REC.t = REC.t + 1
    REC.last = now
  end)
  if not ok then print('[recorder] ' .. tostring(err)) end
end

-- ------------------------------------------------------------------ hooks
local function wrap(name, describe)
  local orig = G.FUNCS[name]
  if not orig then
    print('[recorder] G.FUNCS.' .. name .. ' not found; not recorded')
    return
  end
  G.FUNCS[name] = function(e, ...)
    local ok, action = pcall(describe, e, ...)
    local rec = nil
    if ok and action then rec = capture(action) elseif not ok then print('[recorder] ' .. tostring(action)) end
    local r = { orig(e, ...) }
    if rec and r[1] ~= false then commit(rec) end
    return unpack(r)
  end
end

local function ref(e) return e and e.config and e.config.ref_table end

local function install()
  wrap('play_cards_from_highlighted', function()
    return { type = 'play', cards = in_hand_order(G.hand and G.hand.highlighted) }
  end)
  wrap('discard_cards_from_highlighted', function(e)
    -- hooked discards (The Hook) call this with a second argument and no button
    if e == nil then return nil end
    return { type = 'discard', cards = in_hand_order(G.hand and G.hand.highlighted) }
  end)
  wrap('select_blind', function() return { type = 'select_blind', blind = G.GAME and G.GAME.blind_on_deck } end)
  wrap('skip_blind', function() return { type = 'skip_blind', blind = G.GAME and G.GAME.blind_on_deck } end)
  wrap('cash_out', function() return { type = 'cash_out' } end)
  wrap('reroll_shop', function() return { type = 'reroll' } end)
  wrap('toggle_shop', function() return { type = 'next_round' } end)
  wrap('skip_booster', function() return { type = 'pack_skip' } end)
  wrap('buy_from_shop', function(e)
    local c = ref(e)
    if not c then return nil end
    local use = e.config and e.config.id == 'buy_and_use'
    return { type = use and 'buy_and_use' or 'buy', card = c.sort_id, key = center_key(c),
      targets = use and in_hand_order(G.hand and G.hand.highlighted) or nil }
  end)
  wrap('sell_card', function(e)
    local c = ref(e)
    if not c then return nil end
    return { type = 'sell', card = c.sort_id, key = center_key(c) }
  end)
  wrap('use_card', function(e, mute, nosave)
    local c = ref(e)
    if not c then return nil end
    -- "Buy and Use" calls use_card(e, true) itself; it was already logged as buy_and_use.
    -- Loading a save replays a pending action with nosave = true.
    if mute == true or nosave == true then return nil end
    -- tags (Charm, Meteor, Buffoon, ...) open their pack through use_card: not a decision
    if c.ability and c.ability.set == 'Booster' and c.area ~= G.shop_booster then return nil end
    local targets = in_hand_order(G.hand and G.hand.highlighted)
    if c.area == G.pack_cards then
      return { type = 'pack_pick', card = c.sort_id, key = center_key(c), targets = targets }
    elseif c.area == G.shop_vouchers or c.area == G.shop_booster then
      return { type = 'buy', card = c.sort_id, key = center_key(c) }
    end
    return { type = 'use_consumable', card = c.sort_id, key = center_key(c), targets = targets,
      joker_targets = ids(G.jokers and G.jokers.highlighted) }
  end)
end

-- outcome: watch for game over / win once per frame
local orig_update = Game.update
function Game:update(dt)
  orig_update(self, dt)
  if REC.file and not REC.done and G.GAME then
    local over = G.STATE == G.STATES.GAME_OVER
    if over or G.GAME.won then
      pcall(function()
        local rr = G.GAME.round_resets or {}
        write({ kind = 'outcome', won = G.GAME.won and true or false, final_ante = rr.ante,
          final_round = G.GAME.round, end_reason = over and 'lost_blind' or 'won',
          final_snapshot = snapshot() })
      end)
      REC.done = true
      if over then REC.file:close(); REC.file = nil end
    end
  end
end

-- ------------------------------------------------------------------ settings tab
if MOD then
  MOD.config_tab = function()
    local c = cfg()
    return {
      n = G.UIT.ROOT, config = { r = 0.1, minw = 7, align = 'cm', padding = 0.2, colour = G.C.BLACK },
      nodes = {
        { n = G.UIT.R, config = { align = 'cm', padding = 0.1 }, nodes = {
          create_toggle({ label = 'Record runs', ref_table = c, ref_value = 'enabled' }),
        } },
        { n = G.UIT.R, config = { align = 'cm', padding = 0.1 }, nodes = {
          { n = G.UIT.T, config = { text = 'Folder: the profile you play on. Applies from the next run', scale = 0.35, colour = G.C.UI.TEXT_LIGHT } },
        } },
      },
    }
  end
end

install()
print('[recorder] Balatro Recorder ' .. REC.version .. ' loaded; recording ' ..
  (cfg().enabled and ('on, player ' .. player_name()) or 'off') .. '; writing to ' .. out_dir())
