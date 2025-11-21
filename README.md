# DataStoreModule

A Roblox DataStore wrapper. DataStoreModule is a fork of Suphi's DataStore Module. It behaves the similarly and can be used almost the same. There were a few optimizations and fixes that don't matter but the notable change is the stripping of some encapsulation and validation. The informal changelog can be read in the respective modules' readme files. This is a refactored version designed to eliminate the reliance on the external `Proxy` module and use standard Lua/Luau table-based object composition instead of metatable-based proxying for public/private access at the cost of API safety and safeguards.

Get DataStoreModule here:
https://create.roblox.com/store/asset/95400986405695/DataStoreModule

## Use Cases

### Applicable

#### Single-session DataStore
Type: Session-locked, stateful DataStore
- Each `DataStore` has their own separate key.
- The module locks the session when it is opened.
- Prevents multiple servers from trying to access the same `DataStore`'s data, only the lock holder can access it.

### Not Applicable

#### Multi-server DataStore
Type: Shared, accessible DataStore across servers
- Many servers can write at the same time.
- You do not need session locking because you want concurrent writes, not a single-session lock.
- You do not need this module, use `DataStore:UpdateAsync()` is ideal here, since it handles updates safely for multi-server writes if used right, read more about it at https://devforum.roblox.com/t/how-to-properly-utilize-updateasync/1133216, https://devforum.roblox.com/t/stop-using-setasync-to-save-player-data/276457.

## Breaking Changes

The only breaking change in the API is with `DataStore#SaveInternal`. You can no longer directly modify a DataStore's `SaveInterval` by assigning a value to it because it's no longer assigned a function due to the de-encapsulation. Instead, you must use the `DataStore:SetSaveInterval(interval: number)` method to change the interval.

The renaming does not affect API usage. Just like in the original module, you can use this fork in the same way.

> [!WARNING]
> In this fork, most of the API-safety features are gone, no proxy and metatables. All of the module's methods and properties, as well as the methods and properties of its instances, are fully exposed. There is no distinction or protection for read-only, private, or public properties. Use caution when accessing or modifying properties, and avoid altering or using internal methods and states unless you fully understand it and its consequences.

## Non-breaking Changes

With this fork, Proxy and metatable encapsulation are removed completely, replaced the `SynchronousTaskManager` with my own fork of that module which is `SyncTaskManagerModule` with no Proxy and metatable encapsulation and replaced `Signal` with `Xignal5Module` which is also a fork of Suphi's `Signal`.
- Xignal5Module
- SyncTaskManagerModule

## Roblox Services Used in DataStoreModule

| **Service** | **Usage in Module** |
|-------------|-------------------|
| `DataStoreService` | Used to get `Roblox DataStore` instances via `GetDataStore(name, scope)` in `DataStore` instances from `getActiveDataStoreInstance()` and `createDataStore()`. Also used for `GetAsync()`, `SetAsync()`, and `RemoveAsync()` operations in `DataStore:Load()` and `DataStore:Save()`. |
| `MemoryStoreService` | Used to get `MemoryStoreSortedMap` and `MemoryStoreQueue` Roblox instances in `DataStore` instances for session locking, unlocking, and queue processing operations. |
| `HttpService` | Used to generate GUIDs for locks (`GenerateGUID(false)`) and to JSON encode/decode data for compression usage (`JSONEncode()` in `DataStore:Usage()`). |

## Dependencies of DataStoreModule

| **Module** | **Usage in Module** |
|------------|-------------------|
| `SignalModule` | Used to create, emit, destroy and manage signals for each `DataStore`, including `StateChanged`, `Saving`, `Saved`, `AttemptsChanged`, and `ProcessQueue`. |
| `SyncTaskManagerModule` | Used to enqueue tasks and run them one by one in the order they were queued. Handles the scheduling and execution of tasks like `OpenTask()`, `ReadTask()`, `SaveTask()`, `LockTask()`, `CloseTask()`, `DestroyTask()`, and `ProcessQueueTask()`. |

## Notes

| **Note** | **Remarks** |
|------------|-------------------|
| `DataStore` | Both the original module and this fork create instances called `DataStore`, which share the same name as Roblox's built-in `DataStore` objects. Be careful to distinguish between the module's `DataStore` and Roblox's native `DataStore` instances. |
| `DataStore.ProcessQueue` | Both the original module and this fork only enables the `ProcessQueue` signal as active when the property (`DataStore.ProcessQueue`) is assigned a function. |
| `DataStore.ServerId` | This field did not exist in the original module and was not exposed. |
| `DataStore.DataStoreVersion` | This was `DataStore.Version` from the original module. This field is exposed in the original module. |
| `bindToCloseDataStores[dataStore.LockId]` | Moved `bindToCloseDataStore[dataStore.LockId] = dataStore` assignment to occur only inside `OpenTask()`. Only assigns the `dataStore` to the `bindToCloseDataStore[dataStore.LockId]` right after its `Lock()` and `Load()` operations are completed. In the original module, `dataStore` is immediately assigned right after the `dataStore` object is created. |
| `DataStoreModule.hidden()` | No changes. Creates a `DataStore` with `Hidden = true`. Does not store it in `activeDataStores`, so it cannot be retrieved later using `DataStoreModule.find()`. `Hidden` field is neither used internally in this fork and the original and is a private field.
| `bindToCloseDataStores` | Tracks `DataStore` that are tied to a Roblox server and need to be cleaned up automatically when the Roblox server ends. All entries are cleaned up and removed when `onBindToClose()` is called. |
| `activeDataStores` | Tracks all currently active, in use, non-hidden `DataStore` in the module. It is typically cleaned up when a `DataStore` is closed, or destroyed. Every `DataStore` stored here can be retrieved later using `DataStoreModule.find()` |
| `DataStore.LockId` | This was `DataStore.UniqueId` from the original module. Though, in the original module this field is not exposed. |


## Suphi's DataStore Module

https://devforum.roblox.com/t/suphis-datastore-module/2425597

https://create.roblox.com/marketplace/asset/11671168253

Suphi's DataStore Module comes with 3 dependencies made by Suphi:
- Proxy
- Signal
- SynchronousTaskManager
