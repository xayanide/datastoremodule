--[[
VERSION=1.0.0
@xayanide - April 12, 2025
]]
local ConnectionModule = {}
local ConnectionDisconnect
local ConnectionModuleNew

local SignalModule = {}
local getReusableThread, startResumableThread, onThreadResume
local SignalConnect, SignalOnce, SignalWait, SignalFire, SignalDisconnectAll, SignalDestroy
local SignalModuleNew

local MAX_REUSABLE_THREADS = 16
local NEXT_INDEX = 1
local reusableThreads = {}

local taskSpawn = task.spawn
local taskDefer = task.defer
local coroutineCreate = coroutine.create
local coroutineStatus = coroutine.status
local coroutineRunning = coroutine.running
local coroutineYield = coroutine.yield
local coroutineResume = coroutine.resume

getReusableThread = function()
    local reusableThreadsLength = #reusableThreads
    if reusableThreadsLength == 0 then
        return taskSpawn(startResumableThread)
    end
    local reusableThread = reusableThreads[reusableThreadsLength]
    reusableThreads[reusableThreadsLength] = nil
    return reusableThread
end

startResumableThread = function()
    while true do
        --[[
        Use variadic argument forwarding to capture all values yielded by the coroutine.yield(),
        because local arg, ... = coroutine.yield() is invalid syntax in both Lua and Luau.
        ]]
        onThreadResume(coroutineYield())
    end
end

onThreadResume = function(reusableThread, fn, ...)
    xpcall(fn, warn, ...)
    local reusableThreadsLength = #reusableThreads
    if reusableThreadsLength < MAX_REUSABLE_THREADS then
        reusableThreads[reusableThreadsLength + NEXT_INDEX] = reusableThread
    end
end

ConnectionModuleNew = function(signal, fn)
    signal.Connections += 1
    local connection = {
        Signal = signal,
        Function = fn,
        Disconnect = ConnectionDisconnect,
    }
    local firstSignal = signal.Next
    connection.Prev = signal
    connection.Next = firstSignal
    if firstSignal ~= nil then
        firstSignal.Prev = connection
    end
    signal.Next = connection
    local connectedCallback = signal.Connected
    if signal.Connections == 1 and type(connectedCallback) == "function" then
        taskDefer(connectedCallback, true, signal)
    end
    return connection
end

ConnectionDisconnect = function(connection)
    local signal = connection.Signal
    if signal == nil then
        return
    end
    signal.Connections -= 1
    connection.Signal = nil
    local connectedCallback = signal.Connected
    if signal.Connections == 0 and type(connectedCallback) == "function" then
        taskDefer(connectedCallback, false, signal)
    end
    local prevConnection = connection.Prev
    local nextConnection = connection.Next
    prevConnection.Next = nextConnection
    if nextConnection ~= nil then
        nextConnection.Prev = prevConnection
    end
end

ConnectionModule.new = ConnectionModuleNew

SignalModuleNew = function()
    return {
        Connections = 0,
        Connect = SignalConnect,
        Once = SignalOnce,
        Wait = SignalWait,
        Fire = SignalFire,
        DisconnectAll = SignalDisconnectAll,
        Destroy = SignalDestroy,
    }
end

SignalConnect = function(signal, fn)
    return ConnectionModuleNew(signal, fn)
end

SignalOnce = function(signal, fn)
    local connection = nil
    connection = signal:Connect(function(...)
        ConnectionDisconnect(connection)
        fn(...)
    end)
    return connection
end

SignalWait = function(signal)
    local runningThread = coroutineRunning()
    signal:Once(function(...)
        if coroutineStatus(runningThread) ~= "suspended" then
            return
        end
        taskSpawn(runningThread, ...)
    end)
    return coroutineYield()
end

SignalFire = function(signal, ...)
    local current = signal.Next
    while current ~= nil do
        local nextConnection = current.Next
        if current.Signal == nil then
            current = nextConnection
            continue
        end
        local reusableThread = getReusableThread()
        coroutineResume(reusableThread, reusableThread, current.Function, ...)
        current = nextConnection
    end
end

SignalDisconnectAll = function(signal)
    local current = signal.Next
    while current ~= nil do
        ConnectionDisconnect(current)
        current = current.Next
    end
    signal.Connections = 0
    signal.Next = nil
end

SignalDestroy = function(signal)
    SignalDisconnectAll(signal)
    signal.Connected = nil
    signal.Connections = nil
    signal.Connect = nil
    signal.Once = nil
    signal.Wait = nil
    signal.Fire = nil
    signal.DisconnectAll = nil
    signal.Destroy = nil
end

SignalModule.new = SignalModuleNew
return SignalModule
