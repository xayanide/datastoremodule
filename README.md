# datastoremanagermodule

A Roblox DataStore Wrapper module. datastoremanagermodule is a fork of Suphi's DataStore Module. It behaves the similarly and can be used almost the same. There were a few optimizations and fixes that don't matter but the notable change is the stripping of encapsulation and some validation. The informal changelog can be read in the respective modules' readme files.

The only breaking change in the API is the `dataStore#SaveInternal`. You'll now have to use a method `dataStore#SetSaveInterval()` to change a dataStore's `SaveInterval`, prior it can be changed solely by writing to that property.

The rename from DataStore to DataStoreManager doesn't affect the API.

Get datastoremanagermodule here:
https://create.roblox.com/store/asset/95400986405695/DataStoreManagerModule


# Suphi's DataStore Module

https://devforum.roblox.com/t/suphis-datastore-module/2425597

https://create.roblox.com/marketplace/asset/11671168253

Suphi's DataStore Module comes with 3 dependencies made by Suphi:
- Proxy
- Signal
- SynchronousTaskManager

With this fork, Proxy and metatable encapsulation are removed completely, replaced the SynchronousTaskManagerModule with my own fork of that module which is SyncTaskManager with no Proxy and metatable encapsulation and replaced Signal with Xignal4 which is also a fork of Signal.
- Xignal4Module
- SyncTaskManagerModule
