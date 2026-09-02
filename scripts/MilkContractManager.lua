-- =========================================================================
--  MilkContractManager.lua
--  Zentrale Steuerung: laedt Molkereien, haelt aktive Vertraege, reagiert auf
--  Tag-/Periodenwechsel, sampelt Gesundheit, nimmt taeglich Milch aus dem
--  Stall-Lager und uebernimmt Auszahlung + Persistenz.
--  Abholung/Auszahlung/Persistenz laufen serverseitig; Clients bekommen den
--  Zustand per MilkContractSyncEvent.
-- =========================================================================
MilkContractManager = {}
local MilkContractManager_mt = Class(MilkContractManager)

local MILK_FILLTYPE = "MILK"   -- FillType-Name; ggf. an deine Version anpassen

function MilkContractManager.new(modDirectory)
    local self = setmetatable({}, MilkContractManager_mt)
    self.modDirectory = modDirectory
    self.data      = nil        -- { settings, dairies, byId }
    self.contracts = {}         -- farmId -> MilkContract  (ein Vertrag je Farm)
    self.offerSeed = 1          -- steuert die aktuelle Angebotsauswahl (rotiert jaehrlich)
    self.offerByType = nil      -- Angebot je Milchtyp (aus offerSeed berechnet)
    return self
end

-- Beim Laden der Map aufrufen -----------------------------------------------
function MilkContractManager:load()
    self.data = MilkContractLoader.load(self.modDirectory .. "molkereien.xml")
    if self.data == nil then
        Logging.error("[MilkContract] Keine Molkereidaten - Mod inaktiv")
        return false
    end

    -- Events abonnieren
    g_messageCenter:subscribe(MessageType.DAY_CHANGED,    self.onDayChanged,    self)
    g_messageCenter:subscribe(MessageType.PERIOD_CHANGED, self.onPeriodChanged, self)

    self:restoreFromSavegame()
    self:rebuildOffer()          -- Angebot aus (ggf. geladenem) Seed aufbauen
    return true
end

-- Zugriff fuer die GUI -------------------------------------------------------
-- Alle Molkereien (kompletter Pool) -----------------------------------------
function MilkContractManager:getAllDairies() return self.data ~= nil and self.data.dairies or {} end

-- Aktuell ANGEBOTENE Molkereien (Basis + Zufallsauswahl). Enthaelt zusaetzlich
-- die Molkerei eines laufenden Vertrags, damit man sie im Menue weiter sieht.
function MilkContractManager:getDairies(farmId, milkType)
    if self.data == nil then return {} end
    if self.offerByType == nil then self:rebuildOffer() end
    local mt = milkType or "cow"

    local result, seen = {}, {}
    for _, id in ipairs(self.offerByType[mt] or {}) do
        local d = self.data.byId[id]
        if d ~= nil and not seen[id] then
            result[#result + 1] = d
            seen[id] = true
        end
    end
    -- Molkerei eines aktiven Vertrags dieses Typs immer mit anzeigen
    if farmId ~= nil then
        local c = self:getContract(farmId, mt)
        if c ~= nil and c.dairyId ~= nil and not seen[c.dairyId] then
            local d = self.data.byId[c.dairyId]
            if d ~= nil then table.insert(result, 1, d); seen[c.dairyId] = true end
        end
    end
    return result
end

-- Deterministischer Zufall (LCG), damit Server und Client bei gleichem Seed
-- dasselbe Angebot berechnen -> kein zusaetzlicher Sync noetig ausser dem Seed.
local function makeSeededRandom(seed)
    local state = (seed * 2654435761) % 2147483647
    if state <= 0 then state = state + 2147483646 end
    return function(n)
        state = (state * 48271) % 2147483647
        return (state % n) + 1
    end
end

-- Basis-Molkerei je Milchtyp (immer im Angebot) und die bekannten Typen.
MilkContractManager.BASE_BY_TYPE = { cow = "cooperative", goat = "ziegenhof", buffalo = "bueffelhof" }
MilkContractManager.MILK_TYPES   = { "cow", "goat", "buffalo" }

-- Angebot je Milchtyp bauen: Basis + zufaellige Auswahl des passenden Typs.
function MilkContractManager:rebuildOffer()
    self.offerByType   = { cow = {}, goat = {}, buffalo = {} }
    self.offerDurations = {}
    if self.data == nil then return end

    local rnd = makeSeededRandom(self.offerSeed or 1)

    for _, mt in ipairs(MilkContractManager.MILK_TYPES) do
        local base = MilkContractManager.BASE_BY_TYPE[mt]
        local list = {}
        if base ~= nil and self.data.byId[base] ~= nil then
            list[#list + 1] = base
        end
        local pool = {}
        for _, d in ipairs(self.data.dairies) do
            if (d.milkType or "cow") == mt and d.id ~= base then
                pool[#pool + 1] = d.id
            end
        end
        table.sort(pool)
        for i = #pool, 2, -1 do
            local j = rnd(i); pool[i], pool[j] = pool[j], pool[i]
        end
        local total = 4 + (rnd(2) - 1)                 -- 4 oder 5 gesamt
        local pick  = math.min(total - 1, #pool)
        for i = 1, pick do list[#list + 1] = pool[i] end
        self.offerByType[mt] = list
    end

    -- Laufzeiten fuer alle angebotenen Molkereien (deterministisch aus dem Seed)
    self.offerQuota  = {}   -- [id] = Prozent (minimum) ODER Liter (maximum)
    self.offerHealth = {}   -- [id] = Prozent oder nil
    self.offerCalf   = {}   -- [id] = Monate oder nil
    for _, mt in ipairs(MilkContractManager.MILK_TYPES) do
        for _, id in ipairs(self.offerByType[mt]) do
            self.offerDurations[id] = 3 + (rnd(22) - 1)   -- 3..24

            local d = self.data.byId[id]
            if d ~= nil then
                -- Quote dynamisch (unabhaengig gewuerfelt, eigene Spanne je Molkerei)
                if d.quota.type == "minimum" then
                    local base = d.quota.percentOfEstimated or 0
                    local v    = d.quota.percentVariance or 0
                    self.offerQuota[id] = clampNum(base + rollDelta(rnd, v), 1, 100)
                elseif d.quota.type == "maximum" then
                    local base = d.quota.litersPerMonth or 0
                    local v    = d.quota.litersVariance or 0
                    self.offerQuota[id] = math.max(0, base + rollDelta(rnd, v))
                end
                -- Auflagen dynamisch
                if d.requirements.minHerdHealth ~= nil then
                    local base = d.requirements.minHerdHealth
                    local v    = d.requirements.minHerdHealthVariance or 0
                    self.offerHealth[id] = clampNum(base + rollDelta(rnd, v), 0, 100)
                end
                if d.requirements.minCalfAgeMonths ~= nil then
                    local base = d.requirements.minCalfAgeMonths
                    local v    = d.requirements.minCalfAgeVariance or 0
                    self.offerCalf[id] = math.max(0, base + rollDelta(rnd, v))
                end
            end
        end
    end
end

-- Ganzzahliger Zufallsausschlag in [-v, +v] aus dem Seed-RNG.
function rollDelta(rnd, v)
    v = math.floor((v or 0) + 0.5)
    if v <= 0 then return 0 end
    return rnd(2 * v + 1) - 1 - v
end

function clampNum(x, lo, hi)
    if x < lo then return lo end
    if x > hi then return hi end
    return x
end

-- Getter mit Fallback auf den Basiswert (falls nicht im Angebot oder ohne Varianz)
function MilkContractManager:getOfferQuota(dairyId)
    if self.offerQuota ~= nil and self.offerQuota[dairyId] ~= nil then return self.offerQuota[dairyId] end
    local d = self.data ~= nil and self.data.byId[dairyId] or nil
    if d == nil then return nil end
    if d.quota.type == "minimum" then return d.quota.percentOfEstimated
    elseif d.quota.type == "maximum" then return d.quota.litersPerMonth end
    return nil
end

function MilkContractManager:getOfferHealth(dairyId)
    if self.offerHealth ~= nil and self.offerHealth[dairyId] ~= nil then return self.offerHealth[dairyId] end
    local d = self.data ~= nil and self.data.byId[dairyId] or nil
    return d ~= nil and d.requirements.minHerdHealth or nil
end

function MilkContractManager:getOfferCalf(dairyId)
    if self.offerCalf ~= nil and self.offerCalf[dairyId] ~= nil then return self.offerCalf[dairyId] end
    local d = self.data ~= nil and self.data.byId[dairyId] or nil
    return d ~= nil and d.requirements.minCalfAgeMonths or nil
end

-- Gewuerfelte Laufzeit einer angebotenen Molkerei (Fallback: feste Laufzeit).
function MilkContractManager:getOfferDuration(dairyId)
    if self.offerDurations ~= nil and self.offerDurations[dairyId] ~= nil then
        return self.offerDurations[dairyId]
    end
    local d = self.data ~= nil and self.data.byId[dairyId] or nil
    return d ~= nil and d.durationMonths or 12
end

-- Preis-Bonus fuer laengere Laufzeit: ~1% je Monat ueber dem Minimum (3).
function MilkContractManager:getDurationBonus(months)
    return 1 + 0.01 * math.max(0, (months or 3) - 3)
end

-- Jaehrliche Rotation: neuer Seed -> neues Angebot.
function MilkContractManager:rotateOffer()
    self.offerSeed = (self.offerSeed or 1) + 1
    self:rebuildOffer()
end

function MilkContractManager:getSettings()     return self.data ~= nil and self.data.settings or {} end
-- Vertrags-Speicher: contracts[farmId][milkType] = MilkContract
-- (ein Vertrag je Farm UND Milchtyp -> Kuh + Ziege parallel moeglich)
function MilkContractManager:getContract(farmId, milkType)
    local farm = self.contracts[farmId]
    if farm == nil then return nil end
    if milkType ~= nil then return farm[milkType] end
    return farm.cow or farm.goat            -- ohne Typ: bevorzugt Kuh
end

function MilkContractManager:setContract(farmId, milkType, c)
    if self.contracts[farmId] == nil then self.contracts[farmId] = {} end
    self.contracts[farmId][milkType] = c
end

function MilkContractManager:removeContract(farmId, milkType)
    local farm = self.contracts[farmId]
    if farm == nil then return end
    farm[milkType] = nil
    if next(farm) == nil then self.contracts[farmId] = nil end
end

function MilkContractManager:getFarmContracts(farmId)
    return self.contracts[farmId] or {}
end

-- Flache Momentaufnahme aller Vertraege (sicher zum Iterieren + Entfernen).
function MilkContractManager:allContracts()
    local out = {}
    for farmId, farm in pairs(self.contracts) do
        for milkType, c in pairs(farm) do
            out[#out + 1] = { farmId = farmId, milkType = milkType, contract = c }
        end
    end
    return out
end


-- =========================================================================
--  ZIELMENGE / DECKEL berechnen (periodenskaliert)
-- =========================================================================
-- Faktor, um Bezugsmonat -> aktuelle Periodenlaenge zu skalieren
function MilkContractManager:getPeriodScale()
    local s = self.data.settings
    if not s.scaleByPeriod then return 1 end
    local daysPerPeriod = g_currentMission.environment.daysPerPeriod or 1
    local refDays = s.referenceDays or 30
    return daysPerPeriod / refDays
end

-- geschaetzte Jahresproduktion der Farm (Liter). SEAM-nah: nutzt denselben
-- Herden-Zugriff wie die Gesundheit; hier vereinfacht ueber Tageswert * 365.
function MilkContractManager:estimateAnnualProduction(farmId, fillTypeName)
    local perDay = self:estimateDailyMilk(farmId, fillTypeName)
    -- "Jahr" im Spiel = periodsPerYear * daysPerPeriod
    local env = g_currentMission.environment
    local periodsPerYear = env.periodsPerYear or 12
    local daysPerPeriod  = env.daysPerPeriod or 1
    return perDay * periodsPerYear * daysPerPeriod
end

-- Beim Vertragsabschluss: Ziel + Deckel bestimmen ---------------------------
function MilkContractManager:computeContractNumbers(dairy, farmId, months)
    local target, cap = 0, nil

    if dairy:hasMinimumQuota() then
        local annual = self:estimateAnnualProduction(farmId, dairy.fillTypeName)
        local years = (months or dairy.durationMonths or 12) / 12
        local pct = self:getOfferQuota(dairy.id) or dairy.quota.percentOfEstimated or 0
        target = annual * (pct / 100) * years
    elseif dairy:hasMaximumCap() then
        local cap0 = self:getOfferQuota(dairy.id) or dairy.quota.litersPerMonth or 0
        cap = cap0 * self:getPeriodScale()
    end

    return target, cap
end


-- =========================================================================
--  VERTRAG abschliessen / kuendigen
--  MP: Client schickt ein Event an den Server; der Server fuehrt aus und
--  synchronisiert zurueck. Im Singleplayer/als Host ist g_server gesetzt,
--  dann laeuft es direkt.
-- =========================================================================

-- Von der GUI aufgerufen (Client ODER Host).
function MilkContractManager:requestSign(dairyId, farmId)
    if g_server ~= nil then
        local ok = self:doSign(dairyId, farmId)
        if ok and MilkContractSyncEvent ~= nil then
            MilkContractSyncEvent.sendToClients()
        end
        return ok
    elseif MilkContractActionEvent ~= nil then
        MilkContractActionEvent.sendToServer(farmId, dairyId, MilkContractActionEvent.SIGN)
        return true
    end
    return false
end

function MilkContractManager:requestCancel(farmId, milkType)
    if g_server ~= nil then
        self:doCancel(farmId, milkType)
        if MilkContractSyncEvent ~= nil then
            MilkContractSyncEvent.sendToClients()
        end
    elseif MilkContractActionEvent ~= nil then
        MilkContractActionEvent.sendToServer(farmId, nil, MilkContractActionEvent.CANCEL, milkType)
    end
end

function MilkContractManager:requestExtend(farmId, milkType)
    if g_server ~= nil then
        self:doExtend(farmId, milkType)
        if MilkContractSyncEvent ~= nil then
            MilkContractSyncEvent.sendToClients()
        end
    elseif MilkContractActionEvent ~= nil then
        MilkContractActionEvent.sendToServer(farmId, nil, MilkContractActionEvent.EXTEND, milkType)
    end
end

-- Server-autoritativ: legt den Vertrag tatsaechlich an.
function MilkContractManager:doSign(dairyId, farmId)
    local dairy = self.data.byId[dairyId]
    if dairy == nil then return false end
    local milkType = dairy.milkType or "cow"
    if self:getContract(farmId, milkType) ~= nil then return false end   -- je Typ nur einer

    local months = self:getOfferDuration(dairyId)
    local bonus  = self:getDurationBonus(months)
    local target, cap = self:computeContractNumbers(dairy, farmId, months)

    local c = MilkContract.new(dairy, farmId, target, cap)
    c.durationMonths = months
    c.priceBonus     = bonus
    -- gewuerfelte (dynamische) Konditionen im Vertrag fixieren
    c.effQuotaPercent = dairy:hasMinimumQuota() and self:getOfferQuota(dairyId) or nil
    c.effHealth       = (dairy.requirements.minHerdHealth ~= nil) and self:getOfferHealth(dairyId) or nil
    c.effCalf         = (dairy.requirements.minCalfAgeMonths ~= nil) and self:getOfferCalf(dairyId) or nil
    self:setContract(farmId, milkType, c)
    Logging.info("[MilkContract] Farm %d: Vertrag mit '%s' [%s] (%d Monate, Ziel %.0f l, Bonus x%.2f)",
        farmId, dairyId, milkType, months, target, bonus)
    return true
end

function MilkContractManager:doCancel(farmId, milkType)
    if milkType == nil then
        self.contracts[farmId] = nil            -- alle Typen dieser Farm
    else
        self:removeContract(farmId, milkType)
    end
end

-- Strafe fuer vorzeitige Kuendigung: offener Restwert bis Vertragsende x 1.2
MilkContractManager.EARLY_CANCEL_FACTOR = 1.2

function MilkContractManager:getEarlyCancelPenalty(contract, farmId)
    if contract == nil then return 0 end
    local info = self:getContractValueInfo(contract, farmId)
    local dur  = contract.durationMonths or 12
    local remaining = math.max(0, dur - (contract.periodsElapsed or 0))
    local frac = (dur > 0) and (remaining / dur) or 0
    local restValue = (info.projectedValue or 0) * frac
    return restValue * MilkContractManager.EARLY_CANCEL_FACTOR
end

function MilkContractManager:doEarlyCancel(farmId, milkType)
    local c = self:getContract(farmId, milkType)
    if c == nil then return end
    local penalty = self:getEarlyCancelPenalty(c, farmId)
    if penalty > 0 then
        self:addMoney(farmId, -penalty, false)
    end
    self:removeContract(farmId, milkType)
    self:notifyAll(string.format(g_i18n:getText("mc_notifyCancelled"),
        self:dairyName(c.dairy), g_i18n:formatMoney(penalty, 0, true)))
    Logging.info("[MilkContract] Farm %d: '%s' vorzeitig gekuendigt (Strafe %.0f).",
        farmId, c.dairyId, penalty)
end

function MilkContractManager:requestEarlyCancel(farmId, milkType)
    if g_server ~= nil then
        self:doEarlyCancel(farmId, milkType)
        if MilkContractSyncEvent ~= nil then MilkContractSyncEvent.sendToClients() end
    elseif MilkContractActionEvent ~= nil then
        MilkContractActionEvent.sendToServer(farmId, nil, MilkContractActionEvent.EARLY_CANCEL, milkType)
    end
end

-- Treuebonus beim Verlaengern (einmalig obendrauf auf den Preis).
MilkContractManager.LOYALTY_BONUS = 0.05   -- +5%

-- Ist der Vertrag im Verlaengerungsfenster (letzter Monat vor Ablauf)?
function MilkContractManager:isRenewable(contract)
    if contract == nil or contract.durationMonths == nil then return false end
    local remaining = contract.durationMonths - (contract.periodsElapsed or 0)
    return remaining <= 1 and remaining > 0
end

-- Verlaengern: gleiche Molkerei/Laufzeit/Preis + kleiner Treuebonus, neuer Zeitraum.
function MilkContractManager:doExtend(farmId, milkType)
    local c = self:getContract(farmId, milkType)
    if c == nil then return end

    -- offenen Betrag der laufenden Periode zuerst auszahlen
    if (c.accruedPayout or 0) > 0 then
        self:addMoney(farmId, c.accruedPayout, true)
    end

    -- Fehlmenge des ablaufenden Vertrags als Nachliefer-Schuld uebernehmen
    -- (statt Geldstrafe -> wird auf das neue Ziel draufgerechnet)
    local carryDebt = 0
    if c.dairy:hasMinimumQuota() then
        carryDebt = math.max(0, (c.targetLiters or 0) - (c.deliveredTotal or 0))
    end

    -- neuen Zeitraum starten (Laufzeit bleibt), Treuebonus auf den Preis
    c.periodsElapsed     = 0
    c.priceBonus         = (c.priceBonus or 1) * (1 + MilkContractManager.LOYALTY_BONUS)
    c.deliveredThisPeriod = 0
    c.deliveredTotal      = 0
    c.premiumThisPeriod   = 0
    c.accruedPayout       = 0
    c.healthSum           = 0
    c.healthCount         = 0

    -- Ziel/Deckel fuer den neuen Zeitraum: normales Ziel + uebernommene Restschuld
    local target, cap = self:computeContractNumbers(c.dairy, farmId, c.durationMonths)
    c.targetLiters = target + carryDebt
    c.capPerPeriod = cap
    c.carriedDebt  = carryDebt      -- nur zur Anzeige

    Logging.info("[MilkContract] Farm %d: '%s' verlaengert (Bonus x%.2f, Nachlieferung %.0f l).",
        farmId, c.dairyId, c.priceBonus, carryDebt)
    if carryDebt > 0 then
        self:notifyAll(string.format(g_i18n:getText("mc_notifyExtendedDebt"),
            self:dairyName(c.dairy), g_i18n:formatNumber(carryDebt, 0)))
    else
        self:notifyAll(string.format(g_i18n:getText("mc_notifyExtended"), self:dairyName(c.dairy)))
    end
end

-- =========================================================================
--  MP-Sync-Daten (nur Farm -> Molkerei; Vollzustand bleibt am Server)
-- =========================================================================
function MilkContractManager:getSyncEntries()
    local entries = {}
    for _, rec in ipairs(self:allContracts()) do
        table.insert(entries, { farmId = rec.farmId, dairyId = rec.contract.dairyId, milkType = rec.milkType })
    end
    return entries
end

-- Client uebernimmt die Zuordnung; baut leichte Anzeige-Objekte.
function MilkContractManager:applySyncEntries(entries)
    self.contracts = {}
    for _, e in ipairs(entries or {}) do
        local dairy = self.data ~= nil and self.data.byId[e.dairyId] or nil
        if dairy ~= nil then
            local mt = e.milkType or dairy.milkType or "cow"
            self:setContract(e.farmId, mt, { dairyId = e.dairyId, dairy = dairy })
        end
    end
    Logging.info("[MilkContract] Vertragsliste vom Server empfangen (%d).", #(entries or {}))
end


-- =========================================================================
--  EVENTS
-- =========================================================================
function MilkContractManager:onDayChanged()
    -- Abholung/Sampling laufen NUR auf dem Server (Milch + Geld sind Server-Wahrheit).
    if g_server == nil then return end

    local marketPrice = self:getCurrentMilkMarketPrice()
    for _, rec in ipairs(self:allContracts()) do
        local farmId, contract = rec.farmId, rec.contract
        -- 1) Gesundheit sampeln (nur wenn die Molkerei sie fordert)
        if contract.dairy ~= nil and contract.dairy.needsHealthCheck ~= nil
           and self.data.settings.sampleHealthOnDayChange and contract.dairy:needsHealthCheck() then
            if contract.sampleHealth ~= nil then
                contract:sampleHealth(self:getWeightedHerdHealth(farmId))
            end
        end
        -- 2) Milch aus den Staellen abnehmen (taeglich, damit nichts ueberlaeuft)
        if contract.peekTakeAmount ~= nil then
            self:collectMilk(farmId, contract)   -- Preis wird je Fuelltyp intern bestimmt
        end
    end
end

-- Liefert die Fuelltyp-Indizes eines Milch-Specs, robust gegen beide
-- moeglichen Strukturen (Array von Indizes ODER nach Index gekeyt).
local function getMilkFillTypeIndices(spec)
    local out = {}
    if spec ~= nil and spec.fillTypes ~= nil then
        for k, v in pairs(spec.fillTypes) do
            if type(v) == "number" then
                table.insert(out, v)      -- Array: Wert ist der Index
            elseif type(k) == "number" then
                table.insert(out, k)      -- gekeyt: Schluessel ist der Index
            end
        end
    end
    return out
end

-- Nimmt taeglich die Vertragsmenge aus dem Milch-Lager der Kuh-Staelle.
-- Sicherung: nur gutschreiben, wenn das Lager auch WIRKLICH gesunken ist.
function MilkContractManager:collectMilk(farmId, contract, marketPrice)
    local fillTypeName = contract.dairy ~= nil and contract.dairy.fillTypeName or MILK_FILLTYPE
    local price = marketPrice or self:getCurrentMilkMarketPrice(fillTypeName)
    local wantIndex = g_fillTypeManager ~= nil and g_fillTypeManager:getFillTypeIndexByName(fillTypeName) or nil

    for _, e in ipairs(self:getProducers(farmId, fillTypeName)) do
        if e.kind == "milk" then
            -- Kuh: Milch aus dem Tank
            local spec = e.spec
            for _, ftIndex in ipairs(getMilkFillTypeIndices(spec)) do
                if wantIndex == nil or ftIndex == wantIndex then
                    local available = e.placeable:getHusbandryFillLevel(ftIndex)
                    if available ~= nil and available > 0 then
                        local wanted = contract:peekTakeAmount(available)
                        if wanted > 0 then
                            local before = available
                            self:reduceStorage(e.placeable, farmId, ftIndex, wanted)
                            local after = e.placeable:getHusbandryFillLevel(ftIndex) or before
                            local removed = before - after
                            if removed > 0.001 then contract:commitTake(removed, price) end
                        end
                    end
                end
            end
        else
            -- Ziege etc.: Inhalt aus den gespawnten Paletten abnehmen
            self:collectFromPallets(farmId, contract, e.spec, wantIndex, price)
        end
    end
end

-- Nimmt Milch aus den am Stall stehenden Paletten (leert sie, entfernt leere).
function MilkContractManager:collectFromPallets(farmId, contract, spec, wantIndex, price)
    if spec == nil or spec.pallets == nil then return end
    local emptied = {}
    for pallet, _ in pairs(spec.pallets) do
        if pallet ~= nil and pallet.spec_pallet ~= nil and pallet.getFillUnitFillLevel ~= nil then
            local fu  = pallet.spec_pallet.fillUnitIndex
            local pft = pallet:getFillUnitFillType(fu)
            if wantIndex == nil or pft == wantIndex then
                local lvl = pallet:getFillUnitFillLevel(fu) or 0
                if lvl > 0 then
                    local wanted = contract:peekTakeAmount(lvl)
                    if wanted > 0 then
                        -- negative Menge = entnehmen (bestaetigte Signatur)
                        local delta = pallet:addFillUnitFillLevel(farmId, fu, -wanted, pft, ToolType.UNDEFINED)
                        local removed = -(delta or 0)
                        if removed > 0.001 then contract:commitTake(removed, price) end
                        if (pallet:getFillUnitFillLevel(fu) or 0) <= 0.001 then
                            table.insert(emptied, pallet)
                        end
                    end
                end
            end
        end
    end
    -- leere Paletten entfernen (defensiv)
    for _, pallet in ipairs(emptied) do
        spec.pallets[pallet] = nil
        pcall(function() pallet:delete() end)
    end
end

-- Reduziert den Milch-Lagerstand der Husbandry.
-- Signatur bestaetigt (FS25_automaticMilkSale):
--   husbandry:removeHusbandryFillLevel(nil, menge, fillTypeIndex)
function MilkContractManager:reduceStorage(husbandry, farmId, ftIndex, amount)
    if husbandry.removeHusbandryFillLevel ~= nil then
        husbandry:removeHusbandryFillLevel(nil, amount, ftIndex)
    end
end

function MilkContractManager:onPeriodChanged()
    -- Auszahlung/Strafe/Ende laufen NUR auf dem Server.
    if g_server == nil then return end

    local marketPrice = self:getCurrentMilkMarketPrice()
    local anyEnded = false

    -- Jaehrliche Angebots-Rotation zum Jahreswechsel (Periode 1)
    local period = (g_currentMission.environment ~= nil and g_currentMission.environment.currentPeriod) or 1
    if period == 1 then
        self:rotateOffer()
        anyEnded = true   -- Clients ueber neuen Seed/Angebot informieren
    end

    for _, rec in ipairs(self:allContracts()) do
        local farmId, contract, milkType = rec.farmId, rec.contract, rec.milkType
        local mp = self:getCurrentMilkMarketPrice(contract.dairy ~= nil and contract.dairy.fillTypeName or nil)
        -- Laufzeit hochzaehlen (ein Periodenwechsel = ein Monat)
        contract.periodsElapsed = (contract.periodsElapsed or 0) + 1
        local isContractEnd = contract.periodsElapsed >= (contract.durationMonths or 12)

        -- Am Vertragsende immer auszahlen, sonst nach Rhythmus
        local isPayout = self:isPayoutDue(contract) or isContractEnd

        local settle = contract:settlePeriod(isPayout, isContractEnd, mp)

        if settle.payout > 0 then
            self:addMoney(farmId, settle.payout, true)
            self:notifyAll(string.format(g_i18n:getText("mc_notifyPayout"),
                g_i18n:formatMoney(settle.payout, 0, true), self:dairyName(contract.dairy)))
        end
        local hadPenalty = false
        if settle.penalty > 0 then
            self:addMoney(farmId, -settle.penalty, false)
            hadPenalty = true
            self:notifyAll(string.format(g_i18n:getText("mc_notifyEndedPenalty"),
                self:dairyName(contract.dairy), g_i18n:formatMoney(settle.penalty, 0, true)))
            Logging.info("[MilkContract] Farm %d: Vertragsstrafe %.0f", farmId, settle.penalty)
        end

        if isContractEnd then
            if not contract:meetsHealthRequirement() then
                Logging.info("[MilkContract] Farm %d: Gesundheitsauflage verfehlt", farmId)
            end
            -- Vertrag ist ausgelaufen -> diesen Typ freigeben (Spieler kann neu waehlen)
            self:removeContract(farmId, milkType)
            anyEnded = true
            if not hadPenalty then
                self:notifyAll(string.format(g_i18n:getText("mc_notifyEnded"), self:dairyName(contract.dairy)))
            end
            Logging.info("[MilkContract] Farm %d: Vertrag mit '%s' ausgelaufen.", farmId, contract.dairyId)
        elseif (contract.durationMonths or 12) - contract.periodsElapsed == 1 then
            -- letzter Monat beginnt -> einmalig vorwarnen
            self:notifyAll(string.format(g_i18n:getText("mc_notifyExpiring"), self:dairyName(contract.dairy)))
        end
    end

    -- Clients ueber freigewordene/geaenderte Vertraege informieren
    if anyEnded and MilkContractSyncEvent ~= nil then
        MilkContractSyncEvent.sendToClients()
    end
end

-- Monate bis zur naechsten Auszahlung (fuer die Status-Anzeige).
function MilkContractManager:getPeriodsUntilPayout(contract)
    local n = self:getIntervalMonths(contract.dairy.payout)
    local elapsed = contract.periodsElapsed or 0
    local r = elapsed % n
    local steps = (r == 0) and n or (n - r)
    -- Am Vertragsende wird ohnehin ausgezahlt -> nicht laenger als Restlaufzeit
    local remaining = math.max(0, (contract.durationMonths or 12) - elapsed)
    if remaining > 0 then steps = math.min(steps, remaining) end
    return steps
end

-- Sicher bereits verdient (aufgelaufen) + Hochrechnung auf ein Vertragsjahr.
function MilkContractManager:getContractValueInfo(contract, farmId)
    local ftName = contract.dairy ~= nil and contract.dairy.fillTypeName or nil
    local price  = contract:getPricePerLiter(self:getCurrentMilkMarketPrice(ftName))
    local annual = self:estimateAnnualProduction(farmId, ftName)
    local dairy  = contract.dairy
    local years  = (contract.durationMonths or 12) / 12

    local projectedLiters
    if dairy:hasMinimumQuota() then
        projectedLiters = contract.targetLiters or 0   -- bereits auf die Laufzeit skaliert
    elseif dairy:hasMaximumCap() then
        projectedLiters = math.min(annual, (contract.capPerPeriod or 0) * 12) * years
    else
        projectedLiters = annual * years
    end

    return {
        secure          = contract.accruedPayout or 0,
        projectedValue  = projectedLiters * price,
        projectedLiters = projectedLiters,
        price           = price,
    }
end

-- Molkerei-Name aufloesen ($l10n_ -> Text)
function MilkContractManager:dairyName(dairy)
    if dairy == nil then return "?" end
    local t = dairy.title
    local key = t ~= nil and t:match("^%$l10n_(.+)$") or nil
    if key ~= nil then return g_i18n:getText(key) end
    return t or dairy.id
end

-- FS-Notification (defensiv, Methode variiert je Version) - nach VD-Muster.
function MilkContractManager:notify(text)
    if text == nil then return end
    local mission = g_currentMission
    if mission == nil then return end
    if mission.addIngameNotification ~= nil and FSBaseMission ~= nil and FSBaseMission.INGAME_NOTIFICATION_OK ~= nil then
        mission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK, text)
        return
    end
    if mission.hud ~= nil and mission.hud.addSideNotification ~= nil then
        mission.hud:addSideNotification(nil, text)
        return
    end
    if mission.showBlinkingWarning ~= nil then
        mission:showBlinkingWarning(text, 4000)
        return
    end
    Logging.info("[MilkContract] (Notification) %s", text)
end

-- Zeigt lokal (Host/SP) UND schickt die Meldung an alle Clients.
function MilkContractManager:notifyAll(text)
    self:notify(text)
    if g_server ~= nil and MilkContractNotifyEvent ~= nil then
        g_server:broadcastEvent(MilkContractNotifyEvent.new(text), false, nil, nil)
    end
end

-- Monate je Auszahlungsintervall
function MilkContractManager:getIntervalMonths(interval)
    if interval == "monthly"    then return 1  end
    if interval == "quarterly"  then return 3  end
    if interval == "halfyearly" then return 6  end
    if interval == "yearly"     then return 12 end
    return 1
end

-- Auszahlungsintervall-Logik (vertrags-relativ: alle N Monate seit Abschluss)
function MilkContractManager:isPayoutDue(contract)
    local n = self:getIntervalMonths(contract.dairy.payout)
    local elapsed = contract.periodsElapsed or 0
    -- periodsElapsed wurde in onPeriodChanged bereits hochgezaehlt
    return elapsed > 0 and (elapsed % n) == 0
end

-- Vertragszeitraum-Ende (hier: Jahreswechsel = Periode 1) --------------------
function MilkContractManager:isContractEnd(contract)
    return (g_currentMission.environment.currentPeriod or 1) == 1
end


-- =========================================================================
--  ENGINE-ZUGRIFFE
--  Es bleibt EINE zu verifizierende Nahtstelle: getCowHusbandries(). Alles
--  andere (Produktionsschaetzung, Milchabnahme, Gesundheit) baut darauf auf.
-- =========================================================================

-- Liste aller Kuh-Staelle einer Farm.
-- Einheitliche Erkennung: liefert Produzenten eines Fuelltyps mit Art-Kennung.
-- kind="milk"    -> Kuh-Stall (spec_husbandryMilk, Tank)
-- kind="pallets" -> Ziegen-/Schaf-/Huehnerstall (spec_husbandryPallets, Paletten)
function MilkContractManager:getProducers(farmId, fillTypeName)
    local out = {}
    local system = g_currentMission.husbandrySystem
    if system == nil or system.placeables == nil then return out end

    local wantIndex = nil
    if fillTypeName ~= nil and g_fillTypeManager ~= nil then
        wantIndex = g_fillTypeManager:getFillTypeIndexByName(fillTypeName)
    end

    for _, h in ipairs(system.placeables) do
        if h.getOwnerFarmId == nil or h:getOwnerFarmId() == farmId then
            local milk = h.spec_husbandryMilk
            if milk ~= nil and milk.hasMilkProduction then
                local match = (wantIndex == nil)
                if not match then
                    for _, i in ipairs(getMilkFillTypeIndices(milk)) do
                        if i == wantIndex then match = true; break end
                    end
                end
                if match then out[#out + 1] = { placeable = h, spec = milk, kind = "milk" } end
            end
            local pal = h.spec_husbandryPallets
            if pal ~= nil and pal.fillTypes ~= nil then
                local match = (wantIndex == nil)
                if not match then
                    for _, i in ipairs(pal.fillTypes) do
                        if i == wantIndex then match = true; break end
                    end
                end
                if match then out[#out + 1] = { placeable = h, spec = pal, kind = "pallets" } end
            end
        end
    end
    return out
end

-- Staelle, die einen BESTIMMTEN Milch-Fuelltyp produzieren (Kuh=MILK, Ziege=GOATMILK).
-- fillTypeName=nil -> alle milchgebenden Staelle (Rueckwaertskompatibilitaet).
function MilkContractManager:getHusbandriesForFillType(farmId, fillTypeName)
    local result = {}
    local system = g_currentMission.husbandrySystem
    if system == nil or system.placeables == nil then return result end

    local wantIndex = nil
    if fillTypeName ~= nil and g_fillTypeManager ~= nil then
        wantIndex = g_fillTypeManager:getFillTypeIndexByName(fillTypeName)
    end

    for _, husbandry in ipairs(system.placeables) do
        local spec = husbandry.spec_husbandryMilk
        if spec ~= nil and spec.hasMilkProduction then
            if husbandry.getOwnerFarmId == nil or husbandry:getOwnerFarmId() == farmId then
                local matches = (wantIndex == nil)
                if not matches then
                    for _, ftIndex in ipairs(getMilkFillTypeIndices(spec)) do
                        if ftIndex == wantIndex then matches = true; break end
                    end
                end
                if matches then table.insert(result, husbandry) end
            end
        end
    end
    return result
end

-- Rueckwaertskompatibel: alle milchgebenden Staelle (frueher "Kuh"-Staelle).
function MilkContractManager:getCowHusbandries(farmId)
    return self:getHusbandriesForFillType(farmId, nil)
end

-- Gewichteter Ø-Gesundheitswert aller Kuh-Staelle (0..100).
-- Hinweis: getAverageHealthFactor existiert NICHT (Diagnose). Die Gesundheit
-- liegt in den Tier-Clustern (getClusters). Feldname wird defensiv geprueft.
function MilkContractManager:getWeightedHerdHealth(farmId)
    local sumH, sumN = 0, 0
    for _, husbandry in ipairs(self:getCowHusbandries(farmId)) do
        if husbandry.getClusters ~= nil then
            local clusters = husbandry:getClusters()
            if clusters ~= nil then
                for _, c in ipairs(clusters) do
                    local n = c.numAnimals or (c.getNumAnimals ~= nil and c:getNumAnimals()) or 0
                    -- Gesundheit im Cluster kann 'health' (0..100) heissen; defensiv lesen
                    local h = c.health or c.healthFactor
                    if h ~= nil and n > 0 then
                        if h <= 1 then h = h * 100 end   -- 0..1 -> %
                        sumH = sumH + h * n
                        sumN = sumN + n
                    end
                end
            end
        end
    end
    if sumN == 0 then return nil end   -- kein Wert -> nicht bestrafen
    return sumH / sumN
end

-- Geschaetzte Tagesmilchmenge (Liter). Nutzt die schon im Spiel gerechneten
-- litersPerHour aus spec_husbandryMilk (siehe onHusbandryAnimalsUpdate).
function MilkContractManager:estimateDailyMilk(farmId, fillTypeName)
    local total = 0
    local wantIndex = nil
    if fillTypeName ~= nil and g_fillTypeManager ~= nil then
        wantIndex = g_fillTypeManager:getFillTypeIndexByName(fillTypeName)
    end
    for _, e in ipairs(self:getProducers(farmId, fillTypeName)) do
        local spec = e.spec
        if e.kind == "milk" then
            for _, ftIndex in ipairs(getMilkFillTypeIndices(spec)) do
                if wantIndex == nil or ftIndex == wantIndex then
                    total = total + ((spec.litersPerHour ~= nil and spec.litersPerHour[ftIndex]) or 0) * 24
                end
            end
        else -- pallets
            for _, ftIndex in ipairs(spec.fillTypes or {}) do
                if wantIndex == nil or ftIndex == wantIndex then
                    total = total + ((spec.litersPerHour ~= nil and spec.litersPerHour[ftIndex]) or 0) * 24
                end
            end
        end
    end
    return total
end

-- Listet ALLE milchgebenden Staelle nach echtem Fuelltypnamen (fuer Diagnose).
function MilkContractManager:listMilkStalls(farmId)
    local function ftName(ft)
        if g_fillTypeManager == nil then return tostring(ft) end
        if g_fillTypeManager.getFillTypeNameByIndex ~= nil then
            local n = g_fillTypeManager:getFillTypeNameByIndex(ft)
            if n ~= nil then return n end
        end
        local o = g_fillTypeManager.getFillTypeByIndex ~= nil and g_fillTypeManager:getFillTypeByIndex(ft) or nil
        if o ~= nil then return o.name or o.title or tostring(ft) end
        return tostring(ft)
    end

    local byFt = {}
    for _, e in ipairs(self:getProducers(farmId, nil)) do
        local spec = e.spec
        local indices = (e.kind == "milk") and getMilkFillTypeIndices(spec) or (spec.fillTypes or {})
        for _, ft in ipairs(indices) do
            local name = ftName(ft)
            local rec = byFt[name]
            if rec == nil then rec = { name = name, count = 0, tank = 0, pallets = 0, daily = 0, stored = 0 }; byFt[name] = rec end
            rec.count = rec.count + 1
            if e.kind == "milk" then rec.tank = rec.tank + 1 else rec.pallets = rec.pallets + 1 end
            rec.daily = rec.daily + ((spec.litersPerHour ~= nil and spec.litersPerHour[ft]) or 0) * 24
            if e.kind == "milk" then
                rec.stored = rec.stored + (e.placeable:getHusbandryFillLevel(ft) or 0)
            else
                rec.stored = rec.stored + ((spec.fillLevels ~= nil and spec.fillLevels[ft]) or 0)
                                        + ((spec.pendingLiters ~= nil and spec.pendingLiters[ft]) or 0)
            end
        end
    end
    return byFt
end

-- Aktuell im Stall-Lager vorhandene Milch eines Fuelltyps (fuer Test/Anzeige).
function MilkContractManager:getStoredMilk(farmId, fillTypeName)
    local total = 0
    local wantIndex = nil
    if fillTypeName ~= nil and g_fillTypeManager ~= nil then
        wantIndex = g_fillTypeManager:getFillTypeIndexByName(fillTypeName)
    end
    for _, e in ipairs(self:getProducers(farmId, fillTypeName)) do
        local spec = e.spec
        if e.kind == "milk" then
            for _, ftIndex in ipairs(getMilkFillTypeIndices(spec)) do
                if wantIndex == nil or ftIndex == wantIndex then
                    total = total + (e.placeable:getHusbandryFillLevel(ftIndex) or 0)
                end
            end
        else -- pallets: gespawnte Paletten + Puffer
            for _, ftIndex in ipairs(spec.fillTypes or {}) do
                if wantIndex == nil or ftIndex == wantIndex then
                    total = total + ((spec.fillLevels ~= nil and spec.fillLevels[ftIndex]) or 0)
                                  + ((spec.pendingLiters ~= nil and spec.pendingLiters[ftIndex]) or 0)
                end
            end
        end
    end
    return total
end

function MilkContractManager:getCurrentMilkMarketPrice(fillTypeName)
    -- Bestaetigte Quelle (FS25_automaticMilkSale): economyManager:getPricePerLiter.
    local name = fillTypeName or MILK_FILLTYPE
    local ftIndex = g_fillTypeManager ~= nil and g_fillTypeManager:getFillTypeIndexByName(name) or nil
    if ftIndex ~= nil and g_currentMission ~= nil and g_currentMission.economyManager ~= nil
       and g_currentMission.economyManager.getPricePerLiter ~= nil then
        local p = g_currentMission.economyManager:getPricePerLiter(ftIndex)
        if p ~= nil and p > 0 then return p end
    end
    return 1.0
end

function MilkContractManager:addMoney(farmId, amount, isPositive)
    -- Milchverkauf bucht als SOLD_MILK (wie FS25_automaticMilkSale).
    local moneyType = MoneyType ~= nil and (MoneyType.SOLD_MILK or MoneyType.OTHER) or nil
    g_currentMission:addMoney(amount, farmId, moneyType, true, true)
end


-- =========================================================================
--  PERSISTENZ  (eigene Datei im Savegame-Verzeichnis)
-- =========================================================================
function MilkContractManager:getSavegamePath()
    if g_currentMission == nil or g_currentMission.missionInfo == nil then return nil end
    local dir = g_currentMission.missionInfo.savegameDirectory
    if dir == nil then return nil end
    return dir .. "/milkContract.xml"
end

-- Wird per prependedFunction beim Speichern des Savegames aufgerufen.
-- missionInfo kommt von FSCareerMissionInfo.saveToXMLFile.
function MilkContractManager:saveToSavegame(missionInfo)
    -- Nur der Server/Host besitzt den autoritativen Zustand + savegameDirectory.
    if g_server == nil then return end
    local dir = (missionInfo ~= nil and missionInfo.savegameDirectory)
             or (g_currentMission.missionInfo and g_currentMission.missionInfo.savegameDirectory)
    if missionInfo ~= nil and missionInfo.isValid == false then return end
    if dir == nil then return end

    local path = dir .. "/milkContract.xml"
    local xmlFile = XMLFile.create("milkContractSave", path, "milkContract")
    if xmlFile == nil then
        Logging.warning("[MilkContract] Savegame-Datei konnte nicht angelegt werden (%s).", path)
        return
    end

    xmlFile:setInt("milkContract#offerSeed", self.offerSeed or 1)

    local i = 0
    for _, rec in ipairs(self:allContracts()) do
        local contract = rec.contract
        if contract.saveToXMLFile ~= nil then
            local key = string.format("milkContract.contracts.contract(%d)", i)
            contract:saveToXMLFile(xmlFile, key)
            i = i + 1
        end
    end

    xmlFile:save()
    xmlFile:delete()
    Logging.info("[MilkContract] %d Vertrag/Vertraege gespeichert (%s).", i, path)
end

function MilkContractManager:restoreFromSavegame()
    -- Nur der Server laedt (Clients bekommen den Zustand per Sync-Event).
    if g_server == nil then return end
    local path = self:getSavegamePath()
    if path == nil or not fileExists(path) then
        Logging.info("[MilkContract] Keine Savegame-Datei zum Laden (%s).", tostring(path))
        return
    end

    local xmlFile = XMLFile.load("milkContractSave", path)
    if xmlFile == nil then return end

    self.offerSeed = xmlFile:getInt("milkContract#offerSeed") or self.offerSeed or 1

    local n = 0
    xmlFile:iterate("milkContract.contracts.contract", function(_, key)
        local c = MilkContract.loadFromXMLFile(xmlFile, key, self.data.byId)
        if c ~= nil then
            local mt = (c.dairy ~= nil and c.dairy.milkType) or "cow"
            self:setContract(c.farmId, mt, c)
            n = n + 1
        end
    end)

    xmlFile:delete()
    Logging.info("[MilkContract] %d Vertrag/Vertraege aus Savegame wiederhergestellt.", n)
end


-- =========================================================================
--  BOOTSTRAP  -  Manager erzeugen und in den Spiel-Lebenszyklus haengen
-- =========================================================================
local modDirectory = g_currentModDirectory
g_milkContractManager = nil

-- Netzwerk-Events IMMER laden (Server UND Client, auch dedizierter Server -
-- die Event-Basisklasse ist ueberall da, anders als die GUI).
source(modDirectory .. "scripts/MilkContractSyncEvent.lua")

-- Test-Konsolenbefehle (optional; leicht entfernbar)
source(modDirectory .. "scripts/MilkContractTest.lua")

-- GUI-Klassen NUR am Client und NUR wenn die GUI-Basisklasse bereit ist per
-- source() laden (nicht ueber extraSourceFiles - dort ist
-- TabbedMenuFrameElement noch nicht verfuegbar). Nach VehicleDelivery-Muster.
if g_dedicatedServer == nil and TabbedMenuFrameElement ~= nil then
    source(modDirectory .. "scripts/gui/MilkContractFrame.lua")
    source(modDirectory .. "scripts/gui/InGameMenuMilkContract.lua")
end

local function onMissionLoaded(mission)
    if g_milkContractManager == nil then
        g_milkContractManager = MilkContractManager.new(modDirectory)
        g_milkContractManager:load()
    end

    -- Ein reiner Client fordert die aktuelle Vertragsliste vom Server an.
    if g_client ~= nil and g_server == nil and MilkContractSyncRequestEvent ~= nil then
        MilkContractSyncRequestEvent.sendToServer()
    end

    -- Menue-Seite nur am Client einhaengen (Dedi hat keine GUI).
    local hasGui = (g_dedicatedServer == nil) and (g_gui ~= nil)
    if hasGui and InGameMenuMilkContract ~= nil then
        InGameMenuMilkContract:setup()
    end

    -- Test-Konsolenbefehle registrieren (falls Modul geladen)
    if MilkContractTest ~= nil and MilkContractTest.register ~= nil then
        MilkContractTest.register()
    end
end

local function onMissionSave(missionInfo)
    if g_milkContractManager ~= nil then
        g_milkContractManager:saveToSavegame(missionInfo)
    end
end

-- Nach vollstaendigem Map-Load initialisieren
if Mission00 ~= nil and Mission00.loadMission00Finished ~= nil then
    Mission00.loadMission00Finished =
        Utils.appendedFunction(Mission00.loadMission00Finished, onMissionLoaded)
end

-- Persistenz: prependedFunction wie in der Liefermod (missionInfo als Argument).
if FSCareerMissionInfo ~= nil and FSCareerMissionInfo.saveToXMLFile ~= nil then
    FSCareerMissionInfo.saveToXMLFile =
        Utils.prependedFunction(FSCareerMissionInfo.saveToXMLFile, onMissionSave)
end
