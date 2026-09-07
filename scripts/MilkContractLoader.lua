-- =========================================================================
--  MilkContractLoader.lua
--  Liest molkereien.xml ein, validiert und erzeugt MilkDairy-Objekte.
--  MilkDairy selbst liegt in MilkDairy.lua.
--
--  HINWEIS: XML-API-Signaturen (XMLFile.load / getValue / iterate /
--  XMLValueType) ggf. gegen die Basis-Skripte der FS25-Installation
--  abgleichen - sie variieren leicht zwischen Versionen.
-- =========================================================================
MilkContractLoader = {}

function MilkContractLoader.registerSchema()
    local schema = XMLSchema.new("milkContracts")

    schema:register(XMLValueType.BOOL, "milkContracts.settings.health#sampleOnDayChange", "", true)
    schema:register(XMLValueType.BOOL, "milkContracts.settings.health#weightByAnimalCount", "", true)
    schema:register(XMLValueType.BOOL, "milkContracts.settings.health#acrossAllHusbandries", "", true)
    schema:register(XMLValueType.BOOL, "milkContracts.settings.surplus#keepInStorage", "", true)
    schema:register(XMLValueType.BOOL, "milkContracts.settings.scaling#scaleByDaysPerPeriod", "", true)
    schema:register(XMLValueType.INT,  "milkContracts.settings.scaling#referenceDays", "", 30)

    local key = "milkContracts.dairies.dairy(?)"
    schema:register(XMLValueType.STRING, key .. "#id",    "Interner Schluessel")
    schema:register(XMLValueType.STRING, key .. "#title", "l10n-Key Anzeige")
    schema:register(XMLValueType.STRING, key .. "#desc",  "l10n-Key Beschreibung")
    schema:register(XMLValueType.STRING, key .. "#milkType", "cow|goat|buffalo", "cow")
    schema:register(XMLValueType.STRING, key .. "#fillType", "FillType-Name (optional)")

    schema:register(XMLValueType.STRING, key .. ".pricing#type", "market|fixed")
    schema:register(XMLValueType.FLOAT,  key .. ".pricing#marketMultiplier", "", 1.0)
    schema:register(XMLValueType.FLOAT,  key .. ".pricing#pricePerLiter", "")

    schema:register(XMLValueType.STRING, key .. ".quota#type", "none|minimum|maximum")
    schema:register(XMLValueType.FLOAT,  key .. ".quota#percentOfEstimated", "")
    schema:register(XMLValueType.FLOAT,  key .. ".quota#percentVariance", "+/- Prozentpunkte (dynamisch)", 0)
    schema:register(XMLValueType.FLOAT,  key .. ".quota#litersPerMonth", "")
    schema:register(XMLValueType.FLOAT,  key .. ".quota#litersVariance", "+/- Liter (dynamisch)", 0)

    schema:register(XMLValueType.STRING, key .. ".payout#interval", "monthly|quarterly|halfyearly|yearly", "monthly")
    schema:register(XMLValueType.INT,    key .. ".duration#months", "Vertragslaufzeit in Monaten", 12)
    schema:register(XMLValueType.FLOAT,  key .. ".penalty#factor", "")

    schema:register(XMLValueType.FLOAT, key .. ".requirements.minHerdHealth#percent", "")
    schema:register(XMLValueType.FLOAT, key .. ".requirements.minHerdHealth#variance", "+/- Prozentpunkte (dynamisch)", 0)
    schema:register(XMLValueType.INT,   key .. ".requirements.minCalfAge#months", "")
    schema:register(XMLValueType.INT,   key .. ".requirements.minCalfAge#variance", "+/- Monate (dynamisch)", 0)
    schema:register(XMLValueType.FLOAT, key .. ".requirements.minYoungShare#percent", "Mindestanteil junger Tiere in %")
    schema:register(XMLValueType.FLOAT, key .. ".requirements.minYoungShare#variance", "+/- Prozentpunkte (dynamisch)", 0)
    schema:register(XMLValueType.INT,   key .. ".requirements.minYoungShare#maxAgeMonths", "Grenze 'jung' in Monaten", 12)

    MilkContractLoader.schema = schema
end

local function loadSettings(xmlFile)
    return {
        sampleHealthOnDayChange = xmlFile:getValue("milkContracts.settings.health#sampleOnDayChange", true),
        weightHealthByCount     = xmlFile:getValue("milkContracts.settings.health#weightByAnimalCount", true),
        healthAcrossAll         = xmlFile:getValue("milkContracts.settings.health#acrossAllHusbandries", true),
        keepSurplusInStorage    = xmlFile:getValue("milkContracts.settings.surplus#keepInStorage", true),
        scaleByPeriod           = xmlFile:getValue("milkContracts.settings.scaling#scaleByDaysPerPeriod", true),
        referenceDays           = xmlFile:getValue("milkContracts.settings.scaling#referenceDays", 30),
    }
end

local function loadDairy(xmlFile, key)
    local id = xmlFile:getValue(key .. "#id")
    if id == nil or id == "" then
        Logging.warning("[MilkContract] <dairy> ohne id uebersprungen")
        return nil
    end

    local d = MilkDairy.new(id)
    d.title = xmlFile:getValue(key .. "#title")
    d.milkType = xmlFile:getValue(key .. "#milkType", "cow")
    -- FillType je Milchtyp (per Attribut ueberschreibbar, falls Namen abweichen)
    local defaultFill = "MILK"
    if d.milkType == "goat" then defaultFill = "GOATMILK"
    elseif d.milkType == "buffalo" then defaultFill = "BUFFALOMILK" end
    d.fillTypeName = xmlFile:getValue(key .. "#fillType", defaultFill)
    d.desc  = xmlFile:getValue(key .. "#desc")

    d.pricing.type = xmlFile:getValue(key .. ".pricing#type", "market")
    if d.pricing.type == "market" then
        d.pricing.marketMultiplier = xmlFile:getValue(key .. ".pricing#marketMultiplier", 1.0)
    else
        d.pricing.pricePerLiter = xmlFile:getValue(key .. ".pricing#pricePerLiter")
    end

    d.quota.type = xmlFile:getValue(key .. ".quota#type", "none")
    if d.quota.type == "minimum" then
        d.quota.percentOfEstimated = xmlFile:getValue(key .. ".quota#percentOfEstimated")
        d.quota.percentVariance    = xmlFile:getValue(key .. ".quota#percentVariance", 0)
    elseif d.quota.type == "maximum" then
        d.quota.litersPerMonth = xmlFile:getValue(key .. ".quota#litersPerMonth")
        d.quota.litersVariance = xmlFile:getValue(key .. ".quota#litersVariance", 0)
    end

    d.payout = xmlFile:getValue(key .. ".payout#interval", "monthly")
    d.durationMonths = xmlFile:getValue(key .. ".duration#months", 12)
    d.penaltyFactor = xmlFile:getValue(key .. ".penalty#factor")

    d.requirements.minHerdHealth         = xmlFile:getValue(key .. ".requirements.minHerdHealth#percent")
    d.requirements.minHerdHealthVariance = xmlFile:getValue(key .. ".requirements.minHerdHealth#variance", 0)
    d.requirements.minCalfAgeMonths      = xmlFile:getValue(key .. ".requirements.minCalfAge#months")
    d.requirements.minCalfAgeVariance    = xmlFile:getValue(key .. ".requirements.minCalfAge#variance", 0)
    d.requirements.minYoungSharePercent  = xmlFile:getValue(key .. ".requirements.minYoungShare#percent")
    d.requirements.minYoungShareVariance = xmlFile:getValue(key .. ".requirements.minYoungShare#variance", 0)
    d.requirements.youngMaxAgeMonths     = xmlFile:getValue(key .. ".requirements.minYoungShare#maxAgeMonths", 12)

    return d
end

-- @param path  absoluter Pfad zur molkereien.xml
function MilkContractLoader.load(path)
    if MilkContractLoader.schema == nil then
        MilkContractLoader.registerSchema()
    end

    local xmlFile = XMLFile.load("milkContracts", path, MilkContractLoader.schema)
    if xmlFile == nil then
        Logging.error("[MilkContract] Konnte molkereien.xml nicht laden: %s", tostring(path))
        return nil
    end

    local settings = loadSettings(xmlFile)
    local dairies, byId, seen = {}, {}, {}

    xmlFile:iterate("milkContracts.dairies.dairy", function(_, key)
        local d = loadDairy(xmlFile, key)
        if d ~= nil then
            if seen[d.id] then
                Logging.warning("[MilkContract] doppelte id '%s' - zweiter Eintrag ignoriert", d.id)
            elseif d:validate() then
                table.insert(dairies, d)
                byId[d.id] = d
                seen[d.id] = true
            else
                Logging.warning("[MilkContract] Molkerei '%s' wegen Fehlern uebersprungen", d.id)
            end
        end
    end)

    xmlFile:delete()
    Logging.info("[MilkContract] %d Molkereien geladen", #dairies)
    return { settings = settings, dairies = dairies, byId = byId }
end
