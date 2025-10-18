# datastoremodule

A Roblox DataStore wrapper module. datastoremodule is a fork of Suphi's DataStore Module. It behaves the similarly and can be used almost the same. There were a few optimizations and fixes that don't matter but the notable change is the stripping of some encapsulation and validation. The informal changelog can be read in the respective modules' readme files.

The only breaking change in the API is the `dataStore#SaveInternal`. You'll now have to use a method `dataStore#SetSaveInterval()` to change a dataStore's `SaveInterval`, prior it can be changed solely by writing to that property.

The renames doesn't affect the API.

Get datastoremodule here:
https://create.roblox.com/store/asset/95400986405695/DataStoreModule

## Suphi's DataStore Module

https://devforum.roblox.com/t/suphis-datastore-module/2425597

https://create.roblox.com/marketplace/asset/11671168253

Suphi's DataStore Module comes with 3 dependencies made by Suphi:
- Proxy
- Signal
- SynchronousTaskManager

## Fork Changes

With this fork, Proxy and metatable encapsulation are removed completely, replaced the `SynchronousTaskManager` with my own fork of that module which is `SyncTaskManagerModule` with no Proxy and metatable encapsulation and replaced `Signal` with `Xignal4Module` which is also a fork of Suphi's `Signal`.
- Xignal4Module
- SyncTaskManagerModule
