-- $Id: unit_noselfpwn.lua 3171 2008-11-06 09:06:29Z det $
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function gadget:GetInfo()
  return {
    name      = "Mod statistics",
    desc      = "Gathers mod statistics",
    author    = "Licho",
    date      = "29.3.2009",
    license   = "GNU GPL, v2 or later",
    layer     = 1,
    enabled   = true  --  loaded by default?
  }
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

if VFS.FileExists("mission.lua") then
  -- stats are meaningless in missions
  return
end

  
if (not gadgetHandler:IsSyncedCode()) then
  return false  --  silent removal
end

local damages = {}     -- damages[attacker][victim] = { damage, emp} 
local unitCounts = {}  -- unitCounts[defID] = { created, destroyed}
local lastPara = {}

local plops = {}

local Echo = Spring.Echo
local spIsGameOver      = Spring.IsGameOver
local spGetUnitHealth = Spring.GetUnitHealth
local spAreTeamsAllied = Spring.AreTeamsAllied
local spGetUnitDefID = Spring.GetUnitDefID;
local encode = Spring.Utilities.json.encode;

local gaiaTeamID = Spring.GetGaiaTeamID()
  
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

-- drones are counted as parent for damage done, ignored for damage received
-- key = drone unitdefname
-- value = string parent unitdefname or true for autoresolve

local _, drones = include "LuaRules/Configs/drone_defs.lua"
drones[UnitDefNames.wolverine_mine.id] = "corgarp"

-- fallback for when attacker is already dead at damage event - attackerDefID == nil
-- probably should be autogenerated but meh
local weaponIDToUnitDefIDRaw = {
	logkoda_napalm_bomblet = "logkoda",
	firewalker_napalm_mortar = "firewalker",
	corhurc2_napalm = "corhurc2",
	corpyro_napalm = "corpyro",
	corpyro_flamethrower = "corpyro",
	dante_napalm_rockets = "dante",
	dante_napalm_rocket_salvo = "dante",
	dante_dante_flamer = "dante",
	armtick_death = "armtick",
	tacnuke_weapon = "tacnuke",
	napalmmissile_weapon = "napalmmissile",
	seismic_seismic_weapon = "seismic",
	empmissile_emp_weapon = "emp",
	wolverine_mine_bomblet = "corgarp",
}
local weaponIDToUnitDefID = {}

for weapon,unit in pairs(weaponIDToUnitDefIDRaw) do
  if WeaponDefNames[weapon] and UnitDefNames[unit] then
    local weaponDefID = WeaponDefNames[weapon].id
    weaponIDToUnitDefID[weaponDefID] = UnitDefNames[unit].id
  end
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Factory Plop

local function AddFactoryPlop(teamID, plopUnitDefID)
	plops[#plops + 1] = {
		teamID = teamID,
		plopUnitName = UnitDefs[plopUnitDefID].name,
	}
end
GG.mod_stats_AddFactoryPlop = AddFactoryPlop
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
function gadget:UnitDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, 
                            weaponID, attackerID, attackerDefID, attackerTeam)
                            
	if unitTeam == gaiaTeamID then
		return
	end
	
	if weaponID and (not attackerDefID) then
		attackerDefID = weaponIDToUnitDefID[weaponID]
	end
	if (attackerDefID == nil or  unitDefID == nil or damage == nil) or (not attackerTeam) or (attackerTeam == unitTeam) or (damage < 0)  or spAreTeamsAllied(attackerTeam, unitTeam) then 
		if (paralyzer) then 
			local hp, maxHp, paraDam = spGetUnitHealth(unitID)	
			local paraHp = maxHp - paraDam
			if paraHp < 0 then paraHp = 0 end
			lastPara[unitID] = paraHp
		end
		return
	end
	
	
	-- treat as different unit as needed
	if drones[unitDefID] then
		return
	end
	
	if drones[attackerDefID] then
		local drone = drones[UnitDefs[attackerDefID].name]
		local adi = attackerDefID
		if(type(drone) == "string") then
			adi = (UnitDefNames[name] and UnitDefNames[name].id)
		else 
			carrier = GG.getCarrierByDrone(attackerID)
			adi = carrier and Spring.GetUnitDefID(carrier)
		end
		attackerDefID = adi or attackerDefID
	end	
	
	local attackerAlias = UnitDefs[attackerDefID].customParams.statsname
	if attackerAlias and UnitDefNames[attackerAlias] then
		attackerDefID = UnitDefNames[attackerAlias].id
	end
	local defenderAlias = UnitDefs[unitDefID].customParams.statsname
	if defenderAlias and UnitDefNames[defenderAlias] then
		unitDefID = UnitDefNames[defenderAlias].id
	end
	
	local hp, maxHp, paraDam, capture, build = spGetUnitHealth(unitID)		
	
	if build >= 1 then 
		local attackerName = UnitDefs[attackerDefID].name
		local tab = damages[attackerName]
		if (tab == nil) then 
			tab = {}
			damages[attackerName] = tab
		end
		local unitName = UnitDefs[unitDefID].name
		local dam = tab[unitName] 
		if (dam == nil) then
			dam = {0,0}
			tab[unitName] = dam
		end

		local h
		if (paralyzer)  then h = lastPara[unitID] or maxHp
		else h = hp + damage end 
	
		if h < 0 then h = 0 end
		if h > maxHp then h = maxHp end
		if (damage > h) then damage = h end

		if (paralyzer) then
			dam[2] = dam[2] + damage 
		else 
			dam[1] = dam[1] + damage  
		end
	end

	local paraHp = maxHp - paraDam
	if paraHp < 0 then paraHp = 0 end	
	lastPara[unitID] = paraHp
end


function gadget:UnitCreated(unitID, unitDefID, unitTeam, builderID)
	lastPara[unitID] = nil
	local unitDefName = UnitDefs[unitDefID].name
	
	local unitAlias = UnitDefs[unitDefID].customParams.statsname
	if unitAlias and UnitDefNames[unitAlias] then
		unitDefName = unitAlias
	end	
	
	if (builderID == nil) then 
		local tab = unitCounts[unitDefName]
		if (tab == nil) then
			tab = {0,0}
			unitCounts[unitDefName] = tab
		end
		tab[1] = tab[1] + 1
	end
end


function gadget:UnitFinished(unitID, unitDefID, unitTeam)
	lastPara[unitID] = nil
	local unitDefName = UnitDefs[unitDefID].name

	local unitAlias = UnitDefs[unitDefID].customParams.statsname
	if unitAlias and UnitDefNames[unitAlias] then
		unitDefName = unitAlias
	end	
	
	local tab = unitCounts[unitDefName]
	if (tab == nil) then
		tab = {0,0}
		unitCounts[unitDefName] = tab
	end
	tab[1] = tab[1] + 1
end


function gadget:UnitDestroyed(unitID, unitDefID, unitTeam)
	lastPara[unitID] = nil	
	local unitDefName = UnitDefs[unitDefID].name

	local unitAlias = UnitDefs[unitDefID].customParams.statsname
	if unitAlias and UnitDefNames[unitAlias] then
		unitDefName = unitAlias
	end	
	
	local tab = unitCounts[unitDefName]
	if (tab == nil) then
		tab = {0,0}
		unitCounts[unitDefName] = tab
	end
	tab[2] = tab[2] + 1
end

function SendData(name, data) 
	Spring.SendCommands("wbynum 255 SPRINGIE_STATS:"..tostring(name).."="..encode(data));
end 

function gadget:GameOver()
	if GG.Chicken then
		Spring.Log(gadget:GetInfo().name, LOG.INFO, "modstats: Chicken game, unit stats disabled")
		return	-- don't report stats in chicken
	end	
	
	SendData("damages",damages);
	SendData("units",unitCounts);
	SendData("facplops",plops);
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
