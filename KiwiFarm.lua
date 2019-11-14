-- ============================================================================
-- KiwiFarm (C) 2019 MiCHaEL
-- ============================================================================

local addonName = ...

-- main frame
local addon = CreateFrame('Frame', "KiwiFarm", UIParent)

-- misc values
local CLASSIC = (WOW_PROJECT_ID == WOW_PROJECT_CLASSIC)
local DUMMY = function() end

-- default values
local RESET_MAX = CLASSIC and 5 or 10
local MARGIN = 4
local COLOR_TRANSPARENT = { 0,0,0,0 }
local FONTS = {
	Arial = 'Fonts\\ARIALN.TTF',
	FrizQT = 'Fonts\\FRIZQT__.TTF',
	Morpheus = 'Fonts\\MORPHEUS.TTF',
	Skurri = 'Fonts\\SKURRI.TTF'
}
local SOUNDS = CLASSIC and {
	["Auction Window Open"] = "sound/interface/auctionwindowopen.ogg",
	["Auction Window Close"] = "sound/interface/auctionwindowclose.ogg",
	["Coin" ] = "sound/interface/lootcoinlarge.ogg",
	["Money"] = "sound/interface/imoneydialogopen.ogg",
	["Level Up"] = "sound/interface/levelup.ogg",
	["Pick Up Gems"] = "sound/interface/pickup/pickupgems.ogg",
	["Player Invite"] = "sound/interface/iplayerinvitea.ogg",
	["Put Down Gems"] = "sound/interface/pickup/putdowngems.ogg",
	["PvP Enter Queue"] = "sound/spells/pvpenterqueue.ogg",
	["PvP Through Queue"] =	"sound/spells/pvpthroughqueue.ogg",
	["Raid Warning"] = "sound/interface/raidwarning.ogg",
	["Ready Check"] = "sound/interface/readycheck.ogg",
	["Quest List Open"] = "sound/interface/iquestlogopena.ogg",
} or {
	["Auction Window Open"] = 567482,
	["Auction Window Close"] = 567499,
	["Coin" ] = 567428,
	["Money"] = 567483,
	["Level Up"] = 569593,
	["Pick Up Gems"] = 567568,
	["Player Invite"] = 567451,
	["Put Down Gems"] = 567574,
	["PvP Enter Queue"] = 568587,
	["PvP Through Queue"] =	568011,
	["Raid Warning"] =567397,
	["Ready Check"] = 567478,
	["Quest List Open"] = 567504,
}

-- database defaults
local DEFAULTS = {
	mobKills              = 0,
	moneyCash             = 0,
	moneyItems            = 0,
	countItems            = 0,
	moneyDaily            = {},
	moneyByQuality        = {},
	countByQuality        = {},
	lootedItems           = {},
	priceByItem           = {},
	priceByQuality        = { [0]={vendor=true}, [1]={vendor=true}, [2]={vendor=true}, [3]={vendor=true}, [4]={vendor=true}, [5]={vendor=true} },
	notify 				  = { [1]={chat=0}, [2]={chat=0}, [3]={chat=0}, [4]={chat=0}, [5]={chat=0}, sound={} },
	disabled              = { quality=true },
	backColor 	          = { 0, 0, 0, .4 },
	framePos              = { anchor = 'TOPLEFT', x = 0, y = 0 },
	visible               = true,
	minimapIcon           = { hide = false },
}

-- local references
local time = time
local date = date
local type = type
local next = next
local print = print
local pairs = pairs
local unpack = unpack
local tinsert = tinsert
local tonumber = tonumber
local gsub = gsub
local strfind = strfind
local floor = math.floor
local strlower = strlower
local format = string.format
local band = bit.band
local strmatch = strmatch
local IsInInstance = IsInInstance
local GetZoneText = GetZoneText
local GetItemInfo = GetItemInfo
local COPPER_PER_GOLD = COPPER_PER_GOLD
local COPPER_PER_SILVER = COPPER_PER_SILVER
local COMBATLOG_OBJECT_CONTROL_NPC = COMBATLOG_OBJECT_CONTROL_NPC

-- database references
local config   -- database realm table
local resets   -- instance resets table
local disabled -- disabled texts table
local notify   -- notifications table

-- miscellaneous variables
local inInstance
local combatActive
local combatCurKills = 0
local combatPreKills = 0
local timeLootedItems = 0 -- track changes in config.lootedItems table

-- main frame elements
local texture -- background texture
local textl   -- left text
local textr   -- right text
local timer   -- update timer

-- ============================================================================
-- utils & misc functions
-- ============================================================================

local ZoneTitle
do
	local strcut
	if GetLocale() == "enUS" or GetLocale() == "enGB" then -- standard cut
		local strsub = strsub
		strcut = function(s,c)
			return strsub(s,1,c)
		end
	else -- utf8 cut
		local strbyte = string.byte
		strcut = function(s, c)
			local l, i = #s, 1
			while c>0 and i<=l do
				local b = strbyte(s, i)
				if     b < 192 then	i = i + 1
				elseif b < 224 then i = i + 2
				elseif b < 240 then	i = i + 3
				else				i = i + 4
				end
				c = c - 1
			end
			return s:sub(1, i-1)
		end
	end
	ZoneTitle = setmetatable( {}, { __index = function(t,k) local v=strcut(k,18); t[k]=v; return v; end } )
end

-- text format functions
local function strfirstword(str)
	return strmatch(str, "^(.-) ") or str
end

local function FmtQuality(i)
	return format( "|c%s%s|r", select(4,GetItemQualityColor(i)), _G['ITEM_QUALITY'..i..'_DESC'] )
end

local function FmtMoney(money)
	money = money or 0
	local gold   = floor(  money / COPPER_PER_GOLD )
    local silver = floor( (money % COPPER_PER_GOLD) / COPPER_PER_SILVER )
    local copper = floor(  money % COPPER_PER_SILVER )
	return format( config.moneyFmt or "%d|cffffd70ag|r %d|cffc7c7cfs|r %d|cffeda55fc|r", gold, silver, copper)
end

local function FmtMoneyShort(money)
	local str    = ''
	local gold   = floor(  money / COPPER_PER_GOLD )
    local silver = floor( (money % COPPER_PER_GOLD) / COPPER_PER_SILVER )
    local copper = floor(  money % COPPER_PER_SILVER )
	if silver>0 then str = format( "%s %d|cffc7c7cfs|r", str, silver) end
	if copper>0 then str = format( "%s %d|cffeda55fc|r", str, copper) end
	if gold>0 or str=='' then str = format( "%d|cffffd70ag|r%s", gold, str)  end
	return strtrim(str)
end

local function FmtMoneyPlain(money)
	if money then
		local gold   = floor(  money / COPPER_PER_GOLD )
		local silver = floor( (money % COPPER_PER_GOLD) / COPPER_PER_SILVER )
		local copper = floor(  money % COPPER_PER_SILVER )
		return format( "%dg %ds %dc", gold, silver, copper)
	end
end

local function String2Copper(str)
	str = strlower(gsub(str,' ',''))
	if str~='' then
		local c,s,g = tonumber(strmatch(str,"([%d,.]+)c")), tonumber(strmatch(str,"([%d,.]+)s")), tonumber(strmatch(str,"([%d,.]+)g"))
		if not (c or s or g) then
			g = tonumber(str)
		end
		return floor( (c or 0) + (s or 0)*100 + (g or 0)*10000 )
	end
end

-- dialogs
do
	StaticPopupDialogs["KIWIFARM_DIALOG"] = { timeout = 0, whileDead = 1, hideOnEscape = 1, button1 = ACCEPT, button2 = CANCEL }

	function addon:ShowDialog(message, textDefault, funcAccept, funcCancel, textAccept, textCancel)
		local t = StaticPopupDialogs["KIWIFARM_DIALOG"]
		t.OnShow = function (self) if textDefault then self.editBox:SetText(textDefault) end; self:SetFrameStrata("TOOLTIP") end
		t.OnHide = function(self) self:SetFrameStrata("DIALOG")	end
		t.hasEditBox = textDefault and true or nil
		t.text = message
		t.button1 = funcAccept and (textAccept or ACCEPT) or nil
		t.button2 = funcCancel and (textCancel or CANCEL) or nil
		t.OnCancel = funcCancel
		t.OnAccept = funcAccept and function (self)	funcAccept( textDefault and self.editBox:GetText() ) end or nil
		StaticPopup_Show ("KIWIFARM_DIALOG")
	end

	function addon:MessageDialog(message, funcAccept)
		addon:ShowDialog(message, nil, funcAccept or DUMMY)
	end

	function addon:ConfirmDialog(message, funcAccept, funcCancel, textAccept, textCancel)
		self:ShowDialog(message, nil, funcAccept, funcCancel or DUMMY, textAccept, textCancel )
	end

	function addon:EditDialog(message, text, funcAccept, funcCancel)
		self:ShowDialog(message, text or "", funcAccept, funcCancel or DUMMY)
	end
end

-- ============================================================================
-- addon specific functions
-- ============================================================================

-- notification funcions
local Notify, NotifyEnd
do
	local function fmtLoot(itemLink, quantity, money, pref )
		local prefix = pref and '|cFF7FFF72KiwiFarm:|r ' or ''
		if itemLink then
			return format("%s%sx%d %s", prefix, itemLink, quantity, FmtMoneyShort(money) )
		else
			return format("%sYou loot %s", prefix, FmtMoneyShort(money) )
		end
	end
	local notified = {}
	local channels = {
		chat = function(itemLink, quantity, money)
			print( fmtLoot(itemLink, quantity, money, true) )
		end,
		combat = function(itemLink, quantity, money)
			if CombatText_AddMessage then
				local text = fmtLoot(itemLink, quantity, money)
				CombatText_AddMessage(text, COMBAT_TEXT_SCROLL_FUNCTION, 1, 1, 1)
			else
				print('|cFF7FFF72KiwiFarm:|r Warning, Blizzard Floating Combat Text is not enabled, change the notifications setup or goto Interface Options>Combat to enable this feature.')
			end
		end,
		crit = function(itemLink, quantity, money)
			if CombatText_AddMessage then
				local text = fmtLoot(itemLink, quantity, money)
				CombatText_AddMessage(text, COMBAT_TEXT_SCROLL_FUNCTION, 1, 1, 1, 'crit')
			else
				print('|cFF7FFF72KiwiFarm:|r Warning, Blizzard Floating Combat Text is not enabled, change the notifications setup or goto Interface Options>Combat to enable this feature.')
			end
		end,
		msbt = function(itemLink, quantity, money)
			if MikSBT then
				local text = fmtLoot(itemLink, quantity, money)
				MikSBT.DisplayMessage(text, MikSBT.DISPLAYTYPE_NOTIFICATION, false, 255, 255, 255)
			else
				print('|cFF7FFF72KiwiFarm:|r Warning, MikScrollingCombatText addon is not installed, change the notifications setup or install MSBT.')
			end
		end,
		sound = function(_, _, _, groupKey)
			local sound = notify.sound[groupKey]
			if sound then PlaySoundFile(sound, "master") end
		end,
	}
	function Notify(groupKey, itemLink, quantity, money)
		for channel,v in pairs(notify[groupKey]) do
			if not notified[channel] then
				local func = channels[channel]
				if func and money>=v then
					func(itemLink, quantity, money, groupKey)
					notified[channel] = true
				end
			end
		end
	end
	function NotifyEnd()
		wipe(notified)
	end
end

-- items & price functions
local IsEnchantingMat
if CLASSIC then
	local ENCHANTING = {
		[10940] = true, [11134] = true, [16203] = true,	[11135] = true, [11174] = true,	[14344] = true,
		[11082] = true, [11137] = true,	[11083] = true,	[10998] = true,	[20725] = true,	[11138] = true,
		[11084] = true,	[11139] = true,	[11178] = true,	[10938] = true,	[11176] = true,	[14343] = true,
		[11177] = true,	[10939] = true,	[10978] = true,	[16204] = true,	[16202] = true,	[11175] = true,
	}
	function IsEnchantingMat(itemID)
		return ENCHANTING[itemID]
	end
else
	function IsEnchantingMat(_, class, subClass)
		return class==7 and subClass==12
	end
end

-- calculate item price
local GetItemPrice
do
	local max = math.max
	local ItemUpgradeInfo
	local function GetValue(source, itemLink, itemID, name, class, rarity, vendorPrice, userPrice)
		local price
		if source == 'user' then
			price = userPrice
		elseif source == 'vendor' then
			price = vendorPrice
		elseif source == 'Atr:DBMarket' and ItemUpgradeInfo then -- Auctionator: market
			price = Atr_GetAuctionPrice(name)
		elseif source == 'Atr:Destroy' and ItemUpgradeInfo then -- Auctionator: disenchant
			price = Atr_CalcDisenchantPrice(class, rarity, ItemUpgradeInfo:GetUpgradedItemLevel(itemLink)) -- Atr_GetDisenchantValue() is bugged cannot be used
		elseif TSMAPI_FOUR then -- TSM4 sources
			price = TSMAPI_FOUR.CustomPrice.GetValue(source, "i:"..itemID)
		end
		return price or 0
	end
	function GetItemPrice(itemLink)
		ItemUpgradeInfo = Atr_GetAuctionPrice and Atr_CalcDisenchantPrice and LibStub('LibItemUpgradeInfo-1.0',true) -- Check if auctionator is installed
		GetItemPrice = function(itemLink)
			local itemID = tonumber(strmatch(itemLink, "item:(%d+):"))
			local name, _, rarity, _, _, _, _, _, _, _, vendorPrice, class, subClass = GetItemInfo(itemLink)
			if not (config.ignoreEnchantingMats and IsEnchantingMat(itemID, class, subClass)) then
				local price, sources = 0, config.priceByItem[itemLink] or config.priceByQuality[rarity or 0] or {}
				for src, user in pairs(sources) do
					price = max( price, GetValue(src, itemLink, itemID, name, class, rarity, vendorPrice, user) )
				end
				return price, rarity, name
			end
		end
		return GetItemPrice(itemLink)
	end
end

-- display farming info
local PrepareText, RefreshText
do
	local text_header
	local text_mask
	local data = {}
	-- prepare text
	function PrepareText()
		-- header & session duration
		text_header =              "|cFF7FFF72KiwiFarm:|r\nSession:\n"
		text_mask   =	           "|cFF7FFF72%s|r\n"      -- zone
		text_mask   = text_mask .. "%s%02d:%02d:%02d|r\n"  -- session duration
		-- instance reset & lock info
		if not disabled.reset then
			text_header = text_header .. "Resets:\nLocked:\n"
			text_mask   = text_mask   .. "(%s%d|r) %s%02d:%02d|r\n"  -- last reset
			text_mask   = text_mask   .. "(%s%d|r) %s%02d:%02d|r\n"  -- lock time
		end
		-- count data
		if not disabled.count then
			-- mobs killed
			text_header = text_header .. "Mobs killed:\n"
			text_mask   = text_mask   .. "(%d) %d\n"
			-- items looted
			text_header = text_header .. "Items looted:\n"
			text_mask   = text_mask   .. "%d\n"
		end
		-- gold cash & items
		text_header = text_header .. "Gold cash:\nGold items:\n"
		text_mask   = text_mask   .. "%s\n"  -- money cash
		text_mask   = text_mask   .. "%s\n"  -- money items
		-- gold by item quality
		if not disabled.quality then
			for i=0,5 do -- gold by qualities (poor to legendary)
				text_header = text_header .. format(" %s\n",FmtQuality(i));
				text_mask   = text_mask   .. "(%d) %s\n"
			end
		end
		-- gold hour & total
		text_header = text_header .. "Gold/hour:\nGold total:"
		text_mask   = text_mask .. "%s\n" -- money per hour
		text_mask   = text_mask .. "%s" -- money total
		textl:SetText(text_header)
	end
	-- refresh text
	function RefreshText()
		local curtime = time()
		-- refresh reset data if first reset is +1hour old
		while (#resets>0 and curtime-resets[1]>3600) or #resets>RESET_MAX do -- remove old resets(>1hour)
			table.remove(resets,1)
		end
		-- reset old data
		wipe(data)
		-- zone text
		data[#data+1] = ZoneTitle[ GetZoneText() ]
		-- session duration
		local sSession = curtime - (config.sessionStart or curtime) + (config.sessionDuration or 0)
		local m0, s0 = floor(sSession/60), sSession%60
		local h0, m0 = floor(m0/60), m0%60
		data[#data+1] = config.sessionStart and '|cFF00ff00' or '|cFFff0000'
		data[#data+1] = h0
		data[#data+1] = m0
		data[#data+1] = s0
		-- reset data
		if not disabled.reset then
			local timeLast  = resets[#resets]
			local timeLock  = #resets>0 and resets[1]+3600 or nil
			local remain    = RESET_MAX-#resets
			local sReset = (timeLast and curtime-timeLast) or 0 -- (config.lockspent and curtime-config.lockspent) or 0
			local sUnlock = timeLock and timeLock-curtime or 0
			--
			data[#data+1] = (remain==RESET_MAX and '|cFF00ff00') or (remain>0 and '|cFFff8000') or '|cFFff0000'
			data[#data+1] = #resets
			data[#data+1] = config.lockspent and '|cFFff8000' or '|cFF00ff00'
			data[#data+1] = floor(sReset/60)
			data[#data+1] = sReset%60
			--
			data[#data+1] = remain>0 and '|cFF00ff00' or '|cFFff0000'
			data[#data+1] = remain
			data[#data+1] = remain<=0 and (sUnlock>60*5 and '|cFFff0000' or '|cFFff8000') or '|cFF00ff00'
			data[#data+1] = floor(sUnlock/60)
			data[#data+1] = sUnlock%60
		end
		-- count data
		if not disabled.count then
			-- mob kills
			data[#data+1] = combatCurKills or combatPreKills
			data[#data+1] = config.mobKills
			-- items looted
			data[#data+1] = config.countItems
		end
		-- gold info
		data[#data+1] = FmtMoney(config.moneyCash)
		data[#data+1] = FmtMoney(config.moneyItems)
		if not disabled.quality then
			for i=0,5 do
				data[#data+1] = config.countByQuality[i] or 0
				data[#data+1] = FmtMoney(config.moneyByQuality[i] or 0)
			end
		end
		local total = config.moneyCash+config.moneyItems
		data[#data+1] = FmtMoney(sSession>0 and floor(total*3600/sSession) or 0)
		data[#data+1] = FmtMoney(total)
		-- set text
		textr:SetFormattedText( text_mask, unpack(data) )
		-- update timer status
		local stopped = #resets==0 and not config.lockspent and not config.sessionStart
		if stopped ~= not timer:IsPlaying() then
			if stopped then
				timer:Stop()
			else
				timer:Play()
			end
		end
	end
end

-- adjust the money stats of a looted item whose price was changed by the user.
local function AdjustLootedItemMoneyStats(itemLink)
	local lootedItem = config.lootedItems[itemLink]
	if lootedItem then
		local newPrice, quality = GetItemPrice(itemLink)
		if newPrice then
			local newMoney = newPrice * lootedItem.quantity
			local moneyDiff = newMoney - lootedItem.money
			if moneyDiff ~= 0 then
				-- item
				lootedItem.money = newMoney
				-- total
				config.moneyItems = math.max(0, config.moneyItems + moneyDiff)
				-- quality
				config.moneyByQuality[quality] = math.max(0, config.moneyByQuality[quality] + moneyDiff)
				-- daily
				local dailyKey = date("%Y/%m/%d")
				config.moneyDaily[dailyKey] = math.max(0, config.moneyDaily[dailyKey] + moneyDiff)
				--
				RefreshText()
			end
		end
	end
end

-- register instance reset
local function AddReset()
	local curtime = time()
	if curtime-(resets[#resets] or 0)>3 then -- ignore reset of additional instances
		config.lockspent = nil
		tinsert( resets, curtime )
		if addon:IsVisible() then
			RefreshText()
		end
	end
end

-- session start
local function SessionStart(force)
	if not config.sessionStart or force==true then
		config.sessionStart = config.sessionStart or time()
		config.moneyCash  = config.moneyCash or 0
		config.moneyItems = config.moneyItems or 0
		config.countItems = config.countItems or 0
		config.mobKills   = config.mobKills or 0
		addon:RegisterEvent("PLAYER_REGEN_DISABLED")
		addon:RegisterEvent("PLAYER_REGEN_ENABLED")
		addon:RegisterEvent("CHAT_MSG_LOOT")
		addon:RegisterEvent("CHAT_MSG_MONEY")
		addon:RegisterEvent('COMBAT_LOG_EVENT_UNFILTERED')
		RefreshText()
	end
end

-- session stop
local function SessionStop()
	if config.sessionStart then
		local curtime = time()
		config.sessionDuration = (config.sessionDuration or 0) + (curtime - (config.sessionStart or curtime))
		config.sessionStart = nil
		addon:UnregisterEvent("PLAYER_REGEN_DISABLED")
		addon:UnregisterEvent("PLAYER_REGEN_ENABLED")
		addon:UnregisterEvent("CHAT_MSG_LOOT")
		addon:UnregisterEvent("CHAT_MSG_MONEY")
		addon:UnregisterEvent('COMBAT_LOG_EVENT_UNFILTERED')
	end
end

-- session clear
local function SessionReset()
	config.sessionStart = config.sessionStart and time() or nil
	config.sessionDuration = nil
	config.mobKills   = 0
	config.moneyCash  = 0
	config.moneyItems = 0
	config.countItems = 0
	wipe(config.lootedItems)
	wipe(config.moneyByQuality)
	wipe(config.countByQuality)
	RefreshText()
	timeLootedItems = time()
end

-- restore main frame position
local function RestorePosition()
	addon:ClearAllPoints()
	addon:SetPoint( config.framePos.anchor, UIParent, 'CENTER', config.framePos.x, config.framePos.y )
end

-- save main frame position
local function SavePosition()
	local p, cx, cy = config.framePos, UIParent:GetCenter() -- we are assuming addon frame scale=1 in calculations
	local x = (p.anchor:find("LEFT")   and addon:GetLeft())   or (p.anchor:find("RIGHT") and addon:GetRight()) or addon:GetLeft()+addon:GetWidth()/2
	local y = (p.anchor:find("BOTTOM") and addon:GetBottom()) or (p.anchor:find("TOP")   and addon:GetTop())   or addon:GetTop() -addon:GetHeight()/2
	p.x, p.y = x-cx, y-cy
end

-- frame sizing
local function UpdateFrameSize()
	addon:SetHeight( textl:GetHeight() + MARGIN*2 )
	addon:SetWidth( config.frameWidth or (textl:GetWidth() * 2.3) + MARGIN*2 )
	addon:SetScript('OnUpdate', nil)
end

-- layout main frame
local function LayoutFrame()
	-- background
	texture:SetColorTexture( unpack(config.backColor or COLOR_TRANSPARENT) )
	-- text left
	textl:ClearAllPoints()
	textl:SetPoint('TOPLEFT', MARGIN, -MARGIN)
	textl:SetJustifyH('LEFT')
	textl:SetJustifyV('TOP')
	textl:SetFont(config.fontname or FONTS.Arial or STANDARD_TEXT_FONT, config.fontsize or 14, 'OUTLINE')
	PrepareText()
	-- text right
	textr:ClearAllPoints()
	textr:SetPoint('TOPRIGHT', -MARGIN, -MARGIN)
	textr:SetPoint('TOPLEFT', MARGIN, -MARGIN)
	textr:SetJustifyH('RIGHT')
	textr:SetJustifyV('TOP')
	textr:SetFont(config.fontname or FONTS.Arial or STANDARD_TEXT_FONT, config.fontsize or 14, 'OUTLINE')
	RefreshText()
	-- delayed frame sizing, because textl:GetHeight() returns incorrect height on first login for some fonts.
	addon:SetScript("OnUpdate", UpdateFrameSize)
end

-- ============================================================================
-- events
-- ============================================================================

-- main frame becomes visible
addon:SetScript("OnShow", function(self)
	RefreshText()
end)

-- shift+mouse click to reset instances
addon:SetScript("OnMouseUp", function(self, button)
	if button == 'RightButton' then
		addon:ShowMenu()
	elseif button == 'LeftButton' and IsShiftKeyDown() then -- reset instances data
		ResetInstances()
	end
end)

-- track reset instance event
local PATTERN_RESET = '^'..INSTANCE_RESET_SUCCESS:gsub("([^%w])","%%%1"):gsub('%%%%s','.+')..'$'
function addon:CHAT_MSG_SYSTEM(event,msg)
	if strfind(msg,PATTERN_RESET) then
		AddReset()
	end
end

-- looted items
local PATTERN_LOOTS = LOOT_ITEM_SELF:gsub("%%s", "(.+)")
local PATTERN_LOOTM = LOOT_ITEM_SELF_MULTIPLE:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
function addon:CHAT_MSG_LOOT(event,msg)
	if config.sessionStart then
		local itemLink, quantity = strmatch(msg, PATTERN_LOOTM)
		if not itemLink then
			quantity = 1
			itemLink = strmatch(msg, PATTERN_LOOTS)
		end
		if itemLink then
			local price, rarity, itemName = GetItemPrice(itemLink)
			if price then
				local money = price*quantity
				-- register item looted
				local lootedItem = config.lootedItems[itemLink]
				if not lootedItem then
					lootedItem = { money = 0, quantity = 0 }
					config.lootedItems[itemLink] = lootedItem
					timeLootedItems = time()
				end
				lootedItem.quantity = lootedItem.quantity + quantity
				lootedItem.money    = lootedItem.money    + money
				-- register item money earned
				config.moneyItems = config.moneyItems + money
				config.moneyByQuality[rarity] = (config.moneyByQuality[rarity] or 0) + money
				-- register daily money earned
				local dailyKey = date("%Y/%m/%d")
				config.moneyDaily[dailyKey] = (config.moneyDaily[dailyKey] or 0) + money
				-- register counts
				config.countItems = config.countItems + quantity
				config.countByQuality[rarity] = (config.countByQuality[rarity] or 0) + quantity
				-- notifications
				if notify[rarity] then Notify(rarity,   itemLink, quantity, money) end
				if notify.price   then Notify('price',  itemLink, quantity, money) end
				NotifyEnd()
			end
		end
	end
end

-- looted gold
do
	local digits = {}
	local func = function(n) digits[#digits+1]=n end
	function addon:CHAT_MSG_MONEY(event,msg)
		if config.sessionStart then
			wipe(digits)
			gsub(msg,"%d+",func)
			local money = digits[#digits] + (digits[#digits-1] or 0)*100 + (digits[#digits-2] or 0)*10000
			-- register cash money
			config.moneyCash = config.moneyCash + money
			-- register daily money
			local dailyKey = date("%Y/%m/%d")
			config.moneyDaily[dailyKey] = (config.moneyDaily[dailyKey] or 0) + money
			-- notify
			if notify.money then
				Notify('money', nil, nil, money); NotifyEnd()
			end
		end
	end
end

-- combat start
function addon:PLAYER_REGEN_DISABLED()
	combatActive = true
	combatPreKills = combatCurKills or combatPreKills
	combatCurKills = nil
end

-- combat end
function addon:PLAYER_REGEN_ENABLED()
	combatActive = nil
end

-- zones management
do
	local lastZoneKey
	function addon:ZONE_CHANGED_NEW_AREA(event)
		local zone = GetZoneText()
		if zone and zone~='' then
			inInstance = IsInInstance()
			local zoneKey = format("%s:%s",zone,tostring(inInstance))
			if zoneKey ~= lastZoneKey or (not event) then -- no event => called from config
				if inInstance and #resets>=RESET_MAX then -- locked but inside instance, means locked expired before estimated unlock time
					table.remove(resets,1)
				end
				if config.zones then
					if config.zones[zone] then
						if inInstance and lastZoneKey then
							SessionStart()
						else
							RefreshText()
						end
						self:Show()
					elseif not config.reloadUI then
						SessionStop()
						self:Hide()
					end
				elseif self:IsVisible() then
					RefreshText()
				end
				if config.reloadUI then -- clear reloadUI flag if set
					config.reloadUI = nil
				end
				lastZoneKey = zoneKey
			end
		end
	end
	addon.PLAYER_ENTERING_WORLD = addon.ZONE_CHANGED_NEW_AREA
end

-- stop session and register automatic reset on player logout
do
	local isLogout
	hooksecurefunc("Logout", function() isLogout=true end)
	hooksecurefunc("Quit",   function() isLogout=true end)
	hooksecurefunc("CancelLogout", function() isLogout=nil end)
	function addon:PLAYER_LOGOUT()
		if isLogout then
			if config.lockspent and not IsInInstance() then
				AddReset()
			end
			SessionStop()
		end
		config.reloadUI = not isLogout or nil
	end
end

-- If we kill a npc inside instance a ResetInstance() is executed on player logout, so we need this to track
-- and save this hidden reset, see addon:PLAYER_LOGOUT()
function addon:COMBAT_LOG_EVENT_UNFILTERED()
	local _, eventType,_,_,_,_,_,dstGUID,_,dstFlags = CombatLogGetCurrentEventInfo()
	if eventType == 'UNIT_DIED' and band(dstFlags,COMBATLOG_OBJECT_CONTROL_NPC)~=0 then
		if inInstance and not config.lockspent then
			config.lockspent = time()
			timer:Play()
		end
		config.mobKills = config.mobKills + 1
		combatCurKills = (combatCurKills or 0) + 1
	end
end

-- ============================================================================
-- addon entry point
-- ============================================================================

addon:RegisterEvent("ADDON_LOADED")
addon:RegisterEvent("PLAYER_LOGIN")
addon:SetScript("OnEvent", function(frame, event, name)
	if event == "ADDON_LOADED" and name == addonName then
		addon.__loaded = true
	end
	if not (addon.__loaded and IsLoggedIn()) then return end
	-- unregister init events
	addon:UnregisterAllEvents()
	-- main frame init
	addon:Hide()
	addon:SetSize(1,1)
	addon:EnableMouse(true)
	addon:SetMovable(true)
	addon:RegisterForDrag("LeftButton")
	addon:SetScript("OnDragStart", addon.StartMoving)
	addon:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		self:SetUserPlaced(false)
		SavePosition()
		RestorePosition()
	end )
	-- background texture
	texture = addon:CreateTexture()
	texture:SetAllPoints()
	-- text left
	textl = addon:CreateFontString()
	-- text right
	textr = addon:CreateFontString()
	-- timer
	timer = addon:CreateAnimationGroup()
	timer.animation = timer:CreateAnimation()
	timer.animation:SetDuration(1)
	timer:SetLooping("REPEAT")
	timer:SetScript("OnLoop", RefreshText)
	-- database setup
	local serverKey = GetRealmName()
	local root = KiwiFarmDB
	if not root then
		root = {}; KiwiFarmDB = root
	end
	config = root[serverKey]
	if not config then
		config = { resets = {} }; root[serverKey] = config
	end
	for k,v in pairs(DEFAULTS) do -- apply missing default values
		if config[k]==nil then
			config[k] = v
		end
	end
	resets   = config.resets
	notify   = config.notify
	disabled = config.disabled
	-- minimap icon
	LibStub("LibDBIcon-1.0"):Register(addonName, LibStub("LibDataBroker-1.1"):NewDataObject(addonName, {
		type  = "launcher",
		label = GetAddOnInfo( addonName, "Title"),
		icon  = "Interface\\AddOns\\KiwiFarm\\KiwiFarm",
		OnClick = function(self, button)
			if button == 'RightButton' then
				addon:ShowMenu()
			else
				addon:SetShown( not addon:IsShown() )
				config.visible = addon:IsShown()
			end
		end,
		OnTooltipShow = function(tooltip)
			tooltip:AddDoubleLine("KiwiFarm", GetAddOnMetadata(addonName, "Version") )
			tooltip:AddLine("|cFFff4040Left Click|r toggle window visibility\n|cFFff4040Right Click|r open config menu", 0.2, 1, 0.2)
		end,
	}) , config.minimapIcon)
	-- events
	addon:SetScript('OnEvent', function(self,event,...) self[event](self,event,...) end)
	addon:RegisterEvent("CHAT_MSG_SYSTEM")
	addon:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	addon:RegisterEvent("PLAYER_ENTERING_WORLD")
	addon:RegisterEvent("PLAYER_LOGOUT")
	-- frame position
	RestorePosition()
	-- frame size & appearance
	LayoutFrame()
	-- session
	if config.sessionStart then
		SessionStart(true)
	end
	-- mainframe initial visibility
	addon:SetShown( config.visible and (not config.zones or config.reloadUI) )
end)

-- ============================================================================
-- config cmdline
-- ============================================================================

SLASH_KIWIFARM1,SLASH_KIWIFARM2 = "/kfarm", "/kiwifarm"
SlashCmdList.KIWIFARM = function(args)
	local arg1,arg2,arg3 = strsplit(" ",args,3)
	arg1, arg2 = strlower(arg1 or ''), strlower(arg2 or '')
	if arg1 == 'show' then
		addon:Show()
	elseif arg1 == 'hide' then
		addon:Hide()
	elseif arg1 == 'config' then
		addon:ShowMenu()
	elseif arg1 == 'minimap' then
		config.minimapIcon.hide = not config.minimapIcon.hide
		if config.minimapIcon.hide then
			LibStub("LibDBIcon-1.0"):Hide(addonName)
		else
			LibStub("LibDBIcon-1.0"):Show(addonName)
		end
	else
		print("Kiwi Farm:")
		print("  Right-Click to display config menu.")
		print("  Shift-Click to reset instances.")
		print("  Click&Drag to move main frame.")
		print("Commands:")
		print("  /kfarm show     -- show main window")
		print("  /kfarm hide     -- hide main window")
 		print("  /kfarm config   -- display config menu")
		print("  /kfarm minimap  -- toggle minimap icon visibility")
	end
end

-- ============================================================================
-- config popup menu
-- ============================================================================

do
	-- popup menu main frame
	local menuFrame = CreateFrame("Frame", "KiwiFarmPopupMenu", UIParent, "UIDropDownMenuTemplate")

	-- generic & enhanced popup menu management code, reusable for other menus
	local showMenu, refreshMenu, getMenuLevel, getMenuValue, splitMenu, wipeMenu
	do
		-- menu initialization: special management of enhanced menuList tables, using fields not supported by the base UIDropDownMenu code.
		local function initialize( frame, level, menuList )
			if level then
				frame.menuValues[level] = UIDROPDOWNMENU_MENU_VALUE
				local init = menuList.init
				if init then -- custom initialization function for the menuList
					init(menuList, level, frame)
				end
				for index=1,#menuList do
					local item = menuList[index]
					if item.useParentValue then -- use the value of the parent popup, needed to make splitMenu() transparent
						item.value = UIDROPDOWNMENU_MENU_VALUE
					end
					if type(item.text)=='function' then -- save function text in another field for later use
						item.textf = item.text
					end
					if item.textf then -- text support for functions instead of only strings
						item.text = item.textf(item, level, frame)
					end
					if item.hasColorSwatch then -- simplified color management, only definition of get&set functions required to retrieve&save the color
						if not item.swatchFunc then
							local get, set = item.get, item.set
							item.swatchFunc  = function() local r,g,b,a = get(item); r,g,b = ColorPickerFrame:GetColorRGB(); set(item,r,g,b,a) end
							item.opacityFunc = function() local r,g,b   = get(item); set(item, r,g,b,1-OpacitySliderFrame:GetValue()) end
							item.cancelFunc  = function(c) set(item, c.r, c.g, c.b, 1-c.opacity) end
						end
						item.r, item.g, item.b, item.opacity = item.get(item)
						item.opacity = 1 - item.opacity
					end
					item.index = index
					UIDropDownMenu_AddButton(item,level)
				end
			end
		end
		-- get the MENU_LEVEL of the specified menu element ( element = DropDownList|button|nil )
		function getMenuLevel(element)
			return element and ((element.dropdown and element:GetID()) or element:GetParent():GetID()) or UIDROPDOWNMENU_MENU_LEVEL
		end
		-- get the MENU_VALUE of the specified menu element ( element = level|DropDownList|button|nil )
		function getMenuValue(element)
			return element and (UIDROPDOWNMENU_OPEN_MENU.menuValues[type(element)=='table' and getMenuLevel(element) or element]) or UIDROPDOWNMENU_MENU_VALUE
		end
		-- clear menu table, preserving special control fields
		function wipeMenu(menu)
			local init = menu.init;	wipe(menu); menu.init = init
		end
		-- split a big menu items table in several submenus
		function splitMenu(menu, fsort, fdisp)
			fsort = fsort or 'text'
			fdisp = fdisp or fsort
			table.sort(menu, function(a,b) return a[fsort]<b[fsort] end )
			local count, items, first, last = #menu
			if count>28 then
				for i=1,count do
					if not items or #items>=28 then
						if items then
							menu[#menu].text = strfirstword(first[fdisp]) .. ' - ' .. strfirstword(last[fdisp])
						end
						items = {}
						tinsert(menu, { notCheckable= true, hasArrow = true, useParentValue = true, menuList = items } )
						first = menu[1]
					end
					last = table.remove(menu,1)
					tinsert(items, last)
				end
				menu[#menu].text = strfirstword(first[fdisp]) .. ' - ' .. strfirstword(last[fdisp])
				return true
			end
		end
		-- refresh a submenu ( element = level | button | dropdownlist )
		function refreshMenu(element, hideChilds)
			local level = type(element)=='number' and element or getMenuLevel(element)
			if hideChilds then CloseDropDownMenus(level+1) end
			local frame = _G["DropDownList"..level]
			if frame and frame:IsShown() then
				local _, anchorTo = frame:GetPoint(1)
				if anchorTo and anchorTo.menuList then
					ToggleDropDownMenu(level, getMenuValue(level), nil, nil, nil, nil, anchorTo.menuList, anchorTo)
					return true
				end
			end
		end
		-- show my enhanced popup menu
		function showMenu(menuList, menuFrame, anchor, x, y, autoHideDelay )
			menuFrame.displayMode = "MENU"
			menuFrame.menuValues = menuFrame.menuValues  or {}
			UIDropDownMenu_Initialize(menuFrame, initialize, "MENU", nil, menuList);
			ToggleDropDownMenu(1, nil, menuFrame, anchor, x, y, menuList, nil, autoHideDelay);
		end
	end

	-- here starts the definition of the KiwiFrame menu, misc functions
	local function InitPriceSources(menu)
		for i=#menu,1,-1 do
			if (menu[i].arg1 =='Atr' and not Atr_GetAuctionPrice) or (menu[i].arg1 =='TSM' and not TSMAPI_FOUR) then
				table.remove(menu,i)
			end
		end
		menu.init = nil -- means do not call the function anymore
	end
	local function SetBackground()
		texture:SetColorTexture( unpack(config.backColor or COLOR_TRANSPARENT) )
	end
	local function SetWidth(info)
		config.frameWidth = info.value~=0 and math.max( (config.frameWidth or addon:GetWidth()) + info.value, 50) or nil
		LayoutFrame()
	end
	local function SetFontSize(info)
		config.fontsize = info.value~=0 and math.max( (config.fontsize or 14) + info.value, 5) or 14
		LayoutFrame()
	end
	local function AnchorChecked(info)
		return info.value == config.framePos.anchor
	end
	local function SetAnchor(info)
		config.framePos.anchor = info.value
		SavePosition()
		RestorePosition()
	end
	local function MoneyFmtChecked(info)
		return info.value == (config.moneyFmt or '')
	end
	local function SetMoneyFmt(info)
		config.moneyFmt = info.value~='' and info.value or nil
		RefreshText()
	end
	local function DisplayChecked(info)
		return not disabled[info.value]
	end
	local function SetDisplay(info)
		disabled[info.value] = (not disabled[info.value]) or nil
		PrepareText(); LayoutFrame(); RefreshText()
	end

	-- submenu: quality sources
	local menuQualitySources
	do
		local function checked(info)
			return config.priceByQuality[getMenuValue(info)][info.value]
		end
		local function set(info)
			local sources = config.priceByQuality[getMenuValue(info)]
			sources[info.value] = (not sources[info.value]) or nil
		end
		menuQualitySources = {
			{ text = 'Vendor Price',              value = 'vendor',                     isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = 'Auctionator: Market Value', value = 'Atr:DBMarket', arg1 = 'Atr', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = 'Auctionator: Disenchant',   value = 'Atr:Destroy' , arg1 = 'Atr', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = 'TSM4: Market Value',        value = 'DBMarket',     arg1 = 'TSM', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = 'TSM4: Min Buyout',          value = 'DBMinBuyout',  arg1 = 'TSM', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = 'TSM4: Disenchant',          value = 'Destroy',      arg1 = 'TSM', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			init = InitPriceSources
		}
	end

	-- submenus: item sources, price sources
	local menuPriceItems, menuItemSources
	do
		local function deleteItem(itemLink, confirm)
			if not confirm then
				config.priceByItem[itemLink] = nil
				wipeMenu(menuPriceItems)
				AdjustLootedItemMoneyStats(itemLink)
				return
			end
			C_Timer.After(.1,function()
				addon:ConfirmDialog( format("%s\nThis item has no defined price. Do you want to delete this item?",itemLink), function() deleteItem(itemLink) end)
			end)
		end
		local function setItemPriceSource(info, itemLink, source, value)
			local sources = config.priceByItem[itemLink]
			if value then
				if not sources then
					sources = {}; config.priceByItem[itemLink] = sources
					wipeMenu(menuPriceItems)
				end
				sources[source] = value
			elseif sources then
				sources[source] = nil
				if not next(sources) then
					deleteItem(itemLink, info.arg2 )
				end
			end
			AdjustLootedItemMoneyStats(itemLink)
		end
		local function getItemPriceSource(itemLink, source)
			local sources  = config.priceByItem[itemLink]
			return sources and sources[source]
		end
		local function checked(info)
			return getItemPriceSource(getMenuValue(info), info.value)
		end
		local function set(info)
			info.arg2 = getMenuValue(getMenuLevel(info)-1)=='specific'
			local itemLink, empty = getMenuValue(info)
			if info.value=='user' then
				local price    = FmtMoneyPlain( getItemPriceSource(itemLink,'user') ) or ''
				addon:EditDialog('|cFF7FFF72KiwiFarm|r\n Set a custom price for:\n' .. itemLink, price, function(v)
					setItemPriceSource(info, itemLink, 'user', String2Copper(v))
				end)
			else
				setItemPriceSource(info, itemLink, info.value , not getItemPriceSource(itemLink, info.value))
			end
		end
		local function getText(info, level)
			local price = getItemPriceSource(getMenuValue(level),'user')
			return format( 'Price: %s', price and FmtMoneyShort(price) or 'Not Defined')
		end
		-- submenu: item price sources
		menuItemSources = {
			{ text = getText,	  				  value = 'user',         				isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = 'Vendor Price',              value = 'vendor',                     isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = 'Auctionator: Market Value', value = 'Atr:DBMarket', arg1 = 'Atr', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = 'Auctionator: Disenchant',   value = 'Atr:Destroy' , arg1 = 'Atr', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = 'TSM4: Market Value',        value = 'DBMarket',     arg1 = 'TSM', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = 'TSM4: Min Buyout',          value = 'DBMinBuyout',  arg1 = 'TSM', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = 'TSM4: Disenchant',          value = 'Destroy',      arg1 = 'TSM', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			init = InitPriceSources,
		}
		-- submenu: individual items prices
		menuPriceItems = { init = function(menu)
			if not menu[1] then
				for itemLink,sources in pairs(config.priceByItem) do
					local name = strmatch(itemLink, '%|h%[(.+)%]%|h')
					tinsert( menu, { text = itemLink, value = itemLink, arg1 = name, notCheckable = true, hasArrow = true, menuList = menuItemSources } )
				end
				splitMenu(menu, 'arg1')
			end
		end	}
	end

	-- submenu: looted items
	local menuLootedItems
	do
		local function getText(info)
			local data = config.lootedItems[info.value]
			return data and format("%sx%d %s", info.value, data.quantity, FmtMoneyShort(data.money)) or info.value
		end
		menuLootedItems = { init = function(menu)
			if timeLootedItems>(menu.time or -1) then
				wipeMenu(menu)
				for itemLink, data in pairs(config.lootedItems) do
					local name = strmatch(itemLink, '%|h%[(.+)%]%|h')
					tinsert( menu, { text = getText, value = itemLink, arg1 = name, notCheckable = true, hasArrow = true, menuList = menuItemSources } )
				end
				if not menu[1] then
					menu[1] = { text = "None", notCheckable = true }
				end
				splitMenu(menu, 'arg1')
				menu.time = timeLootedItems
			end
		end }
	end

	-- submenu: zones
	local menuZones
	do
		local function ZoneAdd()
			local zone = GetZoneText()
			config.zones = config.zones or {}
			config.zones[zone] = true
			addon:ZONE_CHANGED_NEW_AREA()
			wipeMenu(menuZones)
		end
		local function ZoneDel(info)
			config.zones[info.value] = nil
			if not next(config.zones) then config.zones = nil end
			addon:ZONE_CHANGED_NEW_AREA()
			wipeMenu(menuZones)
		end
		menuZones = { init = function(menu)
			if not menu[1] then
				for zone in pairs(config.zones or {}) do
					menu[#menu+1] = { text = '(-)'..zone, value = zone, notCheckable = true, func = ZoneDel }
				end
				menu[#menu+1] = { text = '(+)Add Current Zone', notCheckable = true, func = ZoneAdd }
			end
		end	}
	end

	-- submenu: resets
	local menuResets = { init = function(menu)
		local item = { text = 'None', notCheckable = true }
		for i=1,5 do
			if resets[i] then
				item = menu[i] or { notCheckable = true }
				item.text = date("%H:%M:%S",resets[i])
			end
			menu[i], item = item, nil
		end
	end	}

	-- submenu: gold earned by item quality
	local menuGoldQuality = { init = function(menu)
		for i=1,5 do
			menu[i] = menu[i] or { notCheckable = true }
			menu[i].text = format( "%s: %s (%d)", FmtQuality(i-1), FmtMoney(config.moneyByQuality[i-1] or 0), config.countByQuality[i-1] or 0)
		end
	end }

	-- submenu: gold earned by day
	local menuGoldDaily = {	init = function(menu)
		local tim, pre, key, money = time()
		for i=1,7 do
			menu[i] = menu[i] or { notCheckable = true }
			key, pre = date("%Y/%m/%d", tim), pre and date("%m/%d", tim) or 'Today'
			money = config.moneyDaily[key] or 0
			menu[i].text = format('%s: %s', pre, money>0 and FmtMoney(money) or '-' )
			tim = tim - 86400
		end
	end	}

	-- submenu: fonts
	local menuFonts
	do
		local function set(info)
			config.fontname = info.value
			LayoutFrame()
			refreshMenu()
		end
		local function checked(info)
			return info.value == (config.fontname or FONTS.Arial)
		end
		menuFonts  = { init = function(menu)
			local media = LibStub("LibSharedMedia-3.0", true)
			for name, key in pairs(media and media:HashTable('font') or FONTS) do
				tinsert( menu, { text = name, value = key, keepShownOnClick = 1, func = set, checked = checked } )
			end
			splitMenu(menu)
			menu.init = nil -- do not call this init function anymore
		end }
	end

	-- submenu: sounds
	local menuSounds
	do
		-- groupKey = qualityID | 'price'
		local function set(info)
			local sound, groupKey = info.value, getMenuValue(info)
			notify.sound[groupKey] = sound
			PlaySoundFile(sound,"master")
			refreshMenu()
		end
		local function checked(info)
			local sound, groupKey = info.value, getMenuValue(info)
			return notify.sound[groupKey] == sound
		end
		menuSounds = { init = function(menu)
			local blacklist = { ['None']=true, ['BugSack: Fatality']=true }
			local media = LibStub("LibSharedMedia-3.0", true)
			if media then
				for name,fileID in pairs(SOUNDS) do
					media:Register("sound", name, fileID)
				end
			end
			for name, key in pairs(media and media:HashTable('sound') or SOUNDS) do
				if not blacklist[name] then
					tinsert( menu, { text = name, value = key, arg1=strlower(name), func = set, checked = checked, keepShownOnClick = 1 } )
				end
			end
			splitMenu(menu, 'arg1', 'text')
			menu.init = nil -- do not call this init function anymore
		end }
	end

	-- submenu: notify
	local menuNotify
	do
		-- info.value = qualityID | 'price' ; info.arg1 = 'chat'|'combat'|'crit'|'sound'
		local function initText(info, level)
			local groupKey = info.value
			if type(groupKey) ~= 'number' then -- special cases ('price' and 'money' groups notifications require a minimum price/gold amount)
				local price = notify[groupKey] and notify[groupKey][info.arg1]
				return price and format("%s (+%s)", info.arg2, FmtMoneyShort(price)) or format("%s (click to set price)", info.arg2)
			end
			return info.arg2
		end
		local function checked(info)
			local groupKey, channelKey = info.value, info.arg1
			return notify[groupKey] and notify[groupKey][channelKey]~=nil
		end
		local function set(info,value)
			local groupKey, channelKey = info.value, info.arg1
			notify[groupKey] = notify[groupKey] or {}
			notify[groupKey][channelKey] = value or nil
			if not next(notify[groupKey]) then notify[groupKey] = nil end
			if channelKey=='sound' then -- special case for sounds
				notify.sound[groupKey] = nil
				refreshMenu(getMenuLevel(info), true)
			end
		end
		local function setNotify(info)
			if type(info.value) ~= 'number' then -- 'price' & 'money' groups
				local price = notify[info.value] and notify[info.value][info.arg1]
				addon:EditDialog('|cFF7FFF72KiwiFarm|r\nSet the minimum gold amount to display a notification. You can leave the field blank to remove the minimum gold.', FmtMoneyPlain(price), function(v)
					set(info, String2Copper(v) )
					refreshMenu(info)
				end)
			else -- quality groups (0-5)
				set(info, not checked(info) and 0)
			end
		end
		menuNotify = {
			{ text = initText, useParentValue = true, arg1 = 'chat',   arg2 = 'Chat Text',   		    isNotRadio = true, keepShownOnClick = 1, checked = checked, func = setNotify },
			{ text = initText, useParentValue = true, arg1 = 'combat', arg2 = 'CombatText: Scroll',     isNotRadio = true, keepShownOnClick = 1, checked = checked, func = setNotify },
			{ text = initText, useParentValue = true, arg1 = 'crit',   arg2 = 'CombatText: Crit',       isNotRadio = true, keepShownOnClick = 1, checked = checked, func = setNotify },
			{ text = initText, useParentValue = true, arg1 = 'msbt',   arg2 = 'MSBT: Notification', 	isNotRadio = true, keepShownOnClick = 1, checked = checked, func = setNotify },
			{ text = initText, useParentValue = true, arg1 = 'sound',  arg2 = 'Sound',       		    isNotRadio = true, keepShownOnClick = 1, checked = checked, func = setNotify },
			init = function(menu, level)
				local groupKey = getMenuValue(level)
				local value = notify[groupKey] and notify[groupKey].sound
				menu[#menu].hasArrow = value and true or nil
				menu[#menu].menuList = value and menuSounds or nil
			end,
		}
	end

	-- menu: main
	local menuMain = {
		{ text = 'Kiwi Farm [/kfarm]', notCheckable = true, isTitle = true },
		{ text = 'Session Start',      notCheckable = true, func = SessionStart },
		{ text = 'Session Stop',       notCheckable = true, func = SessionStop  },
		{ text = 'Session Clear',      notCheckable = true, func = SessionReset },
		{ text = 'Reset Instances',    notCheckable = true, func = ResetInstances },
		{ text = 'Statistics',         notCheckable = true, isTitle = true },
		{ text = 'Looted Items',       notCheckable = true, hasArrow = true, menuList = menuLootedItems },
		{ text = 'Gold by Qualiy',     notCheckable = true, hasArrow = true, menuList = menuGoldQuality },
		{ text = 'Gold by Day',        notCheckable = true, hasArrow = true, menuList = menuGoldDaily },
		{ text = 'Resets',             notCheckable = true, hasArrow = true, menuList = menuResets },
		{ text = 'Settings',           notCheckable = true, isTitle = true },
		{ text = 'Prices of Items', notCheckable = true, hasArrow = true, menuList = {
			{ text = FmtQuality(0), value = 0, notCheckable= true, hasArrow = true, menuList = menuQualitySources },
			{ text = FmtQuality(1), value = 1, notCheckable= true, hasArrow = true, menuList = menuQualitySources },
			{ text = FmtQuality(2), value = 2, notCheckable= true, hasArrow = true, menuList = menuQualitySources },
			{ text = FmtQuality(3), value = 3, notCheckable= true, hasArrow = true, menuList = menuQualitySources },
			{ text = FmtQuality(4), value = 4, notCheckable= true, hasArrow = true, menuList = menuQualitySources },
			{ text = FmtQuality(5), value = 5, notCheckable= true, hasArrow = true, menuList = menuQualitySources },
			{ text = 'Specific Items', notCheckable= true, hasArrow = true, value = 'specific' ,menuList = menuPriceItems },
			{ text = 'Ignore enchanting mats', isNotRadio = true, keepShownOnClick = 1, checked = function() return config.ignoreEnchantingMats; end, func = function() config.ignoreEnchantingMats = not config.ignoreEnchantingMats or nil; end },
		} },
		{ text = 'Notifications', notCheckable = true, hasArrow = true, menuList = {
			{ text = FmtQuality(0),  value = 0,       notCheckable = true, hasArrow = true, menuList = menuNotify },
			{ text = FmtQuality(1),  value = 1,       notCheckable = true, hasArrow = true, menuList = menuNotify },
			{ text = FmtQuality(2),  value = 2,       notCheckable = true, hasArrow = true, menuList = menuNotify },
			{ text = FmtQuality(3),  value = 3,       notCheckable = true, hasArrow = true, menuList = menuNotify },
			{ text = FmtQuality(4),  value = 4,       notCheckable = true, hasArrow = true, menuList = menuNotify },
			{ text = FmtQuality(5),  value = 5,       notCheckable = true, hasArrow = true, menuList = menuNotify },
			{ text = 'All Items looted', value = 'price', notCheckable = true, hasArrow = true, menuList = menuNotify },
			{ text = 'Money looted', value = 'money', notCheckable = true, hasArrow = true, menuList = menuNotify },
		} },
		{ text = 'Farming Zones', notCheckable= true, hasArrow = true, menuList = menuZones },
		{ text = 'Appearance', notCheckable= true, hasArrow = true, menuList = {
			{ text = 'Display Info', notCheckable= true, hasArrow = true, menuList = {
				{ text = 'Lock&Resets',      value = 'reset',   isNotRadio = true, keepShownOnClick = 1, checked = DisplayChecked, func = SetDisplay },
				{ text = 'Mobs&Items Count', value = 'count',   isNotRadio = true, keepShownOnClick = 1, checked = DisplayChecked, func = SetDisplay },
				{ text = 'Gold by Quality',  value = 'quality', isNotRadio = true, keepShownOnClick = 1, checked = DisplayChecked, func = SetDisplay },
			} },
			{ text = 'Money Format', notCheckable = true, hasArrow = true, menuList = {
				{ text = '999|cffffd70ag|r 99|cffc7c7cfs|r 99|cffeda55fc|r', value = '', 							    checked = MoneyFmtChecked, func = SetMoneyFmt },
				{ text = '999|cffffd70ag|r 99|cffc7c7cfs|r', 				 value = '%d|cffffd70ag|r %d|cffc7c7cfs|r', checked = MoneyFmtChecked, func = SetMoneyFmt },
				{ text = '999|cffffd70ag|r', 								 value = '%d|cffffd70ag|r', 				checked = MoneyFmtChecked, func = SetMoneyFmt },
			} },
			{ text = 'Frame Anchor', notCheckable= true, hasArrow = true, menuList = {
				{ text = 'Top Left',     value = 'TOPLEFT',     checked = AnchorChecked, func = SetAnchor },
				{ text = 'Top Right',    value = 'TOPRIGHT',    checked = AnchorChecked, func = SetAnchor },
				{ text = 'Bottom Left',  value = 'BOTTOMLEFT',  checked = AnchorChecked, func = SetAnchor },
				{ text = 'Bottom Right', value = 'BOTTOMRIGHT', checked = AnchorChecked, func = SetAnchor },
				{ text = 'Left',   		 value = 'LEFT',   		checked = AnchorChecked, func = SetAnchor },
				{ text = 'Right',  		 value = 'RIGHT',  		checked = AnchorChecked, func = SetAnchor },
				{ text = 'Top',    		 value = 'TOP',    		checked = AnchorChecked, func = SetAnchor },
				{ text = 'Bottom', 		 value = 'BOTTOM', 		checked = AnchorChecked, func = SetAnchor },
				{ text = 'Center', 		 value = 'CENTER', 		checked = AnchorChecked, func = SetAnchor },
			} },
			{ text = 'Frame Width', notCheckable= true, hasArrow = true, menuList = {
				{ text = 'Increase(+)',   value =  1,  notCheckable= true, keepShownOnClick=1, func = SetWidth },
				{ text = 'Decrease(-)',   value = -1,  notCheckable= true, keepShownOnClick=1, func = SetWidth },
				{ text = 'Default',       value =  0,  notCheckable= true, keepShownOnClick=1, func = SetWidth },
			} },
			{ text = 'Text Font', notCheckable= true, hasArrow = true, menuList = menuFonts },
			{ text = 'Text Size', notCheckable= true, hasArrow = true, menuList = {
				{ text = 'Increase(+)',  value =  1,  notCheckable= true, keepShownOnClick=1, func = SetFontSize },
				{ text = 'Decrease(-)',  value = -1,  notCheckable= true, keepShownOnClick=1, func = SetFontSize },
				{ text = 'Default (14)', value =  0,  notCheckable= true, keepShownOnClick=1, func = SetFontSize },
			} },
			{ text ='Background color ', notCheckable = true, hasColorSwatch = true, hasOpacity = true, get = function() return unpack(config.backColor) end, set = function(info, ...) config.backColor = {...}; SetBackground(); end },
			{ text = 'Hide Window', notCheckable = true, func = function() addon:Hide() end },
		} },
	}

	function addon:ShowMenu()
		showMenu(menuMain, menuFrame, "cursor", 0 , 0)
	end
end
