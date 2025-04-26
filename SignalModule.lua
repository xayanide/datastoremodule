--[[ Due to the fact we cannot reference local functions before they're defined, we forward declare the functions instead ]]
local ConnectionModule = {}
local ConnectionMethodDisconnect
local ConnectionModuleNew

local SignalModule = {}
local MAX_REUSABLE_THREADS = 16
local reusableThreads = {}
local SignalMethodConnect, SignalMethodOnce, SignalMethodWait, SignalMethodFire, SignalMethodFastFire, SignalMethodDisconnectAll
local createReusableThread, onThreadResume
local SignalModuleNew

export type SignalModule = {
    new: () -> Signal,
}

export type Signal = {
    [any]: any,
    Connections: number,
    Connected: (isConnected: boolean, signal: Signal | Connection) -> ()?,
    Connect: (self: Signal, func: (...any) -> (), ...any) -> Connection,
    Once: (self: Signal, func: (...any) -> (), ...any) -> Connection,
    Wait: (self: Signal, ...any) -> ...any,
    Fire: (self: Signal, ...any) -> (),
    FastFire: (self: Signal, ...any) -> (),
    DisconnectAll: (self: Signal) -> (),
    First: Connection?,
    Last: Connection?,
}

export type ConnectionModule = {
    new: (signal: Signal, func: (...any) -> () | thread, ...any) -> Connection,
}

export type Connection = {
    [any]: any,
    Signal: Signal?,
    Disconnect: (self: Connection) -> (),
    FunctionOrThread: (...any) -> () | thread,
    Once: boolean?,
    Parameters: { any }?,
    Previous: Connection?,
    Next: Connection?,
}

ConnectionModuleNew = function(signal, func, ...)
    signal.Connections += 1
    return {
        Signal = signal,
        Disconnect = ConnectionMethodDisconnect,
        FunctionOrThread = func,
        Once = false,
        Parameters = if ... == nil then nil else { ... },
        Previous = nil,
        Next = nil,
    }
end

ConnectionMethodDisconnect = function(connection)
    local signal = connection.Signal
    if signal == nil then
        return
    end
    signal.Connections -= 1
    connection.Signal = nil
    if signal.First == connection then
        signal.First = connection.Next
    end
    if signal.Last == connection then
        signal.Last = connection.Previous
    end
    if connection.Previous ~= nil then
        connection.Previous.Next = connection.Next
    end
    if connection.Next ~= nil then
        connection.Next.Previous = connection.Previous
    end
    if type(connection.FunctionOrThread) == "thread" then
        task.cancel(connection.FunctionOrThread)
    end
    if signal.Connections == 0 and signal.Connected ~= nil then
        task.defer(signal.Connected, false, signal)
    end
end

ConnectionModule.new = ConnectionModuleNew

SignalModuleNew = function()
    return {
        Connections = 0,
        Connected = nil,
        Connect = SignalMethodConnect,
        Once = SignalMethodOnce,
        Wait = SignalMethodWait,
        Fire = SignalMethodFire,
        FastFire = SignalMethodFastFire,
        DisconnectAll = SignalMethodDisconnectAll,
        First = nil,
        Last = nil,
    }
end

SignalMethodConnect = function(signal, func, ...)
    if type(func) ~= "function" then
        error("Attempt to Connect failed: Passed value is not a function", 3)
    end
    local connection = ConnectionModule.new(signal, func, ...)
    if signal.Last == nil then
        signal.First, signal.Last = connection, connection
    else
        connection.Previous, signal.Last.Next, signal.Last = signal.Last, connection, connection
    end
    if signal.Connections == 1 and signal.Connected ~= nil then
        task.defer(signal.Connected, true, signal)
    end
    return connection
end

SignalMethodOnce = function(signal, func, ...)
    if type(func) ~= "function" then
        error("Attempt to Connect failed: Passed value is not a function", 3)
    end
    local connection = ConnectionModule.new(signal, func, ...)
    connection.Once = true
    if signal.Last == nil then
        signal.First, signal.Last = connection, connection
    else
        connection.Previous, signal.Last.Next, signal.Last = signal.Last, connection, connection
    end
    if signal.Connections == 1 and signal.Connected ~= nil then
        task.defer(signal.Connected, true, signal)
    end
    return connection
end

SignalMethodWait = function(signal, ...)
    local connection = ConnectionModule.new(signal, coroutine.running(), ...)
    connection.Once = true
    if signal.Last == nil then
        signal.First, signal.Last = connection, connection
    else
        connection.Previous, signal.Last.Next, signal.Last = signal.Last, connection, connection
    end
    if signal.Connections == 1 and signal.Connected ~= nil then
        task.defer(signal.Connected, true, signal)
    end
    return coroutine.yield()
end

SignalMethodFire = function(signal, ...)
    local connection = signal.First
    while connection ~= nil do
        if connection.Once == true then
            signal.Connections -= 1
            connection.Signal = nil
            if signal.First == connection then
                signal.First = connection.Next
            end
            if signal.Last == connection then
                signal.Last = connection.Previous
            end
            if connection.Previous ~= nil then
                connection.Previous.Next = connection.Next
            end
            if connection.Next ~= nil then
                connection.Next.Previous = connection.Previous
            end
            if signal.Connections == 0 and signal.Connected ~= nil then
                task.defer(signal.Connected, false, signal)
            end
        end
        local functionOrThread = connection.FunctionOrThread
        local connectionParams = connection.Parameters
        if type(functionOrThread) == "thread" then
            if connectionParams == nil then
                --[[
                fix: cannot spawn non-suspended coroutine with arguments
                https://www.youtube.com/watch?v=yevAvHU3ewo&t=272
                ]]
                if coroutine.status(functionOrThread) == "suspended" then
                    task.spawn(functionOrThread, ...)
                end
            else
                --[[
                fix: cannot spawn non-suspended coroutine with arguments
                https://www.youtube.com/watch?v=yevAvHU3ewo&t=272
                ]]
                local args = { ... }
                if coroutine.status(functionOrThread) == "suspended" then
                    task.spawn(functionOrThread, table.unpack(table.move(connectionParams, 1, #connectionParams, #args + 1, args)))
                end
            end
        else
            local thread = table.remove(reusableThreads)
            if thread == nil then
                thread = coroutine.create(createReusableThread)
                coroutine.resume(thread)
            end
            if connectionParams == nil then
                task.spawn(thread, thread, functionOrThread, ...)
            else
                local args = { ... }
                task.spawn(thread, thread, functionOrThread, table.unpack(table.move(connectionParams, 1, #connectionParams, #args + 1, args)))
            end
        end
        connection = connection.Next
    end
end

SignalMethodFastFire = function(signal, ...)
    local connection = signal.First
    local args = { ... }
    local argsLength = #args + 1
    while connection ~= nil do
        if connection.Once == true then
            signal.Connections -= 1
            connection.Signal = nil
            if signal.First == connection then
                signal.First = connection.Next
            end
            if signal.Last == connection then
                signal.Last = connection.Previous
            end
            if connection.Previous ~= nil then
                connection.Previous.Next = connection.Next
            end
            if connection.Next ~= nil then
                connection.Next.Previous = connection.Previous
            end
            if signal.Connections == 0 and signal.Connected ~= nil then
                task.defer(signal.Connected, false, signal)
            end
        end
        local functionOrThread = connection.FunctionOrThread
        local connectionParams = connection.Parameters
        if type(functionOrThread) == "thread" then
            if connectionParams == nil then
                coroutine.resume(functionOrThread, ...)
            else
                coroutine.resume(functionOrThread, table.unpack(table.move(connectionParams, 1, #connectionParams, argsLength, args)))
            end
        else
            if connectionParams == nil then
                functionOrThread(...)
            else
                functionOrThread(table.unpack(table.move(connectionParams, 1, #connectionParams, argsLength, args)))
            end
        end
        connection = connection.Next
    end
end

SignalMethodDisconnectAll = function(signal)
    local connection = signal.First
    if connection == nil then
        return
    end
    while connection ~= nil do
        connection.Signal = nil
        local functionOrThread = connection.FunctionOrThread
        if type(functionOrThread) == "thread" then
            task.cancel(functionOrThread)
        end
        connection = connection.Next
    end
    if signal.Connected ~= nil then
        task.defer(signal.Connected, false, signal)
    end
    signal.Connections, signal.First, signal.Last = 0, nil, nil
end

createReusableThread = function()
    while true do
        onThreadResume(coroutine.yield())
    end
end

onThreadResume = function(thread, func, ...)
    func(...)
    if #reusableThreads >= MAX_REUSABLE_THREADS then
        return
    end
    table.insert(reusableThreads, thread)
end

SignalModule.new = SignalModuleNew
return SignalModule :: SignalModule
