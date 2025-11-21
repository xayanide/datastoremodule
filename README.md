# DataStoreModule

A Roblox DataStore wrapper. DataStoreModule is a fork of Suphi's DataStore Module. It behaves the similarly and can be used almost the same. There were a few optimizations and fixes that don't matter but the notable change is the stripping of some encapsulation and validation. The informal changelog can be read in the respective modules' readme files.

Get DataStoreModule here:
https://create.roblox.com/store/asset/95400986405695/DataStoreModule

## Breaking Changes

The only breaking change in the API is with `DataStore#SaveInternal`. You can no longer directly modify a DataStore's `SaveInterval` by assigning a value to it because it's no longer assigned a function due to the de-encapsulation. Instead, you must use the `DataStore:SetSaveInterval(interval: number)` method to change the interval.

The renaming does not affect API usage. Just like in the original module, you can use this fork in the same way.

> [!WARNING]
> In this fork, most of the API-safety features are gone, no proxy and metatables. All of the module's methods and properties, as well as the methods and properties of its instances, are fully exposed. There is no distinction or protection for read-only, private, or public properties. Use caution when accessing or modifying properties, and avoid altering or using internal methods and states unless you fully understand it and its consequences.

## Non-breaking Changes

With this fork, Proxy and metatable encapsulation are removed completely, replaced the `SynchronousTaskManager` with my own fork of that module which is `SyncTaskManagerModule` with no Proxy and metatable encapsulation and replaced `Signal` with `Xignal5Module` which is also a fork of Suphi's `Signal`.
- Xignal5Module
- SyncTaskManagerModule

## Roblox Services Used

| **Service** | **Usage in Module** |
|-------------|-------------------|
| `DataStoreService` | Used to get `Roblox DataStore` instances via `GetDataStore(name, scope)` in `DataStore` instances from `getActiveDataStoreInstance` and `createDataStore`. Also used for `GetAsync`, `SetAsync`, and `RemoveAsync` operations in `DataStore:Load()` and `DataStore:Save()`. |
| `MemoryStoreService` | Used to get `MemoryStoreSortedMap` and `MemoryStoreQueue` Roblox instances in `DataStore` instances for session locking, unlocking, and queue processing operations. |
| `HttpService` | Used to generate GUIDs for locks (`GenerateGUID(false)`) and to JSON encode/decode data for compression usage (`JSONEncode` in `DataStore:Usage()`). |

## Child Modules Used

| **Module** | **Usage in Module** |
|------------|-------------------|
| `SignalModule` | Used to create and manage signals for each DataStore, including `StateChanged`, `Saving`, `Saved`, `AttemptsChanged`, and `ProcessQueue`. |
| `SyncTaskManagerModule` | Handles the scheduling and execution of tasks like `OpenTask`, `ReadTask`, `SaveTask`, `LockTask`, `CloseTask`, `DestroyTask`, and `ProcessQueueTask`. |

## Notes

| **Note** | **Remarks** |
|------------|-------------------|
| `DataStore` | Both the original module and this fork create instances called `DataStore`, which share the same name as Roblox's built-in `DataStore` objects. Be careful to distinguish between the module's `DataStore` and Roblox's native `DataStore` instances. |
| `DataStore.ProcessQueue` | Both the original module and this fork only enables this signal as active when the property (`DataStore.ProcessQueue`) is assigned a function. |

## Suphi's DataStore Module

https://devforum.roblox.com/t/suphis-datastore-module/2425597

https://create.roblox.com/marketplace/asset/11671168253

Suphi's DataStore Module comes with 3 dependencies made by Suphi:
- Proxy
- Signal
- SynchronousTaskManager
