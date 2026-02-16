-- Auctionator_SephCraft.lua
-- Ascension (WotLK 3.3.5-ish) addon:
-- Single line in TradeSkill: "[AH mats price]"
-- Hover line to see tooltip breakdown WITH icons + after-bags.
-- SHIFT-hover = Shopping List mode (only mats you still need to buy).
-- Auctionator pricing via Atr_GetAuctionBuyout (preferred).
-- Polling update (Ascension-safe).

local LABEL = "[AH mats price]: "

local function MoneyText(copper)
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100

  local text = ""
  if g > 0 then
    text = text .. g .. "|TInterface\\MoneyFrame\\UI-GoldIcon:14:14:0:0|t "
  end
  if s > 0 or g > 0 then
    text = text .. s .. "|TInterface\\MoneyFrame\\UI-SilverIcon:14:14:0:0|t "
  end
  text = text .. c .. "|TInterface\\MoneyFrame\\UI-CopperIcon:14:14:0:0|t"
  return text
end

local function GetItemIDFromLink(link)
  if not link then return nil end
  local id = link:match("item:(%d+):")
  if id then return tonumber(id) end
  return nil
end

local function GetIconForItemID(itemID)
  if not itemID then return nil end
  local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(itemID)
  return texture
end

local function IconText(texture, size)
  if not texture then return "" end
  size = size or 14
  return string.format("|T%s:%d:%d:0:0|t ", texture, size, size)
end

local function GetAuctionatorPriceCopper(itemID)
  if not itemID then return nil end

  if type(Atr_GetAuctionBuyout) == "function" then
    local p = Atr_GetAuctionBuyout(itemID)
    if type(p) == "number" and p > 0 then return p end
    return nil
  end

  if type(Atr_GetAuctionPrice) == "function" then
    local name = GetItemInfo(itemID)
    if name then
      local p = Atr_GetAuctionPrice(name)
      if type(p) == "number" and p > 0 then return p end
    end
  end

  return nil
end

local function GetBagCount(itemID)
  if not itemID then return 0 end
  if type(GetItemCount) == "function" then
    return GetItemCount(itemID) or 0
  end
  return 0
end

-- UI objects
local costText
local hoverFrame

local function SafeHasText(fs)
  if not fs or not fs.GetText then return false end
  local t = fs:GetText()
  return t ~= nil and t ~= ""
end

local function GetDetailParent()
  if TradeSkillDetailScrollChild and TradeSkillDetailScrollChild.GetObjectType then
    return TradeSkillDetailScrollChild
  end
  return TradeSkillFrame
end

local function PickAnchor(parent)
  if TradeSkillRequirementText
    and TradeSkillRequirementText.IsShown and TradeSkillRequirementText:IsShown()
    and SafeHasText(TradeSkillRequirementText) then
    return TradeSkillRequirementText, "REQ"
  end

  if TradeSkillSkillName and TradeSkillSkillName.GetObjectType then
    return TradeSkillSkillName, "NAME"
  end

  return parent, "FALLBACK"
end

local function EnsureUI()
  local parent = GetDetailParent()
  if not parent then return end

  if not costText then
    costText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    costText:SetText(LABEL .. "(waiting...)")
  end

  if not hoverFrame then
    hoverFrame = CreateFrame("Frame", nil, parent)
    hoverFrame:EnableMouse(true)
    hoverFrame:SetFrameStrata("TOOLTIP")
  end

  costText:ClearAllPoints()
  local anchor, mode = PickAnchor(parent)

  if mode == "REQ" then
    costText:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  elseif mode == "NAME" then
    costText:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
  else
    costText:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -10)
  end

  hoverFrame:ClearAllPoints()
  hoverFrame:SetPoint("TOPLEFT", costText, "TOPLEFT", -2, 2)
  hoverFrame:SetPoint("BOTTOMRIGHT", costText, "BOTTOMRIGHT", 2, -2)

  if hoverFrame:GetParent() ~= parent then
    hoverFrame:SetParent(parent)
  end
end

-- Cached breakdown
local lastBreakdown = nil
local lastTotalCopper = nil
local lastMissing = nil

-- Crafted item header
local lastCraftItemName = nil
local lastCraftItemIcon = nil

-- After bags
local lastAfterBagsCopper = nil
local lastAfterBagsChanged = nil

local function BuildBreakdown()
  lastBreakdown = nil
  lastTotalCopper = nil
  lastMissing = nil
  lastAfterBagsCopper = nil
  lastAfterBagsChanged = nil
  lastCraftItemName = nil
  lastCraftItemIcon = nil

  if not GetTradeSkillSelectionIndex or not GetTradeSkillNumReagents then
    lastMissing = true
    return
  end

  local skillIndex = GetTradeSkillSelectionIndex()
  if not skillIndex or skillIndex <= 0 then
    lastMissing = true
    return
  end

  -- Crafted item header
  if type(GetTradeSkillItemLink) == "function" then
    local craftLink = GetTradeSkillItemLink(skillIndex)
    local craftID = GetItemIDFromLink(craftLink)
    if craftID then
      local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(craftID)
      lastCraftItemName = name
      lastCraftItemIcon = icon
    end
  end

  local numReagents = GetTradeSkillNumReagents(skillIndex)
  if not numReagents or numReagents <= 0 then
    lastTotalCopper = 0
    lastAfterBagsCopper = 0
    lastAfterBagsChanged = false
    lastBreakdown = {}
    return
  end

  local total = 0
  local afterBags = 0
  local changed = false
  local missingAny = false
  local rows = {}

  for i = 1, numReagents do
    local reagentName, _, reagentCount = GetTradeSkillReagentInfo(skillIndex, i)
    local reagentLink = GetTradeSkillReagentItemLink(skillIndex, i)
    local itemID = GetItemIDFromLink(reagentLink)

    reagentName = reagentName or "Unknown"
    reagentCount = reagentCount or 0

    local icon = GetIconForItemID(itemID)
    local bagCount = GetBagCount(itemID)

    local needAH = reagentCount
    if bagCount > 0 then
      needAH = reagentCount - bagCount
      if needAH < 0 then needAH = 0 end
      if needAH ~= reagentCount then changed = true end
    end

    if itemID and reagentCount > 0 then
      local price = GetAuctionatorPriceCopper(itemID)
      if price then
        local sub = price * reagentCount
        total = total + sub

        local subAfter = price * needAH
        afterBags = afterBags + subAfter

        table.insert(rows, {
          id = itemID,
          name = reagentName,
          icon = icon,
          count = reagentCount,
          bag = bagCount,
          needAH = needAH,
          each = price,
          sub = sub,
          subAfter = subAfter,
          missing = false,
        })
      else
        missingAny = true
        table.insert(rows, {
          id = itemID,
          name = reagentName,
          icon = icon,
          count = reagentCount,
          bag = bagCount,
          needAH = needAH,
          each = nil,
          sub = nil,
          subAfter = nil,
          missing = true,
        })
      end
    else
      missingAny = true
      table.insert(rows, {
        id = itemID,
        name = reagentName,
        icon = icon,
        count = reagentCount,
        bag = bagCount,
        needAH = needAH,
        each = nil,
        sub = nil,
        subAfter = nil,
        missing = true,
      })
    end
  end

  lastBreakdown = rows
  lastTotalCopper = total
  lastAfterBagsCopper = afterBags
  lastAfterBagsChanged = changed
  lastMissing = missingAny
end

local function UpdateOneLine()
  EnsureUI()
  if not costText then return end

  BuildBreakdown()

  if lastBreakdown == nil then
    costText:SetText(LABEL .. "unknown")
    return
  end

  if lastMissing then
    costText:SetText(LABEL .. "unknown")
  else
    costText:SetText(LABEL .. MoneyText(lastTotalCopper or 0))
  end
end

local function TooltipHeader()
  if lastCraftItemName then
    GameTooltip:AddLine(IconText(lastCraftItemIcon, 16) .. lastCraftItemName, 1, 1, 1)
  else
    GameTooltip:AddLine("Crafting material cost (Auctionator)", 1, 1, 1)
  end
end

local function ShowTooltip_Normal()
  TooltipHeader()

  if not lastBreakdown then
    GameTooltip:AddLine("No data.", 0.8, 0.8, 0.8)
    return
  end

  GameTooltip:AddLine(" ")

  local anyMissing = false
  for _, r in ipairs(lastBreakdown) do
    local left = string.format("%s%s x%d", IconText(r.icon, 14), r.name, r.count)
    if r.missing then
      anyMissing = true
      GameTooltip:AddDoubleLine(left, "unknown", 0.9, 0.9, 0.9, 1.0, 0.3, 0.3)
    else
      GameTooltip:AddDoubleLine(left, MoneyText(r.sub), 0.9, 0.9, 0.9, 1.0, 1.0, 1.0)
    end
  end

  GameTooltip:AddLine(" ")

  if anyMissing then
    GameTooltip:AddDoubleLine("Total", "unknown", 1, 1, 1, 1.0, 0.3, 0.3)
    GameTooltip:AddLine("Tip: scan AH with Auctionator to learn missing prices.", 0.6, 0.6, 0.6)
  else
    GameTooltip:AddDoubleLine("Total", MoneyText(lastTotalCopper or 0), 1, 1, 1, 1, 1, 1)

    if lastAfterBagsChanged then
      GameTooltip:AddLine("------------------------------------------------", 0.6, 0.6, 0.6)
      GameTooltip:AddDoubleLine("After bags", MoneyText(lastAfterBagsCopper or 0), 0.85, 0.9, 1.0, 0.85, 0.9, 1.0)
      local savings = (lastTotalCopper or 0) - (lastAfterBagsCopper or 0)
      if savings > 0 then
        GameTooltip:AddDoubleLine("Savings", MoneyText(savings), 0.6, 1.0, 0.6, 0.6, 1.0, 0.6)
      end
    end
  end

  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Tip: Hold SHIFT for shopping list", 0.6, 0.6, 0.6)
end

local function ShowTooltip_ShoppingList()
  TooltipHeader()

  if not lastBreakdown then
    GameTooltip:AddLine("No data.", 0.8, 0.8, 0.8)
    return
  end

  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Shopping list (missing mats)", 0.85, 0.9, 1.0)
  GameTooltip:AddLine(" ")

  local anyToBuy = false
  local anyMissingPrice = false
  local missingNames = {}

  local totalToBuy = 0

  for _, r in ipairs(lastBreakdown) do
    if (r.needAH or 0) > 0 then
      anyToBuy = true

      local left = string.format("%s%s x%d", IconText(r.icon, 14), r.name, r.needAH)

      if r.missing or not r.each then
        anyMissingPrice = true
        table.insert(missingNames, r.name)
        GameTooltip:AddDoubleLine(left, "unknown", 0.9, 0.9, 0.9, 1.0, 0.3, 0.3)
      else
        local sub = (r.each * r.needAH)
        totalToBuy = totalToBuy + sub
        GameTooltip:AddDoubleLine(left, MoneyText(sub), 0.9, 0.9, 0.9, 1, 1, 1)
      end
    end
  end

  GameTooltip:AddLine(" ")

  if not anyToBuy then
    GameTooltip:AddLine("You already have all mats in bags.", 0.6, 1.0, 0.6)
    GameTooltip:AddDoubleLine("Total to buy", MoneyText(0), 1, 1, 1, 1, 1, 1)
  else
    if anyMissingPrice then
      GameTooltip:AddDoubleLine("Total to buy", "unknown", 1, 1, 1, 1.0, 0.3, 0.3)
      if #missingNames > 0 then
        GameTooltip:AddLine("Missing prices:", 0.8, 0.8, 0.8)
        for i = 1, math.min(#missingNames, 8) do
          GameTooltip:AddLine("- " .. tostring(missingNames[i]), 0.8, 0.8, 0.8)
        end
        if #missingNames > 8 then
          GameTooltip:AddLine("...and more", 0.8, 0.8, 0.8)
        end
      end
      GameTooltip:AddLine("Tip: scan AH with Auctionator.", 0.6, 0.6, 0.6)
    else
      GameTooltip:AddDoubleLine("Total to buy", MoneyText(totalToBuy), 1, 1, 1, 1, 1, 1)
    end
  end

  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Release SHIFT for full breakdown", 0.6, 0.6, 0.6)
end

local function ShowTooltip()
  if not hoverFrame then return end

  GameTooltip:SetOwner(hoverFrame, "ANCHOR_RIGHT")
  GameTooltip:ClearLines()

  -- Switch mode by modifier key
  if IsShiftKeyDown and IsShiftKeyDown() then
    ShowTooltip_ShoppingList()
  else
    ShowTooltip_Normal()
  end

  GameTooltip:Show()
end

local function HideTooltip()
  if GameTooltip and GameTooltip:IsShown() then
    GameTooltip:Hide()
  end
end

-- Polling
local pollFrame = CreateFrame("Frame")
pollFrame:Hide()

local lastSig = nil
local elapsed = 0

local function BuildSignature()
  local idx = (GetTradeSkillSelectionIndex and GetTradeSkillSelectionIndex()) or 0
  local req = (TradeSkillRequirementText and TradeSkillRequirementText.GetText and TradeSkillRequirementText:GetText()) or ""
  local num = (GetTradeSkillNumReagents and GetTradeSkillNumReagents(idx)) or 0

  local sig = tostring(idx) .. "|" .. tostring(req) .. "|" .. tostring(num)

  if idx > 0 and num and num > 0 and GetTradeSkillReagentItemLink and GetTradeSkillReagentInfo then
    for i = 1, num do
      local _, _, cnt = GetTradeSkillReagentInfo(idx, i)
      local link = GetTradeSkillReagentItemLink(idx, i) or ""
      local itemID = GetItemIDFromLink(link) or 0
      sig = sig .. "|" .. itemID .. "x" .. tostring(cnt or 0)
    end
  end

  return sig
end

pollFrame:SetScript("OnUpdate", function(self, dt)
  elapsed = elapsed + dt
  if elapsed < 0.20 then return end
  elapsed = 0

  if TradeSkillFrame and TradeSkillFrame.IsShown and not TradeSkillFrame:IsShown() then
    self:Hide()
    lastSig = nil
    HideTooltip()
    return
  end

  local sig = BuildSignature()
  if sig ~= lastSig then
    lastSig = sig
    UpdateOneLine()
  end

  -- If tooltip is showing, refresh it so Shift toggle updates instantly
  if GameTooltip and GameTooltip:IsShown() and hoverFrame and hoverFrame:IsMouseOver() then
    ShowTooltip()
  end
end)

local function StartPolling()
  lastSig = nil
  elapsed = 0
  pollFrame:Show()
  UpdateOneLine()

  if hoverFrame and not hoverFrame.__sephHooked then
    hoverFrame.__sephHooked = true
    hoverFrame:SetScript("OnEnter", ShowTooltip)
    hoverFrame:SetScript("OnLeave", HideTooltip)
  end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("TRADE_SKILL_SHOW")
f:RegisterEvent("TRADE_SKILL_UPDATE")

f:SetScript("OnEvent", function(self, event)
  if event == "PLAYER_LOGIN" then
    print("|cff00ff88Auctionator_SephCraft|r loaded.")
  end
  StartPolling()
end)

SLASH_SEPHCRAFTCOST1 = "/scc"
SlashCmdList["SEPHCRAFTCOST"] = function()
  UpdateOneLine()
  print("|cff00ff88Auctionator_SephCraft|r updated.")
end
