-- MilkContractFrame.lua
-- Seiten-Controller fuer die Molkerei-Auswahl im In-Game-Menue.
-- Aufbau nach dem Muster von VehicleDeliveryPage (TabbedMenuFrameElement).

MilkContractFrame = {}
MilkContractFrame._mt = Class(MilkContractFrame, TabbedMenuFrameElement)


function MilkContractFrame.new(i18n, messageCenter)
    local self = MilkContractFrame:superClass().new(nil, MilkContractFrame._mt)
    self.name = "MilkContractFrame"
    self.hasCustomMenuButtons = true
    self.i18n = i18n
    self.messageCenter = messageCenter
    self.dairies = {}
    self.selectedIndex = 1
    self.selectedMilkType = "cow"    -- Umschalter Kuh/Ziege
    return self
end


function MilkContractFrame:setupCustomButtons()
    self.backButtonInfo = {
        inputAction = InputAction.MENU_BACK
    }
    self.signButtonInfo = {
        inputAction = InputAction.MENU_ACTIVATE,
        text = self.i18n:getText("mc_sign"),
        callback = function() self:onClickSign() end
    }
    self.cancelButtonInfo = {
        inputAction = InputAction.MENU_CANCEL,
        text = self.i18n:getText("mc_cancel"),
        callback = function() self:onClickCancel() end
    }
    self.extendButtonInfo = {
        inputAction = InputAction.MENU_ACTIVATE,
        text = self.i18n:getText("mc_extend"),
        callback = function() self:onClickExtend() end
    }
    self.toggleButtonInfo = {
        inputAction = InputAction.MENU_EXTRA_1,
        text = self.i18n:getText("mc_toggleType"),
        callback = function() self:onClickToggleType() end
    }
    self.menuButtons = { self.backButtonInfo }
    self:setMenuButtonInfo(self.menuButtons)
end


function MilkContractFrame:onGuiSetupFinished()
    MilkContractFrame:superClass().onGuiSetupFinished(self)
    self:setupCustomButtons()

    self.dairyList = self:getDescendantById("dairyList")
    if self.dairyList ~= nil then
        self.dairyList:setDataSource(self)
        self.dairyList:setDelegate(self)
    end
    self.emptyText = self:getDescendantById("emptyText")

    -- Kuh/Ziege-Umschalter
    self.milkTypeSelector = self:getDescendantById("milkTypeSelector")
    if self.milkTypeSelector ~= nil and self.milkTypeSelector.setTexts ~= nil then
        self.milkTypeSelector:setTexts({
            self.i18n:getText("mc_typeCow"),
            self.i18n:getText("mc_typeGoat"),
            self.i18n:getText("mc_typeBuffalo"),
        })
        if self.milkTypeSelector.setState ~= nil then
            self.milkTypeSelector:setState(1, false)   -- Start: Kuh
        end
    end

    -- Gemeinsame + Gruppen-Elemente cachen
    self.detailTitle  = self:getDescendantById("detailTitle")
    self.activeSub    = self:getDescendantById("activeSub")
    self.viewOnlyHint = self:getDescendantById("viewOnlyHint")

    -- Gruppe A: Molkerei-Detail
    self.detailPrice    = self:getDescendantById("detailPrice")
    self.detailQuota    = self:getDescendantById("detailQuota")
    self.detailPayout   = self:getDescendantById("detailPayout")
    self.detailPenalty  = self:getDescendantById("detailPenalty")
    self.detailReq      = self:getDescendantById("detailReq")
    self.detailStatus   = self:getDescendantById("detailStatus")
    self.detailEstimate = self:getDescendantById("detailEstimate")
    self.groupDetail = {}
    for _, id in ipairs({ "lblPrice","detailPrice","lblQuota","detailQuota",
                          "lblPayout","detailPayout","lblPenalty","detailPenalty",
                          "lblReq","detailReq",
                          "sepA","lblStatus","detailStatus","detailEstimate" }) do
        local el = self:getDescendantById(id)
        if el ~= nil then table.insert(self.groupDetail, el) end
    end

    -- Gruppe B: Status laufender Vertrag
    self.actDelivered = self:getDescendantById("actDelivered")
    self.actProgress  = self:getDescendantById("actProgress")
    self.actSecure    = self:getDescendantById("actSecure")
    self.actProjected = self:getDescendantById("actProjected")
    self.actNext      = self:getDescendantById("actNext")
    self.actReq       = self:getDescendantById("actReq")
    self.groupActive = {}
    for _, id in ipairs({ "activeSub","lblDelivered","actDelivered","lblProgress","actProgress",
                          "sepB1","lblSecure","actSecure","lblProjected","actProjected",
                          "lblNext","actNext","sepB2","lblReqA","actReq" }) do
        local el = self:getDescendantById(id)
        if el ~= nil then table.insert(self.groupActive, el) end
    end
end


function MilkContractFrame:onFrameOpen()
    MilkContractFrame:superClass().onFrameOpen(self)
    self:refresh()
end


function MilkContractFrame:refresh()
    self.dairies = {}
    if g_milkContractManager ~= nil then
        self.dairies = g_milkContractManager:getDairies(self:getMyFarmId(), self.selectedMilkType)
    end

    -- Kopfzeile
    if self.categoryHeaderText == nil then
        self.categoryHeaderText = self:getDescendantById("categoryHeaderText")
    end
    if self.categoryHeaderText ~= nil then
        self.categoryHeaderText:setText(self.i18n:getText("mc_pageTitle"))
    end

    if self.dairyList ~= nil then
        self.dairyList:reloadData()
    end
    if self.emptyText ~= nil then
        self.emptyText:setVisible(#self.dairies == 0)
    end

    self:updateButtons()
    self:updateDetail()
end


function MilkContractFrame:onClickToggleType()
    self.selectedMilkType = (self.selectedMilkType == "cow") and "goat" or "cow"
    self.selectedIndex = 1
    if self.dairyList ~= nil then self.dairyList:setSelectedItem(1, 1, true) end
    self:refresh()
end

-- Callback des nativen Umschalters (state: 1=Kuh, 2=Ziege, 3=Bueffel)
function MilkContractFrame:onClickMilkTypeSelector(state)
    if state == 2 then
        self.selectedMilkType = "goat"
    elseif state == 3 then
        self.selectedMilkType = "buffalo"
    else
        self.selectedMilkType = "cow"
    end
    self.selectedIndex = 1
    if self.dairyList ~= nil then self.dairyList:setSelectedItem(1, 1, true) end
    self:refresh()
end


-- Buttons abhaengig vom gewaehlten Milchtyp; Umschalter immer verfuegbar.
function MilkContractFrame:updateButtons()
    local active = nil
    if g_milkContractManager ~= nil then
        active = g_milkContractManager:getContract(self:getMyFarmId(), self.selectedMilkType)
    end
    if active ~= nil then
        if g_milkContractManager:isRenewable(active) then
            self.menuButtons = { self.backButtonInfo, self.extendButtonInfo, self.cancelButtonInfo }
        else
            self.menuButtons = { self.backButtonInfo, self.cancelButtonInfo }
        end
    else
        self.menuButtons = { self.backButtonInfo, self.signButtonInfo }
    end
    self:setMenuButtonInfo(self.menuButtons)
    if self.setMenuButtonInfoDirty ~= nil then
        self:setMenuButtonInfoDirty()
    end
end

function MilkContractFrame:onClickExtend()
    if g_milkContractManager == nil then return end
    local farmId = self:getMyFarmId()
    local active = g_milkContractManager:getContract(farmId, self.selectedMilkType)
    if active == nil or not g_milkContractManager:isRenewable(active) then return end

    local carry = 0
    if active.dairy:hasMinimumQuota() then
        carry = math.max(0, (active.targetLiters or 0) - (active.deliveredTotal or 0))
    end
    local text
    if carry > 0 then
        text = string.format(self.i18n:getText("mc_extendConfirmDebt"),
            self:resolveTitle(active.dairy.title, active.dairyId),
            g_i18n:formatNumber(carry, 0))
    else
        text = string.format(self.i18n:getText("mc_extendConfirm"),
            self:resolveTitle(active.dairy.title, active.dairyId))
    end
    text = text:gsub("\\n", "\n")

    local mt = self.selectedMilkType
    if YesNoDialog ~= nil and YesNoDialog.show ~= nil then
        YesNoDialog.show(
            function(yes)
                if yes then
                    g_milkContractManager:requestExtend(self:getMyFarmId(), mt)
                    self:refresh()
                end
            end,
            nil, text,
            nil, nil, nil, nil, nil, nil, nil,
            true
        )
    else
        g_milkContractManager:requestExtend(farmId, mt)
        self:refresh()
    end
end


-- Loest einen Titel auf: '$l10n_key' -> getText('key'), sonst direkt.
function MilkContractFrame:resolveTitle(title, fallback)
    if title == nil then
        return tostring(fallback or "?")
    end
    local key = title:match("^%$l10n_(.+)$")
    if key ~= nil then
        return self.i18n:getText(key)
    end
    return self.i18n:getText(title)
end


-- lokale Farm-Id ermitteln (MP-tauglich, nach VehicleDelivery-Muster) --------
function MilkContractFrame:getMyFarmId()
    if g_currentMission ~= nil then
        if g_currentMission.getFarmId ~= nil then
            return g_currentMission:getFarmId()
        elseif g_localPlayer ~= nil then
            return g_localPlayer.farmId
        end
    end
    return 1
end


-- ===== SmoothList Delegate/DataSource =====

function MilkContractFrame:getNumberOfItemsInSection(list, sectionIndex)
    if list == self.dairyList then
        return #self.dairies
    end
    return 0
end


function MilkContractFrame:getCellTypeForItemInSection(list, sectionIndex, index)
    return "default"
end


function MilkContractFrame:onListSelectionChanged(list, sectionIndex, index)
    self.selectedIndex = index
    self:updateDetail()
end


function MilkContractFrame:populateCellForItemInSection(list, sectionIndex, index, listItem)
    if list ~= self.dairyList then return end
    local dairy = self.dairies[index]
    if dairy == nil then return end

    local nameText  = listItem:getAttribute("nameText")
    local priceText = listItem:getAttribute("priceText")
    local quotaText = listItem:getAttribute("quotaText")

    if nameText ~= nil then
        nameText:setText(self:resolveTitle(dairy.title, dairy.id))
    end
    if priceText ~= nil then
        priceText:setText(self:priceStr(dairy))
    end
    if quotaText ~= nil then
        quotaText:setText(self:quotaStr(dairy))
    end
end


-- ===== Anzeige-Helfer =====

function MilkContractFrame:priceStr(dairy)
    local bonus = 1.0
    if g_milkContractManager ~= nil then
        bonus = g_milkContractManager:getDurationBonus(g_milkContractManager:getOfferDuration(dairy.id))
    end
    if dairy:isMarketPriced() then
        return string.format("%s (x%.2f)", self.i18n:getText("mc_market"),
            (dairy.pricing.marketMultiplier or 1.0) * bonus)
    end
    return g_i18n:formatMoney((dairy.pricing.pricePerLiter or 0) * bonus, 2, true) .. " / l"
end

function MilkContractFrame:quotaStr(dairy)
    if dairy:hasMinimumQuota() then
        local pct = (g_milkContractManager ~= nil and g_milkContractManager:getOfferQuota(dairy.id))
                    or dairy.quota.percentOfEstimated or 0
        return string.format("%s %d %%", self.i18n:getText("mc_minQuota"), pct)
    elseif dairy:hasMaximumCap() then
        local cap = (g_milkContractManager ~= nil and g_milkContractManager:getOfferQuota(dairy.id))
                    or dairy.quota.litersPerMonth or 0
        return string.format("%s %s l", self.i18n:getText("mc_maxCap"),
            g_i18n:formatNumber(cap, 0))
    end
    return self.i18n:getText("mc_noQuota")
end

function MilkContractFrame:reqStr(dairy)
    local parts = {}
    if dairy.requirements.minHerdHealth ~= nil then
        table.insert(parts, string.format("%s%d%%", self.i18n:getText("mc_reqHealthShort"), dairy.requirements.minHerdHealth))
    end
    if dairy.requirements.minCalfAgeMonths ~= nil then
        table.insert(parts, string.format("%s%dM", self.i18n:getText("mc_reqCalfShort"), dairy.requirements.minCalfAgeMonths))
    end
    if #parts == 0 then return self.i18n:getText("mc_noReq") end
    return table.concat(parts, "  ")
end

-- Auflagen mehrzeilig fuers Detailpanel
function MilkContractFrame:reqStrMultiline(dairy)
    local parts = {}
    if dairy.requirements.minHerdHealth ~= nil then
        local h = (g_milkContractManager ~= nil and g_milkContractManager:getOfferHealth(dairy.id))
                  or dairy.requirements.minHerdHealth
        table.insert(parts, string.format("%s %d%%", self.i18n:getText("mc_reqHealthShort"), h))
    end
    if dairy.requirements.minCalfAgeMonths ~= nil then
        local ca = (g_milkContractManager ~= nil and g_milkContractManager:getOfferCalf(dairy.id))
                   or dairy.requirements.minCalfAgeMonths
        table.insert(parts, string.format("%s %dM", self.i18n:getText("mc_reqCalfShort"), ca))
    end
    if #parts == 0 then return self.i18n:getText("mc_noReq") end
    return table.concat(parts, "\n")
end

-- Eigener Anzeigetext fuer die Vertragsstrafe (oder "-", wenn keine).
function MilkContractFrame:penaltyStr(dairy)
    if dairy.hasMinimumQuota ~= nil and dairy:hasMinimumQuota() then
        local factor = dairy.penaltyFactor or 1.0
        return string.format(self.i18n:getText("mc_penaltyValue"), factor)
    end
    return "-"
end


-- Detailpanel rechts fuer die markierte Molkerei fuellen --------------------
function MilkContractFrame:updateDetail()
    if g_milkContractManager == nil then return end
    local farmId = self:getMyFarmId()
    local active = g_milkContractManager:getContract(farmId, self.selectedMilkType)
    local dairy  = self.dairies[self.selectedIndex]

    local hasActive = active ~= nil

    -- Gruppen ein-/ausblenden (flache Elemente)
    for _, el in ipairs(self.groupDetail or {}) do el:setVisible(not hasActive) end
    for _, el in ipairs(self.groupActive or {}) do el:setVisible(hasActive) end
    if self.viewOnlyHint ~= nil then self.viewOnlyHint:setVisible(hasActive) end

    if hasActive then
        self:fillActiveStatus(active, farmId)
    else
        self:fillDairyDetail(dairy, farmId)
    end
end


-- Molkerei-Detail (kein aktiver Vertrag) ------------------------------------
function MilkContractFrame:fillDairyDetail(dairy, farmId)
    if dairy == nil then return end

    if self.detailTitle ~= nil then
        self.detailTitle:setText(self:resolveTitle(dairy.title, dairy.id))
    end
    if self.detailPrice ~= nil then self.detailPrice:setText(self:priceStr(dairy)) end
    if self.detailQuota ~= nil then self.detailQuota:setText(self:quotaStr(dairy)) end
    if self.detailPayout ~= nil then
        local months = g_milkContractManager:getOfferDuration(dairy.id)
        local payoutStr = self.i18n:getText("mc_payout_" .. tostring(dairy.payout))
        payoutStr = payoutStr .. string.format("  ·  %s",
            string.format(self.i18n:getText("mc_durationShort"), months))
        self.detailPayout:setText(payoutStr)
    end
    if self.detailReq ~= nil then self.detailReq:setText(self:reqStrMultiline(dairy)) end
    if self.detailPenalty ~= nil then self.detailPenalty:setText(self:penaltyStr(dairy)) end
    if self.detailStatus ~= nil then
        self.detailStatus:setText(self.i18n:getText("mc_noContract"))
    end
    if self.detailEstimate ~= nil then
        local months = g_milkContractManager:getOfferDuration(dairy.id)
        local annual = g_milkContractManager:estimateAnnualProduction(farmId, dairy.fillTypeName)
        local target = select(1, g_milkContractManager:computeContractNumbers(dairy, farmId, months))
        self.detailEstimate:setText(string.format(self.i18n:getText("mc_estimate"),
            g_i18n:formatNumber(annual, 0), g_i18n:formatNumber(target, 0)))
    end
end


-- Status des laufenden Vertrags ---------------------------------------------
function MilkContractFrame:fillActiveStatus(active, farmId)
    local dairy = active.dairy

    -- Unterzeile: Restlaufzeit (+ Warnung im letzten Monat)
    self.activeSub = self.activeSub or self:getDescendantById("activeSub")
    if self.activeSub ~= nil then
        local remaining = math.max(0, (active.durationMonths or 12) - (active.periodsElapsed or 0))
        if g_milkContractManager:isRenewable(active) then
            self.activeSub:setText(string.format("%s  ·  %s",
                self.i18n:getText("mc_activeHeader"),
                self.i18n:getText("mc_expiringSoon")))
        else
            self.activeSub:setText(string.format("%s  ·  %s",
                self.i18n:getText("mc_activeHeader"),
                string.format(self.i18n:getText("mc_remaining"), remaining)))
        end
    end

    if self.detailTitle ~= nil then
        self.detailTitle:setText(self:resolveTitle(dairy.title, active.dairyId))
    end

    -- Geliefert (gesamt im Vertragszeitraum)
    if self.actDelivered ~= nil then
        self.actDelivered:setText(string.format("%s l",
            g_i18n:formatNumber(active.deliveredTotal or 0, 0)))
    end

    -- Fortschritt: nur sinnvoll bei Mindestmenge (Ziel vorhanden)
    if self.actProgress ~= nil then
        if dairy:hasMinimumQuota() and (active.targetLiters or 0) > 0 then
            local pct = math.min(100, (active.deliveredTotal or 0) / active.targetLiters * 100)
            local txt = string.format("%s / %s l  (%d %%)",
                g_i18n:formatNumber(active.deliveredTotal or 0, 0),
                g_i18n:formatNumber(active.targetLiters, 0), pct)
            if (active.carriedDebt or 0) > 0 then
                txt = txt .. string.format("  " .. self.i18n:getText("mc_carryDebt"),
                    g_i18n:formatNumber(active.carriedDebt, 0))
            end
            self.actProgress:setText(txt)
        else
            self.actProgress:setText("-")
        end
    end

    local info = g_milkContractManager:getContractValueInfo(active, farmId)

    -- Sicher bereits verdient (aufgelaufen, wird zur naechsten Auszahlung gezahlt)
    if self.actSecure ~= nil then
        self.actSecure:setText(g_i18n:formatMoney(info.secure, 0, true))
    end
    -- Hochrechnung aufs Vertragsjahr
    if self.actProjected ~= nil then
        self.actProjected:setText(g_i18n:formatMoney(info.projectedValue, 0, true))
    end

    -- Naechste Auszahlung: Rhythmus + in X Monaten
    if self.actNext ~= nil then
        local rhythm = self.i18n:getText("mc_payout_" .. tostring(dairy.payout))
        local n = g_milkContractManager:getPeriodsUntilPayout(active)
        local whenStr
        if n ~= nil and n <= 1 then
            whenStr = self.i18n:getText("mc_nextPeriodSoon")
        elseif n ~= nil then
            whenStr = string.format(self.i18n:getText("mc_inMonths"), n)
        else
            whenStr = "-"
        end
        self.actNext:setText(string.format("%s (%s)", whenStr, rhythm))
    end

    -- Auflagen (fixierte Vertragswerte) + erfuellt/nicht erfuellt
    if self.actReq ~= nil then
        local parts = {}
        local effH = active.effHealth or dairy.requirements.minHerdHealth
        local effC = active.effCalf or dairy.requirements.minCalfAgeMonths
        if effH ~= nil then
            table.insert(parts, string.format("%s %d%%", self.i18n:getText("mc_reqHealthShort"), effH))
        end
        if effC ~= nil then
            table.insert(parts, string.format("%s %dM", self.i18n:getText("mc_reqCalfShort"), effC))
        end
        local reqStr = (#parts == 0) and self.i18n:getText("mc_noReq") or table.concat(parts, "\n")
        if effH ~= nil then
            local met = active:meetsHealthRequirement()
            local tag = met and self.i18n:getText("mc_reqMet") or self.i18n:getText("mc_reqNotMet")
            reqStr = reqStr .. "  (" .. tag .. ")"
        end
        self.actReq:setText(reqStr)
    end
end


-- ===== Aktionen =====

function MilkContractFrame:onClickSign()
    if g_milkContractManager == nil then return end
    local farmId = self:getMyFarmId()
    local dairy = self.dairies[self.selectedIndex]
    if dairy == nil then return end
    local mt = dairy.milkType or "cow"
    if g_milkContractManager:getContract(farmId, mt) ~= nil then return end

    -- Eckdaten fuer die Bestaetigung zusammenstellen
    local months = g_milkContractManager:getOfferDuration(dairy.id)
    local bonus  = g_milkContractManager:getDurationBonus(months)
    local price  = dairy:getPricePerLiter(g_milkContractManager:getCurrentMilkMarketPrice(dairy.fillTypeName)) * bonus
    local target = select(1, g_milkContractManager:computeContractNumbers(dairy, farmId, months))

    local text = string.format(self.i18n:getText("mc_signConfirm"),
        self:resolveTitle(dairy.title, dairy.id),
        months,
        g_i18n:formatMoney(price, 2, true),
        g_i18n:formatNumber(target, 0))
    text = text:gsub("\\n", "\n")

    local pendingId = dairy.id
    if YesNoDialog ~= nil and YesNoDialog.show ~= nil then
        YesNoDialog.show(
            function(yes)
                if yes then
                    g_milkContractManager:requestSign(pendingId, self:getMyFarmId())
                    self:refresh()
                end
            end,
            nil, text,
            nil, nil, nil, nil, nil, nil, nil,
            true
        )
    else
        g_milkContractManager:requestSign(pendingId, farmId)
        self:refresh()
    end
end


function MilkContractFrame:onClickCancel()
    if g_milkContractManager == nil then return end
    local farmId = self:getMyFarmId()
    local active = g_milkContractManager:getContract(farmId, self.selectedMilkType)
    if active == nil then return end

    local penalty = g_milkContractManager:getEarlyCancelPenalty(active, farmId)
    self.pendingCancelType = self.selectedMilkType

    local text = string.format(self.i18n:getText("mc_cancelConfirm"),
        g_i18n:formatMoney(penalty, 0, true))
    text = text:gsub("\\n", "\n")

    if YesNoDialog ~= nil and YesNoDialog.show ~= nil then
        YesNoDialog.show(
            function(yes)
                if yes then
                    g_milkContractManager:requestEarlyCancel(self:getMyFarmId(), self.pendingCancelType)
                    self:refresh()
                end
            end,
            nil, text,
            nil, nil, nil, nil, nil, nil, nil,
            true
        )
    else
        -- Fallback: ohne Dialog direkt kuendigen
        g_milkContractManager:requestEarlyCancel(farmId, self.pendingCancelType)
        self:refresh()
    end
end
