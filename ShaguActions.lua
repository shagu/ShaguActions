local _G = getfenv(0)
ShaguActions_DB = { }

-- helpers
local GetSpellMaxRank = function(name)
  local name, rank = string.lower(name), ""

  for i = 1, GetNumSpellTabs() do
    local _, _, offset, num = GetSpellTabInfo(i)
    local bookType = BOOKTYPE_SPELL
    for id = offset + 1, offset + num do
      local spellName, spellRank = GetSpellName(id, bookType)
      if name == string.lower(spellName) then
        rank = spellRank
      end
    end
  end

  return rank
end

local GetSpellIndex = function(name, rank)
  local name = string.lower(name)
  local rank = rank or GetSpellMaxRank(name)

  for i = 1, GetNumSpellTabs() do
    local _, _, offset, num = GetSpellTabInfo(i)
    local bookType = BOOKTYPE_SPELL
    for id = offset + 1, offset + num do
      local iname, irank = GetSpellName(id, bookType)

      if rank == irank and name == string.lower(iname) then
        return id, bookType
      end
    end
  end

  return nil
end

local CopyTable = function(src)
  local lookup_table = {}
  local function _copy(src)
    if type(src) ~= "table" then
      return src
    elseif lookup_table[src] then
      return lookup_table[src]
    end
    local new_table = {}
    lookup_table[src] = new_table
    for index, value in pairs(src) do
      new_table[_copy(index)] = _copy(value)
    end
    return setmetatable(new_table, getmetatable(src))
  end
  return _copy(src)
end

local FindItem = function(item)
  for bag = 4, 0, -1 do
    for slot = 1, GetContainerNumSlots(bag) do
      local itemLink = GetContainerItemLink(bag,slot)
      if itemLink then
        local _, _, parse = strfind(itemLink, "(%d+):")
        local query = GetItemInfo(parse)
        if query and query ~= "" and string.lower(query) == string.lower(item) then
          return bag, slot
        end
      end
    end
  end

  return nil
end

-- main addon
local core = CreateFrame("Frame", nil, WorldFrame)
core:RegisterEvent("VARIABLES_LOADED")
core:RegisterEvent("LEARNED_SPELL_IN_TAB")
core:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
core:RegisterEvent("PLAYER_ENTERING_WORLD")
core:SetScript("OnEvent", function()
  if event == "VARIABLES_LOADED" then
    core.db = ShaguActions_DB
    core.db.actions = core.db.actions or {}
    this.wait_actions = GetTime() + .5
  elseif event == "LEARNED_SPELL_IN_TAB" then
    this.wait_talents = GetTime() + .5
    this.wait_actions = nil
  elseif event == "ACTIONBAR_SLOT_CHANGED" and arg1 then
    if this.wait_talents then return end
    this.wait_actions = GetTime() + .5
  end
end)

core:SetScript("OnUpdate", function()
  if this.wait_talents and this.wait_talents < GetTime() then
    this.wait_talents = nil
    this:load()
  end

  if this.wait_actions and this.wait_actions < GetTime() then
    this.wait_actions = nil
    this:save()
  end
end)

core.current = function(self, force)
  local player = UnitName("player")
  local class = UnitClass("player")

  local spec, best = "Empty", 0
  for id=1, GetNumTalentTabs() do
    local name, icon, points = GetTalentTabInfo(id)
    if points > best then spec, best = name, points end
  end

  local idstr = string.format("%s [%s] - %s", player, class, spec)

  if core.db.actions[idstr] then
    self.fallback = core.db.actions[idstr]
  elseif self.fallback then
    core.db.actions[idstr] = CopyTable(self.fallback)
  elseif force then
    core.db.actions[idstr] = {}
  else
    return nil
  end

  return core.db.actions[idstr]
end

core.load = function(self)
  local current = self:current()
  if not current then return end

  for slot=1, 120 do
    local exists = HasAction(slot)
    local book, id, name = self.scanner:get(slot)

    -- try loading all existing entries
    if current[slot] and current[slot].name ~= name then
      local name = current[slot].name
      local book = current[slot].book
      local success = false

      if book == "macro" then
        local id = GetMacroIndexByName(name)
        if id then
          -- remove old slot
          ClearCursor()
          PickupAction(slot)
          ClearCursor()
          -- place new macro
          PickupMacro(id)
          PlaceAction(slot)
          -- save success
          success = true
        end
      elseif book == "spell" then
        local _, _, spell, rank = string.find(name, "(.*) %[(.*)%]")
        spell = spell or name
        local id, book = GetSpellIndex(spell, rank)
        if id and book then
          -- remove old slot
          ClearCursor()
          PickupAction(slot)
          ClearCursor()
          -- place new action
          PickupSpell(id, book)
          PlaceAction(slot)
          -- save success
          success = true
        end
      elseif book == "item" then
        local bagid, bagslot = FindItem(name)
        if bagid and bagslot then
          -- remove old slot
          ClearCursor()
          PickupAction(slot)
          ClearCursor()
          -- place new item
          PickupContainerItem(bagid, bagslot)
          PlaceAction(slot)
          -- save success
          success = true
        end
      end

      if success == true then
        local text = '|cffaaaaaaShaguActions:|r Restored |cffffcc00%s|r [|cffff9900%s|r] on slot |cffffcc00%s|r.'
        DEFAULT_CHAT_FRAME:AddMessage(string.format(text, name, book, slot))
      end
    end
  end
end

core.save = function(self)
  local current = self:current(true)
  if not current then return end

  for slot=1, 120 do
    local exists = HasAction(slot)
    local book, id, name = self.scanner:get(slot)

    if exists and book then
      current[slot] = { name = name, book = book }
    elseif not exists then
      current[slot] = nil
    end
  end
end

core.scanner = CreateFrame("GameTooltip", "ShaguActionsScanner", nil, "GameTooltipTemplate")
core.scanner:SetOwner(WorldFrame,"ANCHOR_NONE")
core.scanner.line = function(self, side, line)
  local side = side or "Left"
  local line = line or 1

  local name = self:GetName()
  local text = _G[name .. "Text" .. side .. line]

  if text and text:IsShown() and text:GetText() then
    return text:GetText()
  else
    return nil
  end
end

core.scanner.get = function(self, id)
  -- detect empty
  if not HasAction(id) then return end

  -- detect macro actions
  local name = GetActionText(id)
  if name then
    local id = GetMacroIndexByName(name)
    return "macro", id, name
  end

  -- detect spells and items
  self:ClearLines()
  self:SetOwner(WorldFrame,"ANCHOR_NONE")
  self:SetAction(id)

  if self:NumLines() > 0 then
    local name = self:line("Left", "1") or ""
    local rank = self:line("Right", "1") or ""
    local id, btype = GetSpellIndex(name, rank)
    if rank ~= "" then name = string.format("%s [%s]", name, rank) end

    if id and btype then
      -- return spell
      return btype, id, name
    else
      -- return item (fallback)
      return "item", 0, name
    end
  end
end
