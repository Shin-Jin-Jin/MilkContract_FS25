# FS25 Mod: MilkContract (Milchvertrag)

Fuegt ein Milch-Vertragssystem mit mehreren Molkereien hinzu (Preis,
Mindest-/Hoechstmenge, Auszahlungsrhythmus, Tierwohl-Auflagen). Solange ein
Vertrag laeuft, nimmt die Mod taeglich die Vertragsmenge direkt aus dem
Stall-Lager ab und verguetet sie zum Vertragspreis. Was der Vertrag nicht
nimmt, bleibt im Lager und kann normal ueber die Spielbasis weggefahren werden.

## Aufbau

```
FS25_MilkContract/
├── modDesc.xml
├── molkereien.xml                      Molkerei-Definitionen (datengetrieben)
├── icon_MilkContract.dds               Mod-Icon (Platzhalter, ersetzbar)
├── gui/
│   ├── menuIcon.dds                    Tab-Icon
│   ├── guiProfiles.xml                 eigene GUI-Profile
│   └── MilkContractFrame.xml           Auswahlmenue (Zweispalten-Layout)
├── scripts/
│   ├── MilkDairy.lua                   Datenobjekt einer Molkerei + Validierung
│   ├── MilkContractLoader.lua          liest molkereien.xml
│   ├── MilkContract.lua                Laufzeit-Vertrag: peek/commit, Abrechnung, Persistenz
│   ├── MilkContractManager.lua         Steuerung: Events, Abnahme, Geld, Savegame, MP, Bootstrap
│   ├── MilkContractSyncEvent.lua       MP: Sync + Aktions-Events (Server<->Client)
│   └── gui/
│       ├── MilkContractFrame.lua       Auswahlmenue (Logik)
│       └── InGameMenuMilkContract.lua  haengt den Tab ins In-Game-Menue
└── translations/
    ├── translation_de.xml
    └── translation_en.xml
```

## Funktioniert (im Singleplayer getestet)

- Eigener In-Game-Menue-Tab mit Icon, Zweispalten-Layout + Detailpanel
- Molkerei-Auswahl, Vertrag abschliessen / kuendigen
- Produktionsschaetzung + Zielmengenberechnung (echte Zahlen aus dem Stall)
- Taegliche Milchabnahme aus dem Stall-Lager (Lager sinkt korrekt)
- Preis ueber economyManager, Buchung als MoneyType.SOLD_MILK
- Aufteilung Quote/Deckel; Ueberschuss bleibt im Lager
- Persistenz + MP-Struktur (Server autoritativ, Clients per Sync)

## Noch zu testen / offen

- MULTIPLAYER praktisch mit 2. Spieler (Struktur steht, ungetestet)
- PERSISTENZ ueber Speichern/Laden-Zyklus praktisch pruefen
- GESUNDHEITSPRUEFUNG (BioLand/Weidehof): Cluster-Feld (health/healthFactor)
  ist defensiv geraten -> mit ungesunder Herde verifizieren
- KAELBER-HALTEDAUER (Weidehof): noch nicht implementiert (Tierverkaufs-Hook)
- automatische Abholung stuendlich statt taeglich (optional, fuers Gefuehl)
- Icons (Mod-Icon + Tab-Icon) sind Platzhalter -> durch eigene ersetzen
- Menue-Feinschliff (in spaeterer Sitzung geplant)

## Wichtige technische Notizen (fuer spaeter)

- Lagerabbau: husbandry:removeHusbandryFillLevel(nil, menge, fillTypeIndex)
  (erstes Argument nil!) - Quelle: FS25_automaticMilkSale
- Stall-Liste: g_currentMission.husbandrySystem.placeables, Milch-Stall hat
  spec_husbandryMilk (hasMilkProduction). Produktion: spec.litersPerHour.
- Menue-Registrierung nach VehicleDelivery-Muster (fixInGameMenu): pagingElement
  .elements UND .pages synchron verschieben + updatePageMapping, sonst crasht
  die Karte. Ans Ende/relativ zu pageStatistics einfuegen. Tab-Icon MUSS
  existieren, sonst bricht addPageTab ab und beschaedigt das Menue.
- GUI-Klassen per source() auf oberster Ebene laden (Client-Guard), NICHT ueber
  extraSourceFiles (TabbedMenuFrameElement dort noch nicht verfuegbar).
- Persistenz: FSCareerMissionInfo.saveToXMLFile via prependedFunction, eigene
  Datei milchvertrag.xml im savegameDirectory (nur Server).
