--[[
A fork. Refactored version of Suphi's SynchronousTaskManager Module. Behaves exactly the same as in the original.
@xayanide (https://www.roblox.com/users/862645934/profile)

Original:
@5uphi (https://www.roblox.com/users/456056545/profile)

Informal changelog:
Due to the fact we cannot reference local functions before they're defined, we forward declare the functions instead
Task Manager, Synchronous Task, Running Task renamed to have no spaces, including in error messages
locals synchronousTask -> syncTask
Added TaskManager types and __set as read only:
    First: SynchronousTask?,
    Last: SynchronousTask?
Added SynchronousTask types and __set as read only:
    Active: boolean,
    Function: (any) -> (any),
    Parameters: {any}?,
    Previous: SynchronousTask?,
    Next: SynchronousTask?
Added RunningTask types and __set as read only:
    SynchronousTask: SynchronousTask
TaskManager: userData -> taskManager
SynchronousTask: userData -> syncTask
RunningTask: userData -> runningTask
RunningTask Iterate() return type self: RunningTask -> self: RunningTask?
implemented SetState method as replacement for property indexing version
reorganized types and modules
Run -> RunNextTask
Added type as read only: SyncTaskManager#Active boolean
RunningTask#SynchronousTask to RunningTask#SyncTask
some else statements converted to returns only when necessary
stored synctask params and synctask function callback as locals
some types and table k,v's missing trailing comma at the last element
resorted ordering of dictionary properties as well as in types
]]
