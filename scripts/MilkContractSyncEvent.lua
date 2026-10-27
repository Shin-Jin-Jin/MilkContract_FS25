-- MilkContractSyncEvent.lua
-- MP-Synchronisation der aktiven Vertraege. Server ist die Wahrheit; Clients
-- bekommen bei Beitritt + bei jeder Aenderung die Zuordnung Farm -> Molkerei.
-- Aktionen (abschliessen/kuendigen) laufen als Client -> Server-Event.
-- Aufbau 1:1 nach dem Muster von VehicleDeliverySyncEvent.

-- ============================================================================
-- SyncEvent: Server -> Clients (vollstaendige Farm->Molkerei-Zuordnung)
-- ============================================================================
MilkContractSyncEvent = {}
local MilkContractSyncEvent_mt = Class(MilkContractSyncEvent, Event)
InitEventClass(MilkContractSyncEvent, "MilkContractSyncEvent")

function MilkContractSyncEvent.emptyNew()
    return Event.new(MilkContractSyncEvent_mt)
end

function MilkContractSyncEvent.new(entries, offerSeed)
    local self = MilkContractSyncEvent.emptyNew()
    self.entries   = entries or {}   -- Server: { farmId=, milkType=, contract= }
    self.offerSeed = offerSeed or 1
    return self
end

function MilkContractSyncEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.offerSeed or 1)
    local entries = self.entries or {}
    local count = math.min(#entries, 255)
    streamWriteUInt8(streamId, count)
    for i = 1, count do
        local e = entries[i]
        streamWriteString(streamId, e.milkType or "cow")
        e.contract:writeStream(streamId)
    end
end

function MilkContractSyncEvent:readStream(streamId, connection)
    self.offerSeed = streamReadInt32(streamId)
    local count = streamReadUInt8(streamId)
    self.entries = {}
    for i = 1, count do
        local e = {}
        e.milkType = streamReadString(streamId)
        e.data     = MilkContract.readStreamData(streamId)   -- liest immer alle Felder
        self.entries[i] = e
    end
    self:run(connection)
end

-- Nur ein REINER CLIENT uebernimmt die Liste (Server behaelt seinen Vollzustand).
function MilkContractSyncEvent:run(connection)
    if g_server ~= nil then
        return
    end
    if g_milkContractManager ~= nil then
        g_milkContractManager.offerSeed = self.offerSeed or g_milkContractManager.offerSeed
        g_milkContractManager:applySyncEntries(self.entries)
        g_milkContractManager:rebuildOffer()
    end
end

function MilkContractSyncEvent.sendToClients()
    if g_server == nil or g_milkContractManager == nil then
        return
    end
    g_server:broadcastEvent(MilkContractSyncEvent.new(
        g_milkContractManager:getSyncEntries(),
        g_milkContractManager.offerSeed), false, nil, nil)
end


-- ============================================================================
-- RequestEvent: Client -> Server (fordert die Liste beim Beitritt an)
-- ============================================================================
MilkContractSyncRequestEvent = {}
local MilkContractSyncRequestEvent_mt = Class(MilkContractSyncRequestEvent, Event)
InitEventClass(MilkContractSyncRequestEvent, "MilkContractSyncRequestEvent")

function MilkContractSyncRequestEvent.emptyNew()
    return Event.new(MilkContractSyncRequestEvent_mt)
end

function MilkContractSyncRequestEvent.new()
    return MilkContractSyncRequestEvent.emptyNew()
end

function MilkContractSyncRequestEvent:writeStream(streamId, connection) end

function MilkContractSyncRequestEvent:readStream(streamId, connection)
    self:run(connection)
end

function MilkContractSyncRequestEvent:run(connection)
    -- laeuft auf dem Server, wenn ein Client anfragt
    if not connection:getIsServer() and g_milkContractManager ~= nil then
        connection:sendEvent(MilkContractSyncEvent.new(
            g_milkContractManager:getSyncEntries(),
            g_milkContractManager.offerSeed))
    end
end

function MilkContractSyncRequestEvent.sendToServer()
    if g_client ~= nil and g_server == nil then
        g_client:getServerConnection():sendEvent(MilkContractSyncRequestEvent.new())
    end
end


-- ============================================================================
-- ActionEvent: Client -> Server (Vertrag abschliessen / kuendigen)
-- ============================================================================
MilkContractActionEvent = {}
local MilkContractActionEvent_mt = Class(MilkContractActionEvent, Event)
InitEventClass(MilkContractActionEvent, "MilkContractActionEvent")

function MilkContractActionEvent.emptyNew()
    return Event.new(MilkContractActionEvent_mt)
end

-- actionType: 0 = abschliessen (dairyId noetig), 1 = kuendigen, 2 = verlaengern
MilkContractActionEvent.SIGN         = 0
MilkContractActionEvent.CANCEL       = 1
MilkContractActionEvent.EXTEND       = 2
MilkContractActionEvent.EARLY_CANCEL = 3

function MilkContractActionEvent.new(farmId, dairyId, actionType, milkType)
    local self = MilkContractActionEvent.emptyNew()
    self.farmId     = farmId or 0
    self.dairyId    = dairyId or ""
    self.actionType = actionType or MilkContractActionEvent.SIGN
    self.milkType   = milkType or ""
    return self
end

function MilkContractActionEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.farmId)
    streamWriteString(streamId, self.dairyId)
    streamWriteUInt8(streamId, self.actionType)
    streamWriteString(streamId, self.milkType or "")
end

function MilkContractActionEvent:readStream(streamId, connection)
    self.farmId     = streamReadInt32(streamId)
    self.dairyId    = streamReadString(streamId)
    self.actionType = streamReadUInt8(streamId)
    self.milkType   = streamReadString(streamId)
    self:run(connection)
end

-- laeuft auf dem Server: fuehrt die Aktion autoritativ aus + synchronisiert
function MilkContractActionEvent:run(connection)
    if g_server == nil or g_milkContractManager == nil then
        return
    end
    local mt = (self.milkType ~= nil and self.milkType ~= "") and self.milkType or nil
    if self.actionType == MilkContractActionEvent.CANCEL then
        g_milkContractManager:doCancel(self.farmId, mt)
    elseif self.actionType == MilkContractActionEvent.EARLY_CANCEL then
        g_milkContractManager:doEarlyCancel(self.farmId, mt)
    elseif self.actionType == MilkContractActionEvent.EXTEND then
        g_milkContractManager:doExtend(self.farmId, mt)
    else
        g_milkContractManager:doSign(self.dairyId, self.farmId)
    end
    MilkContractSyncEvent.sendToClients()
end

function MilkContractActionEvent.sendToServer(farmId, dairyId, actionType, milkType)
    if g_client ~= nil then
        g_client:getServerConnection():sendEvent(MilkContractActionEvent.new(farmId, dairyId, actionType, milkType))
    end
end


-- ============================================================================
-- NotifyEvent: Server -> Clients (zeigt eine Meldung im Info-System)
-- ============================================================================
MilkContractNotifyEvent = {}
local MilkContractNotifyEvent_mt = Class(MilkContractNotifyEvent, Event)
InitEventClass(MilkContractNotifyEvent, "MilkContractNotifyEvent")

function MilkContractNotifyEvent.emptyNew()
    return Event.new(MilkContractNotifyEvent_mt)
end

function MilkContractNotifyEvent.new(text)
    local self = MilkContractNotifyEvent.emptyNew()
    self.text = text or ""
    return self
end

function MilkContractNotifyEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.text or "")
end

function MilkContractNotifyEvent:readStream(streamId, connection)
    self.text = streamReadString(streamId)
    self:run(connection)
end

-- Nur reine Clients zeigen die Meldung (Host hat sie schon lokal gezeigt).
function MilkContractNotifyEvent:run(connection)
    if g_server ~= nil then return end
    if g_milkContractManager ~= nil then
        g_milkContractManager:notify(self.text)
    end
end
