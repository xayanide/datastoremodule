--[[
VERSION="2.3.1"
@xayanide - 2025-11-19
A fork of SDM v1.3 that was last updated on 2023-10-28.
For the general changelog, please see _README.
]]
local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local HttpService = game:GetService("HttpService")

local SignalModule = require(script.Xignal4Module)
local SyncTaskManagerModule = require(script.SyncTaskManagerModule)

local jobId = game.JobId
local SERVER_ID = if jobId == "" then "Studio" else jobId
jobId = nil
local IS_DEBUG_ENABLED = true
local DEFAULT_DATASTORE_SAVE_INTERVAL = 30
local DEFAULT_DATASTORE_SAVE_DELAY = 0
local DEFAULT_DATASTORE_LOCK_INTERVAL = 60
local DEFAULT_DATASTORE_LOCK_ATTEMPTS = 5
local DEFAULT_DATASTORE_SAVE_ON_CLOSE = true

local DEFAULT_MEMORYSTOREQUEUE_ADD_ITEM_EXPIRE_TIME = 604800
local DATASTORE_MIN_SAVE_INTERVAL = 10
local DATASTORE_MAX_SAVE_INTERVAL = 1000
local DATASTORE_RESPONSE_STATE = "State"
local DATASTORE_STATE_DESTROYED = "Destroyed"
local DATASTORE_STATE_DESTROYING = "Destroying"
local DATASTORE_STATE_OPEN = "Open"
local DATASTORE_STATE_CLOSED = "Closed"
local DATASTORE_STATE_CLOSING = "Closing"
local DATASTORE_RESPONSE_SUCCESS = "Success"
local DATASTORE_RESPONSE_SAVED = "Saved"
local DATASTORE_RESPONSE_LOCKED = "Locked"
local DATASTORE_RESPONSE_ERROR = "Error"
local DATASTORE_GLOBAL_SCOPE = "global"
local DATASTORE_MAX_ENTRY_SIZE = 4194303
local DATASTORE_SAVE_MAX_ATTEMPTS = 3
local DATASTORE_LOAD_MAX_ATTEMPTS = 3
local MEMORYSTORESORTEDMAP_SESSION_UNLOCK_MAX_ATTEMPTS = 3
local MEMORYSTORESORTEDMAP_SESSION_LOCK_MAX_ATTEMPTS = 3
local MEMORYSTORESORTEDMAP_SESSION_LOCK_KEY = "LockId"
local MEMORYSTORESORTEDMAP_SESSION_LOCK_EXPIRE_TIME_EXTRA = 30
local MEMORYSTOREQUEUE_ADD_MAX_ATTEMPTS = 3
local MEMORYSTOREQUEUE_REMOVE_MAX_ATTEMPTS = 3
local MEMORYSTOREQUEUE_READ_ITEM_COUNT = 100
local MEMORYSTOREQUEUE_READ_ALL_OR_NOTHING = false
local MEMORYSTOREQUEUE_READ_WAIT_TIMEOUT = 30
local ASYNC_OPERATION_RETRY_WAIT_TIME = 1
local DEFAULT_COMPRESSION_LEVEL = 2
local DEFAULT_DECIMAL_PRECISION = 3
local COMPRESSION_DECIMAL_BASE = 10
local LUA_ARRAY_LENGTH_OFFSET = 1

local DataStoreModule = {}
local scriptName = script.Name
local isModuleActive = true
local activeRobloxDataStores = {}
local activeDataStores, bindToCloseDataStores = {}, {}
local DataStoreModuleNew, DataStoreModuleHidden, DataStoreModuleFind, DataStoreModuleResponse
local DataStoreOpen, DataStoreRead, DataStoreSave, DataStoreClose, DataStoreDestroy, DataStoreQueue, DataStoreRemove, DataStoreClone, DataStoreReconcile, DataStoreUsage, DataStoreSetSaveInterval
local OpenTask, ReadTask, LockTask, SaveTask, CloseTask, DestroyTask, ProcessQueueTask
local Lock, Unlock, Load, Save
local Clone, Reconcile
local Compress, Decompress
local Encode, Decode
local StartSaveTimer, StopSaveTimer
local StartLockTimer, StopLockTimer
local onProcessQueueConnected, onSaveTimerEnded, onLockTimerEnded, onBindToClose
local getActiveRobloxDataStore, createDataStore, getDataStoreId

local baseCharacters = { [0] = "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "!", "$", "%", "&", "'", ",", ".", "/", ":", ";", "=", "?", "@", "[", "]", "^", "_", "`", "{", "}", "~" }
local baseLength = #baseCharacters + LUA_ARRAY_LENGTH_OFFSET
local charValues = {}
for i = (0), #baseCharacters do
    charValues[string.byte(baseCharacters[i])] = i
end

export type DataStoreModule = {
    new: (name: string, scope: string, key: string?) -> DataStore,
    hidden: (name: string, scope: string, key: string?) -> DataStore,
    find: (name: string, scope: string, key: string?) -> DataStore?,
    Response: {
        Success: string,
        Saved: string,
        Locked: string,
        State: string,
        Error: string,
    },
}

export type DataStore = {
    [any]: any,
    Value: any,
    Metadata: { [string]: any },
    UserIds: { any },
    SaveInterval: number,
    SaveDelay: number,
    LockInterval: number,
    LockAttempts: number,
    SaveOnClose: boolean,
    Id: string,
    ServerId: string,
    LockId: string,
    Key: string,
    State: boolean?,
    Hidden: boolean,
    AttemptsRemaining: number,
    CreatedTime: number,
    UpdatedTime: number,
    DataStoreVersion: string,
    CompressedValue: string,
    StateChanged: SignalModule.Signal,
    Saving: SignalModule.Signal,
    Saved: SignalModule.Signal,
    AttemptsChanged: SignalModule.Signal,
    ProcessQueue: SignalModule.Signal & { dataStore: DataStore, Connected: (isConnected: boolean, signal: SignalModule.Signal) -> any },
    Open: (self: DataStore, template: any?) -> (string, any),
    Read: (self: DataStore, template: any?) -> (string, any),
    Save: (self: DataStore) -> (string, any),
    Close: (self: DataStore) -> (string, any),
    Destroy: (self: DataStore) -> (string, any),
    Queue: (self: DataStore, value: any, expiration: number?, priority: number?) -> (string, any),
    Remove: (self: DataStore, id: string) -> (string, any),
    Clone: (self: DataStore) -> any,
    Reconcile: (self: DataStore, template: any) -> (),
    Usage: (self: DataStore) -> (number, number),
    SetSaveInterval: (self: DataStore, value: number) -> (),
    SaveThread: thread?,
    LockThread: thread?,
    TaskManager: SyncTaskManagerModule.TaskManager,
    LockTime: number,
    SaveTime: number,
    ActiveLockInterval: number,
    ProcessingQueue: boolean,
    DataStore: DataStore,
    DataStoreSetOptions: DataStoreSetOptions,
    MemoryStoreSortedMap: MemoryStoreSortedMap,
    MemoryStoreQueue: MemoryStoreQueue,
}

getActiveRobloxDataStore = function(name, scope)
    local dataStoreId = name .. "/" .. scope
    local activeDataStore = activeRobloxDataStores[dataStoreId]
    if activeDataStore ~= nil then
        return activeDataStore
    end
    local robloxDataStore = DataStoreService:GetDataStore(name, scope)
    activeRobloxDataStores[dataStoreId] = robloxDataStore
    return robloxDataStore
end

createDataStore = function(name, scope, key, dataStoreId, isHidden)
    local dataStore = {
        Value = nil,
        Metadata = {},
        UserIds = {},
        SaveInterval = DEFAULT_DATASTORE_SAVE_INTERVAL,
        SaveDelay = DEFAULT_DATASTORE_SAVE_DELAY,
        LockInterval = DEFAULT_DATASTORE_LOCK_INTERVAL,
        LockAttempts = DEFAULT_DATASTORE_LOCK_ATTEMPTS,
        SaveOnClose = DEFAULT_DATASTORE_SAVE_ON_CLOSE,
        Id = dataStoreId,
        ServerId = SERVER_ID,
        LockId = HttpService:GenerateGUID(false),
        Key = key,
        State = false,
        Hidden = isHidden,
        AttemptsRemaining = 0,
        CreatedTime = 0,
        UpdatedTime = 0,
        DataStoreVersion = "",
        CompressedValue = "",
        StateChanged = SignalModule.new(),
        Saving = SignalModule.new(),
        Saved = SignalModule.new(),
        AttemptsChanged = SignalModule.new(),
        ProcessQueue = SignalModule.new(),
        Open = DataStoreOpen,
        Read = DataStoreRead,
        Save = DataStoreSave,
        Close = DataStoreClose,
        Destroy = DataStoreDestroy,
        Queue = DataStoreQueue,
        Remove = DataStoreRemove,
        Clone = DataStoreClone,
        Reconcile = DataStoreReconcile,
        Usage = DataStoreUsage,
        SetSaveInterval = DataStoreSetSaveInterval,
        SaveThread = nil,
        LockThread = nil,
        TaskManager = SyncTaskManagerModule.new(),
        LockTime = -math.huge,
        SaveTime = -math.huge,
        ActiveLockInterval = 0,
        ProcessingQueue = false,
        DataStore = getActiveRobloxDataStore(name, scope),
        DataStoreSetOptions = Instance.new("DataStoreSetOptions"),
        MemoryStoreSortedMap = MemoryStoreService:GetSortedMap(dataStoreId),
        MemoryStoreQueue = MemoryStoreService:GetQueue(dataStoreId),
    }
    dataStore.ProcessQueue.dataStore = dataStore
    dataStore.ProcessQueue.Connected = onProcessQueueConnected
    return dataStore
end

getDataStoreId = function(name, scope, key)
    return name .. "/" .. scope .. "/" .. key
end

DataStoreModuleNew = function(name, scope, key)
    if key == nil then
        key, scope = scope, DATASTORE_GLOBAL_SCOPE
    end
    local dataStoreId = getDataStoreId(name, scope, key)
    local activeDataStore = activeDataStores[dataStoreId]
    if activeDataStore ~= nil then
        return activeDataStore
    end
    local dataStore = createDataStore(name, scope, key, dataStoreId, false)
    activeDataStores[dataStoreId] = dataStore
    return dataStore
end

DataStoreModuleHidden = function(name, scope, key)
    if key == nil then
        key, scope = scope, DATASTORE_GLOBAL_SCOPE
    end
    local dataStoreId = getDataStoreId(name, scope, key)
    return createDataStore(name, scope, key, dataStoreId, true)
end

DataStoreModuleFind = function(name, scope, key)
    if key == nil then
        key, scope = scope, DATASTORE_GLOBAL_SCOPE
    end
    local dataStoreId = getDataStoreId(name, scope, key)
    return activeDataStores[dataStoreId]
end

DataStoreModuleResponse = {
    Success = DATASTORE_RESPONSE_SUCCESS,
    Saved = DATASTORE_RESPONSE_SAVED,
    Locked = DATASTORE_RESPONSE_LOCKED,
    State = DATASTORE_RESPONSE_STATE,
    Error = DATASTORE_RESPONSE_ERROR,
}

DataStoreOpen = function(dataStore, template)
    local dataStoreState = dataStore.State
    if dataStoreState == nil then
        return DATASTORE_RESPONSE_STATE, DATASTORE_STATE_DESTROYED
    end
    local taskManager = dataStore.TaskManager
    local firstSyncOpenTask = taskManager:FindFirst(OpenTask)
    if firstSyncOpenTask ~= nil then
        return firstSyncOpenTask:Wait(template)
    end
    if taskManager:FindLast(DestroyTask) ~= nil then
        return DATASTORE_RESPONSE_STATE, DATASTORE_STATE_DESTROYING
    end
    if dataStoreState == true and taskManager:FindLast(CloseTask) == nil then
        local dataStoreValue = dataStore.Value
        if dataStoreValue == nil then
            dataStore.Value = Clone(template)
        elseif type(dataStoreValue) == "table" and type(template) == "table" then
            Reconcile(dataStore.Value, template)
        end
        return DATASTORE_RESPONSE_SUCCESS
    end
    return taskManager:InsertBack(OpenTask, dataStore):Wait(template)
end

DataStoreRead = function(dataStore, template)
    local taskManager = dataStore.TaskManager
    local firstSyncReadTask = taskManager:FindFirst(ReadTask)
    if firstSyncReadTask ~= nil then
        return firstSyncReadTask:Wait(template)
    end
    if dataStore.State == true and taskManager:FindLast(CloseTask) == nil then
        return DATASTORE_RESPONSE_STATE, DATASTORE_STATE_OPEN
    end
    return taskManager:InsertBack(ReadTask, dataStore):Wait(template)
end

DataStoreSave = function(dataStore)
    local dataStoreState = dataStore.State
    if dataStoreState == false then
        return DATASTORE_RESPONSE_STATE, DATASTORE_STATE_CLOSED
    end
    if dataStoreState == nil then
        return DATASTORE_RESPONSE_STATE, DATASTORE_STATE_DESTROYED
    end
    local taskManager = dataStore.TaskManager
    local firstSyncSaveTask = taskManager:FindFirst(SaveTask)
    if firstSyncSaveTask ~= nil then
        return firstSyncSaveTask:Wait()
    end
    if taskManager:FindLast(CloseTask) ~= nil then
        return DATASTORE_RESPONSE_STATE, DATASTORE_STATE_CLOSING
    end
    if taskManager:FindLast(DestroyTask) ~= nil then
        return DATASTORE_RESPONSE_STATE, DATASTORE_STATE_DESTROYING
    end
    return taskManager:InsertBack(SaveTask, dataStore):Wait()
end

DataStoreClose = function(dataStore)
    local dataStoreState = dataStore.State
    if dataStoreState == nil then
        return DATASTORE_RESPONSE_SUCCESS
    end
    local taskManager = dataStore.TaskManager
    local firstSyncCloseTask = taskManager:FindFirst(CloseTask)
    if firstSyncCloseTask ~= nil then
        return firstSyncCloseTask:Wait()
    end
    if dataStoreState == false and taskManager:FindLast(OpenTask) == nil then
        return DATASTORE_RESPONSE_SUCCESS
    end
    local firstSyncDestroyTask = taskManager:FindFirst(DestroyTask)
    if firstSyncDestroyTask ~= nil then
        return firstSyncDestroyTask:Wait()
    end
    StopLockTimer(dataStore)
    StopSaveTimer(dataStore)
    return taskManager:InsertBack(CloseTask, dataStore):Wait()
end

DataStoreDestroy = function(dataStore)
    if dataStore.State == nil then
        return DATASTORE_RESPONSE_SUCCESS
    end
    activeDataStores[dataStore.Id] = nil
    StopLockTimer(dataStore)
    StopSaveTimer(dataStore)
    local taskManager = dataStore.TaskManager
    local firstSyncDestroyTask = taskManager:FindFirst(DestroyTask)
    local syncDestroyTask = if firstSyncDestroyTask ~= nil then firstSyncDestroyTask else taskManager:InsertBack(DestroyTask, dataStore)
    return syncDestroyTask:Wait()
end

DataStoreQueue = function(dataStore, queueValue, expiration, priority)
    if expiration ~= nil and type(expiration) ~= "number" then
        error("Attempt to AddQueue failed: Passed value is not nil or number", 3)
    end
    if priority ~= nil and type(priority) ~= "number" then
        error("Attempt to AddQueue failed: Passed value is not nil or number", 3)
    end
    local success, value
    local memoryStoreQueue = dataStore.MemoryStoreQueue
    local dataStoreId = dataStore.Id
    for i = 1, MEMORYSTOREQUEUE_ADD_MAX_ATTEMPTS do
        if i > 1 then
            task.wait(ASYNC_OPERATION_RETRY_WAIT_TIME)
        end
        local sTime = os.clock()
        if IS_DEBUG_ENABLED == true then
            print("[" .. dataStoreId .. "] INIT: Queue. MemoryStoreQueue:AddAsync")
        end
        success, value = pcall(memoryStoreQueue.AddAsync, memoryStoreQueue, queueValue, expiration or DEFAULT_MEMORYSTOREQUEUE_ADD_ITEM_EXPIRE_TIME, priority)
        if IS_DEBUG_ENABLED == true then
            print("[" .. dataStoreId .. "] DONE: Queue. MemoryStoreQueue:AddAsync. Took " .. os.clock() - sTime .. "s")
        end
        if success == true then
            return DATASTORE_RESPONSE_SUCCESS
        end
    end
    return DATASTORE_RESPONSE_ERROR, value
end

DataStoreRemove = function(dataStore, id)
    if type(id) ~= "string" then
        error("Attempt to RemoveQueue failed: Passed value is not a string", 3)
    end
    local success, value
    local memoryStoreQueue = dataStore.MemoryStoreQueue
    local dataStoreId = dataStore.Id
    for i = 1, MEMORYSTOREQUEUE_REMOVE_MAX_ATTEMPTS do
        if i > 1 then
            task.wait(ASYNC_OPERATION_RETRY_WAIT_TIME)
        end
        local sTime = os.clock()
        if IS_DEBUG_ENABLED == true then
            print("[" .. dataStoreId .. "] INIT: Remove. MemoryStoreQueue:RemoveAsync")
        end
        success, value = pcall(memoryStoreQueue.RemoveAsync, memoryStoreQueue, id)
        if IS_DEBUG_ENABLED == true then
            print("[" .. dataStoreId .. "] DONE: Remove. MemoryStoreQueue:RemoveAsync. Took " .. os.clock() - sTime .. "s")
        end
        if success == true then
            return DATASTORE_RESPONSE_SUCCESS
        end
    end
    return DATASTORE_RESPONSE_ERROR, value
end

DataStoreClone = function(dataStore)
    return Clone(dataStore.Value)
end

DataStoreReconcile = function(dataStore, template)
    local dataStoreValue = dataStore.Value
    if dataStoreValue == nil then
        dataStore.Value = Clone(template)
        return
    end
    if type(dataStoreValue) == "table" and type(template) == "table" then
        Reconcile(dataStore.Value, template)
    end
end

DataStoreUsage = function(dataStore)
    local dataStoreValue = dataStore.Value
    if dataStoreValue == nil then
        return 0, 0
    end
    local metadataCompress = dataStore.Metadata.Compress
    if type(metadataCompress) ~= "table" then
        local strLength = #HttpService:JSONEncode(dataStoreValue)
        return strLength, strLength / DATASTORE_MAX_ENTRY_SIZE
    end
    local level = metadataCompress.Level or DEFAULT_COMPRESSION_LEVEL
    local decimals = COMPRESSION_DECIMAL_BASE ^ (metadataCompress.Decimals or DEFAULT_DECIMAL_PRECISION)
    local compressSafety = metadataCompress.Safety
    local isSafetyEnabled = if compressSafety == nil then true else compressSafety
    dataStore.CompressedValue = Compress(dataStoreValue, level, decimals, isSafetyEnabled)
    local strLength = #HttpService:JSONEncode(dataStore.CompressedValue)
    return strLength, strLength / DATASTORE_MAX_ENTRY_SIZE
end

DataStoreSetSaveInterval = function(dataStore, value)
    if type(value) ~= "number" then
        error("Attempt to set SaveInterval failed: Passed value is not a number", 3)
    end
    if value < DATASTORE_MIN_SAVE_INTERVAL and value ~= 0 then
        error("Attempt to set SaveInterval failed: Passed value is less than 10 and not 0", 3)
    end
    if value > DATASTORE_MAX_SAVE_INTERVAL then
        error("Attempt to set SaveInterval failed: Passed value is more than 1000", 3)
    end
    if value == dataStore.SaveInterval then
        return
    end
    dataStore.SaveInterval = value
    if value == 0 then
        StopSaveTimer(dataStore)
        return
    end
    StartSaveTimer(dataStore)
end

OpenTask = function(runningTask, dataStore)
    local lockResponse, lockResponseData = Lock(dataStore, MEMORYSTORESORTEDMAP_SESSION_LOCK_MAX_ATTEMPTS)
    if lockResponse ~= DATASTORE_RESPONSE_SUCCESS then
        for thread in runningTask:Iterate() do
            task.defer(thread, lockResponse, lockResponseData)
        end
        return
    end
    local loadResponse, loadResponseData = Load(dataStore, DATASTORE_LOAD_MAX_ATTEMPTS)
    if loadResponse ~= DATASTORE_RESPONSE_SUCCESS then
        Unlock(dataStore, MEMORYSTORESORTEDMAP_SESSION_UNLOCK_MAX_ATTEMPTS)
        for thread in runningTask:Iterate() do
            task.defer(thread, loadResponse, loadResponseData)
        end
        return
    end
    local dataStoreLockId = dataStore.LockId
    if isModuleActive == true then
        bindToCloseDataStores[dataStoreLockId] = dataStore
    end
    dataStore.State = true
    local taskManager = dataStore.TaskManager
    if taskManager:FindLast(CloseTask) == nil and taskManager:FindLast(DestroyTask) == nil then
        StartSaveTimer(dataStore)
        StartLockTimer(dataStore)
    end
    local dataStoreValue = dataStore.Value
    for thread, template in runningTask:Iterate() do
        if dataStoreValue == nil then
            dataStore.Value = Clone(template)
        elseif type(dataStoreValue) == "table" and type(template) == "table" then
            Reconcile(dataStore.Value, template)
        end
        task.defer(thread, loadResponse)
    end
    if dataStore.ProcessingQueue == false and dataStore.ProcessQueue.Connections > 0 then
        task.defer(ProcessQueueTask, dataStore)
    end
    dataStore.StateChanged:Fire(true, dataStore)
end

ReadTask = function(runningTask, dataStore)
    if dataStore.State == true then
        for thread in runningTask:Iterate() do
            task.defer(thread, DATASTORE_RESPONSE_STATE, DATASTORE_STATE_OPEN)
        end
        return
    end
    local response, responseData = Load(dataStore, DATASTORE_LOAD_MAX_ATTEMPTS)
    if response ~= DATASTORE_RESPONSE_SUCCESS then
        for thread in runningTask:Iterate() do
            task.defer(thread, response, responseData)
        end
        return
    end
    local dataStoreValue = dataStore.Value
    for thread, template in runningTask:Iterate() do
        if dataStoreValue == nil then
            dataStore.Value = Clone(template)
        elseif type(dataStoreValue) == "table" and type(template) == "table" then
            Reconcile(dataStore.Value, template)
        end
        task.defer(thread, response)
    end
end

LockTask = function(runningTask, dataStore)
    local previousAttemptsRemaining = dataStore.AttemptsRemaining
    local response, responseData = Lock(dataStore, MEMORYSTORESORTEDMAP_SESSION_LOCK_MAX_ATTEMPTS)
    if response ~= DATASTORE_RESPONSE_SUCCESS then
        dataStore.AttemptsRemaining -= 1
    end
    local currentAttemptsRemaining = dataStore.AttemptsRemaining
    if currentAttemptsRemaining ~= previousAttemptsRemaining then
        dataStore.AttemptsChanged:Fire(currentAttemptsRemaining, dataStore)
    end
    local taskManager = dataStore.TaskManager
    if currentAttemptsRemaining > 0 then
        if taskManager:FindLast(CloseTask) == nil and taskManager:FindLast(DestroyTask) == nil then
            StartLockTimer(dataStore)
        end
    else
        dataStore.State = false
        StopLockTimer(dataStore)
        StopSaveTimer(dataStore)
        if dataStore.SaveOnClose == true then
            Save(dataStore, DATASTORE_SAVE_MAX_ATTEMPTS)
        end
        Unlock(dataStore, MEMORYSTORESORTEDMAP_SESSION_UNLOCK_MAX_ATTEMPTS)
        dataStore.StateChanged:Fire(false, dataStore)
    end
    return response, responseData
end

SaveTask = function(runningTask, dataStore)
    if dataStore.State == false then
        for thread in runningTask:Iterate() do
            task.defer(thread, DATASTORE_RESPONSE_STATE, DATASTORE_STATE_CLOSED)
        end
        return
    end
    StopSaveTimer(dataStore)
    runningTask:End()
    local response, responseData = Save(dataStore, DATASTORE_SAVE_MAX_ATTEMPTS)
    local taskManager = dataStore.TaskManager
    if taskManager:FindLast(CloseTask) == nil and taskManager:FindLast(DestroyTask) == nil then
        StartSaveTimer(dataStore)
    end
    for thread in runningTask:Iterate() do
        task.defer(thread, response, responseData)
    end
end

CloseTask = function(runningTask, dataStore)
    if dataStore.State == false then
        for thread in runningTask:Iterate() do
            task.defer(thread, DATASTORE_RESPONSE_SUCCESS)
        end
        return
    end
    dataStore.State = false
    local response, responseData = nil, nil
    if dataStore.SaveOnClose == true then
        response, responseData = Save(dataStore, DATASTORE_SAVE_MAX_ATTEMPTS)
    end
    Unlock(dataStore, MEMORYSTORESORTEDMAP_SESSION_UNLOCK_MAX_ATTEMPTS)
    dataStore.StateChanged:Fire(false, dataStore)
    if response == DATASTORE_RESPONSE_SAVED then
        for thread in runningTask:Iterate() do
            task.defer(thread, response, responseData)
        end
        return
    end
    for thread in runningTask:Iterate() do
        task.defer(thread, DATASTORE_RESPONSE_SUCCESS)
    end
end

DestroyTask = function(runningTask, dataStore)
    local response, responseData = nil, nil
    if dataStore.State == false then
        dataStore.State = nil
    else
        dataStore.State = nil
        if dataStore.SaveOnClose == true then
            response, responseData = Save(dataStore, DATASTORE_SAVE_MAX_ATTEMPTS)
        end
        Unlock(dataStore, MEMORYSTORESORTEDMAP_SESSION_UNLOCK_MAX_ATTEMPTS)
    end
    local signalStateChanged = dataStore.StateChanged
    signalStateChanged:Fire(nil, dataStore)
    signalStateChanged:DisconnectAll()
    dataStore.Saving:DisconnectAll()
    dataStore.Saved:DisconnectAll()
    dataStore.AttemptsChanged:DisconnectAll()
    dataStore.ProcessQueue:DisconnectAll()
    bindToCloseDataStores[dataStore.LockId] = nil
    if response == DATASTORE_RESPONSE_SAVED then
        for thread in runningTask:Iterate() do
            task.defer(thread, response, responseData)
        end
        return
    end
    for thread in runningTask:Iterate() do
        task.defer(thread, DATASTORE_RESPONSE_SUCCESS)
    end
end

ProcessQueueTask = function(dataStore)
    if dataStore.State ~= true then
        return
    end
    if dataStore.ProcessQueue.Connections == 0 then
        return
    end
    if dataStore.ProcessingQueue == true then
        return
    end
    dataStore.ProcessingQueue = true
    local memoryStoreQueue = dataStore.MemoryStoreQueue
    local dataStoreId = dataStore.Id
    while true do
        local sTime = os.clock()
        if IS_DEBUG_ENABLED == true then
            print("[" .. dataStoreId .. "] INIT: ProcessQueueTask. MemoryStoreQueue:ReadAsync")
        end
        local success, items, id = pcall(memoryStoreQueue.ReadAsync, memoryStoreQueue, MEMORYSTOREQUEUE_READ_ITEM_COUNT, MEMORYSTOREQUEUE_READ_ALL_OR_NOTHING, MEMORYSTOREQUEUE_READ_WAIT_TIMEOUT)
        if IS_DEBUG_ENABLED == true then
            print("[" .. dataStoreId .. "] DONE: ProcessQueueTask. MemoryStoreQueue:ReadAsync. Took " .. os.clock() - sTime .. "s")
        end
        if dataStore.State ~= true then
            break
        end
        local signalProcessQueue = dataStore.ProcessQueue
        if signalProcessQueue.Connections == 0 then
            break
        end
        if success == true and id ~= nil then
            signalProcessQueue:Fire(id, items, dataStore)
        end
    end
    dataStore.ProcessingQueue = false
end

Lock = function(dataStore, attempts)
    local success, value, previousLockId, lockTime, lockInterval, lockAttempts = nil, nil, nil, nil, dataStore.LockInterval, dataStore.LockAttempts
    local lockExpireTime = lockInterval * lockAttempts + MEMORYSTORESORTEDMAP_SESSION_LOCK_EXPIRE_TIME_EXTRA
    local lockId = dataStore.LockId
    local function onLockUpdateAsync(previousValue)
        previousLockId = previousValue
        if previousLockId == nil then
            return lockId
        end
        if previousLockId == lockId then
            return lockId
        end
        return nil
    end
    local memoryStoreSortedMap = dataStore.MemoryStoreSortedMap
    local dataStoreId = dataStore.Id
    for i = 1, attempts do
        if i > 1 then
            task.wait(ASYNC_OPERATION_RETRY_WAIT_TIME)
        end
        lockTime = os.clock()
        local sTime = os.clock()
        if IS_DEBUG_ENABLED == true then
            print("[" .. dataStoreId .. "] INIT: Lock. MemoryStoreSortedMap:UpdateAsync")
        end
        success, value = pcall(memoryStoreSortedMap.UpdateAsync, memoryStoreSortedMap, MEMORYSTORESORTEDMAP_SESSION_LOCK_KEY, onLockUpdateAsync, lockExpireTime)
        if IS_DEBUG_ENABLED == true then
            print("[" .. dataStoreId .. "] DONE: Lock. MemoryStoreSortedMap:UpdateAsync. Took " .. os.clock() - sTime .. "s")
        end
        if success == true then
            break
        end
    end
    if success == false then
        return DATASTORE_RESPONSE_ERROR, value
    end
    if value == nil then
        return DATASTORE_RESPONSE_LOCKED, previousLockId
    end
    dataStore.LockTime = lockTime + lockInterval * lockAttempts
    dataStore.ActiveLockInterval = lockInterval
    dataStore.AttemptsRemaining = lockAttempts
    return DATASTORE_RESPONSE_SUCCESS
end

Unlock = function(dataStore, attempts)
    local success, value, previousLockId = nil, nil, nil
    local lockExpireTime = 0
    local lockId = dataStore.LockId
    local function onUnlockUpdateAsync(previousValue)
        previousLockId = previousValue
        if previousLockId == nil then
            return lockId
        end
        if previousLockId == lockId then
            return lockId
        end
        return nil
    end
    local memoryStoreSortedMap = dataStore.MemoryStoreSortedMap
    local dataStoreId = dataStore.Id
    for i = 1, attempts do
        if i > 1 then
            task.wait(ASYNC_OPERATION_RETRY_WAIT_TIME)
        end
        local sTime = os.clock()
        if IS_DEBUG_ENABLED == true then
            print("[" .. dataStoreId .. "] INIT: Unlock. MemoryStoreSortedMap:UpdateAsync")
        end
        success, value = pcall(memoryStoreSortedMap.UpdateAsync, memoryStoreSortedMap, MEMORYSTORESORTEDMAP_SESSION_LOCK_KEY, onUnlockUpdateAsync, lockExpireTime)
        if IS_DEBUG_ENABLED == true then
            print("[" .. dataStoreId .. "] DONE: Unlock. MemoryStoreSortedMap:UpdateAsync. Took " .. os.clock() - sTime .. "s")
        end
        if success == true then
            break
        end
    end
    if success == false then
        return DATASTORE_RESPONSE_ERROR, value
    end
    if value == nil and previousLockId ~= nil then
        return DATASTORE_RESPONSE_LOCKED, previousLockId
    end
    return DATASTORE_RESPONSE_SUCCESS
end

Load = function(dataStore, attempts)
    local success, value, info = nil, nil, nil
    local robloxDataStore = dataStore.DataStore
    local dataStoreId = dataStore.Id
    local dataStoreKey = dataStore.Key
    for i = 1, attempts do
        if i > 1 then
            task.wait(ASYNC_OPERATION_RETRY_WAIT_TIME)
        end
        local sTime = os.clock()
        if IS_DEBUG_ENABLED == true then
            print("[" .. dataStoreId .. "] INIT: Load. DataStore:GetAsync")
        end
        success, value, info = pcall(robloxDataStore.GetAsync, robloxDataStore, dataStoreKey)
        if IS_DEBUG_ENABLED == true then
            print("[" .. dataStoreId .. "] DONE: Load. DataStore:GetAsync. Took " .. os.clock() - sTime .. "s")
        end
        if success == true then
            break
        end
    end
    if success == false then
        return DATASTORE_RESPONSE_ERROR, value
    end
    if info == nil then
        dataStore.Metadata, dataStore.UserIds, dataStore.CreatedTime, dataStore.UpdatedTime, dataStore.DataStoreVersion = {}, {}, 0, 0, ""
    else
        dataStore.Metadata, dataStore.UserIds, dataStore.CreatedTime, dataStore.UpdatedTime, dataStore.DataStoreVersion = info:GetMetadata(), info:GetUserIds(), info.CreatedTime, info.UpdatedTime, info.Version
    end
    local metadataCompress = dataStore.Metadata.Compress
    if type(metadataCompress) ~= "table" then
        dataStore.Value = value
    else
        dataStore.CompressedValue = value
        local decimals = COMPRESSION_DECIMAL_BASE ^ (metadataCompress.Decimals or DEFAULT_DECIMAL_PRECISION)
        dataStore.Value = Decompress(dataStore.CompressedValue, decimals)
    end
    return DATASTORE_RESPONSE_SUCCESS
end

Save = function(dataStore, attempts)
    local deltaTime = os.clock() - dataStore.SaveTime
    local dataStoreSaveDelay = dataStore.SaveDelay
    if deltaTime < dataStoreSaveDelay then
        task.wait(dataStoreSaveDelay - deltaTime)
    end
    local dataStoreValue = dataStore.Value
    dataStore.Saving:Fire(dataStoreValue, dataStore)
    local success, value = nil, nil
    local robloxDataStore = dataStore.DataStore
    local dataStoreId = dataStore.Id
    local dataStoreMetadata = dataStore.Metadata
    local metadataCompress = dataStoreMetadata.Compress
    local signalSaved = dataStore.Saved
    local dataStoreKey = dataStore.Key
    if dataStoreValue == nil then
        for i = 1, attempts do
            if i > 1 then
                task.wait(ASYNC_OPERATION_RETRY_WAIT_TIME)
            end
            local sTime = os.clock()
            if IS_DEBUG_ENABLED == true then
                print("[" .. dataStoreId .. "] INIT: Save. DataStore:RemoveAsync")
            end
            success, value = pcall(robloxDataStore.RemoveAsync, robloxDataStore, dataStoreKey)
            if IS_DEBUG_ENABLED == true then
                print("[" .. dataStoreId .. "] DONE: Save. DataStore:RemoveAsync. Took " .. os.clock() - sTime .. "s")
            end
            if success == true then
                break
            end
        end
        if success == false then
            signalSaved:Fire(DATASTORE_RESPONSE_ERROR, value, dataStore)
            return DATASTORE_RESPONSE_ERROR, value
        end
        dataStore.Metadata, dataStore.UserIds, dataStore.CreatedTime, dataStore.UpdatedTime, dataStore.DataStoreVersion = {}, {}, 0, 0, ""
    elseif type(metadataCompress) ~= "table" then
        local dataStoreUserIds = dataStore.UserIds
        local dataStoreDataStoreSetOptions = dataStore.DataStoreSetOptions
        dataStoreDataStoreSetOptions:SetMetadata(dataStoreMetadata)
        for i = 1, attempts do
            if i > 1 then
                task.wait(ASYNC_OPERATION_RETRY_WAIT_TIME)
            end
            local sTime = os.clock()
            if IS_DEBUG_ENABLED == true then
                print("[" .. dataStoreId .. "] INIT: Save. DataStore:SetAsync")
            end
            success, value = pcall(robloxDataStore.SetAsync, robloxDataStore, dataStoreKey, dataStoreValue, dataStoreUserIds, dataStoreDataStoreSetOptions)
            if IS_DEBUG_ENABLED == true then
                print("[" .. dataStoreId .. "] DONE: Save. DataStore:SetAsync. Took " .. os.clock() - sTime .. "s")
            end
            if success == true then
                break
            end
        end
        if success == false then
            signalSaved:Fire(DATASTORE_RESPONSE_ERROR, value, dataStore)
            return DATASTORE_RESPONSE_ERROR, value
        end
        dataStore.DataStoreVersion = value
    else
        local level = metadataCompress.Level or DEFAULT_COMPRESSION_LEVEL
        local decimals = COMPRESSION_DECIMAL_BASE ^ (metadataCompress.Decimals or DEFAULT_DECIMAL_PRECISION)
        local compressSafety = metadataCompress.Safety
        local isSafetyEnabled = if compressSafety == nil then true else compressSafety
        dataStore.CompressedValue = Compress(dataStoreValue, level, decimals, isSafetyEnabled)
        local dataStoreUserIds = dataStore.UserIds
        local dataStoreDataStoreSetOptions = dataStore.DataStoreSetOptions
        dataStoreDataStoreSetOptions:SetMetadata(dataStoreMetadata)
        for i = 1, attempts do
            if i > 1 then
                task.wait(ASYNC_OPERATION_RETRY_WAIT_TIME)
            end
            local sTime = os.clock()
            if IS_DEBUG_ENABLED == true then
                print("[" .. dataStoreId .. "] INIT: Save. DataStore:SetAsync")
            end
            success, value = pcall(robloxDataStore.SetAsync, robloxDataStore, dataStoreKey, dataStore.CompressedValue, dataStoreUserIds, dataStoreDataStoreSetOptions)
            if IS_DEBUG_ENABLED == true then
                print("[" .. dataStoreId .. "] DONE: Save. DataStore:SetAsync. Took " .. os.clock() - sTime .. "s")
            end
            if success == true then
                break
            end
        end
        if success == false then
            signalSaved:Fire(DATASTORE_RESPONSE_ERROR, value, dataStore)
            return DATASTORE_RESPONSE_ERROR, value
        end
        dataStore.DataStoreVersion = value
    end
    dataStore.SaveTime = os.clock()
    signalSaved:Fire(DATASTORE_RESPONSE_SAVED, dataStoreValue, dataStore)
    return DATASTORE_RESPONSE_SAVED, dataStoreValue
end

Clone = function(originalValue)
    if type(originalValue) ~= "table" then
        return originalValue
    end
    local dictionary = {}
    for key, value in pairs(originalValue) do
        dictionary[key] = Clone(value)
    end
    return dictionary
end

Reconcile = function(target, template)
    for key, value in pairs(template) do
        if type(key) == "number" then
            continue
        end
        local targetValue = target[key]
        if targetValue == nil then
            target[key] = Clone(value)
            continue
        end
        if type(targetValue) == "table" and type(value) == "table" then
            Reconcile(target[key], value)
        end
    end
end

Compress = function(value, level, decimals, safety)
    local data = {}
    if type(value) == "boolean" then
        table.insert(data, if value == false then "-" else "+")
    elseif type(value) == "number" then
        if value % 1 == 0 then
            table.insert(data, if value < 0 then "<" .. Encode(-value) else ">" .. Encode(value))
        else
            table.insert(data, if value < 0 then "(" .. Encode(math.round(-value * decimals)) else ")" .. Encode(math.round(value * decimals)))
        end
    elseif type(value) == "string" then
        if safety == true then
            value = value:gsub("", " ")
        end
        table.insert(data, "#" .. value .. "")
    elseif type(value) == "table" then
        if #value > 0 and level == 2 then
            table.insert(data, "|")
            for i = 1, #value do
                table.insert(data, Compress(value[i], level, decimals, safety))
            end
            table.insert(data, "")
        else
            table.insert(data, "*")
            for key, tableValue in value do
                table.insert(data, Compress(key, level, decimals, safety))
                table.insert(data, Compress(tableValue, level, decimals, safety))
            end
            table.insert(data, "")
        end
    end
    return table.concat(data)
end

Decompress = function(value, decimals, index)
    local i1, i2, dataType, data = value:find("([-+<>()#|*])", index or 1)
    if dataType == "-" then
        return false, i2
    elseif dataType == "+" then
        return true, i2
    elseif dataType == "<" then
        i1, i2, data = value:find("([^-+<>()#|*]*)", i2 + 1)
        return -Decode(data), i2
    elseif dataType == ">" then
        i1, i2, data = value:find("([^-+<>()#|*]*)", i2 + 1)
        return Decode(data), i2
    elseif dataType == "(" then
        i1, i2, data = value:find("([^-+<>()#|*]*)", i2 + 1)
        return -Decode(data) / decimals, i2
    elseif dataType == ")" then
        i1, i2, data = value:find("([^-+<>()#|*]*)", i2 + 1)
        return Decode(data) / decimals, i2
    elseif dataType == "#" then
        i1, i2, data = value:find("(.-)", i2 + 1)
        return data, i2
    elseif dataType == "|" then
        local array = {}
        while true do
            data, i2 = Decompress(value, decimals, i2 + 1)
            if data == nil then
                break
            end
            table.insert(array, data)
        end
        return array, i2
    elseif dataType == "*" then
        local dictionary, key = {}, nil
        while true do
            key, i2 = Decompress(value, decimals, i2 + 1)
            if key == nil then
                break
            end
            data, i2 = Decompress(value, decimals, i2 + 1)
            dictionary[key] = data
        end
        return dictionary, i2
    end
    return nil, i2
end

Encode = function(value)
    if value == 0 then
        return "0"
    end
    local data = {}
    while value > 0 do
        table.insert(data, baseCharacters[value % baseLength])
        value = math.floor(value / baseLength)
    end
    return table.concat(data)
end

Decode = function(value)
    local number, power, data = 0, 1, { string.byte(value, 1, #value) }
    for i, code in pairs(data) do
        number += charValues[code] * power
        power *= baseLength
    end
    return number
end

StartSaveTimer = function(dataStore)
    local dataStoreSaveThread = dataStore.SaveThread
    if dataStoreSaveThread ~= nil then
        task.cancel(dataStoreSaveThread)
    end
    if dataStore.SaveInterval == 0 then
        return
    end
    dataStore.SaveThread = task.delay(dataStore.SaveInterval, onSaveTimerEnded, dataStore)
end

StartLockTimer = function(dataStore)
    local dataStoreLockThread = dataStore.LockThread
    if dataStoreLockThread ~= nil then
        task.cancel(dataStoreLockThread)
    end
    local dataStoreActiveLockInterval = dataStore.ActiveLockInterval
    local startTime = dataStore.LockTime - dataStore.AttemptsRemaining * dataStoreActiveLockInterval
    dataStore.LockThread = task.delay(startTime - os.clock() + dataStoreActiveLockInterval, onLockTimerEnded, dataStore)
end

StopSaveTimer = function(dataStore)
    local dataStoreSaveThread = dataStore.SaveThread
    if dataStoreSaveThread == nil then
        return
    end
    task.cancel(dataStoreSaveThread)
    dataStore.SaveThread = nil
end

StopLockTimer = function(dataStore)
    local dataStoreLockThread = dataStore.LockThread
    if dataStoreLockThread == nil then
        return
    end
    task.cancel(dataStoreLockThread)
    dataStore.LockThread = nil
end

onProcessQueueConnected = function(isConnected, signal)
    if isConnected == false then
        return
    end
    ProcessQueueTask(signal.dataStore)
end

onSaveTimerEnded = function(dataStore)
    dataStore.SaveThread = nil
    local taskManager = dataStore.TaskManager
    if taskManager:FindLast(SaveTask) ~= nil then
        return
    end
    taskManager:InsertBack(SaveTask, dataStore)
end

onLockTimerEnded = function(dataStore)
    dataStore.LockThread = nil
    local taskManager = dataStore.TaskManager
    if taskManager:FindFirst(LockTask) ~= nil then
        return
    end
    taskManager:InsertBack(LockTask, dataStore)
end

onBindToClose = function()
    local sTime = os.clock()
    if IS_DEBUG_ENABLED == true then
        print("[" .. scriptName .. "] INIT: onBindToClose")
    end
    isModuleActive = false
    for lockId, dataStore in pairs(bindToCloseDataStores) do
        if dataStore.State == nil then
            continue
        end
        activeDataStores[dataStore.Id] = nil
        StopLockTimer(dataStore)
        StopSaveTimer(dataStore)
        local taskManager = dataStore.TaskManager
        if taskManager:FindFirst(DestroyTask) ~= nil then
            continue
        end
        taskManager:InsertBack(DestroyTask, dataStore)
    end
    while next(bindToCloseDataStores) ~= nil do
        task.wait()
    end
    for dataStoreId, activeRobloxDataStore in pairs(activeRobloxDataStores) do
        activeRobloxDataStores[dataStoreId] = nil
    end
    while next(activeRobloxDataStores) ~= nil do
        task.wait()
    end
    if IS_DEBUG_ENABLED == true then
        print("[" .. scriptName .. "] DONE: onBindToClose. Took " .. os.clock() - sTime .. "s")
    end
end

game:BindToClose(onBindToClose)

DataStoreModule.new = DataStoreModuleNew
DataStoreModule.hidden = DataStoreModuleHidden
DataStoreModule.find = DataStoreModuleFind
DataStoreModule.Response = DataStoreModuleResponse
return DataStoreModule :: DataStoreModule
