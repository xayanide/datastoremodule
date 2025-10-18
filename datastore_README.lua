--[[
A fork. Refactored version of Suphi's DataStore Module. Can be used the same way and behaves in a similar manner as in the original.
@xayanide (https://www.roblox.com/users/862645934/profile)

Original:
https://create.roblox.com/store/asset/11671168253
@5uphi (https://www.roblox.com/users/456056545/profile)

Informal changelog:
cleary differentiate between DataStoreModule.new()'s DataStore and Roblox DataStoreService:GetDataStore()'s DataStore
string.byte assigned to local getByteValues
Large refactor for naming only, DataStoreManager -> DataStore, dataStore.DataStore is referenced as dataStoreInstance and its plural form as well. do not confuse dataStore and dataStoreInstance
Due to the fact we cannot reference local functions before they're defined, we forward declare the functions instead
Re-added unsandboxed SyncTaskManager:
Initialized dataStore.Value, dataStore.SaveThread, dataStore.LockThread as nil in the public property
General local variables sorting
Capitalization on first letters of the local variable names of Services
ProcessQueue -> ProcessQueueTask
ProcessQueue.dataStore -> ProcessQueue.dataStoreManager
SignalConnected -> ProcessQueueConnected
Prefxied "on" for variable names SaveTimerEnded, LockTimerEnded, BindToClose, ProcessQueueConnected
local active -> local isModuleActive
Constructor -> DataStoreManagerModule
Queue value param -> queueValue
Queue and Remove local errorMessage -> value
Consistency: Queue error message -> AddQueue
Consistency: Remove error message -> RemoveQueue
Save helper function compress data save: dataStore.Version = value -> dataStore.Version = value
Save helper function: Removed local info as it is not used
ProcessQueue.DataStore -> ProcessQueue.dataStore
DataStore.UniqueId -> DataStore.LockId
DataStore.MemoryStore -> MemoryStoreSortedMap
DataStore.Queue -> MemoryStoreQueue
DataStore.Version -> Datastore.DataStoreVersion
DataStore.Options -> DataStore.DataStoreSetOptions
DataStore -> DataStoreManager
local id -> local managerId
Include dataStoreManager.LockId as a ResponseData if OpenTask was successful.
MemoryStoreSortedMap Key "LockId" -> MemoryStoreSortedMap Key "LockId"
Added new types to DataStoreManager, and __set as read only:
    SaveThread: thread?,
    LockThread: thread?,
    TaskManager: SyncTaskManagerModule.TaskManager,
    LockTime: number,
    SaveTime: number,
    ActiveLockInterval: number,
    ProcessingQueue: boolean,
    DataStore: DataStore,
    MemoryStoreSortedMap: MemoryStoreSortedMap,
    MemoryStoreQueue: MemoryStoreQueue,
    DataStoreSetOptions: DataStoreSetOptions,
Changed type: ProcessQueue: SignalModule.SignalModule & { dataStoreManager: DataStoreManager, Connected: (isConnected: boolean, signal: SignalModule.Signal) -> any },
proxy -> dataStoreManager
cached dataStoreManager.DataStore, dataStoreManager.MemoryStoreSortedMap and dataStoreManager.MemoryStoreQueue as a local variable before entering their for loops
values -> items (local success, items, id = pcall(memoryStoreQueue.ReadAsync, memoryStoreQueue, 100, false, 30))
Lock and Unlock's local id -> local previousId
Lock and Unlock's MemoryStoreSortedMap expire time are cached before entering their for loops
Lock and Unlock helper functions: Cached dataStoreManager.LockId as a local variable before entering their for loops
Lock and Unlock's helper functions: UpdateAsync transform function parameter value -> previousValue
OpenTask: Renamed potential conflicting local variable names returned by Lock and Load helper functions
Added DataStoreManager property and __set as read only: ServerId
Moved bindToCloseDataStoreManagers[dataStoreManager.LockId] = dataStoreManager assignment to occur only inside OpenTask, and insert to the table right after its Lock and Load operations are completed.
local base -> local baseIndex
Added helper function CreatePublicDataStoreManager
implemented SetSaveInterval method as replacement for property indexing version
reorganized types and modules
in {} -> in pairs({})
refactor global characters scope shadowing on functions : characters -> baseCharacters (lua functions ignore shadowed variables outside scope, so it's not a fix)
bytes -> charValues
baseIndex -> baseLength
stored results of repeatedly used properties as locals only when necessary
magic strings or numbers are now constants
added helper functions: createDataStoreManager, getActiveDataStore, getManagerId
]]
