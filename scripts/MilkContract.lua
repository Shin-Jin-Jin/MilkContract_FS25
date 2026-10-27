-- =========================================================================
--  MilkContract.lua
--  Laufzeit-Zustand eines AKTIVEN Vertrags. Kennt seine Molkerei (per
--  Referenz), zaehlt gelieferte Mengen, sampelt Gesundheit, rechnet beim
--  Periodenwechsel ab und schreibt sich ins Savegame.
-- =========================================================================
MilkContract = {}
local MilkContract_mt = Class(MilkContract)

-- Standard-Straffaktor bei Mindestmengen-Vertraegen ohne eigenen Faktor.
MilkContract.DEFAULT_PENALTY_FACTOR = 1.0

-- @param dairy       MilkDairy-Objekt
-- @param farmId      Farm, die den Vertrag haelt
-- @param targetLiters berechnete Zielmenge fuer den Vertragszeitraum (0 bei none/maximum)
-- @param capPerPeriod Deckel je Periode in Litern (nil, wenn keine Hoechstmenge)
function MilkContract.new(dairy, farmId, targetLiters, capPerPeriod)
    local self = setmetatable({}, MilkContract_mt)
    self.dairyId  = dairy.id
    self.dairy    = dairy
    self.farmId   = farmId

    self.targetLiters  = targetLiters or 0     -- Ziel ueber den Vertragszeitraum
    self.capPerPeriod  = capPerPeriod          -- nil oder Liter-Deckel je Periode

    -- Laufzeit
    self.durationMonths = dairy.durationMonths or 12
    self.periodsElapsed = 0                     -- vergangene Monate seit Abschluss
    self.priceBonus     = 1.0                   -- Aufschlag fuer laengere Laufzeit
    self.carriedDebt    = 0                      -- aus Vorjahr uebernommene Nachliefermenge
    self.effQuotaPercent = nil                   -- gewuerfelte Mindestmenge (%) - fixiert
    self.effHealth      = nil                    -- gewuerfelte Gesundheitsauflage (%) - fixiert
    self.effCalf        = nil                    -- gewuerfelte Kaelber-Haltedauer (Monate) - fixiert
    self.lockedBasePrice = nil                   -- Festpreis je Liter (ohne Bonus), beim Abschluss fixiert
    self.warnedNoSupply = false                  -- Warnung "keine Milch" bereits gezeigt (nicht gespeichert)

    -- laufende Zaehler
    self.deliveredThisPeriod = 0               -- an die Molkerei geliefert (Periode)
    self.deliveredTotal      = 0               -- an die Molkerei geliefert (gesamt)
    self.premiumThisPeriod   = 0               -- zum Premiumpreis abgenommen (fuer Deckel)
    self.accruedPayout       = 0               -- aufgelaufenes, noch nicht ausgezahltes Geld

    -- Gesundheits-Sampling (gleitender Mittelwert)
    self.healthSum    = 0
    self.healthCount  = 0
    self.youngSum     = 0
    self.youngCount   = 0

    self.active = true
    return self
end

-- Effektiven Preis pro Liter ermitteln --------------------------------------
-- Festpreis-Vertraege nutzen den beim Abschluss fixierten Literpreis,
-- marktgekoppelte folgen dem aktuellen Milchpreis.
function MilkContract:getPricePerLiter(currentMarketPrice)
    local base
    if self.lockedBasePrice ~= nil and not self.dairy:isMarketPriced() then
        base = self.lockedBasePrice
    else
        base = self.dairy:getPricePerLiter(currentMarketPrice)
    end
    return base * (self.priceBonus or 1)
end

-- Aktuellen Ø-Gesundheitswert -----------------------------------------------
function MilkContract:getAverageHealth()
    if self.healthCount == 0 then return nil end
    return self.healthSum / self.healthCount
end

-- Wird bei jedem Day-Change mit dem gewichteten Herdenschnitt gefuettert -----
function MilkContract:getAverageYoung()
    if (self.youngCount or 0) == 0 then return nil end
    return self.youngSum / self.youngCount
end

function MilkContract:sampleYoung(youngPercent)
    if youngPercent ~= nil then
        self.youngSum   = (self.youngSum or 0) + youngPercent
        self.youngCount = (self.youngCount or 0) + 1
    end
end

function MilkContract:meetsYoungRequirement()
    local req = self.effYoungShare
    if req == nil then return true end
    local avg = self:getAverageYoung()
    if avg == nil then return true end
    return avg >= req
end

function MilkContract:sampleHealth(healthPercent)
    if healthPercent ~= nil then
        self.healthSum   = self.healthSum + healthPercent
        self.healthCount = self.healthCount + 1
    end
end

-- Auflagen erfuellt? (Gesundheit; Kaelber-Regel prueft der Manager per Hook) -
function MilkContract:meetsHealthRequirement()
    local req = self.effHealth or self.dairy.requirements.minHerdHealth
    if req == nil then return true end
    local avg = self:getAverageHealth()
    if avg == nil then return true end   -- noch kein Sample -> nicht bestrafen
    return avg >= req
end

-- --------------------------------------------------------------------------
--  KERN (zweistufig, damit nie "Geld aus dem Nichts" entsteht):
--    peekTakeAmount(available) - wie viel DUERFTE der Vertrag nehmen?
--                                (rechnet nur, bucht nichts)
--    commitTake(amount, price) - bucht die TATSAECHLICH aus dem Lager
--                                entfernte Menge auf den Vertrag.
--  Regel: Was der Vertrag nicht nimmt, bleibt im Lager (kein Marktverkauf).
-- --------------------------------------------------------------------------
function MilkContract:peekTakeAmount(availableLiters)
    if availableLiters <= 0 then return 0 end

    -- Hoechstmengen-Molkerei: nur bis zum Periodendeckel
    if self.dairy:hasMaximumCap() and self.capPerPeriod ~= nil then
        local remaining = math.max(0, self.capPerPeriod - self.premiumThisPeriod)
        return math.min(availableLiters, remaining)
    end

    return availableLiters
end

function MilkContract:commitTake(amount, currentMarketPrice)
    if amount <= 0 then return end
    local contractPrice = self:getPricePerLiter(currentMarketPrice)
    local income = amount * contractPrice

    self.deliveredThisPeriod = self.deliveredThisPeriod + amount
    self.deliveredTotal      = self.deliveredTotal      + amount
    self.premiumThisPeriod   = self.premiumThisPeriod   + amount
    self.accruedPayout       = self.accruedPayout       + income
end

-- --------------------------------------------------------------------------
--  Abrechnung. isPayoutPeriod: faellt in dieser Periode eine Auszahlung an?
--  isContractEnd: endet in dieser Periode der Vertragszeitraum (Strafpruefung)?
--  Gibt { payout=?, penalty=? } zurueck; der Manager bucht die Betraege.
-- --------------------------------------------------------------------------
function MilkContract:settlePeriod(isPayoutPeriod, isContractEnd, currentMarketPrice)
    local out = { payout = 0, penalty = 0 }

    if isPayoutPeriod then
        out.payout = self.accruedPayout
        self.accruedPayout = 0
    end

    -- Strafe bei Mindestmengen-Vertraegen am Vertragsende (allgemein, auch ohne eigenen Faktor)
    if isContractEnd and self.dairy:hasMinimumQuota() then
        local shortfall = self.targetLiters - self.deliveredTotal
        if shortfall > 0 then
            local factor = self.dairy.penaltyFactor or MilkContract.DEFAULT_PENALTY_FACTOR
            local price = self:getPricePerLiter(currentMarketPrice)
            out.penalty = shortfall * price * factor
        end
    end

    -- Periodenzaehler zuruecksetzen (Deckel gilt je Periode)
    self.deliveredThisPeriod = 0
    self.premiumThisPeriod   = 0
    -- Hinweis: deliveredTotal laeuft ueber den ganzen Vertragszeitraum weiter
    -- und wird erst bei Vertragsende fuer die Strafpruefung ausgewertet.

    return out
end

-- Periodenzaehler NUR zuruecksetzen (Periodenwechsel ohne Auszahlung) --------
function MilkContract:resetPeriodCounters()
    self.deliveredThisPeriod = 0
    self.premiumThisPeriod   = 0
end

-- --------------------------------------------------------------------------
--  MP-Sync: kompletter Anzeige-Zustand fuer Clients
--  (Clients brauchen echte Vertragsobjekte, sonst bricht die Statusanzeige
--   bei Methodenaufrufen wie getPricePerLiter/meetsHealthRequirement ab.)
-- --------------------------------------------------------------------------
local function writeOptFloat(streamId, v)
    if streamWriteBool(streamId, v ~= nil) then streamWriteFloat32(streamId, v) end
end
local function readOptFloat(streamId)
    if streamReadBool(streamId) then return streamReadFloat32(streamId) end
    return nil
end

function MilkContract:writeStream(streamId)
    streamWriteString(streamId, self.dairyId or "")
    streamWriteInt32(streamId, self.farmId or 0)
    streamWriteFloat32(streamId, self.targetLiters or 0)
    writeOptFloat(streamId, self.capPerPeriod)
    streamWriteInt32(streamId, self.durationMonths or 12)
    streamWriteInt32(streamId, self.periodsElapsed or 0)
    streamWriteFloat32(streamId, self.priceBonus or 1)
    streamWriteFloat32(streamId, self.carriedDebt or 0)
    streamWriteFloat32(streamId, self.deliveredThisPeriod or 0)
    streamWriteFloat32(streamId, self.deliveredTotal or 0)
    streamWriteFloat32(streamId, self.premiumThisPeriod or 0)
    streamWriteFloat32(streamId, self.accruedPayout or 0)
    streamWriteFloat32(streamId, self.healthSum or 0)
    streamWriteInt32(streamId, self.healthCount or 0)
    streamWriteFloat32(streamId, self.youngSum or 0)
    streamWriteInt32(streamId, self.youngCount or 0)
    writeOptFloat(streamId, self.effQuotaPercent)
    writeOptFloat(streamId, self.effHealth)
    writeOptFloat(streamId, self.effCalf)
    writeOptFloat(streamId, self.effYoungShare)
    writeOptFloat(streamId, self.effYoungAge)
    writeOptFloat(streamId, self.lockedBasePrice)
end

-- Liest IMMER alle Felder (auch wenn der Client die Molkerei nicht kennt),
-- damit der Stream synchron bleibt. Gibt eine reine Datentabelle zurueck.
function MilkContract.readStreamData(streamId)
    local d = {}
    d.dairyId             = streamReadString(streamId)
    d.farmId              = streamReadInt32(streamId)
    d.targetLiters        = streamReadFloat32(streamId)
    d.capPerPeriod        = readOptFloat(streamId)
    d.durationMonths      = streamReadInt32(streamId)
    d.periodsElapsed      = streamReadInt32(streamId)
    d.priceBonus          = streamReadFloat32(streamId)
    d.carriedDebt         = streamReadFloat32(streamId)
    d.deliveredThisPeriod = streamReadFloat32(streamId)
    d.deliveredTotal      = streamReadFloat32(streamId)
    d.premiumThisPeriod   = streamReadFloat32(streamId)
    d.accruedPayout       = streamReadFloat32(streamId)
    d.healthSum           = streamReadFloat32(streamId)
    d.healthCount         = streamReadInt32(streamId)
    d.youngSum            = streamReadFloat32(streamId)
    d.youngCount          = streamReadInt32(streamId)
    d.effQuotaPercent     = readOptFloat(streamId)
    d.effHealth           = readOptFloat(streamId)
    d.effCalf             = readOptFloat(streamId)
    d.effYoungShare       = readOptFloat(streamId)
    d.effYoungAge         = readOptFloat(streamId)
    d.lockedBasePrice     = readOptFloat(streamId)
    return d
end

-- Baut aus den Sync-Daten ein vollwertiges Vertragsobjekt (Client-Seite).
function MilkContract.fromSyncData(d, dairyById)
    local dairy = dairyById ~= nil and dairyById[d.dairyId] or nil
    if dairy == nil then return nil end
    local c = MilkContract.new(dairy, d.farmId, d.targetLiters, d.capPerPeriod)
    for _, k in ipairs({ "durationMonths", "periodsElapsed", "priceBonus", "carriedDebt",
                         "deliveredThisPeriod", "deliveredTotal", "premiumThisPeriod",
                         "accruedPayout", "healthSum", "healthCount", "youngSum", "youngCount",
                         "effQuotaPercent", "effHealth", "effCalf", "effYoungShare",
                         "effYoungAge", "lockedBasePrice" }) do
        c[k] = d[k]
    end
    if c.effCalf ~= nil then c.effCalf = math.floor(c.effCalf + 0.5) end
    if c.effYoungAge ~= nil then c.effYoungAge = math.floor(c.effYoungAge + 0.5) end
    return c
end


-- --------------------------------------------------------------------------
--  Persistenz
-- --------------------------------------------------------------------------
function MilkContract:saveToXMLFile(xmlFile, key)
    -- Typisierte Setter (kein Schema noetig, im Gegensatz zu setValue).
    xmlFile:setString(key .. "#dairyId",             self.dairyId)
    xmlFile:setInt(key .. "#farmId",                 self.farmId or 1)
    xmlFile:setFloat(key .. "#targetLiters",         self.targetLiters or 0)
    if self.capPerPeriod ~= nil then
        xmlFile:setFloat(key .. "#capPerPeriod",     self.capPerPeriod)
    end
    xmlFile:setFloat(key .. "#deliveredThisPeriod",  self.deliveredThisPeriod or 0)
    xmlFile:setFloat(key .. "#deliveredTotal",       self.deliveredTotal or 0)
    xmlFile:setFloat(key .. "#premiumThisPeriod",    self.premiumThisPeriod or 0)
    xmlFile:setFloat(key .. "#accruedPayout",        self.accruedPayout or 0)
    xmlFile:setFloat(key .. "#healthSum",            self.healthSum or 0)
    xmlFile:setInt(key .. "#healthCount",            self.healthCount or 0)
    xmlFile:setInt(key .. "#periodsElapsed",         self.periodsElapsed or 0)
    xmlFile:setInt(key .. "#durationMonths",         self.durationMonths or 12)
    xmlFile:setFloat(key .. "#priceBonus",           self.priceBonus or 1)
    xmlFile:setFloat(key .. "#carriedDebt",          self.carriedDebt or 0)
    if self.effQuotaPercent ~= nil then xmlFile:setFloat(key .. "#effQuotaPercent", self.effQuotaPercent) end
    if self.effHealth       ~= nil then xmlFile:setFloat(key .. "#effHealth",       self.effHealth) end
    if self.effCalf         ~= nil then xmlFile:setInt(key   .. "#effCalf",         self.effCalf) end
    if self.effYoungShare   ~= nil then xmlFile:setFloat(key .. "#effYoungShare",   self.effYoungShare) end
    if self.effYoungAge     ~= nil then xmlFile:setInt(key   .. "#effYoungAge",     self.effYoungAge) end
    if self.lockedBasePrice ~= nil then xmlFile:setFloat(key .. "#lockedBasePrice", self.lockedBasePrice) end
    xmlFile:setFloat(key .. "#youngSum",   self.youngSum or 0)
    xmlFile:setInt(key   .. "#youngCount", self.youngCount or 0)
end

-- @param dairyById  Lookup aus MilkContractLoader.load().byId
function MilkContract.loadFromXMLFile(xmlFile, key, dairyById)
    local dairyId = xmlFile:getString(key .. "#dairyId")
    if dairyId == nil then return nil end

    local dairy = dairyById[dairyId]
    if dairy == nil then
        Logging.warning("[MilkContract] gespeicherte Molkerei '%s' nicht mehr vorhanden - Vertrag verworfen", dairyId)
        return nil
    end

    local farmId       = xmlFile:getInt(key .. "#farmId") or 1
    local targetLiters = xmlFile:getFloat(key .. "#targetLiters") or 0
    local capPerPeriod = xmlFile:getFloat(key .. "#capPerPeriod")   -- nil, wenn nicht vorhanden

    local c = MilkContract.new(dairy, farmId, targetLiters, capPerPeriod)

    -- Migration: fruehere Versionen haben den Monats-Deckel faelschlich mit
    -- daysPerPeriod/30 skaliert und dadurch winzig gespeichert (z.B. 129 l
    -- statt 3862 l). Erkennbar daran, dass er weit unter dem konfigurierten
    -- Monatswert der Molkerei liegt -> auf den Monatswert korrigieren.
    if dairy.hasMaximumCap ~= nil and dairy:hasMaximumCap() then
        local base = (dairy.quota ~= nil) and dairy.quota.litersPerMonth or nil
        if base ~= nil and base > 0 and (c.capPerPeriod == nil or c.capPerPeriod < base * 0.5) then
            c.capPerPeriod = base
        end
    end

    c.deliveredThisPeriod = xmlFile:getFloat(key .. "#deliveredThisPeriod") or 0
    c.deliveredTotal      = xmlFile:getFloat(key .. "#deliveredTotal") or 0
    c.premiumThisPeriod   = xmlFile:getFloat(key .. "#premiumThisPeriod") or 0
    c.accruedPayout       = xmlFile:getFloat(key .. "#accruedPayout") or 0
    c.healthSum           = xmlFile:getFloat(key .. "#healthSum") or 0
    c.healthCount         = xmlFile:getInt(key .. "#healthCount") or 0
    c.periodsElapsed      = xmlFile:getInt(key .. "#periodsElapsed") or 0
    local savedDuration   = xmlFile:getInt(key .. "#durationMonths")
    if savedDuration ~= nil then c.durationMonths = savedDuration end
    c.priceBonus          = xmlFile:getFloat(key .. "#priceBonus") or 1
    c.carriedDebt         = xmlFile:getFloat(key .. "#carriedDebt") or 0
    c.effQuotaPercent     = xmlFile:getFloat(key .. "#effQuotaPercent")
    c.effHealth           = xmlFile:getFloat(key .. "#effHealth")
    c.effCalf             = xmlFile:getInt(key   .. "#effCalf")
    c.effYoungShare       = xmlFile:getFloat(key .. "#effYoungShare")
    c.effYoungAge         = xmlFile:getInt(key   .. "#effYoungAge")
    c.youngSum            = xmlFile:getFloat(key .. "#youngSum") or 0
    c.youngCount          = xmlFile:getInt(key   .. "#youngCount") or 0
    c.lockedBasePrice     = xmlFile:getFloat(key .. "#lockedBasePrice")
    -- Hinweis: Festpreis-Vertraege aus aelteren Versionen (absoluter EUR-Preis,
    -- ohne lockedBasePrice) werden vom Manager nach dem Laden auf den neuen,
    -- relativen Festpreis umgestellt (siehe restoreFromSavegame).
    return c
end
