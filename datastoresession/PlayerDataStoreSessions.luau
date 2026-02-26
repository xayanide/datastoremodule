-- Configure
local Template = {
    Level = 0,
    Coins = 0,
}

-- Require
local DataStoreSession = require("./DataStoreSession")
local Signal = require("./Signal")

-- Types
export type DataStoreValue = typeof(Template)
export type DataStoreSession = DataStoreSession.DataStoreSession<DataStoreValue> & {
    Player: Player,
    PlayerDataStoreSession: PlayerDataStoreSession,
}
export type PlayerDataStoreSessions = {
    [Player]: PlayerDataStoreSession?,
    Opened: Signal.Signal<Player, PlayerDataStoreSession>,
    Closed: Signal.Signal<Player, PlayerDataStoreSession>,
}
export type PlayerDataStoreSession = {
    Value: DataStoreValue,
    SaveAsync: (self: PlayerDataStoreSession) -> (),
}

-- Initialize
local PlayersService = game:GetService("Players")
local PlayerDataStoreSessionsMetatable = {}
local PlayerDataStoreSessions = setmetatable({}, PlayerDataStoreSessionsMetatable) :: PlayerDataStoreSessions
local PlayerDataStoreSession = {} :: PlayerDataStoreSession
(PlayerDataStoreSession :: any).__index = PlayerDataStoreSession
local DataStoreSessions = {} :: { [PlayerDataStoreSession]: DataStoreSession? }

-- Functions
local function Opened(dataStoreSession: DataStoreSession)
    PlayerDataStoreSessionsMetatable.Opened:Spawn(dataStoreSession.Player, dataStoreSession.PlayerDataStoreSession)
end

local function Closed(dataStoreSession: DataStoreSession)
    PlayerDataStoreSessionsMetatable.Closed:Spawn(dataStoreSession.Player, dataStoreSession.PlayerDataStoreSession)
    -- TODO reopen if player is still online
    -- TODO remove from PlayerDataStoreSessions until its open again
end

-- PlayerDataStoreSessionsMetatable
PlayerDataStoreSessionsMetatable.__index = PlayerDataStoreSessionsMetatable
PlayerDataStoreSessionsMetatable.Opened = Signal()
PlayerDataStoreSessionsMetatable.Closed = Signal()

function PlayerDataStoreSession:SaveAsync()
    local dataStoreSession = DataStoreSessions[self]
    if dataStoreSession == nil then
        return
    end
    dataStoreSession:SaveAsync()
end

-- Events
PlayersService.PlayerAdded:Connect(function(player)
    local dataStoreSession = DataStoreSession("Players", tostring(player.UserId)) :: DataStoreSession
    dataStoreSession.Player = player
    dataStoreSession.PlayerDataStoreSession = setmetatable({}, PlayerDataStoreSession) :: PlayerDataStoreSession
    dataStoreSession.Opened:Connect(Opened)
    dataStoreSession.Closed:Connect(Closed)

    DataStoreSessions[dataStoreSession.PlayerDataStoreSession] = dataStoreSession

    local response = dataStoreSession:OpenAsync(Template)
    -- TODO handle response
    dataStoreSession.PlayerDataStoreSession.Value = dataStoreSession.Value

    PlayerDataStoreSessions[player] = dataStoreSession.PlayerDataStoreSession
end)

PlayersService.PlayerRemoving:Connect(function(player)
    local playerDataStoreSession = PlayerDataStoreSessions[player]
    if playerDataStoreSession == nil then
        return
    end
    PlayerDataStoreSessions[player] = nil

    local dataStoreSession = DataStoreSessions[playerDataStoreSession]
    if dataStoreSession == nil then
        return
    end
    local response = dataStoreSession:CloseAsync()
    DataStoreSessions[playerDataStoreSession] = nil
end)

game:BindToClose(function()
    while next(DataStoreSessions) do
        task.wait()
    end
end)

return PlayerDataStoreSessions
