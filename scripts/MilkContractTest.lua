-- =========================================================================
--  MilkContractTest.lua
--  Konsolenbefehle zum Testen (Entwicklerkonsole mit ~ oeffnen).
--  Rein optional - kann jederzeit entfernt werden (aus extraSourceFiles +
--  Bootstrap streichen). Zustandsaendernde Befehle laufen nur am Host/SP.
-- =========================================================================
MilkContractTest = {}

local FT_COW  = "MILK"
local FT_GOAT = "GOATMILK"

local function mgr()
    return g_milkContractManager
end

local function myFarm()
    if g_currentMission ~= nil and g_currentMission.getFarmId ~= nil then
        local f = g_currentMission:getFarmId()
        if f ~= nil and f > 0 then return f end
    end
    return 1
end

local function p(fmt, ...)
    print("[MilkTest] " .. string.format(fmt, ...))
end

local function isServer()
    if g_server == nil then
        p("Nur am Host/Einzelspieler moeglich (Server hat den Zustand).")
        return false
    end
    return true
end

local function dairyName(m, dairy)
    if dairy == nil then return "?" end
    return m:dairyName(dairy)
end

-- ---- mcStatus : Ueberblick ------------------------------------------------
function MilkContractTest.status(self)
    local m = mgr()
    if m == nil then p("Manager nicht bereit."); return end
    local farmId = myFarm()

    p("== STATUS (Farm %d) ==", farmId)
    p("Marktpreis Kuh (%s): %.3f  |  Ziege (%s): %.3f",
        FT_COW,  m:getCurrentMilkMarketPrice(FT_COW),
        FT_GOAT, m:getCurrentMilkMarketPrice(FT_GOAT))

    -- Angebot je Milchtyp
    p("Angebot (Seed %s):", tostring(m.offerSeed))
    for _, mt in ipairs({ "cow", "goat", "buffalo" }) do
        local ft = (mt == "goat") and FT_GOAT or ((mt == "buffalo") and "BUFFALOMILK" or FT_COW)
        p("  [%s]  Stall: %s", mt, m:getBarnStatus(farmId, ft))
        for _, d in ipairs(m:getDairies(nil, mt)) do
            local months = m:getOfferDuration(d.id)
            local price  = m:getOfferPricePerLiter(d)
            p("    - %-26s %.2f EUR/l  (x%.2f, Bonus x%.3f)  %2dM  (%s)",
                dairyName(m, d), price, d:getPriceFactor() or 0,
                m:getDurationBonus(months, d), months, d.payout)
        end
    end

    -- Aktive Vertraege (je Milchtyp einer moeglich)
    local farm = m:getFarmContracts(farmId)
    if next(farm) == nil then
        p("Aktive Vertraege: keine")
    else
        for mt, c in pairs(farm) do
            local rem = (c.durationMonths or 0) - (c.periodsElapsed or 0)
            p("Vertrag [%s]: %s", mt, dairyName(m, c.dairy))
            p("  geliefert %.0f / Ziel %.0f l | Monat %d/%d (noch %d) | Bonus x%.2f | sicher %.0f EUR",
                c.deliveredTotal or 0, c.targetLiters or 0,
                c.periodsElapsed or 0, c.durationMonths or 0, rem,
                c.priceBonus or 1, c.accruedPayout or 0)
            -- Auflagen: aktuell vs. gefordert
            local ftName = c.dairy ~= nil and c.dairy.fillTypeName or nil
            if c.effHealth ~= nil then
                local cur = m:getWeightedHerdHealth(myFarm(), ftName)
                p("  Gesundheit: aktuell %s%% (Schnitt %s) | gefordert %.0f%% -> %s",
                    cur and string.format("%.0f", cur) or "-",
                    c.getAverageHealth ~= nil and c:getAverageHealth() and string.format("%.0f", c:getAverageHealth()) or "-",
                    c.effHealth, c:meetsHealthRequirement() and "erfuellt" or "NICHT erfuellt")
            end
            if c.effYoungShare ~= nil then
                local cur = m:getYoungShare(myFarm(), ftName, c.effYoungAge)
                p("  Nachwuchs (< %d M): aktuell %s%% (Schnitt %s) | gefordert %.0f%% -> %s",
                    c.effYoungAge or 12,
                    cur and string.format("%.0f", cur) or "-",
                    c.getAverageYoung ~= nil and c:getAverageYoung() and string.format("%.0f", c:getAverageYoung()) or "-",
                    c.effYoungShare, c:meetsYoungRequirement() and "erfuellt" or "NICHT erfuellt")
            end
        end
    end
end

-- ---- mcStalls : Staelle & Mengen je Milchtyp ------------------------------
function MilkContractTest.stalls(self)
    local m = mgr()
    if m == nil then p("Manager nicht bereit."); return end
    local farmId = myFarm()

    local list = m:listMilkStalls(farmId)
    local any = false
    for name, r in pairs(list) do
        any = true
        p("== %s ==  Staelle: %d  (Tank %d / Paletten %d)", name, r.count, r.tank, r.pallets)
        p("   Tagesmenge ~ %.0f l | Lager aktuell %.0f l | Marktpreis %.3f",
            r.daily, r.stored, m:getCurrentMilkMarketPrice(name))
    end
    if not any then
        p("Keine milchgebenden Staelle auf Farm %d gefunden.", farmId)
    end
end

-- ---- mcRotate : Angebot rotieren (neuer Seed +1) --------------------------
function MilkContractTest.rotate(self)
    local m = mgr(); if m == nil then return end
    if not isServer() then return end
    m:rotateOffer()
    if MilkContractSyncEvent ~= nil then MilkContractSyncEvent.sendToClients() end
    p("Angebot rotiert -> Seed %s", tostring(m.offerSeed))
    MilkContractTest:status()
end

-- ---- mcReroll : Angebot komplett neu wuerfeln (zufaelliger Seed) ----------
function MilkContractTest.reroll(self)
    local m = mgr(); if m == nil then return end
    if not isServer() then return end
    m.offerSeed = math.random(1, 1000000)
    m:rebuildOffer()
    if MilkContractSyncEvent ~= nil then MilkContractSyncEvent.sendToClients() end
    p("Angebot neu gewuerfelt -> Seed %s", tostring(m.offerSeed))
    MilkContractTest:status()
end

-- ---- mcPeriod : einen Monat vorspulen (Auszahlung/Ende/Rotation) ----------
function MilkContractTest.period(self)
    local m = mgr(); if m == nil then return end
    if not isServer() then return end
    p("Loese Periodenwechsel aus ...")
    m:onPeriodChanged()
    MilkContractTest:status()
end

-- ---- mcSign <dairyId> : Vertrag sofort abschliessen -----------------------
function MilkContractTest.sign(self, dairyId)
    local m = mgr(); if m == nil then return end
    if not isServer() then return end
    if dairyId == nil or dairyId == "" then
        p("Nutzung: mcSign <dairyId>  (z.B. mcSign bioland / mcSign ziegenhof)")
        p("Verfuegbare IDs:")
        for _, d in ipairs(m.data.dairies) do
            p("  %-20s [%s]  %s", d.id, d.milkType or "cow", dairyName(m, d))
        end
        return
    end
    local dairy = m.data.byId[dairyId]
    if dairy == nil then
        p("Unbekannte ID '%s' - nicht in den geladenen Daten.", tostring(dairyId))
        p("Tipp: molkereien.xml wird nur beim Start eines Spielstands geladen.")
        p("Geladene IDs:")
        for _, d in ipairs(m.data.dairies) do
            p("  %-20s [%s]  %s", d.id, d.milkType or "cow", dairyName(m, d))
        end
        return
    end
    local milkType = dairy.milkType or "cow"
    if m:getContract(myFarm(), milkType) ~= nil then
        p("Es laeuft bereits ein %s-Vertrag - erst 'mcCancel %s'.", milkType, milkType)
        return
    end
    local ok = m:doSign(dairyId, myFarm())
    if ok then
        if MilkContractSyncEvent ~= nil then MilkContractSyncEvent.sendToClients() end
        p("Vertrag '%s' abgeschlossen.", dairyId)
    else
        p("Abschluss fehlgeschlagen.")
    end
    MilkContractTest:status()
end

-- ---- mcCancel : aktiven Vertrag kuendigen ---------------------------------
function MilkContractTest.cancel(self, milkType)
    local m = mgr(); if m == nil then return end
    if not isServer() then return end
    local mt = (milkType ~= nil and milkType ~= "") and milkType or nil
    m:doCancel(myFarm(), mt)
    if MilkContractSyncEvent ~= nil then MilkContractSyncEvent.sendToClients() end
    p("Vertrag gekuendigt/entfernt%s.", mt and (" ["..mt.."]") or " (alle)")
    MilkContractTest:status()
end

-- ---- mcExtend : aktiven Vertrag verlaengern -------------------------------
function MilkContractTest.extend(self, milkType)
    local m = mgr(); if m == nil then return end
    if not isServer() then return end
    local mt = (milkType ~= nil and milkType ~= "") and milkType or nil
    local c = m:getContract(myFarm(), mt)
    if c == nil then p("Kein passender aktiver Vertrag (Typ: %s).", mt or "auto"); return end
    m:doExtend(myFarm(), mt or ((c.dairy and c.dairy.milkType) or "cow"))
    if MilkContractSyncEvent ~= nil then MilkContractSyncEvent.sendToClients() end
    p("Vertrag verlaengert.")
    MilkContractTest:status()
end

-- ---- mcAnimals : Tier-Cluster der Staelle roh ausgeben (Diagnose) -----------
function MilkContractTest.animals(self)
    local m = mgr()
    if m == nil then p("Manager nicht bereit."); return end
    local farmId = myFarm()

    local producers = m:getProducers(farmId, nil)
    if #producers == 0 then p("Keine milchgebenden Staelle gefunden."); return end

    for pi, e in ipairs(producers) do
        local h = e.placeable
        p("== Stall %d [%s] ==", pi, e.kind)
        if h.getClusters == nil then
            p("   (kein getClusters)")
        else
            local clusters = h:getClusters()
            if clusters == nil or #clusters == 0 then
                p("   (keine Cluster / leer)")
            else
                for ci, c in ipairs(clusters) do
                    -- alle Felder des Clusters auflisten (nur einfache Werte)
                    local fields = {}
                    for k, v in pairs(c) do
                        local tv = type(v)
                        if tv == "number" or tv == "string" or tv == "boolean" then
                            table.insert(fields, string.format("%s=%s", tostring(k), tostring(v)))
                        elseif tv == "function" then
                            table.insert(fields, tostring(k) .. "()")
                        end
                    end
                    table.sort(fields)
                    p("   Cluster %d: %s", ci, table.concat(fields, "  "))
                end
            end
        end
    end
    p("Hinweis: gesucht sind Felder fuer Alter, Untertyp (Kalb/erwachsen) und Anzahl.")
end

-- ---- Registrierung --------------------------------------------------------
function MilkContractTest.register()
    if addConsoleCommand == nil then return end
    addConsoleCommand("mcStatus", "Milchvertrag: Ueberblick (Angebot, Vertrag, Preise)", "status", MilkContractTest)
    addConsoleCommand("mcStalls", "Milchvertrag: Staelle & Mengen je Milchtyp",          "stalls", MilkContractTest)
    addConsoleCommand("mcAnimals","Milchvertrag: Tier-Cluster roh ausgeben (Diagnose)",  "animals", MilkContractTest)
    addConsoleCommand("mcRotate", "Milchvertrag: Angebot rotieren (Seed +1)",            "rotate", MilkContractTest)
    addConsoleCommand("mcReroll", "Milchvertrag: Angebot neu wuerfeln (zufaellig)",      "reroll", MilkContractTest)
    addConsoleCommand("mcPeriod", "Milchvertrag: einen Monat vorspulen",                 "period", MilkContractTest)
    addConsoleCommand("mcSign",   "Milchvertrag: Vertrag abschliessen <dairyId>",        "sign",   MilkContractTest)
    addConsoleCommand("mcCancel", "Milchvertrag: Vertrag kuendigen",                     "cancel", MilkContractTest)
    addConsoleCommand("mcExtend", "Milchvertrag: Vertrag verlaengern",                   "extend", MilkContractTest)
end
