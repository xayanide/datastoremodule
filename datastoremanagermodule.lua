--[[
@xayanide
A fork of SDM v1.3 (That was last updated on October 28, 2023 UTC+8)

For list of general changelog, please see _README
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
local DEFAULT_DATSTORE_MANAGER_SAVE_INTERVAL = 30
local DEFAULT_DATSTORE_MANAGER_SAVE_DELAY = 0
local DEFAULT_DATSTORE_MANAGER_LOCK_INTERVAL = 60
local DEFAULT_DATSTORE_MANAGER_LOCK_ATTEMPTS = 5
local DEFAULT_DATSTORE_MANAGER_SAVE_ON_CLOSE = true

local DEFAULT_MEMORYSTOREQUEUE_ADD_ITEM_EXPIRE_TIME = 604800
local DATASTORE_MANAGER_MIN_SAVE_INTERVAL = 10
local DATASTORE_MANAGER_MAX_SAVE_INTERVAL = 1000
local DATASTORE_MANAGER_RESPONSE_STATE = "State"
local DATASTORE_MANAGER_STATE_DESTROYED = "Destroyed"
local DATASTORE_MANAGER_STATE_DESTROYING = "Destroying"
local DATASTORE_MANAGER_STATE_OPEN = "Open"
local DATASTORE_MANAGER_STATE_CLOSED = "Closed"
local DATASTORE_MANAGER_STATE_CLOSING = "Closing"
local DATASTORE_MANAGER_RESPONSE_SUCCESS = "Success"
local DATASTORE_MANAGER_RESPONSE_SAVED = "Saved"
local DATASTORE_MANAGER_RESPONSE_LOCKED = "Locked"
local DATASTORE_MANAGER_RESPONSE_ERROR = "Error"
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

local DataStoreManagerModule = {}
local scriptName = script.Name
local isModuleActive = true
local activeDataStores = {}
local activeDataStoreManagers, bindToCloseDataStoreManagers = {}, {}
local DataStoreManagerModuleNew, DataStoreManagerModuleHidden, DataStoreManagerModuleFind, DataStoreManagerModuleResponse
local DataStoreManagerMethodOpen, DataStoreManagerMethodRead, DataStoreManagerMethodSave, DataStoreManagerMethodClose, DataStoreManagerMethodDestroy, DataStoreManagerMethodQueue, DataStoreManagerMethodRemove, DataStoreManagerMethodClone, DataStoreManagerMethodReconcile, DataStoreManagerMethodUsage, DataStoreManagerMethodSetSaveInterval
local OpenTask, ReadTask, LockTask, SaveTask, CloseTask, DestroyTask, ProcessQueueTask
local Lock, Unlock, Load, Save
local Clone, Reconcile
local Compress, Decompress
local Encode, Decode
local StartSaveTimer, StopSaveTimer
local StartLockTimer, StopLockTimer
local onProcessQueueConnected, onSaveTimerEnded, onLockTimerEnded, onBindToClose
local getActiveDataStore, createDataStoreManager, getManagerId

local baseCharacters = { [0] = "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "!", "$", "%", "&", "'", ",", ".", "/", ":", ";", "=", "?", "@", "[", "]", "^", "_", "`", "{", "}", "~" }
local baseLength = #baseCharacters + LUA_ARRAY_LENGTH_OFFSET
local charValues = {}
for i = (0), #baseCharacters do
    charValues[string.byte(baseCharacters[i])] = i
end

export type DataStoreManagerModule = {
    new: (name: string, scope: string, key: string?) -> DataStoreManager,
    hidden: (name: string, scope: string, key: string?) -> DataStoreManager,
    find: (name: string, scope: string, key: string?) -> DataStoreManager?,
    Response: {
        Success: string,
        Saved: string,
        Locked: string,
        State: string,
        Error: string,
    },
}

export type DataStoreManager = {
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
    StateChanged: SignalModule.SignalModul,
    Saving: SignalModule.Signal,
    Saved: SignalModule.Signal,
    AttemptsChanged: SignalModule.Signal,
    ProcessQueue: SignalModule.Signal & { dataStoreManager: DataStoreManager, Connected: (isConnected: boolean, signal: SignalModule.Signal) -> any },
    Open: (self: DataStoreManager, template: any?) -> (string, any),
    Read: (self: DataStoreManager, template: any?) -> (string, any),
    Save: (self: DataStoreManager) -> (string, any),
    Close: (self: DataStoreManager) -> (string, any),
    Destroy: (self: DataStoreManager) -> (string, any),
    Queue: (self: DataStoreManager, value: any, expiration: number?, priority: number?) -> (string, any),
    Remove: (self: DataStoreManager, id: string) -> (string, any),
    Clone: (self: DataStoreManager) -> any,
    Reconcile: (self: DataStoreManager, template: any) -> (),
    Usage: (self: DataStoreManager) -> (number, number),
    SetSaveInterval: (self: DataStoreManager, value: number) -> (),
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

export type DataStore = DataStoreManager

getActiveDataStore = function(name, scope)
    local dataStoreId = name .. "/" .. scope
    local activeDataStore = activeDataStores[dataStoreId]
    if activeDataStore ~= nil then
        return activeDataStore
    end
    local dataStore = DataStoreService:GetDataStore(name, scope)
    activeDataStores[dataStoreId] = dataStore
    return dataStore
end

createDataStoreManager = function(name, scope, key, managerId, isHidden)
    local dataStoreManager = {
        Value = nil,
        Metadata = {},
        UserIds = {},
        SaveInterval = DEFAULT_DATSTORE_MANAGER_SAVE_INTERVAL,
        SaveDelay = DEFAULT_DATSTORE_MANAGER_SAVE_DELAY,
        LockInterval = DEFAULT_DATSTORE_MANAGER_LOCK_INTERVAL,
        LockAttempts = DEFAULT_DATSTORE_MANAGER_LOCK_ATTEMPTS,
        SaveOnClose = DEFAULT_DATSTORE_MANAGER_SAVE_ON_CLOSE,
        Id = managerId,
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
        Open = DataStoreManagerMethodOpen,
        Read = DataStoreManagerMethodRead,
        Save = DataStoreManagerMethodSave,
        Close = DataStoreManagerMethodClose,
        Destroy = DataStoreManagerMethodDestroy,
        Queue = DataStoreManagerMethodQueue,
        Remove = DataStoreManagerMethodRemove,
        Clone = DataStoreManagerMethodClone,
        Reconcile = DataStoreManagerMethodReconcile,
        Usage = DataStoreManagerMethodUsage,
        SetSaveInterval = DataStoreManagerMethodSetSaveInterval,
        SaveThread = nil,
        LockThread = nil,
        TaskManager = SyncTaskManagerModule.new(),
        LockTime = -math.huge,
        SaveTime = -math.huge,
        ActiveLockInterval = 0,
        ProcessingQueue = false,
        DataStore = getActiveDataStore(name, scope),
        DataStoreSetOptions = Instance.new("DataStoreSetOptions"),
        MemoryStoreSortedMap = MemoryStoreService:GetSortedMap(managerId),
        MemoryStoreQueue = MemoryStoreService:GetQueue(managerId),
    }
    dataStoreManager.ProcessQueue.dataStoreManager = dataStoreManager
    dataStoreManager.ProcessQueue.Connected = onProcessQueueConnected
    return dataStoreManager
end

getManagerId = function(name, scope, key)
    return name .. "/" .. scope .. "/" .. key
end

DataStoreManagerModuleNew = function(name, scope, key)
    if key == nil then
        key, scope = scope, DATASTORE_GLOBAL_SCOPE
    end
    local managerId = getManagerId(name, scope, key)
    local activeDataStoreManager = activeDataStoreManagers[managerId]
    if activeDataStoreManager ~= nil then
        return activeDataStoreManager
    end
    local dataStoreManager = createDataStoreManager(name, scope, key, managerId, false)
    activeDataStoreManagers[managerId] = dataStoreManager
    return dataStoreManager
end

DataStoreManagerModuleHidden = function(name, scope, key)
    if key == nil then
        key, scope = scope, DATASTORE_GLOBAL_SCOPE
    end
    local managerId = getManagerId(name, scope, key)
    return createDataStoreManager(name, scope, key, managerId, true)
end

DataStoreManagerModuleFind = function(name, scope, key)
    if key == nil then
        key, scope = scope, DATASTORE_GLOBAL_SCOPE
    end
    local managerId = getManagerId(name, scope, key)
    return activeDataStoreManagers[managerId]
end

DataStoreManagerModuleResponse = {
    Success = DATASTORE_MANAGER_RESPONSE_SUCCESS,
    Saved = DATASTORE_MANAGER_RESPONSE_SAVED,
    Locked = DATASTORE_MANAGER_RESPONSE_LOCKED,
    State = DATASTORE_MANAGER_RESPONSE_STATE,
    Error = DATASTORE_MANAGER_RESPONSE_ERROR,
}

DataStoreManagerMethodOpen = function(dataStoreManager, template)
    local dataStoreManagerState = dataStoreManager.State
    if dataStoreManagerState == nil then
        return DATASTORE_MANAGER_RESPONSE_STATE, DATASTORE_MANAGER_STATE_DESTROYED
    end
    local taskManager = dataStoreManager.TaskManager
    local firstSyncOpenTask = taskManager:FindFirst(OpenTask)
    if firstSyncOpenTask ~= nil then
        return firstSyncOpenTask:Wait(template)
    end
    if taskManager:FindLast(DestroyTask) ~= nil then
        return DATASTORE_MANAGER_RESPONSE_STATE, DATASTORE_MANAGER_STATE_DESTROYING
    end
    if dataStoreManagerState == true and taskManager:FindLast(CloseTask) == nil then
        local dataStoreManagerValue = dataStoreManager.Value
        if dataStoreManagerValue == nil then
            dataStoreManager.Value = Clone(template)
        elseif type(dataStoreManagerValue) == "table" and type(template) == "table" then
            Reconcile(dataStoreManager.Value, template)
        end
        return DATASTORE_MANAGER_RESPONSE_SUCCESS
    end
    return taskManager:InsertBack(OpenTask, dataStoreManager):Wait(template)
end

DataStoreManagerMethodRead = function(dataStoreManager, template)
    local taskManager = dataStoreManager.TaskManager
    local firstSyncReadTask = taskManager:FindFirst(ReadTask)
    if firstSyncReadTask ~= nil then
        return firstSyncReadTask:Wait(template)
    end
    if dataStoreManager.State == true and taskManager:FindLast(CloseTask) == nil then
        return DATASTORE_MANAGER_RESPONSE_STATE, DATASTORE_MANAGER_STATE_OPEN
    end
    return taskManager:InsertBack(ReadTask, dataStoreManager):Wait(template)
end

DataStoreManagerMethodSave = function(dataStoreManager)
    local dataStoreManagerState = dataStoreManager.State
    if dataStoreManagerState == false then
        return DATASTORE_MANAGER_RESPONSE_STATE, DATASTORE_MANAGER_STATE_CLOSED
    end
    if dataStoreManagerState == nil then
        return DATASTORE_MANAGER_RESPONSE_STATE, DATASTORE_MANAGER_STATE_DESTROYED
    end
    local taskManager = dataStoreManager.TaskManager
    local firstSyncSaveTask = taskManager:FindFirst(SaveTask)
    if firstSyncSaveTask ~= nil then
        return firstSyncSaveTask:Wait()
    end
    if taskManager:FindLast(CloseTask) ~= nil then
        return DATASTORE_MANAGER_RESPONSE_STATE, DATASTORE_MANAGER_STATE_CLOSING
    end
    if taskManager:FindLast(DestroyTask) ~= nil then
        return DATASTORE_MANAGER_RESPONSE_STATE, DATASTORE_MANAGER_STATE_DESTROYING
    end
    return taskManager:InsertBack(SaveTask, dataStoreManager):Wait()
end

DataStoreManagerMethodClose = function(dataStoreManager)
    local dataStoreManagerState = dataStoreManager.State
    if dataStoreManagerState == nil then
        return DATASTORE_MANAGER_RESPONSE_SUCCESS
    end
    local taskManager = dataStoreManager.TaskManager
    local firstSyncCloseTask = taskManager:FindFirst(CloseTask)
    if firstSyncCloseTask ~= nil then
        return firstSyncCloseTask:Wait()
    end
    if dataStoreManagerState == false and taskManager:FindLast(OpenTask) == nil then
        return DATASTORE_MANAGER_RESPONSE_SUCCESS
    end
    local firstSyncDestroyTask = taskManager:FindFirst(DestroyTask)
    if firstSyncDestroyTask ~= nil then
        return firstSyncDestroyTask:Wait()
    end
    StopLockTimer(dataStoreManager)
    StopSaveTimer(dataStoreManager)
    return taskManager:InsertBack(CloseTask, dataStoreManager):Wait()
end

DataStoreManagerMethodDestroy = function(dataStoreManager)
    if dataStoreManager.State == nil then
        return DATASTORE_MANAGER_RESPONSE_SUCCESS
    end
    activeDataStoreManagers[dataStoreManager.Id] = nil
    StopLockTimer(dataStoreManager)
    StopSaveTimer(dataStoreManager)
    local taskManager = dataStoreManager.TaskManager
    local firstSyncDestroyTask = taskManager:FindFirst(DestroyTask)
    local syncDestroyTask = if firstSyncDestroyTask ~= nil then firstSyncDestroyTask else taskManager:InsertBack(DestroyTask, dataStoreManager)
    return syncDestroyTask:Wait()
end

DataStoreManagerMethodQueue = function(dataStoreManager, queueValue, expiration, priority)
    if expiration ~= nil and type(expiration) ~= "number" then
        error("Attempt to AddQueue failed: Passed value is not nil or number", 3)
    end
    if priority ~= nil and type(priority) ~= "number" then
        error("Attempt to AddQueue failed: Passed value is not nil or number", 3)
    end
    local success, value
    local memoryStoreQueue = dataStoreManager.MemoryStoreQueue
    local dataStoreManagerId = dataStoreManager.Id
    for i = 1, MEMORYSTOREQUEUE_ADD_MAX_ATTEMPTS do
        if i > 1 then
            task.wait(ASYNC_OPERATION_RETRY_WAIT_TIME)
        end
        local sTime = os.clock()
        if IS_DEBUG_ENABLED == true then
            print("[" .. dataStoreManagerId .. "] INIT: Queue. MemoryStoreQueue:AddAsync")
        end
        success, value = pcall(memoryStoreQueue.AddAsync, memoryStoreQueue, queueValue, expiration or DEFAULT_MEMORYSTOREQUEUE_ADD_ITEM_EXPIRE_TIME, priority)
        if IS_DEBUG_ENABLED == true then
            print("[" .. dataStoreManagerId .. "] DONE: Queue. MemoryStoreQueue:AddAsync. Took " .. os.clock() - sTime .. "s")
        end
        if success == true then
            return DATASTORE_MANAGER_RESPONSE_SUCCESS
        end
    end
    return DATASTORE_MANAGER_RESPONSE_ERROR, value
end

DataStoreManagerMethodRemove = function(dataStoreManager, id)
    if type(id) ~= "string" then
        error("Attempt to RemoveQueue failed: Passed value is not a string", 3)
    end
    local success, value
    local memoryStoreQueue = dataStoreManager.MemoryStoreQueue
    local dataStoreManagerId = dataStoreManager.Id
    for i = 1, MEMORYSTOREQUEUE_REMOVE_MAX_ATTEMPTS do
        if i > 1 then
            task.wait(ASYNC_OPERATION_RETRY_WAIT_TIME)
        end
        local sTime = os.clock()
        if IS_DEBUG_ENABLED == true then
            print("[" .. dataStoreManagerId .. "] INIT: Remove. MemoryStoreQueue:RemoveAsync")
        end
        success, value = pcall(memoryStoreQueue.RemoveAsync, memoryStoreQueue, id)
        if IS_DEBUG_ENABLED == true then
            print("[" .. dataStoreManagerId .. "] DONE: Remove. MemoryStoreQueue:RemoveAsync. Took " .. os.clock() - sTime .. "s")
        end
        if success == true then
            return DATASTORE_MANAGER_RESPONSE_SUCCESS
        end
    end
    return DATASTORE_MANAGER_RESPONSE_ERROR, value
end

DataStoreManagerMethodClone = function(dataStoreManager)
    return Clone(dataStoreManager.Value)
end

DataStoreManagerMethodReconcile = function(dataStoreManager, template)
    local dataStoreManagerValue = dataStoreManager.Value
    if dataStoreManagerValue == nil then
        dataStoreManager.Value = Clone(template)
        return
    end
    if type(dataStoreManagerValue) == "table" and type(template) == "table" then
        Reconcile(dataStoreManager.Value, template)
    end
end

DataStoreManagerMethodUsage = function(dataStoreManager)
    local dataStoreManagerValue = dataStoreManager.Value
    if dataStoreManagerValue == nil then
        return 0, 0
    end
    local metadataCompress = dataStoreManager.Metadata.Compress
    if type(metadataCompress) ~= "table" then
        local strLength = #HttpService:JSONEncode(dataStoreManagerValue)
        return strLength, strLength / DATASTORE_MAX_ENTRY_SIZE
    end
    local level = metadataCompress.Level or DEFAULT_COMPRESSION_LEVEL
    local decimals = COMPRESSION_DECIMAL_BASE ^ (metadataCompress.Decimals or DEFAULT_DECIMAL_PRECISION)
    local compressSafety = metadataCompress.Safety
    local isSafetyEnabled = if compressSafety == nil then true else compressSafety
    dataStoreManager.CompressedValue = Compress(dataStoreManagerValue, level, decimals, isSafetyEnabled)
    local strLength = #HttpService:JSONEncode(dataStoreManager.CompressedValue)
    return strLength, strLength / DATASTORE_MAX_ENTRY_SIZE
end

DataStoreManagerMethodSetSaveInterval = function(dataStoreManager, value)
    if type(value) ~= "number" then
        error("Attempt to set SaveInterval failed: Passed value is not a number", 3)
    end
    if value < DATASTORE_MANAGER_MIN_SAVE_INTERVAL and value ~= 0 then
        error("Attempt to set SaveInterval failed: Passed value is less then 10 and not 0", 3)
    end
    if value > DATASTORE_MANAGER_MAX_SAVE_INTERVAL then
        error("Attempt to set SaveInterval failed: Passed value is more then 1000", 3)
    end
    if value == dataStoreManager.SaveInterval then
        return
    end
    dataStoreManager.SaveInterval = value
    if value == 0 then
        StopSaveTimer(dataStoreManager)
        return
    end
    StartSaveTimer(dataStoreManager)
end

OpenTask = function(runningTask, dataStoreManager)
    local lockResponse, lockResponseData = Lock(dataStoreManager, MEMORYSTORESORTEDMAP_SESSION_LOCK_MAX_ATTEMPTS)
    if lockResponse ~= DATASTORE_MANAGER_RESPONSE_SUCCESS then
        for thread in runningTask:Iterate() do
            task.defer(thread, lockResponse, lockResponseData)
        end
        return
    end
    local loadResponse, loadResponseData = Load(dataStoreManager, DATASTORE_LOAD_MAX_ATTEMPTS)
    if loadResponse ~= DATASTORE_MANAGER_RESPONSE_SUCCESS then
        Unlock(dataStoreManager, MEMORYSTORESORTEDMAP_SESSION_UNLOCK_MAX_ATTEMPTS)
        for thread in runningTask:Iterate() do
            task.defer(thread, loadResponse, loadResponseData)
        end
        return
    end
    local dataStoreManagerLockId = dataStoreManager.LockId
    if isModuleActive == true then
        bindToCloseDataStoreManagers[dataStoreManagerLockId] = dataStoreManager
    end
    dataStoreManager.State = true
    local taskManager = dataStoreManager.TaskManager
    if taskManager:FindLast(CloseTask) == nil and taskManager:FindLast(DestroyTask) == nil then
        StartSaveTimer(dataStoreManager)
        StartLockTimer(dataStoreManager)
    end
    local dataStoreManagerValue = dataStoreManager.Value
    for thread, template in runningTask:Iterate() do
        if dataStoreManagerValue == nil then
            dataStoreManager.Value = Clone(template)
        elseif type(dataStoreManagerValue) == "table" and type(template) == "table" then
            Reconcile(dataStoreManager.Value, template)
        end
        task.defer(thread, loadResponse, dataStoreManagerLockId)
    end
    if dataStoreManager.ProcessingQueue == false and dataStoreManager.ProcessQueue.Connections > 0 then
        task.defer(ProcessQueueTask, dataStoreManager)
    end
    dataStoreManager.StateChanged:Fire(true, dataStoreManager)
end

ReadTask = function(runningTask, dataStoreManager)
    if dataStoreManager.State == true then
        for thread in runningTask:Iterate() do
            task.defer(thread, DATASTORE_MANAGER_RESPONSE_STATE, DATASTORE_MANAGER_STATE_OPEN)
        end
        return
    end
    local response, responseData = Load(dataStoreManager, DATASTORE_LOAD_MAX_ATTEMPTS)
    if response ~= DATASTORE_MANAGER_RESPONSE_SUCCESS then
        for thread in runningTask:Iterate() do
            task.defer(thread, response, responseData)
        end
        return
    end
    local dataStoreManagerValue = dataStoreManager.Value
    for thread, template in runningTask:Iterate() do
        if dataStoreManagerValue == nil then
            dataStoreManager.Value = Clone(template)
        elseif type(dataStoreManagerValue) == "table" and type(template) == "table" then
            Reconcile(dataStoreManager.Value, template)
        end
        task.defer(thread, response)
    end
end

LockTask = function(runningTask, dataStoreManager)
    local previousAttemptsRemaining = dataStoreManager.AttemptsRemaining
    local response, responseData = Lock(dataStoreManager, MEMORYSTORESORTEDMAP_SESSION_LOCK_MAX_ATTEMPTS)
    if response ~= DATASTORE_MANAGER_RESPONSE_SUCCESS then
        dataStoreManager.AttemptsRemaining -= 1
    end
    local currentAttemptsRemaining = dataStoreManager.AttemptsRemaining
    if currentAttemptsRemaining ~= previousAttemptsRemaining then
        dataStoreManager.AttemptsChanged:Fire(currentAttemptsRemaining, dataStoreManager)
    end
    local taskManager = dataStoreManager.TaskManager
    if currentAttemptsRemaining > 0 then
        if taskManager:FindLast(CloseTask) == nil and taskManager:FindLast(DestroyTask) == nil then
            StartLockTimer(dataStoreManager)
        end
    else
        dataStoreManager.State = false
        StopLockTimer(dataStoreManager)
        StopSaveTimer(dataStoreManager)
        if dataStoreManager.SaveOnClose == true then
            Save(dataStoreManager, DATASTORE_SAVE_MAX_ATTEMPTS)
        end
        Unlock(dataStoreManager, MEMORYSTORESORTEDMAP_SESSION_UNLOCK_MAX_ATTEMPTS)
        dataStoreManager.StateChanged:Fire(false, dataStoreManager)
    end
    return response, responseData
end

SaveTask = function(runningTask, dataStoreManager)
    if dataStoreManager.State == false then
        for thread in runningTask:Iterate() do
            task.defer(thread, DATASTORE_MANAGER_RESPONSE_STATE, DATASTORE_MANAGER_STATE_CLOSED)
        end
        return
    end
    StopSaveTimer(dataStoreManager)
    runningTask:End()
    local response, responseData = Save(dataStoreManager, DATASTORE_SAVE_MAX_ATTEMPTS)
    local taskManager = dataStoreManager.TaskManager
    if taskManager:FindLast(CloseTask) == nil and taskManager:FindLast(DestroyTask) == nil then
        StartSaveTimer(dataStoreManager)
    end
    for thread in runningTask:Iterate() do
        task.defer(thread, response, responseData)
    end
end

CloseTask = function(runningTask, dataStoreManager)
    if dataStoreManager.State == false then
        for thread in runningTask:Iterate() do
            task.defer(thread, DATASTORE_MANAGER_RESPONSE_SUCCESS)
        end
        return
    end
    dataStoreManager.State = false
    local response, responseData = nil, nil
    if dataStoreManager.SaveOnClose == true then
        response, responseData = Save(dataStoreManager, DATASTORE_SAVE_MAX_ATTEMPTS)
    end
    Unlock(dataStoreManager, MEMORYSTORESORTEDMAP_SESSION_UNLOCK_MAX_ATTEMPTS)
    dataStoreManager.StateChanged:Fire(false, dataStoreManager)
    if response == DATASTORE_MANAGER_RESPONSE_SAVED then
        for thread in runningTask:Iterate() do
            task.defer(thread, response, responseData)
        end
        return
    end
    for thread in runningTask:Iterate() do
        task.defer(thread, DATASTORE_MANAGER_RESPONSE_SUCCESS)
    end
end

DestroyTask = function(runningTask, dataStoreManager)
    local response, responseData = nil, nil
    if dataStoreManager.State == false then
        dataStoreManager.State = nil
    else
        dataStoreManager.State = nil
        if dataStoreManager.SaveOnClose == true then
            response, responseData = Save(dataStoreManager, DATASTORE_SAVE_MAX_ATTEMPTS)
        end
        Unlock(dataStoreManager, MEMORYSTORESORTEDMAP_SESSION_UNLOCK_MAX_ATTEMPTS)
    end
    local signalStateChanged = dataStoreManager.StateChanged
    signalStateChanged:Fire(nil, dataStoreManager)
    signalStateChanged:DisconnectAll()
    dataStoreManager.Saving:DisconnectAll()
    dataStoreManager.Saved:DisconnectAll()
    dataStoreManager.AttemptsChanged:DisconnectAll()
    dataStoreManager.ProcessQueue:DisconnectAll()
    bindToCloseDataStoreManagers[dataStoreManager.LockId] = nil
    if response == DATASTORE_MANAGER_RESPONSE_SAVED then
        for thread in runningTask:Iterate() do
            task.defer(thread, response, responseData)
        end
        return
    end
    for thread in runningTask:Iterate() do
        task.defer(thread, DATASTORE_MANAGER_RESPONSE_SUCCESS)
    end
end

ProcessQueueTask = function(dataStoreManager)
    if dataStoreManager.State ~= true then
        return
    end
    if dataStoreManager.ProcessQueue.Connections == 0 then
        return
    end
    if dataStoreManager.ProcessingQueue == true then
        return
    end
    dataStoreManager.ProcessingQueue = true
    local memoryStoreQueue = dataStoreManager.MemoryStoreQueue
    local dataStoreManagerId = dataStoreManager.Id
    while true do
        local sTime = os.clock()
        if IS_DEBUG_ENABLED == true then
            print("[" .. dataStoreManagerId .. "] INIT: ProcessQueueTask. MemoryStoreQueue:ReadAsync")
        end
        local success, items, id = pcall(memoryStoreQueue.ReadAsync, memoryStoreQueue, MEMORYSTOREQUEUE_READ_ITEM_COUNT, MEMORYSTOREQUEUE_READ_ALL_OR_NOTHING, MEMORYSTOREQUEUE_READ_WAIT_TIMEOUT)
        if IS_DEBUG_ENABLED == true then
            print("[" .. dataStoreManagerId .. "] DONE: ProcessQueueTask. MemoryStoreQueue:ReadAsync. Took " .. os.clock() - sTime .. "s")
        end
        if dataStoreManager.State ~= true then
            break
        end
        local signalProcessQueue = dataStoreManager.ProcessQueue
        if signalProcessQueue.Connections == 0 then
            break
        end
        if success == true and id ~= nil then
            signalProcessQueue:Fire(id, items, dataStoreManager)
        end
    end
    dataStoreManager.ProcessingQueue = false
end

Lock = function(dataStoreManager, attempts)
    local success, value, previousLockId, lockTime, lockInterval, lockAttempts = nil, nil, nil, nil, dataStoreManager.LockInterval, dataStoreManager.LockAttempts
    local lockExpireTime = lockInterval * lockAttempts + MEMORYSTORESORTEDMAP_SESSION_LOCK_EXPIRE_TIME_EXTRA
    local lockId = dataStoreManager.LockId
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
    local memoryStoreSortedMap = dataStoreManager.MemoryStoreSortedMap
    local dataStoreManagerId = dataStoreManager.Id
    for i = 1, attempts do
        if i > 1 then
            task.wait(ASYNC_OPERATION_RETRY_WAIT_TIME)
        end
        lockTime = os.clock()
        local sTime = os.clock()
        if IS_DEBUG_ENABLED == true then
            print("[" .. dataStoreManagerId .. "] INIT: Lock. MemoryStoreSortedMap:UpdateAsync")
        end
        success, value = pcall(memoryStoreSortedMap.UpdateAsync, memoryStoreSortedMap, MEMORYSTORESORTEDMAP_SESSION_LOCK_KEY, onLockUpdateAsync, lockExpireTime)
        if IS_DEBUG_ENABLED == true then
            print("[" .. dataStoreManagerId .. "] DONE: Lock. MemoryStoreSortedMap:UpdateAsync. Took " .. os.clock() - sTime .. "s")
        end
        if success == true then
            break
        end
    end
    if success == false then
        return DATASTORE_MANAGER_RESPONSE_ERROR, value
    end
    if value == nil then
        return DATASTORE_MANAGER_RESPONSE_LOCKED, previousLockId
    end
    dataStoreManager.LockTime = lockTime + lockInterval * lockAttempts
    dataStoreManager.ActiveLockInterval = lockInterval
    dataStoreManager.AttemptsRemaining = lockAttempts
    return DATASTORE_MANAGER_RESPONSE_SUCCESS
end

Unlock = function(dataStoreManager, attempts)
    local success, value, previousLockId = nil, nil, nil
    local lockExpireTime = 0
    local lockId = dataStoreManager.LockId
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
    local memoryStoreSortedMap = dataStoreManager.MemoryStoreSortedMap
    local dataStoreManagerId = dataStoreManager.Id
    for i = 1, attempts do
        if i > 1 then
            task.wait(ASYNC_OPERATION_RETRY_WAIT_TIME)
        end
        local sTime = os.clock()
        if IS_DEBUG_ENABLED == true then
            print("[" .. dataStoreManagerId .. "] INIT: Unlock. MemoryStoreSortedMap:UpdateAsync")
        end
        success, value = pcall(memoryStoreSortedMap.UpdateAsync, memoryStoreSortedMap, MEMORYSTORESORTEDMAP_SESSION_LOCK_KEY, onUnlockUpdateAsync, lockExpireTime)
        if IS_DEBUG_ENABLED == true then
            print("[" .. dataStoreManagerId .. "] DONE: Unlock. MemoryStoreSortedMap:UpdateAsync. Took " .. os.clock() - sTime .. "s")
        end
        if success == true then
            break
        end
    end
    if success == false then
        return DATASTORE_MANAGER_RESPONSE_ERROR, value
    end
    if value == nil and previousLockId ~= nil then
        return DATASTORE_MANAGER_RESPONSE_LOCKED, previousLockId
    end
    return DATASTORE_MANAGER_RESPONSE_SUCCESS
end

Load = function(dataStoreManager, attempts)
    local success, value, info = nil, nil, nil
    local dataStore = dataStoreManager.DataStore
    local dataStoreManagerId = dataStoreManager.Id
    local dataStoreManagerKey = dataStoreManager.Key
    for i = 1, attempts do
        if i > 1 then
            task.wait(ASYNC_OPERATION_RETRY_WAIT_TIME)
        end
        local sTime = os.clock()
        if IS_DEBUG_ENABLED == true then
            print("[" .. dataStoreManagerId .. "] INIT: Load. DataStore:GetAsync")
        end
        success, value, info = pcall(dataStore.GetAsync, dataStore, dataStoreManagerKey)
        if IS_DEBUG_ENABLED == true then
            print("[" .. dataStoreManagerId .. "] DONE: Load. DataStore:GetAsync. Took " .. os.clock() - sTime .. "s")
        end
        if success == true then
            break
        end
    end
    if success == false then
        return DATASTORE_MANAGER_RESPONSE_ERROR, value
    end
    if info == nil then
        dataStoreManager.Metadata, dataStoreManager.UserIds, dataStoreManager.CreatedTime, dataStoreManager.UpdatedTime, dataStoreManager.DataStoreVersion = {}, {}, 0, 0, ""
    else
        dataStoreManager.Metadata, dataStoreManager.UserIds, dataStoreManager.CreatedTime, dataStoreManager.UpdatedTime, dataStoreManager.DataStoreVersion = info:GetMetadata(), info:GetUserIds(), info.CreatedTime, info.UpdatedTime, info.Version
    end
    local metadataCompress = dataStoreManager.Metadata.Compress
    if type(metadataCompress) ~= "table" then
        dataStoreManager.Value = value
    else
        dataStoreManager.CompressedValue = value
        local decimals = COMPRESSION_DECIMAL_BASE ^ (metadataCompress.Decimals or DEFAULT_DECIMAL_PRECISION)
        dataStoreManager.Value = Decompress(dataStoreManager.CompressedValue, decimals)
    end
    return DATASTORE_MANAGER_RESPONSE_SUCCESS
end

Save = function(dataStoreManager, attempts)
    local deltaTime = os.clock() - dataStoreManager.SaveTime
    local dataStoreManagerSaveDelay = dataStoreManager.SaveDelay
    if deltaTime < dataStoreManagerSaveDelay then
        task.wait(dataStoreManagerSaveDelay - deltaTime)
    end
    local dataStoreManagerValue = dataStoreManager.Value
    dataStoreManager.Saving:Fire(dataStoreManagerValue, dataStoreManager)
    local success, value = nil, nil
    local dataStore = dataStoreManager.DataStore
    local dataStoreManagerId = dataStoreManager.Id
    local dataStoreManagerMetadata = dataStoreManager.Metadata
    local metadataCompress = dataStoreManagerMetadata.Compress
    local signalSaved = dataStoreManager.Saved
    local dataStoreManagerKey = dataStoreManager.Key
    if dataStoreManagerValue == nil then
        for i = 1, attempts do
            if i > 1 then
                task.wait(ASYNC_OPERATION_RETRY_WAIT_TIME)
            end
            local sTime = os.clock()
            if IS_DEBUG_ENABLED == true then
                print("[" .. dataStoreManagerId .. "] INIT: Save. DataStore:RemoveAsync")
            end
            success, value = pcall(dataStore.RemoveAsync, dataStore, dataStoreManagerKey)
            if IS_DEBUG_ENABLED == true then
                print("[" .. dataStoreManagerId .. "] DONE: Save. DataStore:RemoveAsync. Took " .. os.clock() - sTime .. "s")
            end
            if success == true then
                break
            end
        end
        if success == false then
            signalSaved:Fire(DATASTORE_MANAGER_RESPONSE_ERROR, value, dataStoreManager)
            return DATASTORE_MANAGER_RESPONSE_ERROR, value
        end
        dataStoreManager.Metadata, dataStoreManager.UserIds, dataStoreManager.CreatedTime, dataStoreManager.UpdatedTime, dataStoreManager.DataStoreVersion = {}, {}, 0, 0, ""
    elseif type(metadataCompress) ~= "table" then
        local dataStoreManagerUserIds = dataStoreManager.UserIds
        local dataStoreManagerDataStoreSetOptions = dataStoreManager.DataStoreSetOptions
        dataStoreManagerDataStoreSetOptions:SetMetadata(dataStoreManagerMetadata)
        for i = 1, attempts do
            if i > 1 then
                task.wait(ASYNC_OPERATION_RETRY_WAIT_TIME)
            end
            local sTime = os.clock()
            if IS_DEBUG_ENABLED == true then
                print("[" .. dataStoreManagerId .. "] INIT: Save. DataStore:SetAsync")
            end
            success, value = pcall(dataStore.SetAsync, dataStore, dataStoreManagerKey, dataStoreManagerValue, dataStoreManagerUserIds, dataStoreManagerDataStoreSetOptions)
            if IS_DEBUG_ENABLED == true then
                print("[" .. dataStoreManagerId .. "] DONE: Save. DataStore:SetAsync. Took " .. os.clock() - sTime .. "s")
            end
            if success == true then
                break
            end
        end
        if success == false then
            signalSaved:Fire(DATASTORE_MANAGER_RESPONSE_ERROR, value, dataStoreManager)
            return DATASTORE_MANAGER_RESPONSE_ERROR, value
        end
        dataStoreManager.DataStoreVersion = value
    else
        local level = metadataCompress.Level or DEFAULT_COMPRESSION_LEVEL
        local decimals = COMPRESSION_DECIMAL_BASE ^ (metadataCompress.Decimals or DEFAULT_DECIMAL_PRECISION)
        local compressSafety = metadataCompress.Safety
        local isSafetyEnabled = if compressSafety == nil then true else compressSafety
        dataStoreManager.CompressedValue = Compress(dataStoreManagerValue, level, decimals, isSafetyEnabled)
        local dataStoreManagerUserIds = dataStoreManager.UserIds
        local dataStoreManagerDataStoreSetOptions = dataStoreManager.DataStoreSetOptions
        dataStoreManagerDataStoreSetOptions:SetMetadata(dataStoreManagerMetadata)
        for i = 1, attempts do
            if i > 1 then
                task.wait(ASYNC_OPERATION_RETRY_WAIT_TIME)
            end
            local sTime = os.clock()
            if IS_DEBUG_ENABLED == true then
                print("[" .. dataStoreManagerId .. "] INIT: Save. DataStore:SetAsync")
            end
            success, value = pcall(dataStore.SetAsync, dataStore, dataStoreManagerKey, dataStoreManager.CompressedValue, dataStoreManagerUserIds, dataStoreManagerDataStoreSetOptions)
            if IS_DEBUG_ENABLED == true then
                print("[" .. dataStoreManagerId .. "] DONE: Save. DataStore:SetAsync. Took " .. os.clock() - sTime .. "s")
            end
            if success == true then
                break
            end
        end
        if success == false then
            signalSaved:Fire(DATASTORE_MANAGER_RESPONSE_ERROR, value, dataStoreManager)
            return DATASTORE_MANAGER_RESPONSE_ERROR, value
        end
        dataStoreManager.DataStoreVersion = value
    end
    dataStoreManager.SaveTime = os.clock()
    signalSaved:Fire(DATASTORE_MANAGER_RESPONSE_SAVED, dataStoreManagerValue, dataStoreManager)
    return DATASTORE_MANAGER_RESPONSE_SAVED, dataStoreManagerValue
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

StartSaveTimer = function(dataStoreManager)
    local dataStoreManagerSaveThread = dataStoreManager.SaveThread
    if dataStoreManagerSaveThread ~= nil then
        task.cancel(dataStoreManagerSaveThread)
    end
    if dataStoreManager.SaveInterval == 0 then
        return
    end
    dataStoreManager.SaveThread = task.delay(dataStoreManager.SaveInterval, onSaveTimerEnded, dataStoreManager)
end

StartLockTimer = function(dataStoreManager)
    local dataStoreManagerLockThread = dataStoreManager.LockThread
    if dataStoreManagerLockThread ~= nil then
        task.cancel(dataStoreManagerLockThread)
    end
    local dataStoreManagerActiveLockInterval = dataStoreManager.ActiveLockInterval
    local startTime = dataStoreManager.LockTime - dataStoreManager.AttemptsRemaining * dataStoreManagerActiveLockInterval
    dataStoreManager.LockThread = task.delay(startTime - os.clock() + dataStoreManagerActiveLockInterval, onLockTimerEnded, dataStoreManager)
end

StopSaveTimer = function(dataStoreManager)
    local dataStoreManagerSaveThread = dataStoreManager.SaveThread
    if dataStoreManagerSaveThread == nil then
        return
    end
    task.cancel(dataStoreManagerSaveThread)
    dataStoreManager.SaveThread = nil
end

StopLockTimer = function(dataStoreManager)
    local dataStoreManagerLockThread = dataStoreManager.LockThread
    if dataStoreManagerLockThread == nil then
        return
    end
    task.cancel(dataStoreManagerLockThread)
    dataStoreManager.LockThread = nil
end

onProcessQueueConnected = function(isConnected, signal)
    if isConnected == false then
        return
    end
    ProcessQueueTask(signal.dataStoreManager)
end

onSaveTimerEnded = function(dataStoreManager)
    dataStoreManager.SaveThread = nil
    local taskManager = dataStoreManager.TaskManager
    if taskManager:FindLast(SaveTask) ~= nil then
        return
    end
    taskManager:InsertBack(SaveTask, dataStoreManager)
end

onLockTimerEnded = function(dataStoreManager)
    dataStoreManager.LockThread = nil
    local taskManager = dataStoreManager.TaskManager
    if taskManager:FindFirst(LockTask) ~= nil then
        return
    end
    taskManager:InsertBack(LockTask, dataStoreManager)
end

onBindToClose = function()
    local sTime = os.clock()
    if IS_DEBUG_ENABLED == true then
        print("[" .. scriptName .. "] INIT: onBindToClose")
    end
    isModuleActive = false
    for lockId, dataStoreManager in pairs(bindToCloseDataStoreManagers) do
        if dataStoreManager.State == nil then
            continue
        end
        activeDataStoreManagers[dataStoreManager.Id] = nil
        StopLockTimer(dataStoreManager)
        StopSaveTimer(dataStoreManager)
        local taskManager = dataStoreManager.TaskManager
        if taskManager:FindFirst(DestroyTask) ~= nil then
            continue
        end
        taskManager:InsertBack(DestroyTask, dataStoreManager)
    end
    while next(bindToCloseDataStoreManagers) ~= nil do
        task.wait()
    end
    for dataStoreId, activeDataStore in pairs(activeDataStores) do
        activeDataStores[dataStoreId] = nil
    end
    while next(activeDataStores) ~= nil do
        task.wait()
    end
    if IS_DEBUG_ENABLED == true then
        print("[" .. scriptName .. "] DONE: onBindToClose. Took " .. os.clock() - sTime .. "s")
    end
end

game:BindToClose(onBindToClose)

DataStoreManagerModule.new = DataStoreManagerModuleNew
DataStoreManagerModule.hidden = DataStoreManagerModuleHidden
DataStoreManagerModule.find = DataStoreManagerModuleFind
DataStoreManagerModule.Response = DataStoreManagerModuleResponse
return DataStoreManagerModule :: DataStoreManagerModule
