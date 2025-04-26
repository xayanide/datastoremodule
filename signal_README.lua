--[[
A fork. Refactored version of Suphi's Signal Module. Behaves exactly the same as in the original.
@xayanide (https://www.roblox.com/users/862645934/profile)

Original:
https://create.roblox.com/store/asset/11670710927
@5uphi (https://www.roblox.com/users/456056545/profile)

Informal changelog:
Minor fix: fix: cannot spawn non-suspended coroutine with arguments
Added Signal types:
    First: Connection?,
    Last: Connection?,
Added Connection types:
    FunctionOrThread: (...any) -> () | thread,
    Parameters: { any }?,
    Once: boolean?,
    Previous: Connection?,
    Next: Connection?,
Signal: userData -> signal
Connection: userData -> connectionUserData
Signal type change: Connected: (connected: boolean, signal: Signal) -> Connected: (isConnected: boolean, signal: Signal)
Added Once property to connection created from Signal Connect method.
Updated Signal.Connected() 2nd parameter: Signal | Connection
reorganized types and modules
Thread -> createResumableThread
Call -> onThreadResume
Fixed a bug: signal#Connected callback when disconnecting a connection returns a "boolean, connection" instead of "boolean, signal"
]]
