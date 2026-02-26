-- This module is unfinished
-- Require
local Signal = require("./Signal")
local TaskManager = require("./TaskManager")

-- Types
export type Success = { Code: "Success", Success: true }
export type SuccessData<A> = { Code: "Success", Success: true, Data: A }
export type Locked = { Code: "Locked", Success: false, SessionId: string? }
export type Error = { Code: "Error", Success: false, Message: string }
export type DataStoreSession<T = any> = {
    -- Read only
    Type: "DataStoreSession",
    Id: string,
    SessionId: string,
    Key: string,
    DataStore: DataStore,
    Thread: thread?,
    Open: boolean,
    TaskManager: TaskManager.TaskManager,

    -- Properties
    Value: T,
    UserIds: { number },
    SaveInterval: number,

    -- Events
    Opened: Signal.Signal<any>, -- TODO change any to DataStoreSession<T>
    Closed: Signal.Signal<any>, -- TODO change any to DataStoreSession<T>
    Saving: Signal.Signal<any>, -- TODO change any to DataStoreSession<T>

    -- Methods
    OpenAsync: (self: DataStoreSession<T>, template: T) -> Success | Locked | Error,
    SaveAsync: (self: DataStoreSession<T>) -> Success | Error,
    CloseAsync: (self: DataStoreSession<T>) -> Success | Error,
    GetAsync: (self: DataStoreSession<T>, template: T?) -> SuccessData<T> | Error,
    SetAsync: (self: DataStoreSession<T>, value: T, userIds: { number }) -> Success | Locked | Error,
    UpdateAsync: (self: DataStoreSession<T>, transformFunction: (value: T, userIds: { number }) -> (T, { number }), attempts: number?) -> Success | Locked | Error,
    RemoveAsync: (self: DataStoreSession<T>) -> Success | Locked | Error,
}

-- Initialize
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local DataStore = {} :: DataStoreSession
(DataStore :: any).__index = DataStore
local SessionTimeout = 300_000

-- Functions
local function Success(): Success
    return { Code = "Success", Success = true }
end

local function SuccessData<A>(data: A): SuccessData<A>
    return { Code = "Success", Success = true, Data = data }
end

local function Locked(sessionId: string): Locked
    return { Code = "Locked", Success = false, SessionId = sessionId }
end

local function Error(message: string): Error
    return { Code = "Error", Success = false, Message = message }
end

local function Clone(template: any): any
    if type(template) ~= "table" then
        return template
    end
    local clone = {}
    for index, value in template do
        clone[index] = Clone(value)
    end
    return clone
end

local function Reconcile(target: any, template: any): any
    if target == nil then
        return Clone(template)
    end
    if type(target) == "table" and type(template) == "table" then
        for index, value in template do
            if type(index) == "number" then
                continue
            end
            target[index] = Reconcile(target[index], value)
        end
    end
    return target
end

local function Save(self: DataStoreSession): ()
    self.Thread = nil
    self:SaveAsync()
end

local function OpenTask(synchronousTask: TaskManager.SynchronousTask, self: DataStoreSession)
    if self.Open == true then
        synchronousTask:Complete(Success())
    else
        while true do
            local cancelled: boolean, metadata: { [string]: any }, lastWaiter: TaskManager.TaskWaiter?
            local success, updatedValue: any, updatedKeyInfo: DataStoreKeyInfo = pcall(self.DataStore.UpdateAsync, self.DataStore, self.Key, function(value: any, keyInfo: DataStoreKeyInfo)
                cancelled = synchronousTask.Cancelled
                metadata = if keyInfo then keyInfo:GetMetadata() else {}
                lastWaiter = nil

                if cancelled then
                    return
                end

                if metadata.SessionId ~= nil and metadata.SessionId ~= self.SessionId then
                    local updatedTime = keyInfo.UpdatedTime
                    if metadata.SessionTime == nil then
                        metadata.SessionTime = updatedTime
                    end
                    if updatedTime - metadata.SessionTime <= SessionTimeout then
                        return value, keyInfo:GetUserIds(), metadata
                    end
                end

                metadata.SessionId = self.SessionId
                metadata.SessionTime = nil

                for taskWaiter, template in synchronousTask:Iterate() do
                    value = Reconcile(value, template)
                    lastWaiter = taskWaiter
                end
                self.Value = value

                return self.Value, self.UserIds, metadata
            end)

            if cancelled then
                break
            end

            if success == true then
                if metadata.SessionId == self.SessionId then
                    if lastWaiter then
                        for taskWaiter, template in synchronousTask:Iterate(lastWaiter) do
                            self.Value = Reconcile(self.Value, template)
                        end
                    end
                    self.Thread = task.delay(self.SaveInterval, Save, self)
                    self.Open = true
                    synchronousTask:Complete(Success())
                    self.Opened:Spawn(self)
                    return
                elseif updatedKeyInfo.UpdatedTime - metadata.SessionTime <= SessionTimeout then
                    synchronousTask:Complete(Locked(metadata.SessionId))
                    return
                elseif synchronousTask.Cancelled then
                    break
                end
            else
                if synchronousTask.Cancelled then
                    break
                end
                task.wait(10)
                if synchronousTask.Cancelled then
                    break
                end
            end
        end

        synchronousTask:Complete(Error("Cancelled"))
    end
end

local function SaveTask(synchronousTask: TaskManager.SynchronousTask, self: DataStoreSession)
    if self.Open == false then
        synchronousTask:Complete(Error("Session not open"))
    else
        if self.Thread then
            task.cancel(self.Thread)
            self.Thread = nil
        end

        while true do
            self.Saving:Spawn(self)

            local cancelled: boolean, metadata: { [string]: any }
            local success, updatedValue: any, updatedKeyInfo: DataStoreKeyInfo = pcall(self.DataStore.UpdateAsync, self.DataStore, self.Key, function(value: any, keyInfo: DataStoreKeyInfo)
                cancelled = synchronousTask.Cancelled
                metadata = if keyInfo then keyInfo:GetMetadata() else {}

                if cancelled then
                    return
                end

                if metadata.SessionId ~= self.SessionId then
                    return
                end
                metadata.SessionTime = nil
                return self.Value, self.UserIds, metadata
            end)

            if cancelled then
                break
            end

            if success == true then
                if updatedValue == nil then
                    self.Open = false
                    synchronousTask:Complete(Locked(metadata.SessionId))
                    self.Closed:Spawn(self)
                    return
                else
                    self.Thread = task.delay(self.SaveInterval, Save, self)
                    synchronousTask:Complete(Success())
                    return
                end
            else
                if synchronousTask.Cancelled then
                    break
                end
                task.wait(10)
                if synchronousTask.Cancelled then
                    break
                end
            end
        end

        self.Thread = task.delay(self.SaveInterval, Save, self)
        synchronousTask:Complete(Error("Cancelled"))
    end
end

local function CloseTask(synchronousTask: TaskManager.SynchronousTask, self: DataStoreSession)
    if self.Open == false then
        synchronousTask:Complete(Success())
    else
        self.Saving:Spawn(self)

        self.Open = false
        self.Closed:Spawn(self)

        while true do
            local cancelled: boolean, metadata: { [string]: any }
            local success, updatedValue: any, updatedKeyInfo: DataStoreKeyInfo = pcall(self.DataStore.UpdateAsync, self.DataStore, self.Key, function(value: any, keyInfo: DataStoreKeyInfo)
                cancelled = synchronousTask.Cancelled
                metadata = if keyInfo then keyInfo:GetMetadata() else {}

                if cancelled then
                    return
                end

                if metadata.SessionId ~= self.SessionId then
                    return
                end
                metadata.SessionId = nil
                metadata.SessionTime = nil
                return self.Value, self.UserIds, metadata
            end)

            if cancelled then
                break
            end

            if success == true then
                if updatedValue == nil then
                    synchronousTask:Complete(Locked(metadata.SessionId))
                    return
                else
                    synchronousTask:Complete(Success())
                    return
                end
            else
                if synchronousTask.Cancelled then
                    break
                end
                task.wait(10)
                if synchronousTask.Cancelled then
                    break
                end
            end
        end

        synchronousTask:Complete(Error("Cancelled"))
    end
end

-- DataStore
function DataStore:OpenAsync(template)
    if self.Open == true then
        return Success()
    else
        local openTask = self.TaskManager:FindFirst(OpenTask)
        if openTask then
            return openTask:Wait(template)
        else
            return self.TaskManager:InsertBack(OpenTask, self):Wait(template)
        end
    end
end

function DataStore:SaveAsync()
    local saveTask = self.TaskManager:FindFirst(SaveTask)
    if saveTask then
        return saveTask:Wait()
    else
        if self.Open then
            local closeTask = self.TaskManager:FindFirst(CloseTask)
            if closeTask then
                return closeTask:InsertBefore(SaveTask, self):Wait()
            else
                return self.TaskManager:InsertBack(SaveTask, self):Wait()
            end
        else
            if self.TaskManager:FindFirst(OpenTask) then
                local closeTask = self.TaskManager:FindFirst(CloseTask)
                if closeTask then
                    return closeTask:InsertBefore(SaveTask, self):Wait()
                else
                    return self.TaskManager:InsertBack(SaveTask, self):Wait()
                end
            else
                return Error("Session not open")
            end
        end
    end
end

function DataStore:CloseAsync()
    local closeTask = self.TaskManager:FindFirst(CloseTask)
    if closeTask then
        return closeTask:Wait()
    else
        if self.Open then
            return self.TaskManager:InsertBack(CloseTask, self):Wait()
        else
            if self.TaskManager.ActiveTask and self.TaskManager.ActiveTask.Function == OpenTask then
                self.TaskManager.ActiveTask:Cancel()
                return self.TaskManager:InsertBack(CloseTask, self):Wait()
            else
                if self.TaskManager:FindFirst(OpenTask) then
                    return self.TaskManager:InsertBack(CloseTask, self):Wait()
                else
                    return Success()
                end
            end
        end
    end
end

function DataStore:GetAsync(template)
    local success, value: any, keyInfo: DataStoreKeyInfo = pcall(self.DataStore.GetAsync, self.DataStore, self.Key, nil)
    if success then
        return SuccessData(if template then Reconcile(value, template) else value)
    else
        return Error("Failed to access DataStore")
    end
end

-- Returns a new DataStoreSession from the given name, scope and key
return function<A>(name: string, scopeOrKey: string, key: string?): DataStoreSession<A>
    if type(name) ~= "string" then
        error("Name must be a string", 2)
    end
    if type(scopeOrKey) ~= "string" then
        error("ScopeOrKey must be a string", 2)
    end
    if key and type(key) ~= "string" then
        error("Key must be a string or nil", 2)
    end
    local self = setmetatable({}, DataStore) :: DataStoreSession<A>
    self.Type = "DataStoreSession"
    self.Id = if key then `{name}/{scopeOrKey}/{key}` else `{name}/global/{scopeOrKey}`
    self.SessionId = HttpService:GenerateGUID(false)
    self.Key = if key then key else scopeOrKey
    self.DataStore = DataStoreService:GetDataStore(name, if key then scopeOrKey else "global")
    self.Open = false
    self.TaskManager = TaskManager()
    self.SaveInterval = 30
    self.Opened = Signal()
    self.Closed = Signal()
    self.Saving = Signal()
    return self
end
