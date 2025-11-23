local oldLockId, lockId = 1, 1
function onLockUpdate1(oldValue)
    oldLockId = oldValue
    return if oldLockId == nil or oldLockId == lockId then lockId else nil
end

function onUnlockUpdate1(value)
    oldLockId = value
    return if oldLockId == lockId then lockId else nil
end

local function onLockUpdate(oldValue)
    oldLockId = oldValue
    if oldLockId == nil then
        return lockId
    end
    if oldLockId == lockId then
        return lockId
    end
    return nil
end

local function onUnlockUpdate(oldValue)
    oldLockId = oldValue
    if oldLockId == lockId then
        return lockId
    end
    return nil
end
