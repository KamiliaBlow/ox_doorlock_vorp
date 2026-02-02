-- Entity state doesn't work, it keeps throwing an error for some reason. 0x3BB78F05
-- local Entity = Entity
local targetIds = {}
local ox_target = nil


local function getDoorHashFromEntity(entity)
	local doors = DoorSystemGetActive()
	for index, value in ipairs(doors) do
		local doorHash = value[1]
		local doorHandle = value[2]
		if doorHandle == entity then
			return doorHash
		end
	end
end

local function getDoorFromEntity(data)
	local entity = type(data) == 'table' and data.entity or data

	if not entity then return end

	-- local state = Entity(entity)?.state
	local state = DoorEntity[entity]
	local doorId = state?.doorId

	if not doorId then return end

	local door = doors[doorId]

	if not door then
		state.doorId = nil
	end

	return door
end

exports('getClosestDoorId', function() return ClosestDoor?.id end)
exports('getDoorIdFromEntity', function(entityId) return getDoorFromEntity(entityId)?.id end) -- same as Entity(entityId).state.doorId

local function entityIsNotDoor(data)
	local entity = type(data) == 'number' and data or data.entity
	return not getDoorFromEntity(entity)
end

PickingLock = false

local function canPickLock(entity)
    if PickingLock then return false end

    local door = getDoorFromEntity(entity)

    return door and door.lockpick and (Config.CanPickUnlockedDoors or door.state == 1)
end

---@param entity number
local function pickLock(entity)
    local door = getDoorFromEntity(entity)
    if not door or PickingLock or not door.lockpick or (not Config.CanPickUnlockedDoors and door.state == 0) then return end
    
    PickingLock = true
    TaskTurnPedToFaceCoord(cache.ped, door.coords.x, door.coords.y, door.coords.z, 4000)
    Wait(500)
    
    RequestAnimDict('script_ca@carust@02@ig@ig1_rustlerslockpickingconv01')
	
    while not HasAnimDictLoaded('script_ca@carust@02@ig@ig1_rustlerslockpickingconv01') do
        Citizen.Wait(100)
    end
	
    TaskPlayAnim(cache.ped, 'script_ca@carust@02@ig@ig1_rustlerslockpickingconv01', 'idle_base_smhthug_01', 1.0, -1.0, -1, 1, 1.0, false, false, false, '', false)
    
    -- НАСТРОЙКА ПАРАМЕТРОВ
    local difficulty = 2 -- По умолчанию Normal (2)
    local rawDifficulty = door.lockpickDifficulty

    -- Проверка: если сложность - это число от 1 до 4, используем его.
    if type(rawDifficulty) == "number" and rawDifficulty >= 1 and rawDifficulty <= 4 then
        difficulty = rawDifficulty
    -- Если это таблица (старый формат от lib.skillCheck) или неверный тип,
    -- то игнорируем её и оставляем difficulty = 2. Это предотвратит ошибку арифметики.
    elseif type(rawDifficulty) == "table" then
        print("^3[ox_doorlock] ^7Door " .. door.id .. " has old lockpickDifficulty format (table). Resetting to 2 (Normal).")
    end

    -- Обработка AreaSize (второй параметр)
    local areaSize = false
    if door.lockpickAreaSize == true then
        areaSize = true
    end
    
    -- ЗАПУСК МИНИ-ИГРЫ
    local success = exports['kb_lockpicking']:startLockpickManual(difficulty, areaSize)
    
	--print("success minigame: ", tostring(success))
    
    if success then
        -- УСПЕХ: Открываем дверь. Отмычка НЕ тратится (так как мы убрали удаление в серверной части).
        TriggerServerEvent('ox_doorlock:setState', door.id, door.state == 1 and 0 or 1, true)
    else
        -- ПРОВАЛ: Отправляем событие на сервер, чтобы сломать отмычку.
        TriggerServerEvent('ox_doorlock:failedLockpick')
    end

    
    -- Остановка анимации
    ClearPedTasks(cache.ped) -- Очищает задачи педа (сбрасывает анимацию)
    RemoveAnimDict(animDict) -- Удаляет словарь из памяти для оптимизации
    
    PickingLock = false
end

exports('pickClosestDoor', function()
	if not ClosestDoor then return end

	pickLock(ClosestDoor.entity)
end)

local tempData = {}

local function addDoorlock(data)
	local entity = type(data) == 'number' and data or data.entity
	local model = GetEntityModel(entity)
	local coords = GetEntityCoords(entity)
	local doorHash = getDoorHashFromEntity(entity)

	AddDoorToSystemNew(doorHash, true, true, false, 0, 0, false)
	DoorSystemSetDoorState(doorHash, 4, false, false)

	coords = GetEntityCoords(entity)
	tempData[#tempData + 1] = {
		entity = entity,
		model = model,
		coords = coords,
		heading = math.floor(GetEntityHeading(entity) + 0.5),
		hash = doorHash
	}

	RemoveDoorFromSystem(doorHash)
end

local isAddingDoorlock = false

RegisterNUICallback('notify', function(data, cb)
	cb(1)
	lib.notify({ title = data })
end)

RegisterNUICallback('createDoor', function(data, cb)
    cb(1)
    SetNuiFocus(false, false)

    data.state = data.state and 1 or 0

    -- Очистка пустых полей
    if data.items and not next(data.items) then
        data.items = nil
    end

    if data.characters and not next(data.characters) then
        data.characters = nil
    end

    -- ИЗМЕНЕНИЕ ЛОГИКИ DIFFICULTY
    -- Раньше здесь была проверка if data.lockpickDifficulty and not next(data.lockpickDifficulty)
    -- Так как теперь lockpickDifficulty это число (1-4), проверка next вызовет ошибку.
    -- Мы просто проверяем, есть ли значение.
    if not data.lockpickDifficulty then
        data.lockpickDifficulty = nil
    end

    if data.groups and not next(data.groups) then
        data.groups = nil
    end

    -- Если UI не отправил lockpickAreaSize, ставим nil или false по умолчанию
    if data.lockpickAreaSize == nil then
        data.lockpickAreaSize = false 
    end

    if not data.id then
        isAddingDoorlock = true
        local doorCount = data.doors and 2 or 1
        local lastEntity = 0

        lib.showTextUI(locale('add_door_textui'))

        repeat
            DisablePlayerFiring(cache.playerId, true)
            DisableControlAction(0, 25, true)

            local hit, entity, coords = lib.raycast.cam(1|16)
            local changedEntity = lastEntity ~= entity
            local doorA = tempData[1]?.entity
            if changedEntity and lastEntity ~= doorA then
                -- SetEntityDrawOutline(lastEntity, false)
            end
            if doorA then
                local mypos = GetEntityCoords(doorA)
                Citizen.InvokeNative(0x2A32FAA57B937173, 0x6EB7D3BB, mypos.x, mypos.y, mypos.z, 0, 0, 0, 0, 0, 0, 1.0, 1.0, 1.0, 255, 42, 24, 100, false, false, 0, false)
            end

            lastEntity = entity
            if hit then
                ---@diagnostic disable-next-line: param-type-mismatch
                Citizen.InvokeNative(0x2A32FAA57B937173, 0x50638AB9, coords.x, coords.y, coords.z, 0, 0, 0, 0, 0, 0, 0.2, 0.2, 0.2, 255, 42, 24, 100, false, false, 0, false, false)
            end

            if hit and entity > 0 and GetEntityType(entity) == 3 and (doorCount == 1 or doorA ~= entity) and entityIsNotDoor(entity) then
                local mypos = GetEntityCoords(entity)
                Citizen.InvokeNative(0x2A32FAA57B937173, 0x6EB7D3BB, mypos.x, mypos.y, mypos.z, 0, 0, 0, 0, 0, 0, 1.0, 1.0, 1.0, 255, 42, 24, 100, false, false, 0, false)
                if changedEntity then
                    -- SetEntityDrawOutline(entity, true)
                end

                if IsDisabledControlJustPressed(0, `INPUT_ATTACK`) then
                    addDoorlock(entity)
                end
            end

            if IsDisabledControlJustPressed(0, `INPUT_AIM`) then
                -- SetEntityDrawOutline(entity, false)

                if not doorA then
                    isAddingDoorlock = false
                    return lib.hideTextUI()
                end

                -- SetEntityDrawOutline(doorA, false)
                table.wipe(tempData)
            end
        until tempData[doorCount]

        lib.hideTextUI()
        -- SetEntityDrawOutline(tempData[1].entity, false)

        if data.doors then
            -- SetEntityDrawOutline(tempData[2].entity, false)
            tempData[1].entity = nil
            tempData[2].entity = nil
            data.doors = tempData
        else
            data.model = tempData[1].model
            data.coords = tempData[1].coords
            data.heading = tempData[1].heading
            data.hash = tempData[1].hash
        end
    else
        if data.doors then
            for i = 1, 2 do
                local coords = data.doors[i].coords
                data.doors[i].coords = vector3(coords.x, coords.y, coords.z)
                data.doors[i].entity = nil
            end
        else
            data.entity = nil
        end

        data.coords = vector3(data.coords.x, data.coords.y, data.coords.z)
        data.distance = nil
        data.zone = nil
    end

    isAddingDoorlock = false

    TriggerServerEvent('ox_doorlock:editDoorlock', data.id or false, data)
    table.wipe(tempData)
end)

RegisterNUICallback('deleteDoor', function(id, cb)
	cb(1)
	TriggerServerEvent('ox_doorlock:editDoorlock', id)
end)

RegisterNUICallback('teleportToDoor', function(id, cb)
	cb(1)
	SetNuiFocus(false, false)
	local doorCoords = doors[id].coords
	if not doorCoords then return end
	SetEntityCoords(cache.ped, doorCoords.x, doorCoords.y, doorCoords.z, false, false, false, false)
end)

RegisterNUICallback('exit', function(_, cb)
	cb(1)
	SetNuiFocus(false, false)
end)

local function openUi(id)
	if source == '' or isAddingDoorlock then return end

	if not NuiHasLoaded then
		NuiHasLoaded = true

		SendNuiMessage(json.encode({
			action = 'updateDoorData',
			data = doors
		}, { with_hole = false }))
		Wait(100)

		SendNUIMessage({
			action = 'setSoundFiles',
			data = lib.callback.await('ox_doorlock:getSounds', false)
		})
	end

	SetNuiFocus(true, true)
	SendNuiMessage(json.encode({
		action = 'setVisible',
		data = id
	}))
end

RegisterNetEvent('ox_doorlock:triggeredCommand', function(closest)
	openUi(closest and ClosestDoor?.id or nil)
end)

CreateThread(function()
    -- Убедитесь, что lib доступна
    
    local target
    
    if GetResourceState('ox_target'):find('start') then
        target = {
            ox = true,
            exp = exports.ox_target
        }
        --print("^2[ox_doorlock] ^7ox_target enabled")
    elseif GetResourceState('qtarget'):find('start') then
        target = {
            qt = true,
            exp = exports.qtarget
        }
    end
    
    if not target then 
        --print("^1[ox_doorlock] ^7No target resource found!")
        return 
    end
    
    if target.ox then
        -- Функция для проверки наличия отмычек через сервер
        local function hasLockpicks()
            return lib.callback('ox_doorlock:checkLockpicks', false)
        end
        
        -- Функция для использования отмычки через сервер
        local function useLockpick()
            return lib.callback('ox_doorlock:useLockpick', false)
        end
        
        -- Настройки глобального объекта
        target.exp:addGlobalObject({
            {
                name = 'pickDoorlock',
                label = locale('pick_lock'),
                icon = 'fas fa-user-lock',
                onSelect = function(data)
                    -- Проверяем наличие отмычек
                    if not hasLockpicks() then
                        lib.notify({
                            type = 'error',
                            description = locale('no_lockpick')
                        })
                        return
                    end
                    
                    -- Получаем сущность из данных
                    local entity = data.entity or (type(data) == 'number' and data)
                    if entity then
                        pickLock(entity)
                    end
                end,
                canInteract = function(entity, distance, data)
                    -- Проверяем, можем ли мы взломать эту дверь
                    return canPickLock(entity)
                end,
                distance = 1.5,
                debug = GetConvarInt('ox_target:debug', 0) == 1
            }
        })
        
        print("^2[ox_doorlock] ^7Global doorlock target registered successfully")
    else
        -- Сохраняем поддержку qtarget для совместимости
        local options = {
            {
                label = locale('pick_lock'),
                icon = 'fas fa-user-lock',
                action = pickLock,
                canInteract = canPickLock,
                item = Config.LockpickItems[1],
                distance = 1
            }
        }
        
        if target.qt then
            target.exp:Object({ options = options })
        end
        
        AddEventHandler('onResourceStop', function(resource)
            if resource == cache.resource then
                if target.qt then
                    target.exp:RemoveObject({ locale('pick_lock') })
                end
            end
        end)
    end
end)
