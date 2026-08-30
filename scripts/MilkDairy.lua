-- =========================================================================
--  MilkDairy.lua
--  Datenobjekt einer einzelnen Molkerei (aus molkereien.xml erzeugt).
-- =========================================================================
MilkDairy = {}
local MilkDairy_mt = Class(MilkDairy)

function MilkDairy.new(id)
    local self = setmetatable({}, MilkDairy_mt)
    self.id            = id
    self.title         = nil
    self.desc          = nil
    self.milkType      = "cow"        -- "cow" oder "goat"
    self.fillTypeName  = "MILK"       -- FillType-Name (aus milkType abgeleitet, ueberschreibbar)
    self.pricing       = { type = "market", marketMultiplier = 1.0 }
    self.quota         = { type = "none" }
    self.payout        = "monthly"
    self.durationMonths = 12          -- Vertragslaufzeit in Monaten (Perioden)
    self.penaltyFactor = nil          -- nil = keine Strafe
    self.requirements  = {}           -- { minHerdHealth=?, minCalfAgeMonths=? }
    return self
end

-- Komfort-Abfragen fuers Script ---------------------------------------------
function MilkDairy:isMarketPriced()  return self.pricing.type == "market" end
function MilkDairy:hasMinimumQuota() return self.quota.type == "minimum" end
function MilkDairy:hasMaximumCap()   return self.quota.type == "maximum" end
function MilkDairy:needsHealthCheck() return self.requirements.minHerdHealth ~= nil end
function MilkDairy:needsCalfHook()    return self.requirements.minCalfAgeMonths ~= nil end

-- Effektiver Preis pro Liter fuer eine gegebene Marktreferenz ----------------
function MilkDairy:getPricePerLiter(currentMarketPrice)
    if self.pricing.type == "market" then
        return currentMarketPrice * (self.pricing.marketMultiplier or 1.0)
    end
    return self.pricing.pricePerLiter or 0
end

-- Plausibilitaetspruefung. true, wenn der Eintrag brauchbar ist. -------------
function MilkDairy:validate()
    local ok = true
    local function warn(msg)
        Logging.warning("[MilkContract] Molkerei '%s': %s", tostring(self.id), msg)
        ok = false
    end

    if self.pricing.type == "fixed" then
        if self.pricing.pricePerLiter == nil or self.pricing.pricePerLiter <= 0 then
            warn("type='fixed' braucht ein gueltiges pricePerLiter > 0")
        end
    elseif self.pricing.type == "market" then
        if self.pricing.pricePerLiter ~= nil then
            warn("pricePerLiter gehoert nicht in einen 'market'-Block (wird ignoriert)")
        end
    else
        warn("unbekannter pricing type '" .. tostring(self.pricing.type) .. "'")
    end

    if self.quota.type == "minimum" then
        if self.quota.percentOfEstimated == nil then
            warn("quota='minimum' braucht percentOfEstimated")
        end
    elseif self.quota.type == "maximum" then
        if self.quota.litersPerMonth == nil then
            warn("quota='maximum' braucht litersPerMonth")
        end
        if self.penaltyFactor ~= nil then
            warn("penalty bei quota='maximum' ist wirkungslos (Deckel erzwingt nichts)")
        end
    elseif self.quota.type ~= "none" then
        warn("unbekannter quota type '" .. tostring(self.quota.type) .. "'")
    end

    local validPayout = { monthly = true, quarterly = true, halfyearly = true, yearly = true }
    if not validPayout[self.payout] then
        warn("unbekanntes payout interval '" .. tostring(self.payout) .. "'")
    end

    return ok
end
