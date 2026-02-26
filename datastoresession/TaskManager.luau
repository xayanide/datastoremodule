-- Types
export type TaskManager = {
    Type: "TaskManager",
    PreviousTask: TaskManager | SynchronousTask,
    NextTask: TaskManager | SynchronousTask,
    ActiveTask: SynchronousTask?,
    Running: boolean,
    InsertFront: (self: TaskManager, func: (SynchronousTask, ...any) -> (), ...any) -> SynchronousTask,
    InsertBack: (self: TaskManager, func: (SynchronousTask, ...any) -> (), ...any) -> SynchronousTask,
    FindFirst: (self: TaskManager, func: (SynchronousTask, ...any) -> ()) -> SynchronousTask?,
    FindLast: (self: TaskManager, func: (SynchronousTask, ...any) -> ()) -> SynchronousTask?,
    Disconnect: (self: TaskManager) -> (),
}

export type SynchronousTask = {
    Type: "SynchronousTask",
    PreviousTask: TaskManager | SynchronousTask,
    NextTask: TaskManager | SynchronousTask,
    PreviousWaiter: SynchronousTask | TaskWaiter,
    NextWaiter: SynchronousTask | TaskWaiter,
    TaskManager: TaskManager?,
    Function: (SynchronousTask, ...any) -> (),
    Parameters: { any },
    Cancelled: boolean,
    Connect: (self: SynchronousTask, func: (...any) -> (), ...any) -> (),
    Wait: (self: SynchronousTask, ...any) -> ...any,
    InsertAfter: (self: SynchronousTask, func: (SynchronousTask, ...any) -> (), ...any) -> SynchronousTask,
    InsertBefore: (self: SynchronousTask, func: (SynchronousTask, ...any) -> (), ...any) -> SynchronousTask,
    Next: (self: SynchronousTask, taskWaiter: TaskWaiter?) -> (TaskWaiter?, ...any),
    Iterate: (self: SynchronousTask, taskWaiter: TaskWaiter?) -> ((self: SynchronousTask, taskWaiter: TaskWaiter?) -> (TaskWaiter?, ...any), SynchronousTask, TaskWaiter?),
    Complete: (self: SynchronousTask, ...any) -> (),
    Cancel: (self: SynchronousTask) -> (),
    Disconnect: (self: SynchronousTask) -> (),
}

export type TaskWaiter = {
    Type: "TaskWaiter",
    PreviousWaiter: SynchronousTask | TaskWaiter,
    NextWaiter: SynchronousTask | TaskWaiter,
    SynchronousTask: SynchronousTask?,
    FunctionOrThread: (...any) -> () | thread,
    Parameters: { any },
    Resume: (self: TaskWaiter, ...any) -> (),
}

-- Initialize
local TaskManager = {} :: TaskManager
(TaskManager :: any).__index = TaskManager
local SynchronousTask = {} :: SynchronousTask
(SynchronousTask :: any).__index = SynchronousTask
local TaskWaiter = {} :: TaskWaiter
(TaskWaiter :: any).__index = TaskWaiter

-- Functions
local function Run(taskManager: TaskManager)
    if taskManager.Running then
        return
    end
    TaskManager.Running = true
    local synchronousTask = taskManager.NextTask
    while synchronousTask.Type == "SynchronousTask" do
        TaskManager.ActiveTask = synchronousTask
        synchronousTask:Function(table.unpack(synchronousTask.Parameters))
        synchronousTask = taskManager.NextTask
    end
    TaskManager.Running = false
end

-- TaskManager
function TaskManager:InsertFront(func, ...)
    local synchronousTask = setmetatable({}, SynchronousTask) :: SynchronousTask
    synchronousTask.Type = "SynchronousTask"
    synchronousTask.PreviousTask = self
    synchronousTask.NextTask = self.NextTask
    synchronousTask.PreviousWaiter = synchronousTask
    synchronousTask.NextWaiter = synchronousTask
    synchronousTask.TaskManager = self
    synchronousTask.Function = func
    synchronousTask.Parameters = { ... }
    self.NextTask.PreviousTask = synchronousTask
    self.NextTask = synchronousTask
    if self.Running == false then
        task.defer(Run, self)
    end
    return synchronousTask
end

function TaskManager:InsertBack(func, ...)
    local synchronousTask = setmetatable({}, SynchronousTask) :: SynchronousTask
    synchronousTask.Type = "SynchronousTask"
    synchronousTask.PreviousTask = self.PreviousTask
    synchronousTask.NextTask = self
    synchronousTask.PreviousWaiter = synchronousTask
    synchronousTask.NextWaiter = synchronousTask
    synchronousTask.TaskManager = self
    synchronousTask.Function = func
    synchronousTask.Parameters = { ... }
    self.PreviousTask.NextTask = synchronousTask
    self.PreviousTask = synchronousTask
    if self.Running == false then
        task.defer(Run, self)
    end
    return synchronousTask
end

function TaskManager:FindFirst(func)
    local synchronousTask = self.NextTask
    while synchronousTask.Type == "SynchronousTask" do
        if synchronousTask.Function == func then
            return synchronousTask
        end
        synchronousTask = synchronousTask.NextTask
    end
    return nil
end

function TaskManager:FindLast(func)
    local synchronousTask = self.PreviousTask
    while synchronousTask.Type == "SynchronousTask" do
        if synchronousTask.Function == func then
            return synchronousTask
        end
        synchronousTask = synchronousTask.PreviousTask
    end
    return nil
end

function TaskManager:Disconnect()
    local synchronousTask = self.NextTask
    while synchronousTask.Type == "SynchronousTask" do
        synchronousTask.PreviousTask.NextTask = synchronousTask.NextTask
        synchronousTask.NextTask.PreviousTask = synchronousTask.PreviousTask
        synchronousTask.TaskManager = nil
        synchronousTask = synchronousTask.NextTask
    end
end

-- SynchronousTask
function SynchronousTask:Connect(func, ...)
    local taskWaiter = setmetatable({}, TaskWaiter) :: TaskWaiter
    taskWaiter.Type = "TaskWaiter"
    taskWaiter.PreviousWaiter = self.PreviousWaiter
    taskWaiter.NextWaiter = self
    taskWaiter.SynchronousTask = self
    taskWaiter.FunctionOrThread = func
    taskWaiter.Parameters = { ... }
    self.PreviousWaiter.NextWaiter = taskWaiter
    self.PreviousWaiter = taskWaiter
end

function SynchronousTask:Wait(...)
    local taskWaiter = setmetatable({}, TaskWaiter) :: TaskWaiter
    taskWaiter.Type = "TaskWaiter"
    taskWaiter.PreviousWaiter = self.PreviousWaiter
    taskWaiter.NextWaiter = self
    taskWaiter.SynchronousTask = self
    taskWaiter.FunctionOrThread = coroutine.running()
    taskWaiter.Parameters = { ... }
    self.PreviousWaiter.NextWaiter = taskWaiter
    self.PreviousWaiter = taskWaiter
    return coroutine.yield()
end

function SynchronousTask:InsertAfter(func, ...)
    local synchronousTask = setmetatable({}, SynchronousTask) :: SynchronousTask
    synchronousTask.Type = "SynchronousTask"
    synchronousTask.PreviousTask = self
    synchronousTask.NextTask = self.NextTask
    synchronousTask.PreviousWaiter = synchronousTask
    synchronousTask.NextWaiter = synchronousTask
    synchronousTask.TaskManager = self.TaskManager
    synchronousTask.Function = func
    synchronousTask.Parameters = { ... }
    if self.TaskManager then
        self.NextTask.PreviousTask = synchronousTask
    end
    self.NextTask = synchronousTask
    return synchronousTask
end

function SynchronousTask:InsertBefore(func, ...)
    local synchronousTask = setmetatable({}, SynchronousTask) :: SynchronousTask
    synchronousTask.Type = "SynchronousTask"
    synchronousTask.PreviousTask = self.PreviousTask
    synchronousTask.NextTask = self
    synchronousTask.PreviousWaiter = synchronousTask
    synchronousTask.NextWaiter = synchronousTask
    synchronousTask.TaskManager = self.TaskManager
    synchronousTask.Function = func
    synchronousTask.Parameters = { ... }
    if self.TaskManager then
        self.PreviousTask.NextTask = synchronousTask
    end
    self.PreviousTask = synchronousTask
    return synchronousTask
end

function SynchronousTask:Next(taskWaiter)
    local nextWaiter = if taskWaiter then taskWaiter.NextWaiter else self.NextWaiter
    if nextWaiter.Type == "TaskWaiter" then
        return nextWaiter, table.unpack(nextWaiter.Parameters)
    end
    return nil
end

function SynchronousTask:Iterate(taskWaiter)
    return self.Next, self, taskWaiter
end

function SynchronousTask:Complete(...)
    if self.TaskManager then
        if self.TaskManager.ActiveTask == self then
            self.TaskManager.ActiveTask = nil
        end
        self.PreviousTask.NextTask = self.NextTask
        self.NextTask.PreviousTask = self.PreviousTask
        self.TaskManager = nil
    end
    local taskWaiter = self.NextWaiter
    self.NextWaiter = self
    self.PreviousWaiter = self
    while taskWaiter.Type == "TaskWaiter" do
        task.spawn(taskWaiter.FunctionOrThread, ...)
        taskWaiter = taskWaiter.NextWaiter
    end
end

function SynchronousTask:Cancel()
    self.Cancelled = true
end

function SynchronousTask:Disconnect()
    if self.TaskManager == nil then
        return
    end
    self.PreviousTask.NextTask = self.NextTask
    self.NextTask.PreviousTask = self.PreviousTask
    self.TaskManager = nil
end

-- TaskWaiter
function TaskWaiter:Resume(...)
    if self.SynchronousTask == nil then
        return
    end
    self.PreviousWaiter.NextWaiter = self.NextWaiter
    self.NextWaiter.PreviousWaiter = self.PreviousWaiter
    self.SynchronousTask = nil
    task.spawn(self.FunctionOrThread, ...)
end

-- Returns a new TaskManager
return function(): TaskManager
    local self = setmetatable({}, TaskManager) :: TaskManager
    self.Type = "TaskManager"
    self.PreviousTask = self
    self.NextTask = self
    self.Running = false
    return self
end
