-------------------------------------------------------------------------------
-- Upvalued Lua globals.
-------------------------------------------------------------------------------
local _G = _G
local string = _G.string
local pairs = _G.pairs
local ipairs = _G.ipairs
local table = _G.table
local tonumber = _G.tonumber
local tostring = _G.tostring
local pcall = _G.pcall
local issecretvalue = _G.issecretvalue

-------------------------------------------------------------------------------
-- Retail 12.0 Secret-Value & Cross-Client Safety Helpers
-------------------------------------------------------------------------------
local function SafeStr(val, fallback)
	if val == nil then return fallback or "" end
	if issecretvalue and issecretvalue(val) then return fallback or "" end
	return tostring(val)
end

local function SafeNum(val, fallback)
	if val == nil then return fallback or 0 end
	if issecretvalue and issecretvalue(val) then return fallback or 0 end
	return tonumber(val) or fallback or 0
end

local function SafeBool(val)
	if val == nil then return false end
	if issecretvalue and issecretvalue(val) then return false end
	return val and true or false
end

-------------------------------------------------------------------------------
-- Cross-Expansion Friends / Battle.net / Guild Polyfills
-------------------------------------------------------------------------------
local function RequestShowFriends()
	if _G.C_FriendList and _G.C_FriendList.ShowFriends then
		pcall(_G.C_FriendList.ShowFriends)
	elseif _G.ShowFriends then
		pcall(_G.ShowFriends)
	end
end

local function GetWowFriendCounts()
	if _G.C_FriendList and _G.C_FriendList.GetNumFriends then
		local total = SafeNum(_G.C_FriendList.GetNumFriends(), 0)
		local online = _G.C_FriendList.GetNumOnlineFriends and SafeNum(_G.C_FriendList.GetNumOnlineFriends(), 0) or 0
		return total, online
	elseif _G.GetNumFriends then
		local total, online = _G.GetNumFriends()
		return SafeNum(total, 0), SafeNum(online, 0)
	end
	return 0, 0
end

local function GetWowFriendInfo(index)
	if _G.C_FriendList and _G.C_FriendList.GetFriendInfoByIndex then
		local info = _G.C_FriendList.GetFriendInfoByIndex(index)
		if info then
			local status = ""
			if SafeBool(info.afk) then
				status = _G.CHAT_FLAG_AFK or "<AFK>"
			elseif SafeBool(info.dnd) then
				status = _G.CHAT_FLAG_DND or "<DND>"
			end
			return SafeStr(info.name, nil),
				SafeNum(info.level, 0),
				SafeStr(info.className, ""),
				SafeStr(info.area, ""),
				SafeBool(info.connected),
				status,
				SafeStr(info.notes, "")
		end
		return nil
	elseif _G.GetFriendInfo then
		local name, level, class, area, connected, status, note = _G.GetFriendInfo(index)
		return SafeStr(name, nil), SafeNum(level, 0), SafeStr(class, ""), SafeStr(area, ""), SafeBool(connected), SafeStr(status, ""), SafeStr(note, "")
	end
	return nil
end

local function GetBNFriendCounts()
	if _G.BNGetNumFriends then
		local total, online = _G.BNGetNumFriends()
		return SafeNum(total, 0), SafeNum(online, 0)
	end
	return 0, 0
end

local function RequestGuildRoster()
	if _G.C_GuildInfo and _G.C_GuildInfo.GuildRoster then
		pcall(_G.C_GuildInfo.GuildRoster)
	elseif _G.GuildRoster then
		pcall(_G.GuildRoster)
	end
end

local function SafeGetGuildMOTD()
	if _G.C_GuildInfo and _G.C_GuildInfo.GetMOTD then
		local ok, motd = pcall(_G.C_GuildInfo.GetMOTD)
		if ok and motd then return SafeStr(motd, "") end
	end
	if _G.GetGuildRosterMOTD then
		local ok, motd = pcall(_G.GetGuildRosterMOTD)
		if ok and motd then return SafeStr(motd, "") end
	end
	return ""
end

local function SafeInviteUnit(name)
	if not name or name == "" then return end
	if _G.C_PartyInfo and _G.C_PartyInfo.InviteUnit then
		pcall(_G.C_PartyInfo.InviteUnit, name)
	elseif _G.InviteUnit then
		pcall(_G.InviteUnit, name)
	end
end

local function SafeToggleGuildFrame()
	if _G.ToggleGuildFrame then
		pcall(_G.ToggleGuildFrame, 1)
	elseif _G.ToggleCommunitiesFrame then
		pcall(_G.ToggleCommunitiesFrame)
	end
end

-------------------------------------------------------------------------------
-- AddOn namespace.
-------------------------------------------------------------------------------
local L = LibStub("AceLocale-3.0"):GetLocale("GGSocialState", true)
local LibQTip = LibStub("LibQTip-1.0")
local LDBIcon = LibStub("LibDBIcon-1.0", true)
local frame = CreateFrame("Frame")

local tooltip
local LDB_ANCHOR

local LDB = LibStub("LibDataBroker-1.1"):NewDataObject("GGSocialState", {
	type  = "data source",
	icon  = "Interface\\Icons\\INV_Drink_08",
	label = "GGSocialState",
	text  = "GGSocialState",
})

local update_Broker

-------------------------------------------------------------------------------
-- Font definitions.
-------------------------------------------------------------------------------
local ssTitleFont = CreateFont("ssTitleFont")
ssTitleFont:SetTextColor(1, 0.823529, 0)
ssTitleFont:SetFont(GameTooltipText:GetFont(), 14, "")

local ssHeaderFont = CreateFont("ssHeaderFont")
ssHeaderFont:SetTextColor(1, 0.823529, 0)
ssHeaderFont:SetFont(GameTooltipHeaderText:GetFont(), 12, "")

local ssRegFont = CreateFont("ssRegFont")
ssRegFont:SetTextColor(1, 0.823529, 0)
ssRegFont:SetFont(GameTooltipText:GetFont(), 12, "")

local list_sort = {
	TOONNAME = function(a, b)
		return (a["TOONNAME"] or "") < (b["TOONNAME"] or "")
	end,
	LEVEL = function(a, b)
		local la, lb = tonumber(a["LEVEL"]) or 0, tonumber(b["LEVEL"]) or 0
		if la < lb then
			return true
		elseif la > lb then
			return false
		else
			return (a["TOONNAME"] or "") < (b["TOONNAME"] or "")
		end
	end,
	RANKINDEX = function(a, b)
		local ra, rb = tonumber(a["RANKINDEX"]) or 0, tonumber(b["RANKINDEX"]) or 0
		if ra > rb then
			return true
		elseif ra < rb then
			return false
		else
			return (a["TOONNAME"] or "") < (b["TOONNAME"] or "")
		end
	end,
	ZONENAME = function(a, b)
		local za, zb = a["ZONENAME"] or "", b["ZONENAME"] or ""
		if za < zb then
			return true
		elseif za > zb then
			return false
		else
			return (a["TOONNAME"] or "") < (b["TOONNAME"] or "")
		end
	end,
	REALMNAME = function(a, b)
		local ra, rb = a["REALMNAME"] or "", b["REALMNAME"] or ""
		if ra < rb then
			return true
		elseif ra > rb then
			return false
		else
			return (a["ZONENAME"] or "") < (b["ZONENAME"] or "")
		end
	end,
	revTOONNAME = function(a, b)
		return (a["TOONNAME"] or "") > (b["TOONNAME"] or "")
	end,
	revLEVEL = function(a, b)
		local la, lb = tonumber(a["LEVEL"]) or 0, tonumber(b["LEVEL"]) or 0
		if la > lb then
			return true
		elseif la < lb then
			return false
		else
			return (a["TOONNAME"] or "") < (b["TOONNAME"] or "")
		end
	end,
	revRANKINDEX = function(a, b)
		local ra, rb = tonumber(a["RANKINDEX"]) or 0, tonumber(b["RANKINDEX"]) or 0
		if ra < rb then
			return true
		elseif ra > rb then
			return false
		else
			return (a["TOONNAME"] or "") < (b["TOONNAME"] or "")
		end
	end,
	revZONENAME = function(a, b)
		local za, zb = a["ZONENAME"] or "", b["ZONENAME"] or ""
		if za > zb then
			return true
		elseif za < zb then
			return false
		else
			return (a["TOONNAME"] or "") < (b["TOONNAME"] or "")
		end
	end,
	revREALMNAME = function(a, b)
		local ra, rb = a["REALMNAME"] or "", b["REALMNAME"] or ""
		if ra > rb then
			return true
		elseif ra < rb then
			return false
		else
			return (a["ZONENAME"] or "") < (b["ZONENAME"] or "")
		end
	end,
}

-------------------------------------------------------------------------------
-- Ace config table
-------------------------------------------------------------------------------
local options = {
	name = L["GGSocialState"],
	type = "group",
	args = {
		confdesc = {
			order = 1,
			type = "description",
			name = L["LDB plugin that shows friends and guild list."],
			cmdHidden = true,
		},
		displayheader = {
			order = 2,
			type = "header",
			name = L["Tooltip Options"],
		},
		hide_guildname = {
			type = "toggle", width = "normal",
			name = L["Hide Guild name"],
			desc = L["Show or hide the guild name."],
			order = 3,
			get = function() return GGSocialStateDB.hide_guildname end,
			set = function(_, v) GGSocialStateDB.hide_guildname = v end,
		},
		hide_hintline = {
			type = "toggle", width = "normal",
			name = L["Hide the Hint line"],
			desc = L["Show or hide the hint line under tooltip."],
			order = 4,
			get = function() return GGSocialStateDB.hide_hintline end,
			set = function(_, v) GGSocialStateDB.hide_hintline = v end,
		},
		hide_motd = {
			type = "toggle", width = "normal",
			name = L["Hide the MotD"],
			desc = L["Hide the guild MotD under the tooltip."],
			order = 5,
			get = function() return GGSocialStateDB.hide_gmotd end,
			set = function(_, v) GGSocialStateDB.hide_gmotd = v end,
		},
		expand_realID = {
			order = 6,
			type = "toggle", width = "normal",
			name = L["RealID 2 lines"],
			desc = L["Expand RealID to 2 lines in the tooltip for extended info."],
			get = function() return GGSocialStateDB.expand_realID end,
			set = function(_, v) GGSocialStateDB.expand_realID = v end,
		},
		tooltip_autohide = {
			order = 7,
			type = "input", width = "half",
			name = L["Autohide Delay:"],
			desc = L["The tooltip will hide when not hovered over for this (default: 0.25)"],
			get = function() return GGSocialStateDB.tooltip_autohide end,
			set = function(_, v) GGSocialStateDB.tooltip_autohide = v end,
		},
		displayheader2 = {
			order = 8,
			type = "header",
			name = L["LDB Display Options"],
		},
		hide_ldb_labels = {
			order = 9,
			type = "toggle", width = "double",
			name = L["Hide Friends/Guild Labels"],
			desc = L["Hide the Friends and Guild labels from the LDB"],
			get = function() return GGSocialStateDB.hide_LDB_labels end,
			set = function(_, v) GGSocialStateDB.hide_LDB_labels = v update_Broker() end,
		},
		hide_ldb_totals = {
			order = 10,
			type = "toggle", width = "normal",
			name = L["Hide Totals"],
			desc = L["Hide the Totals field from the LDB"],
			get = function() return GGSocialStateDB.hide_LDB_totals end,
			set = function(_, v) GGSocialStateDB.hide_LDB_totals = v update_Broker() end,
		},
		split_ldb_friends = {
			order = 11,
			type = "toggle", width = "normal",
			name = L["Split Real ID and Normal Friends"],
			desc = L["Split Real ID and Normal Friends on the LDB"],
			get = function() return GGSocialStateDB.split_LDB_friends end,
			set = function(_, v) GGSocialStateDB.split_LDB_friends = v update_Broker() end,
		},
		hide_minimap = {
			order = 12,
			type = "toggle", width = "normal",
			name = L["Hide Minimap Icon"],
			desc = L["Hide the GGSocialState minimap icon."],
			get = function() return GGSocialStateDB and GGSocialStateDB.minimap and GGSocialStateDB.minimap.hide end,
			set = function(_, v)
				if not GGSocialStateDB.minimap then GGSocialStateDB.minimap = {} end
				GGSocialStateDB.minimap.hide = v
				if LDBIcon then
					if v then LDBIcon:Hide("GGSocialState") else LDBIcon:Show("GGSocialState") end
				end
			end,
		},
	},
}

LibStub("AceConfig-3.0"):RegisterOptionsTable("GGSocialState", options)
LibStub("AceConfigDialog-3.0"):AddToBlizOptions("GGSocialState")

local GetNumSubgroupMembers = _G.GetNumSubgroupMembers or _G.GetNumPartyMembers or function() return 0 end
local GetNumGroupMembers = _G.GetNumGroupMembers or _G.GetNumRaidMembers or function() return 0 end

-------------------------------------------------------------------------------
-- Helper Routines
-------------------------------------------------------------------------------
local GGSocialState_CLASS_COLORS = {}
local GGSocialState_classes_female, GGSocialState_classes_male = {}, {}

if _G.FillLocalizedClassList then
	_G.FillLocalizedClassList(GGSocialState_classes_female, true)
	_G.FillLocalizedClassList(GGSocialState_classes_male, false)
end

local classColorsTable = _G.CUSTOM_CLASS_COLORS or _G.RAID_CLASS_COLORS or {}
for token, localizedName in pairs(GGSocialState_classes_female) do
	local c = classColorsTable[token]
	if c then
		GGSocialState_CLASS_COLORS[localizedName] = string.format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
		GGSocialState_CLASS_COLORS[token] = GGSocialState_CLASS_COLORS[localizedName]
	end
end

for token, localizedName in pairs(GGSocialState_classes_male) do
	local c = classColorsTable[token]
	if c then
		GGSocialState_CLASS_COLORS[localizedName] = string.format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
		GGSocialState_CLASS_COLORS[token] = GGSocialState_CLASS_COLORS[localizedName]
	end
end

-- Find alias in GuildGreet / GuildGreet-Extended
local function GGSocialState_GetGGAlias(toonName)
	if not toonName then return nil end
	local shortName = _G.Ambiguate and _G.Ambiguate(toonName, "guild") or toonName
	if _G.GLDG_DataChar then
		local entry = _G.GLDG_DataChar[toonName] or _G.GLDG_DataChar[shortName]
		if entry and entry.alias ~= nil and entry.alias ~= "" then
			return entry.alias
		end
	end
	if _G.GuildGreetDB and _G.GuildGreetDB.players then
		local entry = _G.GuildGreetDB.players[toonName] or _G.GuildGreetDB.players[shortName]
		if entry and entry.alias and entry.alias ~= "" then
			return entry.alias
		end
	end
	return nil
end

-- Find main in GuildGreet / GuildGreet-Extended
local function GGSocialState_GetGGMain(toonName)
	if not toonName then return nil end
	local shortName = _G.Ambiguate and _G.Ambiguate(toonName, "guild") or toonName
	if _G.GLDG_DataChar then
		local entry = _G.GLDG_DataChar[toonName] or _G.GLDG_DataChar[shortName]
		if entry and entry.alt ~= nil and entry.alt ~= "" then
			local mainEntry = _G.GLDG_DataChar[entry.alt]
			local mainClass = mainEntry and mainEntry.class
			local hex = (mainClass and GGSocialState_CLASS_COLORS[mainClass]) or "B8B8B8"
			local displayMain = _G.Ambiguate and _G.Ambiguate(entry.alt, "guild") or entry.alt
			return string.format("|cff%s%s|r", hex, displayMain)
		end
	end
	if _G.GuildGreetDB and _G.GuildGreetDB.players then
		local entry = _G.GuildGreetDB.players[toonName] or _G.GuildGreetDB.players[shortName]
		if entry and entry.main and entry.main ~= "" and entry.main ~= shortName then
			local mainEntry = _G.GuildGreetDB.players[entry.main]
			local mainClass = mainEntry and mainEntry.class
			local hex = (mainClass and GGSocialState_CLASS_COLORS[mainClass]) or "B8B8B8"
			local displayMain = _G.Ambiguate and _G.Ambiguate(entry.main, "guild") or entry.main
			return string.format("|cff%s%s|r", hex, displayMain)
		end
	end
	return nil
end

-- Display (main / alias) from GuildGreet
local function GGSocialState_GetMainAlt(toonName)
	local main = GGSocialState_GetGGMain(toonName)
	local alias = GGSocialState_GetGGAlias(toonName)
	if main ~= nil and alias ~= nil then
		return "(" .. main .. " / |cffffa0a0" .. alias .. "|r)"
	elseif main ~= nil then
		return "(" .. main .. ")"
	elseif alias ~= nil then
		return "(|cffffa0a0" .. alias .. "|r)"
	end
	return ""
end

local function inGroup(name)
	if not name or name == "" then return false end
	if GetNumSubgroupMembers() > 0 and _G.UnitInParty(name) then
		return true
	elseif GetNumGroupMembers() > 0 and _G.UnitInRaid(name) then
		return true
	end
	return false
end

local function player_name_to_index(name)
	local numFriends = GetWowFriendCounts()
	for i = 1, numFriends do
		local lookupname = GetWowFriendInfo(i)
		if lookupname == name then
			return i
		end
	end
	return nil
end

local function guild_name_to_index(name)
	for i = 1, _G.GetNumGuildMembers() do
		local lookupname = _G.GetGuildRosterInfo(i)
		if lookupname == name then
			return i
		end
	end
	return nil
end

local function ColoredLevel(level)
	local numLevel = tonumber(level)
	if numLevel and numLevel > 0 then
		local color = _G.GetQuestDifficultyColor and _G.GetQuestDifficultyColor(numLevel) or { r = 1, g = 0.82, b = 0 }
		return string.format("|cff%02x%02x%02x%d|r", color.r * 255, color.g * 255, color.b * 255, numLevel)
	end
	return ""
end

-------------------------------------------------------------------------------
-- Battle.net Friend Helper (C_BattleNet + Legacy BN* Fallback)
-------------------------------------------------------------------------------
local CLIENT_LABELS = {
	S2   = "|cff82c5ffStarCraft II|r",
	D3   = "|cff82c5ffDiablo III|r",
	Fen  = "|cff82c5ffDiablo IV|r",
	OSI  = "|cff82c5ffDiablo II: Resurrected|r",
	ANBS = "|cff82c5ffDiablo Immortal|r",
	WTCG = "|cff82c5ffHearthstone|r",
	Hero = "|cff82c5ffHeroes of the Storm|r",
	Pro  = "|cff82c5ffOverwatch 2|r",
	GRY  = "|cff82c5ffWarcraft Rumble|r",
	RTRO = "|cff82c5ffBlizzard Arcade|r",
	App  = "|cff82c5ffBattle.net Desktop|r",
	BSAp = "|cff82c5ffBattle.net Mobile|r",
}

local FACTION_COLOR_HORDE = _G.RED_FONT_COLOR_CODE or "|cffff2020"
local FACTION_COLOR_ALLIANCE = "|cff0070dd"
local GROUP_CHECKMARK = "|TInterface\\Buttons\\UI-CheckBox-Check:0|t"
local AWAY_ICON = "|TInterface\\FriendsFrame\\StatusIcon-Away:18|t"
local BUSY_ICON = "|TInterface\\FriendsFrame\\StatusIcon-DnD:18|t"
local MOBILE_ICON = "|TInterface\\ChatFrame\\UI-ChatIcon-ArmoryChat:18|t"
local MINIMIZE = "|TInterface\\BUTTONS\\UI-PlusButton-Up:0|t"
local BROADCAST_ICON = "|TInterface\\FriendsFrame\\BroadcastIcon:0|t"

local function CollectOnlineBNFriends()
	local realid_table = {}
	local numBNTotal, numBNOnline = GetBNFriendCounts()
	if numBNOnline <= 0 then return realid_table end

	if _G.C_BattleNet and _G.C_BattleNet.GetFriendAccountInfo then
		for i = 1, numBNTotal do
			local accountInfo = _G.C_BattleNet.GetFriendAccountInfo(i)
			if accountInfo then
				local presenceID = SafeNum(accountInfo.bnetAccountID, i)
				local givenName = SafeStr(accountInfo.accountName, "")
				if givenName == "" then
					givenName = SafeStr(accountInfo.battleTag, "Battle.net")
				end
				local isAFK = SafeBool(accountInfo.isAFK)
				local isDND = SafeBool(accountInfo.isDND)
				local broadcast = SafeStr(accountInfo.customMessage, "")
				local note = SafeStr(accountInfo.note, "")
				if note ~= "" then note = "|cffff8800{" .. note .. "}|r" end

				local numGameAccounts = _G.C_BattleNet.GetFriendNumGameAccounts and SafeNum(_G.C_BattleNet.GetFriendNumGameAccounts(i), 0) or 0
				local addedAny = false

				for toonidx = 1, numGameAccounts do
					local ga = _G.C_BattleNet.GetFriendGameAccountInfo(i, toonidx)
					if ga and SafeBool(ga.isOnline) then
						local client = SafeStr(ga.clientProgram, "App")
						local toonName = SafeStr(ga.characterName, "")
						if toonName ~= "" or client ~= "App" then
							if toonName == "" then toonName = givenName end
							local faction = SafeStr(ga.factionName, "")
							local fcolor = FACTION_COLOR_ALLIANCE
							if faction == "Horde" or faction == _G.FACTION_HORDE then
								fcolor = FACTION_COLOR_HORDE
							end
							local status = ""
							if isAFK or SafeBool(ga.isGameAFK) then
								status = AWAY_ICON
							elseif isDND or SafeBool(ga.isGameBusy) then
								status = BUSY_ICON
							end

							local existingIdx = nil
							for idx, p in ipairs(realid_table) do
								if p.PRESENCEID == presenceID then
									existingIdx = idx
									break
								end
							end

							local entry = {
								GIVENNAME = givenName,
								SURNAME = "",
								LEVEL = SafeNum(ga.characterLevel, ""),
								CLASS = SafeStr(ga.className, ""),
								FCOLOR = fcolor,
								STATUS = status,
								BROADCAST_TEXT = broadcast,
								TOONNAME = toonName,
								CLIENT = client,
								ZONENAME = SafeStr(ga.areaName, ""),
								REALMNAME = SafeStr(ga.realmName, ""),
								GAMETEXT = SafeStr(ga.richPresence, ""),
								NOTE = note,
								PRESENCEID = presenceID,
								GAMEACCOUNTID = SafeNum(ga.gameAccountID, 0),
							}

							if existingIdx then
								if client == "WoW" or realid_table[existingIdx].CLIENT == "App" or realid_table[existingIdx].CLIENT == "BSAp" then
									realid_table[existingIdx] = entry
								end
							else
								table.insert(realid_table, entry)
							end
							addedAny = true
						end
					end
				end

				-- Fallback to primary gameAccountInfo if online
				if not addedAny and accountInfo.gameAccountInfo and SafeBool(accountInfo.gameAccountInfo.isOnline) then
					local ga = accountInfo.gameAccountInfo
					local client = SafeStr(ga.clientProgram, "App")
					local toonName = SafeStr(ga.characterName, givenName)
					local faction = SafeStr(ga.factionName, "")
					local fcolor = (faction == "Horde" or faction == _G.FACTION_HORDE) and FACTION_COLOR_HORDE or FACTION_COLOR_ALLIANCE
					local status = isAFK and AWAY_ICON or (isDND and BUSY_ICON or "")
					table.insert(realid_table, {
						GIVENNAME = givenName,
						SURNAME = "",
						LEVEL = SafeNum(ga.characterLevel, ""),
						CLASS = SafeStr(ga.className, ""),
						FCOLOR = fcolor,
						STATUS = status,
						BROADCAST_TEXT = broadcast,
						TOONNAME = toonName,
						CLIENT = client,
						ZONENAME = SafeStr(ga.areaName, ""),
						REALMNAME = SafeStr(ga.realmName, ""),
						GAMETEXT = SafeStr(ga.richPresence, ""),
						NOTE = note,
						PRESENCEID = presenceID,
						GAMEACCOUNTID = SafeNum(ga.gameAccountID, 0),
					})
				end
			end
		end
	elseif _G.BNGetFriendInfo and _G.BNGetNumFriendToons and _G.BNGetFriendToonInfo then
		for i = 1, numBNOnline do
			local presenceID, givenName, surname = _G.BNGetFriendInfo(i)
			for toonidx = 1, _G.BNGetNumFriendToons(i) do
				local _, _, _, _, _, _, _, _, _, isAFK, isDND, broadcast, note = _G.BNGetFriendInfoByID(presenceID)
				local _, toonName, client, realmName, _, faction, _, class, _, zoneName, level, gameText = _G.BNGetFriendToonInfo(i, toonidx)
				if toonName then
					local fcolor = (faction == "Horde") and FACTION_COLOR_HORDE or FACTION_COLOR_ALLIANCE
					local status = isAFK and AWAY_ICON or (isDND and BUSY_ICON or "")
					if note and note ~= "" then note = "|cffff8800{" .. note .. "}|r" end
					table.insert(realid_table, {
						GIVENNAME = givenName or "",
						SURNAME = surname or "",
						LEVEL = level or "",
						CLASS = class or "",
						FCOLOR = fcolor,
						STATUS = status,
						BROADCAST_TEXT = broadcast or "",
						TOONNAME = toonName,
						CLIENT = client or "WoW",
						ZONENAME = zoneName or "",
						REALMNAME = realmName or "",
						GAMETEXT = gameText or "",
						NOTE = note or "",
						PRESENCEID = presenceID or i,
					})
				end
			end
		end
	end

	return realid_table
end

---------------------
--  Update button  --
---------------------
function update_Broker()
	if not GGSocialStateDB then return end
	RequestShowFriends()

	local displayline = ""
	local NumFriends, online = GetWowFriendCounts()
	local realidTotal, realidOnline = GetBNFriendCounts()

	if not GGSocialStateDB.split_LDB_friends then
		displayline = tostring(online + realidOnline)
		if not GGSocialStateDB.hide_LDB_totals then
			displayline = displayline .. "/" .. tostring(NumFriends + realidTotal)
		end
		if not GGSocialStateDB.hide_LDB_labels then
			displayline = L["Friends"] .. " " .. displayline
		end
	else
		if not GGSocialStateDB.hide_LDB_labels then
			displayline = displayline .. L["RealID"] .. " "
		end
		displayline = displayline .. tostring(realidOnline)
		if not GGSocialStateDB.hide_LDB_totals then
			displayline = displayline .. "/" .. tostring(realidTotal)
		end

		displayline = displayline .. "|r : |cffffff00"
		if not GGSocialStateDB.hide_LDB_labels then
			displayline = displayline .. L["Friends"] .. " "
		end
		displayline = displayline .. tostring(online)
		if not GGSocialStateDB.hide_LDB_totals then
			displayline = displayline .. "/" .. tostring(NumFriends)
		end
	end

	if _G.IsInGuild() then
		RequestGuildRoster()
		local guildTotal, _, guildOnlineAndMobile = _G.GetNumGuildMembers()
		local guildOnline = SafeNum(guildOnlineAndMobile or select(2, _G.GetNumGuildMembers()), 0)
		guildTotal = SafeNum(guildTotal, 0)
		displayline = displayline .. "|r : |cff00ff00"
		if not GGSocialStateDB.hide_LDB_labels then
			displayline = displayline .. L["Guild"] .. " "
		end
		displayline = displayline .. tostring(guildOnline)
		if not GGSocialStateDB.hide_LDB_totals then
			displayline = displayline .. "/" .. tostring(guildTotal)
		end
	end

	LDB.text = "|cff82c5ff" .. displayline .. "|r"
end

----------------------------
--  If names are clicked  --
----------------------------
local function Entry_OnMouseUp(cellFrame, info, button)
	local i_type, toon_name, full_name, presence_id, game_account_id = string.split(":", info)
	presence_id = tonumber(presence_id)
	game_account_id = tonumber(game_account_id)

	if button == "LeftButton" then
		-- Invite to group/raid
		if _G.IsAltKeyDown() then
			if i_type == "realid" then
				if game_account_id and game_account_id > 0 and _G.BNInviteFriend then
					pcall(_G.BNInviteFriend, game_account_id)
					return
				end
				SafeInviteUnit(toon_name)
				return
			else
				SafeInviteUnit(toon_name)
				return
			end
		end

		-- Lookup player via /who
		if _G.IsShiftKeyDown() then
			_G.SetItemRef("player:" .. toon_name, "|Hplayer:" .. toon_name .. "|h[" .. toon_name .. "]|h", "LeftButton")
			return
		end

		-- Edit Player Note
		if _G.IsControlKeyDown() then
			if i_type == "guild" and _G.CanEditPublicNote and _G.CanEditPublicNote() then
				local idx = guild_name_to_index(toon_name)
				if idx and _G.SetGuildRosterSelection then
					_G.SetGuildRosterSelection(idx)
					_G.StaticPopup_Show("SET_GUILDPLAYERNOTE")
				end
				return
			end

			if i_type == "friends" and _G.FriendsFrame then
				_G.FriendsFrame.NotesID = player_name_to_index(toon_name)
				if _G.FriendsFrame.NotesID then
					_G.StaticPopup_Show("SET_FRIENDNOTE", (GetWowFriendInfo(_G.FriendsFrame.NotesID)))
				end
				return
			end

			if i_type == "realid" and _G.FriendsFrame and presence_id then
				_G.FriendsFrame.NotesID = presence_id
				_G.StaticPopup_Show("SET_BNFRIENDNOTE", full_name)
				return
			end
		end

		-- Send a tell to player
		if i_type == "realid" and presence_id then
			if _G.ChatFrame_SendBNetTell then
				pcall(_G.ChatFrame_SendBNetTell, full_name)
			else
				local name = full_name .. ":" .. tostring(presence_id)
				_G.SetItemRef("BNplayer:" .. name, ("|HBNplayer:%1$s|h[%1$s]|h"):format(name), "LeftButton")
			end
		else
			_G.SetItemRef("player:" .. full_name, ("|Hplayer:%1$s|h[%1$s]|h"):format(full_name), "LeftButton")
		end
	elseif button == "RightButton" then
		-- Edit Guild Officer Notes
		if _G.IsControlKeyDown() then
			if i_type == "guild" and _G.CanEditOfficerNote and _G.CanEditOfficerNote() then
				local idx = guild_name_to_index(toon_name)
				if idx and _G.SetGuildRosterSelection then
					_G.SetGuildRosterSelection(idx)
					_G.StaticPopup_Show("SET_GUILDOFFICERNOTE")
				end
			end
		end
	elseif button == "MiddleButton" then
		GGSocialStateDB.expand_realID = not GGSocialStateDB.expand_realID
		LDB.OnEnter(LDB_ANCHOR)
	end
end

local function HideOnMouseUp(cell, section)
	GGSocialStateDB[section] = not GGSocialStateDB[section]
	LDB.OnEnter(LDB_ANCHOR)
end

local function SetGuildSort(cell, sortsection)
	if GGSocialStateDB["GuildSort"] == sortsection then
		GGSocialStateDB["GuildSort"] = "rev" .. sortsection
	else
		GGSocialStateDB["GuildSort"] = sortsection
	end
	LDB.OnEnter(LDB_ANCHOR)
end

local function SetRealIDSort(cell, sortsection)
	if GGSocialStateDB["RealIDSort"] == sortsection then
		GGSocialStateDB["RealIDSort"] = "rev" .. sortsection
	else
		GGSocialStateDB["RealIDSort"] = sortsection
	end
	LDB.OnEnter(LDB_ANCHOR)
end

------------------------------------------
--  Click to open friend / guild panel  --
------------------------------------------
function LDB:OnClick(button)
	if button == "LeftButton" then
		if _G.IsAltKeyDown() then
			SafeToggleGuildFrame()
		else
			if _G.ToggleFriendsFrame then
				pcall(_G.ToggleFriendsFrame, 1)
			end
		end
	elseif button == "RightButton" then
		LibStub("AceConfigDialog-3.0"):Open("GGSocialState")
	end
end

function LDB.OnLeave() end

------------------------
--      Tooltip!      --
------------------------
function LDB.OnEnter(self)
	if not self then return end
	LDB_ANCHOR = self

	if LibQTip:IsAcquired("GGSocialState") then
		tooltip:Clear()
	else
		tooltip = LibQTip:Acquire("GGSocialState", 7, "RIGHT", "CENTER", "LEFT", "LEFT", "CENTER", "CENTER", "RIGHT")
		if _G.ElvUI and not tooltip.isSkinned and tooltip.SetTemplate then
			pcall(tooltip.SetTemplate, tooltip, "Transparent")
		end
		if tooltip.SetHeaderFont then
			tooltip:SetHeaderFont(ssHeaderFont)
		end
		if tooltip.SetFont then
			tooltip:SetFont(ssRegFont)
		end
	end
	tooltip:SetFrameStrata("TOOLTIP")
	tooltip:SetFrameLevel(100)

	local _, numBNOnline = GetBNFriendCounts()
	local totalWowFriends, numFriendsOnline = GetWowFriendCounts()
	local totalFriendsOnline = (numBNOnline or 0) + (numFriendsOnline or 0)
	local totalFriendsCount = (select(1, GetBNFriendCounts()) or 0) + (totalWowFriends or 0)
	local guildOnline = 0
	local guildTotal = 0
	if _G.IsInGuild() then
		local gt, _, go = _G.GetNumGuildMembers()
		guildTotal = SafeNum(gt, 0)
		guildOnline = SafeNum(go or select(2, _G.GetNumGuildMembers()), 0)
	end

	-- Title Banner
	local titleLine = tooltip:AddHeader()
	local titleRight = string.format(
		"   |cff82c5ff%s: %d/%d|r" .. (_G.IsInGuild() and ("   |cff555c68•|r   |cff44ff66%s: %d/%d|r") or ""),
		_G.FRIENDS or L["Friends"], totalFriendsOnline, totalFriendsCount,
		_G.GUILD or L["Guild"], guildOnline, guildTotal
	)
	tooltip:SetCell(
		titleLine,
		1,
		"|TInterface\\Icons\\INV_Drink_08:15:15:0:0:64:64:5:59:5:59|t  |cffffd200GGSocialState|r  |cff00ff96v2.0.0|r" .. titleRight,
		ssTitleFont,
		"LEFT",
		7
	)
	tooltip:SetLineColor(titleLine, 0.12, 0.15, 0.21, 0.92)
	tooltip:AddSeparator(1, 0.79, 0.64, 0.15, 0.85)

	local line
	if (numBNOnline > 0) or (numFriendsOnline > 0) then
		line = tooltip:AddLine()
		local friendsLabel = string.format("|cffffd200%s|r  |cff8892a4(%d/%d)|r", _G.FRIENDS or L["Friends"], totalFriendsOnline, totalFriendsCount)
		if not GGSocialStateDB.hide_friendsection then
			tooltip:SetCell(line, 1, friendsLabel, "LEFT", 7)
		else
			tooltip:SetCell(line, 1, MINIMIZE .. " " .. friendsLabel, "LEFT", 7)
		end
		tooltip:SetLineColor(line, 0.14, 0.17, 0.23, 0.85)
		tooltip:SetCellScript(line, 1, "OnMouseUp", HideOnMouseUp, "hide_friendsection")

		if not GGSocialStateDB.hide_friendsection then
			line = tooltip:AddHeader()
			line = tooltip:SetCell(line, 1, "|cffffd200Lvl|r")
			tooltip:SetCellScript(line, 1, "OnMouseUp", SetRealIDSort, "LEVEL")
			line = tooltip:SetCell(line, 3, "|cffffd200" .. (_G.NAME or "Name") .. "|r")
			tooltip:SetCellScript(line, 3, "OnMouseUp", SetRealIDSort, "TOONNAME")
			line = tooltip:SetCell(line, 4, "|cffffd200" .. (_G.BATTLENET_FRIEND or L["RealID"]) .. "|r")
			tooltip:SetCellScript(line, 4, "OnMouseUp", SetRealIDSort, "REALID")
			line = tooltip:SetCell(line, 5, "|cffffd200" .. (_G.LOCATION_COLON or "Zone") .. "|r")
			tooltip:SetCellScript(line, 5, "OnMouseUp", SetRealIDSort, "ZONENAME")
			line = tooltip:SetCell(line, 6, "|cffffd200" .. (_G.FRIENDS_LIST_REALM or "Realm") .. "|r")
			tooltip:SetCellScript(line, 6, "OnMouseUp", SetRealIDSort, "REALMNAME")
			if not GGSocialStateDB.hide_friend_notes then
				line = tooltip:SetCell(line, 7, "|cffffd200" .. (_G.NOTE_COLON or "Note") .. "|r")
			else
				line = tooltip:SetCell(line, 7, MINIMIZE .. "|cffffd200" .. (_G.NOTE_COLON or "Note") .. "|r")
			end
			tooltip:SetCellScript(line, 7, "OnMouseUp", HideOnMouseUp, "hide_friend_notes")
			tooltip:SetLineColor(line, 0.11, 0.13, 0.18, 0.90)

			tooltip:AddSeparator(1, 0.26, 0.30, 0.38, 0.85)

			local friendRowIdx = 0
			if numBNOnline > 0 then
				local realid_table = CollectOnlineBNFriends()

				local sortKey = GGSocialStateDB["RealIDSort"]
				if sortKey ~= "REALID" and sortKey ~= "revREALID" and list_sort[sortKey] then
					table.sort(realid_table, list_sort[sortKey])
				end

				for _, player in ipairs(realid_table) do
					friendRowIdx = friendRowIdx + 1
					local broadcast_flag = ""
					if not GGSocialStateDB.expand_realID and player["BROADCAST_TEXT"] ~= "" then
						broadcast_flag = " " .. BROADCAST_ICON
					end

					line = tooltip:AddLine()
					line = tooltip:SetCell(line, 1, ColoredLevel(player["LEVEL"]))
					line = tooltip:SetCell(line, 2, player["STATUS"])
					line = tooltip:SetCell(line, 3,
						string.format("|cff%s%s|r", GGSocialState_CLASS_COLORS[player["CLASS"]] or "d0d6e2", player["TOONNAME"]) ..
						(inGroup(player["TOONNAME"]) and GROUP_CHECKMARK or ""))
					line = tooltip:SetCell(line, 4,
						"|cff82c5ff" .. player["GIVENNAME"] .. "|r" .. broadcast_flag)

					if player["CLIENT"] == "WoW" or player["CLIENT"] == _G.BNET_CLIENT_WOW then
						line = tooltip:SetCell(line, 5, player["ZONENAME"])
						line = tooltip:SetCell(line, 6, (player["FCOLOR"] or "|cffffffff") .. (player["REALMNAME"] or "") .. "|r")
					else
						line = tooltip:SetCell(line, 5, player["GAMETEXT"])
						line = tooltip:SetCell(line, 6, CLIENT_LABELS[player["CLIENT"]] or ("|cff82c5ff" .. tostring(player["CLIENT"] or "") .. "|r"))
					end

					if not GGSocialStateDB.hide_friend_notes then
						line = tooltip:SetCell(line, 7, player["NOTE"])
					end
					if friendRowIdx % 2 == 0 then
						tooltip:SetLineColor(line, 0.11, 0.13, 0.17, 0.55)
					end

					local clickPayload = string.format("realid:%s:%s:%d:%d",
						player["TOONNAME"] or "",
						player["GIVENNAME"] or "",
						tonumber(player["PRESENCEID"]) or 0,
						tonumber(player["GAMEACCOUNTID"]) or 0)
					tooltip:SetLineScript(line, "OnMouseUp", Entry_OnMouseUp, clickPayload)

					if GGSocialStateDB.expand_realID and player["BROADCAST_TEXT"] ~= "" then
						line = tooltip:AddLine()
						line = tooltip:SetCell(line, 1, BROADCAST_ICON .. " |cff7b8489" .. player["BROADCAST_TEXT"] .. "|r", "LEFT", 7)
						tooltip:SetLineScript(line, "OnMouseUp", Entry_OnMouseUp, clickPayload)
					end
				end
			end

			if numFriendsOnline > 0 then
				local friend_table = {}
				for i = 1, totalWowFriends do
					local toonName, level, class, zoneName, connected, status, note = GetWowFriendInfo(i)
					if connected and toonName then
						note = (note and note ~= "") and ("|cffff8800{" .. note .. "}|r") or ""
						if status == _G.CHAT_FLAG_AFK then
							status = AWAY_ICON
						elseif status == _G.CHAT_FLAG_DND then
							status = BUSY_ICON
						end
						table.insert(friend_table, {
							TOONNAME = toonName,
							LEVEL = level,
							CLASS = class,
							ZONENAME = zoneName,
							REALMNAME = "",
							STATUS = status,
							NOTE = note,
						})
					end
				end

				local sortKey = GGSocialStateDB["RealIDSort"]
				if sortKey ~= "REALID" and sortKey ~= "revREALID" and list_sort[sortKey] then
					table.sort(friend_table, list_sort[sortKey])
				else
					table.sort(friend_table, list_sort["TOONNAME"])
				end

				for _, player in ipairs(friend_table) do
					friendRowIdx = friendRowIdx + 1
					line = tooltip:AddLine()
					line = tooltip:SetCell(line, 1, ColoredLevel(player["LEVEL"]))
					line = tooltip:SetCell(line, 2, player["STATUS"])
					line = tooltip:SetCell(line, 3,
						string.format("|cff%s%s|r", GGSocialState_CLASS_COLORS[player["CLASS"]] or "ffffff", player["TOONNAME"]) ..
						(inGroup(player["TOONNAME"]) and GROUP_CHECKMARK or ""))
					line = tooltip:SetCell(line, 5, player["ZONENAME"])
					if not GGSocialStateDB.hide_friend_notes then
						line = tooltip:SetCell(line, 7, player["NOTE"])
					end
					if friendRowIdx % 2 == 0 then
						tooltip:SetLineColor(line, 0.11, 0.13, 0.17, 0.55)
					end

					tooltip:SetLineScript(line, "OnMouseUp", Entry_OnMouseUp, string.format("friends:%s:%s", player["TOONNAME"], player["TOONNAME"]))
				end
			end
		end
	end

	------------------------
	--  Begin guild list  --
	------------------------
	if _G.IsInGuild() then
		local guild_table = {}
		if not GGSocialStateDB.hide_gmotd then
			local motdText = SafeGetGuildMOTD()
			if motdText ~= "" then
				tooltip:AddSeparator(1, 0.24, 0.27, 0.35, 0.85)
				line = tooltip:AddLine()
				local motdHeader = "|cffffd200" .. (_G.CHAT_GUILD_MOTD_SEND or "Guild MOTD") .. "|r"
				if not GGSocialStateDB.minimize_gmotd then
					tooltip:SetCell(line, 1, motdHeader .. "  |cff44ff66" .. motdText .. "|r", "LEFT", 7)
				else
					tooltip:SetCell(line, 1, MINIMIZE .. " " .. motdHeader, "LEFT", 7)
				end
				tooltip:SetLineColor(line, 0.10, 0.15, 0.13, 0.70)
				tooltip:SetCellScript(line, 1, "OnMouseUp", HideOnMouseUp, "minimize_gmotd")
			end
		end

		tooltip:AddSeparator(1, 0.24, 0.27, 0.35, 0.85)
		local ssGuildName
		if not GGSocialStateDB.hide_guildname then
			ssGuildName = SafeStr(_G.GetGuildInfo("player"), _G.GUILD or L["Guild"])
		else
			ssGuildName = _G.GUILD or L["Guild"]
		end
		local guildHeaderLabel = string.format("|cffffd200%s|r  |cff8892a4(%d/%d)|r", ssGuildName, guildOnline, guildTotal)

		line = tooltip:AddLine()
		if not GGSocialStateDB.hide_guildsection then
			tooltip:SetCell(line, 1, guildHeaderLabel, "LEFT", 7)
		else
			line = tooltip:SetCell(line, 1, MINIMIZE .. " " .. guildHeaderLabel, "LEFT", 7)
		end
		tooltip:SetLineColor(line, 0.14, 0.17, 0.23, 0.85)
		tooltip:SetCellScript(line, 1, "OnMouseUp", HideOnMouseUp, "hide_guildsection")

		if not GGSocialStateDB.hide_guildsection then
			line = tooltip:AddHeader()
			line = tooltip:SetCell(line, 1, "|cffffd200Lvl|r")
			tooltip:SetCellScript(line, 1, "OnMouseUp", SetGuildSort, "LEVEL")
			line = tooltip:SetCell(line, 3, "|cffffd200" .. (_G.NAME or "Name") .. "|r")
			tooltip:SetCellScript(line, 3, "OnMouseUp", SetGuildSort, "TOONNAME")
			line = tooltip:SetCell(line, 5, "|cffffd200" .. (_G.ZONE or "Zone") .. "|r")
			tooltip:SetCellScript(line, 5, "OnMouseUp", SetGuildSort, "ZONENAME")
			line = tooltip:SetCell(line, 6, "|cffffd200" .. (_G.RANK or "Rank") .. "|r")
			tooltip:SetCellScript(line, 6, "OnMouseUp", SetGuildSort, "RANKINDEX")

			if not GGSocialStateDB.hide_guild_onotes then
				line = tooltip:SetCell(line, 7, "|cffffd200" .. (_G.NOTE_COLON or "Note") .. "|r")
			else
				line = tooltip:SetCell(line, 7, MINIMIZE .. "|cffffd200" .. (_G.NOTE_COLON or "Note") .. "|r")
			end
			tooltip:SetCellScript(line, 7, "OnMouseUp", HideOnMouseUp, "hide_guild_onotes")
			tooltip:SetLineColor(line, 0.11, 0.13, 0.18, 0.90)

			tooltip:AddSeparator(1, 0.26, 0.30, 0.38, 0.85)

			local numGuildTotal = SafeNum(_G.GetNumGuildMembers(), 0)
			for i = 1, numGuildTotal do
				local toonName, rank, rankindex, level, class, zoneName, note, onote, connected, status, classFileName, _, _, isMobile = _G.GetGuildRosterInfo(i)
				toonName = SafeStr(toonName, nil)
				if SafeBool(connected) and toonName then
					note = SafeStr(note, "")
					onote = SafeStr(onote, "")
					if note ~= "" then note = "|cff00ff00[" .. note .. "]|r" end
					if onote ~= "" then onote = "|cff00ffff[" .. onote .. "]|r" end

					status = SafeNum(status, 0)
					local statusIcon = ""
					if status == 1 then
						statusIcon = AWAY_ICON
					elseif status == 2 then
						statusIcon = BUSY_ICON
					end

					zoneName = SafeStr(zoneName, "???")
					if SafeBool(isMobile) then
						statusIcon = MOBILE_ICON
						zoneName = "Remote Chat"
					end

					table.insert(guild_table, {
						TOONNAME = toonName,
						TOONALIAS = GGSocialState_GetMainAlt(toonName),
						RANK = SafeStr(rank, ""),
						RANKINDEX = SafeNum(rankindex, 0),
						LEVEL = SafeNum(level, 0),
						CLASS = SafeStr(classFileName or class, ""),
						ZONENAME = zoneName,
						NOTE = note,
						ONOTE = onote,
						STATUS = statusIcon,
					})
				end
			end

			local guildSortFn = list_sort[GGSocialStateDB["GuildSort"]] or list_sort["RANKINDEX"]
			table.sort(guild_table, guildSortFn)

			for idx, player in ipairs(guild_table) do
				line = tooltip:AddLine()
				line = tooltip:SetCell(line, 1, ColoredLevel(player["LEVEL"]))
				line = tooltip:SetCell(line, 2, player["STATUS"])
				local shortName = _G.Ambiguate and _G.Ambiguate(player["TOONNAME"], "guild") or player["TOONNAME"]
				line = tooltip:SetCell(line, 3,
					string.format("|cff%s%s|r", GGSocialState_CLASS_COLORS[player["CLASS"]] or "ffffff", shortName) ..
					(inGroup(shortName) and GROUP_CHECKMARK or ""))
				line = tooltip:SetCell(line, 4, player["TOONALIAS"] or "")
				line = tooltip:SetCell(line, 5, player["ZONENAME"] or "???")
				line = tooltip:SetCell(line, 6, player["RANK"])
				if not GGSocialStateDB.hide_guild_onotes then
					line = tooltip:SetCell(line, 7, (player["NOTE"] or "") .. (player["ONOTE"] or ""))
				end
				if idx % 2 == 0 then
					tooltip:SetLineColor(line, 0.11, 0.13, 0.17, 0.55)
				end

				tooltip:SetLineScript(line, "OnMouseUp", Entry_OnMouseUp, string.format("guild:%s:%s", player["TOONNAME"], player["TOONNAME"]))
			end
		end
	end

	if not GGSocialStateDB.hide_hintline then
		tooltip:AddSeparator(1, 0.24, 0.27, 0.35, 0.85)
		line = tooltip:AddLine()
		if not GGSocialStateDB.minimize_hintline then
			tooltip:SetCell(line, 1, "|cffffd200" .. L["Hint:"] .. "|r", "LEFT", 7)
		else
			tooltip:SetCell(line, 1, MINIMIZE .. " |cffffd200" .. L["Hint:"] .. "|r", "LEFT", 7)
		end
		tooltip:SetLineColor(line, 0.14, 0.17, 0.23, 0.85)
		tooltip:SetCellScript(line, 1, "OnMouseUp", HideOnMouseUp, "minimize_hintline")

		if not GGSocialStateDB.minimize_hintline then
			line = tooltip:AddLine()
			tooltip:SetCell(line, 1, "|cffffd200" .. L["Click"] .. "|r " .. L["to open the friends panel."], "LEFT", 4)
			tooltip:SetCell(line, 5, "|cffffd200" .. L["Alt-Click"] .. "|r " .. L["to open the guild panel."], "LEFT", 3)

			line = tooltip:AddLine()
			tooltip:SetCell(line, 1, "|cffffd200" .. L["Click"] .. "|r " .. L["a line to whisper a player."], "LEFT", 4)
			tooltip:SetCell(line, 5, "|cffffd200" .. L["Shift-Click"] .. "|r " .. L["a line to lookup a player."], "LEFT", 3)

			line = tooltip:AddLine()
			tooltip:SetCell(line, 1, "|cffffd200" .. L["Ctrl-Click"] .. "|r " .. L["a line to edit a note."], "LEFT", 4)
			tooltip:SetCell(line, 5, "|cffffd200" .. L["Ctrl-RightClick"] .. "|r " .. L["a line to edit an officer note."], "LEFT", 3)

			line = tooltip:AddLine()
			tooltip:SetCell(line, 1, "|cffffd200" .. L["Alt-Click"] .. "|r " .. L["a line to invite."], "LEFT", 4)
			tooltip:SetCell(line, 5, "|cffffd200" .. L["MiddleClick"] .. "|r " .. L["a line to expand RealID."], "LEFT", 3)

			line = tooltip:AddLine()
			tooltip:SetCell(line, 1, "|cffffd200" .. L["Click"] .. "|r " .. L["a Header to hide it or sort it."], "LEFT", 4)
			tooltip:SetCell(line, 5, "|cffffd200" .. L["Right-Click"] .. "|r " .. L["to open configuration."], "LEFT", 3)
		end
	end

	tooltip:SmartAnchorTo(self)
	tooltip:SetAutoHideDelay(tonumber(GGSocialStateDB and GGSocialStateDB.tooltip_autohide) or 0.25, self)
	tooltip:UpdateScrolling()
	tooltip:Show()
end

-------------------------------------------------------------------------------
-- Addon Compartment Callbacks (Retail / Modern Clients)
-------------------------------------------------------------------------------
function _G.GGSocialState_OnAddonCompartmentClick(_, buttonName)
	LDB:OnClick(buttonName or "LeftButton")
end

function _G.GGSocialState_OnAddonCompartmentEnter(_, menuButtonFrame)
	if menuButtonFrame then
		LDB.OnEnter(menuButtonFrame)
	end
end

function _G.GGSocialState_OnAddonCompartmentLeave()
	LDB.OnLeave()
end

-------------------------------------------------------------------------------
-- Event & Timer Handling
-------------------------------------------------------------------------------
frame:SetScript("OnEvent", function(self, event, ...)
	if self[event] then
		return self[event](self, event, ...)
	end
	update_Broker()
end)

local DELAY = 15
local elapsed = DELAY - 5

frame:SetScript("OnUpdate", function(self, el)
	elapsed = elapsed + el
	if elapsed >= DELAY then
		elapsed = 0
		update_Broker()
	end
end)

function frame:PLAYER_LOGIN()
	if not GGSocialStateDB then
		GGSocialStateDB = {}
	end
	if not GGSocialStateDB.minimap then
		GGSocialStateDB.minimap = { hide = false }
	end
	if not GGSocialStateDB.tooltip_autohide then
		GGSocialStateDB.tooltip_autohide = "0.25"
	end
	if not GGSocialStateDB["RealIDSort"] then
		GGSocialStateDB["RealIDSort"] = "REALID"
	end
	if not GGSocialStateDB["GuildSort"] then
		GGSocialStateDB["GuildSort"] = "RANKINDEX"
	end

	if LDBIcon and not LDBIcon:IsRegistered("GGSocialState") then
		LDBIcon:Register("GGSocialState", LDB, GGSocialStateDB.minimap)
	end

	local events = {
		"FRIENDLIST_UPDATE",
		"BN_FRIEND_INFO_CHANGED",
		"BN_FRIEND_ACCOUNT_ONLINE",
		"BN_FRIEND_ACCOUNT_OFFLINE",
		"GUILD_ROSTER_UPDATE",
		"PLAYER_GUILD_UPDATE",
	}
	for _, ev in ipairs(events) do
		pcall(frame.RegisterEvent, frame, ev)
	end

	update_Broker()
end

frame:RegisterEvent("PLAYER_LOGIN")
