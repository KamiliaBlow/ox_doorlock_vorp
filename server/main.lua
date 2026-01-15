if not LoadResourceFile(cache.resource, 'web/build/index.html') then
	error(
		'Unable to load UI. Build ox_doorlock or download the latest release.\n	^3https://github.com/overextended/ox_doorlock/releases/latest/download/ox_doorlock.zip^0')
end

if not lib.checkDependency('oxmysql', '2.4.0') then return end
if not lib.checkDependency('ox_lib', '3.14.0') then return end

lib.versionCheck('overextended/ox_doorlock')
require 'server.convert'

local Core = exports.vorp_core:GetCore()

function GetPlayer(playerId)
    local user = Core.getUser(playerId)
    if not user then return nil end
    return user.getUsedCharacter
end

function GetCharacterId(player)
    return player.charIdentifier
end

local utils = require 'server.utils'
local doors = {}

local function encodeData(door)
    local double = door.doors

    return json.encode({
        auto = door.auto,
        autolock = door.autolock,
        coords = door.coords,
        doors = double and {
            {
                coords = double[1].coords,
                heading = double[1].heading,
                model = double[1].model,
                hash = double[1].hash,
            },
            {
                coords = double[2].coords,
                heading = double[2].heading,
                model = double[2].model,
                hash = double[2].hash,
            },
        },
        characters = door.characters,
        groups = door.groups,
        heading = door.heading,
        items = door.items,
        lockpick = door.lockpick,
        hideUi = door.hideUi,
        holdOpen = door.holdOpen,
        lockSound = door.lockSound,
        maxDistance = door.maxDistance,
        doorRate = door.doorRate,
        model = door.model,
        hash = door.hash,
        state = door.state,
        unlockSound = door.unlockSound,
        passcode = door.passcode,
        lockpickDifficulty = door.lockpickDifficulty,
        lockpickAreaSize = door.lockpickAreaSize -- Добавляем сохранение нового параметра
    })
end

local function getDoor(door)
	door = type(door) == 'table' and door or doors[door]
	if not door then return false end
	return {
		id = door.id,
		name = door.name,
		state = door.state,
		coords = door.coords,
		characters = door.characters,
		groups = door.groups,
		items = door.items,
		maxDistance = door.maxDistance,
	}
end

exports('getDoor', getDoor)

exports('getAllDoors', function()
	local allDoors = {}

	for _, door in pairs(doors) do
		allDoors[#allDoors+1] = getDoor(door)
	end

	return allDoors
end)

exports('getDoorFromName', function(name)
	for _, door in pairs(doors) do
		if door.name == name then
			return getDoor(door)
		end
	end
end)

exports('editDoor', function(id, data)
	local door = doors[id]

	if door then
		for k, v in pairs(data) do
			if k ~= 'id' then
				local current = door[k]
				local t1 = type(current)
				local t2 = type(v)

				if t1 ~= 'nil' and v ~= '' and t1 ~= t2 then
					error(("Expected '%s' for door.%s, received %s (%s)"):format(t1, k, t2, v))
				end

				door[k] = v ~= '' and v or nil
			end
		end

		MySQL.update('UPDATE ox_doorlock SET name = ?, data = ? WHERE id = ?', { door.name, encodeData(door), id })
		TriggerClientEvent('ox_doorlock:editDoorlock', -1, id, door)
	end
end)

local soundDirectory = Config.NativeAudio and 'audio/dlc_oxdoorlock/oxdoorlock' or 'web/build/sounds'
local fileFormat = Config.NativeAudio and '%.wav' or '%.ogg'
local sounds = utils.getFilesInDirectory(soundDirectory, fileFormat)

lib.callback.register('ox_doorlock:getSounds', function()
	return sounds
end)

local function createDoor(id, door, name)
    local double = door.doors
    door.id = id
    door.name = name

    if double then
        for i = 1, 2 do
            local coords = double[i].coords
            double[i].coords = vector3(coords.x, coords.y, coords.z)
        end

        if not door.coords then
            door.coords = double[1].coords - ((double[1].coords - double[2].coords) / 2)
        end
    else
        -- door.hash = joaat(('ox_door_%s'):format(id))
    end

    door.coords = vector3(door.coords.x, door.coords.y, door.coords.z)

    if not door.state then
        door.state = 1
    end

    -- === АВТО-ИСПРАВЛЕНИЕ СТАРОГО ФОРМАТА СЛОЖНОСТИ ===
    local needUpdate = false
    if type(door.lockpickDifficulty) == 'table' then
        print(('^3[ox_doorlock] ^7Fixing door %s (%s): lockpickDifficulty was a table, set to 2 (Normal).'):format(id, door.name))
        door.lockpickDifficulty = 2
        needUpdate = true
    elseif not door.lockpickDifficulty then
        door.lockpickDifficulty = 2
    end
    
    if door.lockpickAreaSize == nil then
        door.lockpickAreaSize = false
    end

    -- Если были изменения, сохраняем в БД
    if needUpdate then
        MySQL.update('UPDATE ox_doorlock SET data = ? WHERE id = ?', { encodeData(door), id })
    end
    -- ============================================

    if type(door.items?[1]) == 'string' then
        local items = {}

        for i = 1, #door.items do
            items[i] = {
                name = door.items[i],
                remove = false,
            }
        end

        door.items = items
        MySQL.update('UPDATE ox_doorlock SET data = ? WHERE id = ?', { encodeData(door), id })
    end

    doors[id] = door
    return door
end

local isLoaded = false
local ox_inventory = exports.ox_inventory

SetTimeout(0, function()
	if GetPlayer then return end

	function GetPlayer(_) end
end)

function RemoveItem(playerId, item, slot)
	local player = GetPlayer(playerId)

	if player then ox_inventory:RemoveItem(playerId, item, 1, nil, slot) end
end

---@param player table
---@param items string[] | { name: string, remove?: boolean, metadata?: string }[]
---@param removeItem? boolean
---@return string?
function DoesPlayerHaveItem(playerId, items, removeItem)
    -- Защита, если items это строка, превращаем в таблицу
    if type(items) ~= 'table' then
        items = { items }
    end

    for i = 1, #items do
        local item = items[i]
        local itemName = item.name or item
        
        -- ИСПРАВЛЕНИЕ: Используем playerId (serverId) напрямую для VORP инвентаря
        local itemData = exports.vorp_inventory:getItem(playerId, itemName)
        
        -- Проверяем, что предмет найден, это таблица и количество > 0
        if itemData and type(itemData) == 'table' and itemData.count and itemData.count > 0 then
            if removeItem or item.remove then
                -- Удаляем 1 предмет
                exports.vorp_inventory:subItem(playerId, itemName, 1)
            end
            return itemName
        end
    end
    
    return nil
end

local function isAuthorised(playerId, door, lockpick)
	if Config.PlayerAceAuthorised and IsPlayerAceAllowed(playerId, 'command.doorlock') then
		return true
	end

	-- e.g. add_ace group.police "doorlock.mrpd locker rooms" allow
	-- add_principal fivem:123456 group.police
	-- or add_ace identifier.fivem:123456 "doorlock.mrpd locker rooms" allow
	if IsPlayerAceAllowed(playerId, ('doorlock.%s'):format(door.name)) then
		return true
	end

	local player = GetPlayer(playerId)
	local authorised = door.passcode or false --[[@as boolean | string | nil]]

	if player then
		if lockpick then
			return DoesPlayerHaveItem(playerId, Config.LockpickItems)
		end

		if door.characters and table.contains(door.characters, GetCharacterId(player)) then
			return true
		end

		if door.groups then
			authorised = IsPlayerInGroup(player, door.groups) and true or nil
		end

		if not authorised and door.items then
			authorised = DoesPlayerHaveItem(playerId, door.items) or nil
		end

		if authorised ~= nil and door.passcode then
			authorised = door.passcode == lib.callback.await('ox_doorlock:inputPassCode', playerId)
		end
	end

	return authorised
end

local sql = LoadResourceFile(cache.resource, 'sql/ox_doorlock.sql')

if sql then MySQL.query(sql) end

MySQL.ready(function()
	while Config.DoorList do Wait(100) end

	local response = MySQL.query.await('SELECT `id`, `name`, `data` FROM `ox_doorlock`')

	for i = 1, #response do
		local door = response[i]
		createDoor(door.id, json.decode(door.data), door.name)
	end

	isLoaded = true

	TriggerEvent('ox_doorlock:loaded')
end)

---@param id number
---@param state 0 | 1 | boolean
---@param lockpick? boolean
---@return boolean
---@param id number
---@param state 0 | 1 | boolean
---@param lockpick? boolean
---@return boolean
local function setDoorState(id, state, lockpick)
    local door = doors[id]

    state = (state == 1 or state == 0) and state or (state and 1 or 0)

    if door then
        local authorised = not source or source == '' or isAuthorised(source, door, lockpick)

        if authorised then
            door.state = state
            TriggerClientEvent('ox_doorlock:setState', -1, id, state, source)

            if door.autolock and state == 0 then
                SetTimeout(door.autolock * 1000, function()
                    if door.state ~= 1 then
                        door.state = 1

                        TriggerClientEvent('ox_doorlock:setState', -1, id, door.state)
                        TriggerEvent('ox_doorlock:stateChanged', nil, door.id, door.state == 1)
                    end
                end)
            end

            TriggerEvent('ox_doorlock:stateChanged', source, door.id, state == 1, type(authorised) == 'string' and authorised)

            return true
        end

        if source then
            lib.notify(source, { type = 'error', icon = 'lock', description = state == 0 and 'cannot_unlock' or 'cannot_lock' })
        end
    end

    return false
end

RegisterNetEvent('ox_doorlock:failedLockpick', function()
    local src = source
    local player = GetPlayer(src)
    
    if player then
        -- Удаляем отмычку (true в конце означает удалить)
        local item = DoesPlayerHaveItem(src, Config.LockpickItems, true)
        
        if item then
            lib.notify(src, { type = 'error', description = locale('lockpick_broke') })
        end
    end
end)

RegisterNetEvent('ox_doorlock:setState', setDoorState)
exports('setDoorState', setDoorState)

lib.callback.register('ox_doorlock:getDoors', function()
	while not isLoaded do Wait(100) end

	return doors, sounds
end)

RegisterNetEvent('ox_doorlock:editDoorlock', function(id, data)
	if IsPlayerAceAllowed(source, 'command.doorlock') then
		if data then
			if not data.coords then
				local double = data.doors
				data.coords = double[1].coords - ((double[1].coords - double[2].coords) / 2)
			end

			if not data.name then
				data.name = tostring(data.coords)
			end
		end

		if id then
			if data then
				MySQL.update('UPDATE ox_doorlock SET name = ?, data = ? WHERE id = ?',
					{ data.name, encodeData(data), id })
			else
				MySQL.update('DELETE FROM ox_doorlock WHERE id = ?', { id })
			end

			doors[id] = data
			TriggerClientEvent('ox_doorlock:editDoorlock', -1, id, data)
		else
			local insertId = MySQL.insert.await('INSERT INTO ox_doorlock (name, data) VALUES (?, ?)', { data.name, encodeData(data) })
			local door = createDoor(insertId, data, data.name)

			TriggerClientEvent('ox_doorlock:setState', -1, door.id, door.state, false, door)
		end
	end
end)

RegisterNetEvent('ox_doorlock:breakLockpick', function()
	local player = GetPlayer(source)
	return player and DoesPlayerHaveItem(player, Config.LockpickItems, true)
end)

lib.addCommand('doorlock', {
	help = locale('create_modify_lock'),
	params = {
		{
			name = 'closest',
			help = locale('command_closest'),
			optional = true,
		},
	},
	restricted = Config.CommandPrincipal
}, function(source, args)
	TriggerClientEvent('ox_doorlock:triggeredCommand', source, args.closest)
end)

-- Регистрация callback для проверки отмычек
lib.callback.register('ox_doorlock:checkLockpicks', function(source)
    -- Проверяем доступность VORP инвентаря
    if not exports.vorp_inventory then
        --print("^3[ox_doorlock] ^7vorp_inventory not available, skipping item check")
        return true -- Разрешаем взаимодействие, если инвентарь недоступен
    end
    
    local hasLockpick = false
    
    -- Проверяем наличие любого из предметов-отмычек
    for _, itemName in ipairs(Config.LockpickItems) do
        local itemData = exports.vorp_inventory:getItem(source, itemName)
        
        if itemData and itemData.count and itemData.count > 0 then
            hasLockpick = true
            break
        end
    end
    
    return hasLockpick
end)

-- Регистрация callback для использования отмычки
lib.callback.register('ox_doorlock:useLockpick', function(source)
    -- Проверяем доступность VORP инвентаря
    if not exports.vorp_inventory then
        return true -- Считаем, что отмычка использована, если инвентарь недоступен
    end
    
    local usedLockpick = false
    
    -- Пытаемся использовать любой из предметов-отмычек
    for _, itemName in ipairs(Config.LockpickItems) do
        local itemData = exports.vorp_inventory:getItem(source, itemName)
        
        if itemData and itemData.count and itemData.count > 0 then
            -- Удаляем 1 отмычку из инвентаря
            exports.vorp_inventory:subItem(source, itemName, 1, itemData.metadata or {}, false)
            usedLockpick = true
            break
        end
    end
    
    return usedLockpick
end)