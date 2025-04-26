local RunningTaskModule = {}
local RunningTaskMethodNext, RunningTaskMethodIterate, RunningTaskMethodEnd
local RunningTaskModuleNew

local SyncTaskModule = {}
local SyncTaskMethodWait, SyncTaskMethodCancel
local SyncTaskModuleNew

local SyncTaskManagerModule = {}
local TaskManagerMethodInsertFront, TaskManagerMethodInsertBack, TaskManagerMethodFindFirst, TaskManagerMethodFindLast, TaskManagerMethodCancelAll, TaskManagerMethodSetState
local StartTaskRunner
local SyncTaskManagerModuleNew

export type SyncTaskManagerModule = {
    new: () -> TaskManager,
}

export type TaskManager = {
    [any]: any,
    Enabled: boolean,
    Tasks: number,
    Running: SyncTask?,
    Active: boolean,
    InsertFront: (self: TaskManager, func: (RunningTask, ...any) -> (), ...any) -> SyncTask,
    InsertBack: (self: TaskManager, func: (RunningTask, ...any) -> (), ...any) -> SyncTask,
    FindFirst: (self: TaskManager, func: (RunningTask, ...any) -> ()) -> (SyncTask?, number?),
    FindLast: (self: TaskManager, func: (RunningTask, ...any) -> ()) -> (SyncTask?, number?),
    CancelAll: (self: TaskManager, func: (RunningTask, ...any) -> ()?) -> (),
    SetState: (self: TaskManager, value: boolean) -> (),
    First: SyncTask?,
    Last: SyncTask?,
}

export type SyncTaskModule = {
    new: (taskManager: TaskManager, func: (RunningTask, ...any) -> (), ...any) -> SyncTask,
}

export type SyncTask = {
    [any]: any,
    TaskManager: TaskManager?,
    Running: boolean,
    Wait: (self: SyncTask, ...any) -> ...any,
    Cancel: (self: SyncTask) -> (),
    Active: boolean,
    Function: (any) -> any,
    Parameters: { any }?,
    Previous: SyncTask?,
    Next: SyncTask?,
}

export type RunningTaskModule = {
    new: (syncTask: SyncTask) -> RunningTask,
}

export type RunningTask = {
    Next: (self: RunningTask) -> (thread, ...any),
    Iterate: (self: RunningTask) -> ((self: RunningTask?) -> (thread, ...any), RunningTask),
    End: (self: RunningTask) -> (),
    SyncTask: SyncTask,
}

RunningTaskModuleNew = function(syncTask)
    return {
        SyncTask = syncTask,
        Next = RunningTaskMethodNext,
        Iterate = RunningTaskMethodIterate,
        End = RunningTaskMethodEnd,
    }
end

RunningTaskMethodNext = function(runningTask)
    local syncTask = runningTask.SyncTask
    local firstSyncTask = syncTask.First
    if firstSyncTask == nil then
        return
    end
    syncTask.First = firstSyncTask.Next
    if syncTask.Last == firstSyncTask then
        syncTask.Last = nil
    end
    return table.unpack(firstSyncTask)
end

RunningTaskMethodIterate = function(runningTask)
    return runningTask.Next, runningTask
end

RunningTaskMethodEnd = function(runningTask)
    runningTask.SyncTask.Active = false
end

RunningTaskModule.new = RunningTaskModuleNew

SyncTaskModuleNew = function(taskManager, func, ...)
    return {
        TaskManager = taskManager,
        Running = false,
        Wait = SyncTaskMethodWait,
        Cancel = SyncTaskMethodCancel,
        Active = true,
        Function = func,
        Parameters = if ... == nil then nil else { ... },
        Previous = nil,
        Next = nil,
    }
end

SyncTaskMethodWait = function(syncTask, ...)
    if syncTask.Active == false then
        return
    end
    local runningThreadNode = { coroutine.running(), ... }
    if syncTask.Last == nil then
        syncTask.First, syncTask.Last = runningThreadNode, runningThreadNode
    else
        syncTask.Last.Next, syncTask.Last = runningThreadNode, runningThreadNode
    end
    return coroutine.yield()
end

SyncTaskMethodCancel = function(syncTask)
    if syncTask.Running == true then
        return false
    end
    local taskManager = syncTask.TaskManager
    if taskManager == nil then
        return false
    end
    taskManager.Tasks -= 1
    if taskManager.First == syncTask then
        taskManager.First = syncTask.Next
    end
    if taskManager.Last == syncTask then
        taskManager.Last = syncTask.Previous
    end
    if syncTask.Previous ~= nil then
        syncTask.Previous.Next = syncTask.Next
    end
    if syncTask.Next ~= nil then
        syncTask.Next.Previous = syncTask.Previous
    end
    syncTask.Active, syncTask.TaskManager, syncTask.Previous, syncTask.Next = false, nil, nil, nil
    return true
end

SyncTaskModule.new = SyncTaskModuleNew

SyncTaskManagerModuleNew = function()
    return {
        Enabled = true,
        Tasks = 0,
        Running = nil,
        Active = false,
        InsertFront = TaskManagerMethodInsertFront,
        InsertBack = TaskManagerMethodInsertBack,
        FindFirst = TaskManagerMethodFindFirst,
        FindLast = TaskManagerMethodFindLast,
        CancelAll = TaskManagerMethodCancelAll,
        SetState = TaskManagerMethodSetState,
        First = nil,
        Last = nil,
    }
end

TaskManagerMethodInsertFront = function(taskManager, func, ...)
    if type(func) ~= "function" then
        error("Attempt to InsertFront failed: Passed value is not a function", 3)
    end
    taskManager.Tasks += 1
    local syncTask = SyncTaskModule.new(taskManager, func, ...)
    if taskManager.First == nil then
        taskManager.First, taskManager.Last = syncTask, syncTask
    else
        syncTask.Next, taskManager.First.Previous, taskManager.First = taskManager.First, syncTask, syncTask
    end
    if taskManager.Active == false and taskManager.Enabled == true then
        taskManager.Active = true
        task.defer(StartTaskRunner, taskManager)
    end
    return syncTask
end

TaskManagerMethodInsertBack = function(taskManager, func, ...)
    if type(func) ~= "function" then
        error("Attempt to InsertBack failed: Passed value is not a function", 3)
    end
    taskManager.Tasks += 1
    local syncTask = SyncTaskModule.new(taskManager, func, ...)
    if taskManager.Last == nil then
        taskManager.First, taskManager.Last = syncTask, syncTask
    else
        syncTask.Previous, taskManager.Last.Next, taskManager.Last = taskManager.Last, syncTask, syncTask
    end
    if taskManager.Active == false and taskManager.Enabled == true then
        taskManager.Active = true
        task.defer(StartTaskRunner, taskManager)
    end
    return syncTask
end

TaskManagerMethodFindFirst = function(taskManager, func)
    if type(func) ~= "function" then
        error("Attempt to FindFirst failed: Passed value is not a function", 3)
    end
    local syncTask = taskManager.Running
    if syncTask ~= nil then
        if syncTask.Active == true and syncTask.Function == func then
            return syncTask, 0
        end
    end
    local index = 1
    local firstSyncTask = taskManager.First
    while firstSyncTask ~= nil do
        if firstSyncTask.Function == func then
            return firstSyncTask, index
        end
        firstSyncTask = firstSyncTask.Next
        index += 1
    end
end

TaskManagerMethodFindLast = function(taskManager, func)
    if type(func) ~= "function" then
        error("Attempt to FindFirst failed: Passed value is not a function", 3)
    end
    local index = if taskManager.Running == nil then taskManager.Tasks else taskManager.Tasks - 1
    local lastSyncTask = taskManager.Last
    while lastSyncTask ~= nil do
        if lastSyncTask.Function == func then
            return lastSyncTask, index
        end
        lastSyncTask = lastSyncTask.Previous
        index -= 1
    end
    local syncTask = taskManager.Running
    if syncTask ~= nil then
        if syncTask.Active == true and syncTask.Function == func then
            return syncTask, 0
        end
    end
end

TaskManagerMethodCancelAll = function(taskManager, func)
    if func == nil then
        local firstSyncTask = taskManager.First
        taskManager.First = nil
        taskManager.Last = nil
        if taskManager.Running == nil then
            taskManager.Tasks = 0
        else
            taskManager.Tasks = 1
        end
        while firstSyncTask ~= nil do
            firstSyncTask, firstSyncTask.Active, firstSyncTask.TaskManager, firstSyncTask.Previous, firstSyncTask.Next = firstSyncTask.Next, false, nil, nil, nil
        end
        return
    end
    if type(func) ~= "function" then
        error("Attempt to CancelAll failed: Passed value is not nil or function", 3)
    end
    local firstSyncTask = taskManager.First
    while firstSyncTask ~= nil do
        if firstSyncTask.Function == func then
            taskManager.Tasks -= 1
            if taskManager.First == firstSyncTask then
                taskManager.First = firstSyncTask.Next
            end
            if taskManager.Last == firstSyncTask then
                taskManager.Last = firstSyncTask.Previous
            end
            if firstSyncTask.Previous ~= nil then
                firstSyncTask.Previous.Next = firstSyncTask.Next
            end
            if firstSyncTask.Next ~= nil then
                firstSyncTask.Next.Previous = firstSyncTask.Previous
            end
            firstSyncTask, firstSyncTask.Active, firstSyncTask.TaskManager, firstSyncTask.Previous, firstSyncTask.Next = firstSyncTask.Next, false, nil, nil, nil
        else
            firstSyncTask = firstSyncTask.Next
        end
    end
end

TaskManagerMethodSetState = function(taskManager, value)
    if type(value) ~= "boolean" then
        error("Attempt to set Enabled failed: Passed value is not a boolean", 3)
    end
    taskManager.Enabled = value
    if value == false or taskManager.First == nil or taskManager.Active == true then
        return
    end
    taskManager.Active = true
    task.defer(StartTaskRunner, taskManager)
end

StartTaskRunner = function(taskManager)
    if taskManager.Enabled == false then
        taskManager.Active = false
        return
    end
    local firstSyncTask = taskManager.First
    if firstSyncTask == nil then
        taskManager.Active = false
        return
    end
    taskManager.Running = firstSyncTask
    taskManager.First = firstSyncTask.Next
    firstSyncTask.Running = true
    if firstSyncTask.Next == nil then
        taskManager.Last = nil
    else
        firstSyncTask.Next.Previous = nil
        firstSyncTask.Next = nil
    end
    local runningTask = RunningTaskModule.new(firstSyncTask)
    local syncTaskParams = firstSyncTask.Parameters
    local syncTaskCallback = firstSyncTask.Function
    if syncTaskParams == nil then
        syncTaskCallback(runningTask)
    else
        syncTaskCallback(runningTask, table.unpack(syncTaskParams))
    end
    taskManager.Tasks -= 1
    taskManager.Running = nil
    firstSyncTask.Active = false
    firstSyncTask.TaskManager = nil
    firstSyncTask.Running = false
    if taskManager.Enabled == false or taskManager.First == nil then
        taskManager.Active = false
        return
    end
    task.defer(StartTaskRunner, taskManager)
end

SyncTaskManagerModule.new = SyncTaskManagerModuleNew
return SyncTaskManagerModule :: SyncTaskManagerModule
