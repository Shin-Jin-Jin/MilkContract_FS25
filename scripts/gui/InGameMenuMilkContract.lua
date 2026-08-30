-- InGameMenuMilkContract.lua
-- Haengt das MilkContractFrame als eigenen Reiter ins InGameMenu ein.
-- 1:1 nach dem bewaehrten Muster aus VehicleDeliveryGUI (fixInGameMenu).

InGameMenuMilkContract = {
    dir = g_currentModDirectory,
    modName = g_currentModName
}

InGameMenuMilkContract.ICON_UVS = {0, 0, 1024, 1024}
InGameMenuMilkContract.ICON_FILE = "gui/menuIcon.dds"


local function findIndex(tbl, value)
    for i, v in ipairs(tbl) do
        if v == value then return i end
    end
    return nil
end


local function moveElement(tbl, element, position)
    for i, v in ipairs(tbl) do
        if v == element then
            table.remove(tbl, i)
            table.insert(tbl, position, element)
            break
        end
    end
end


---Richtet die Seite ein und haengt sie ins Menue.
function InGameMenuMilkContract:setup()
    local inGameMenu = g_gui.screenControllers[InGameMenu]
    if inGameMenu == nil then
        Logging.warning("MilkContract: InGameMenu-Instanz nicht gefunden -- Seite nicht eingehaengt.")
        return
    end

    -- Eigene Profile laden.
    g_gui:loadProfiles(self.dir .. "gui/guiProfiles.xml")

    if MilkContractFrame == nil then
        Logging.warning("MilkContract: MilkContractFrame-Klasse nicht geladen -- Seite nicht erstellt.")
        return
    end

    local page = MilkContractFrame.new(g_i18n, g_messageCenter)
    g_gui:loadGui(self.dir .. "gui/MilkContractFrame.xml", "MilkContractFrame", page, true)

    self.fixInGameMenu(page, "MilkContractFrame", InGameMenuMilkContract.ICON_UVS, 2, nil)

    Logging.info("MilkContract: Seite ins InGameMenu eingehaengt.")
end


---Haengt die Seite als neuen Reiter ins InGameMenu (nach VehicleDelivery fixInGameMenu).
function InGameMenuMilkContract.fixInGameMenu(frame, pageName, uvs, position, predicateFunc)
    local inGameMenu = g_gui.screenControllers[InGameMenu]

    -- SCHUTZ: Ohne existierendes Tab-Icon wuerde addPageTab abbrechen und die
    -- Seiten-Listen (elements/pages vs. pageFrames) inkonsistent lassen -> die
    -- Karten-Seite crasht dann jeden Frame (pairs on nil). Darum: fehlt das
    -- Icon, wird gar nicht erst eingehaengt.
    local iconPath = Utils.getFilename(InGameMenuMilkContract.ICON_FILE, InGameMenuMilkContract.dir)
    if not fileExists(iconPath) then
        Logging.warning("MilkContract: Tab-Icon fehlt (%s) -- Seite NICHT eingehaengt (Menue bleibt intakt).", tostring(iconPath))
        return
    end

    inGameMenu.controlIDs[pageName] = nil

    local targetPos = findIndex(inGameMenu.pagingElement.elements, inGameMenu.pageStatistics) or position

    inGameMenu[pageName] = frame
    inGameMenu.pagingElement:addElement(frame)
    inGameMenu:exposeControlsAsFields(pageName)

    moveElement(inGameMenu.pagingElement.elements, frame, targetPos)

    for i, page in ipairs(inGameMenu.pagingElement.pages) do
        if page.element == frame then
            table.remove(inGameMenu.pagingElement.pages, i)
            table.insert(inGameMenu.pagingElement.pages, targetPos, page)
            break
        end
    end

    inGameMenu.pagingElement:updateAbsolutePosition()
    inGameMenu.pagingElement:updatePageMapping()

    inGameMenu:registerPage(frame, position, predicateFunc)

    inGameMenu:addPageTab(frame, iconPath, GuiUtils.getUVs(uvs))

    moveElement(inGameMenu.pageFrames, frame, targetPos)

    inGameMenu:rebuildTabList()
end
