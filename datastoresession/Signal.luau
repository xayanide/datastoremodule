-- Types
export type Signal<T... = ()> = {
    Type: "Signal",
    Previous: Signal<T...> | Connection<T...>,
    Next: Signal<T...> | Connection<T...>,
    Connections: number,
    Connect: (self: Signal<T...>, func: (T...) -> ()) -> Connection<T...>,
    ParameterConnect: (self: Signal<T...>, parameter: any, func: (parameter: any, T...) -> ()) -> Connection<T...>,
    Once: (self: Signal<T...>, func: (T...) -> ()) -> Connection<T...>,
    ParameterOnce: (self: Signal<T...>, parameter: any, func: (parameter: any, T...) -> ()) -> Connection<T...>,
    Wait: (self: Signal<T...>) -> T...,
    Spawn: (self: Signal<T...>, T...) -> (),
    Defer: (self: Signal<T...>, T...) -> (),
    Disconnect: (self: Signal<T...>) -> (),
}

export type Connection<T... = ()> = {
    Type: "Connection",
    Previous: Signal<T...> | Connection<T...>,
    Next: Signal<T...> | Connection<T...>,
    Signal: Signal<T...>?,
    Once: boolean,
    Parameter: any,
    FunctionOrThread: (...any) -> () | thread,
    Disconnect: (self: Connection<T...>) -> (),
}

-- Initialize
local Signal = {} :: Signal<...any>
(Signal :: any).__index = Signal
local Connection = {} :: Connection<...any>
(Connection :: any).__index = Connection

-- Signal
function Signal:Connect(func)
    local connection = setmetatable({}, Connection) :: Connection<...any>
    connection.Type = "Connection"
    connection.Previous = self.Previous
    connection.Next = self
    connection.Signal = self
    connection.Once = false
    connection.FunctionOrThread = func
    self.Previous.Next = connection
    self.Previous = connection
    self.Connections += 1
    return connection
end

function Signal:ParameterConnect(parameter, func)
    local connection = setmetatable({}, Connection) :: Connection<...any>
    connection.Type = "Connection"
    connection.Previous = self.Previous
    connection.Next = self
    connection.Signal = self
    connection.Once = false
    connection.Parameter = parameter
    connection.FunctionOrThread = func
    self.Previous.Next = connection
    self.Previous = connection
    self.Connections += 1
    return connection
end

function Signal:Once(func)
    local connection = setmetatable({}, Connection) :: Connection<...any>
    connection.Type = "Connection"
    connection.Previous = self.Previous
    connection.Next = self
    connection.Signal = self
    connection.Once = true
    connection.FunctionOrThread = func
    self.Previous.Next = connection
    self.Previous = connection
    self.Connections += 1
    return connection
end

function Signal:ParameterOnce(parameter, func)
    local connection = setmetatable({}, Connection) :: Connection<...any>
    connection.Type = "Connection"
    connection.Previous = self.Previous
    connection.Next = self
    connection.Signal = self
    connection.Once = true
    connection.Parameter = parameter
    connection.FunctionOrThread = func
    self.Previous.Next = connection
    self.Previous = connection
    self.Connections += 1
    return connection
end

function Signal:Wait()
    local connection = setmetatable({}, Connection) :: Connection<...any>
    connection.Type = "Connection"
    connection.Previous = self.Previous
    connection.Next = self
    connection.Signal = self
    connection.Once = true
    connection.FunctionOrThread = coroutine.running()
    self.Previous.Next = connection
    self.Previous = connection
    self.Connections += 1
    return coroutine.yield()
end

function Signal:Spawn(...)
    local connection = self.Next
    while connection.Type == "Connection" do
        if connection.Once then
            connection.Previous.Next = connection.Next
            connection.Next.Previous = connection.Previous
            connection.Signal = nil
            self.Connections -= 1
        end
        if connection.Parameter == nil then
            task.spawn(connection.FunctionOrThread, ...)
        else
            task.spawn(connection.FunctionOrThread, connection.Parameter, ...)
        end
        connection = connection.Next
    end
end

function Signal:Defer(...)
    local connection = self.Next
    while connection.Type == "Connection" do
        if connection.Once then
            connection.Previous.Next = connection.Next
            connection.Next.Previous = connection.Previous
            connection.Signal = nil
            self.Connections -= 1
        end
        if connection.Parameter == nil then
            task.defer(connection.FunctionOrThread, ...)
        else
            task.defer(connection.FunctionOrThread, connection.Parameter, ...)
        end
        connection = connection.Next
    end
end

function Signal:Disconnect()
    local connection = self.Next
    while connection.Type == "Connection" do
        connection.Signal = nil
        connection = connection.Next
    end
    self.Previous = self
    self.Next = self
    self.Connections = 0
end

-- Connection
function Connection:Disconnect()
    if self.Signal == nil then
        return
    end
    self.Previous.Next = self.Next
    self.Next.Previous = self.Previous
    self.Signal.Connections -= 1
    self.Signal = nil
end

-- Returns a new Signal
return function<A...>(): Signal<A...>
    local self = setmetatable({}, Signal) :: Signal<A...>
    self.Type = "Signal"
    self.Previous = self
    self.Next = self
    self.Connections = 0
    return self
end
