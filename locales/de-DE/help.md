# Tastenzuordnung {#mapping}

## Grundlegende Verwendung {#mapping-basic}

Die Tastenzuordnung wandelt eine Taste oder Tastenkombination in eine andere Taste oder Kombination um.

### Verwendung

1. Wählen Sie links „Zuordnung hinzufügen“.
2. Zeichnen Sie die Eingabe- und Ausgabekombination nacheinander auf. Jede Kombination kann bis zu drei Tasten enthalten.
3. Prüfen Sie die angezeigten Kombinationen, wählen Sie „Speichern“ und aktivieren Sie anschließend das Kontrollkästchen der Zuordnung.

> Wenn Sie die Ausgabe auf „Keine“ setzen und die Zuordnung aktivieren, wird die Eingabetaste blockiert. Sobald Sie das Kontrollkästchen deaktivieren, funktioniert die Eingabetaste wieder normal.

## Regeln für Kombinationen {#mapping-combo}

- Eingabe- und Ausgabekombinationen können eine bis drei Tasten enthalten.
- Esc kann als normale Eingabe- oder Ausgabetaste verwendet werden.
- Die Zuordnung wird ausgelöst, sobald die letzte Eingabetaste gedrückt wird, und die Ausgabe wird freigegeben, sobald eine Eingabetaste losgelassen wird.
- Eingaben mit einer, zwei oder drei Tasten dürfen keine Präfixkonflikte aufweisen. Strg und Strg+C können beispielsweise nicht gleichzeitig gespeichert werden.
- Ausgabekombinationen werden nicht auf Duplikate oder Präfixe geprüft. Mehrere Zuordnungen können daher dieselbe Ausgabe verwenden.
- Eine Mausradrichtung kann nur die letzte Taste einer Kombination sein.

## Einschränkungen für Maustasten {#mapping-mouse}

- Die linke und rechte Maustaste können weder einzeln zugeordnet noch als erste Taste einer Kombination verwendet werden.
- Wenn zuerst eine andere Taste gedrückt wurde, kann die linke oder rechte Maustaste als zweite oder dritte Taste aufgezeichnet werden.
- Während der Aufzeichnung sind andere Zuordnungen ausgesetzt. Außerhalb des aktiven Aufnahmefelds können Sie mit der linken und rechten Maustaste weiterhin normal klicken.
- Eine Aufzeichnung ist nur möglich, wenn die Tasten- und Mauszuordnung im Vordergrund ist. Fensterwechsel, Minimieren oder Ausblenden beendet die Aufzeichnung: bereits angeklickte Bildschirmtasten werden übernommen, andernfalls wird abgebrochen.

## Bildschirmtastatur {#mapping-virtual}

- Über „Bildschirmtastatur“ links neben der Hilfe in der Titelleiste öffnen Sie eine Standard-Tastatur mit 104 Tasten. „Tastatur ausblenden“ schließt sie wieder.
- Die Tastatur dockt standardmäßig am unteren Fensterrand an. Ist der sichtbare Arbeitsbereich zu niedrig, wird sie zu einem verschiebbaren schwebenden Feld.
- Bildschirmtasten werden nur in das gerade aufgenommene Zuordnungsfeld geschrieben. Sie werden nicht an das System gesendet und lösen keine gespeicherten Zuordnungen aus.
- Aktivieren Sie zuerst das Aufnahmefeld für Eingabe oder Ausgabe. Ein Klick auf eine Bildschirmtaste ohne aktive Aufnahme fordert Sie auf, zuerst die Zuordnungsaufnahme zu starten.
- „Übernehmen“ über dem Ziffernblock ist erst nach einem Klick auf eine Bildschirmtaste verfügbar. Nach einer oder zwei Tasten beendet „Übernehmen“ die Aufnahme. Bei drei Tasten wird automatisch abgeschlossen.
- Physische Tasten und Bildschirmtasten können in der Reihenfolge der Betätigung gemischt werden. Nach einer Bildschirmtaste beendet das Loslassen einer physischen Taste die Aufnahme nicht. Übernehmen, drei Tasten oder ein Klick außerhalb des Aufnahmefelds sind erforderlich.
- Ein Klick auf eine leere Stelle, Fensterwechsel, Minimieren oder Ausblenden beendet die Aufnahme: bereits angeklickte Bildschirmtasten werden übernommen, andernfalls wird abgebrochen.

# Einstellungen {#settings}

## Autostart, Infobereich und Sprache {#settings-general}

- „Mit Windows starten“ führt die App nach der Windows-Anmeldung automatisch aus.
- Beim Schließen wird das Fenster ausgeblendet, während aktivierte Zuordnungen weiter funktionieren.
- Klicken Sie mit der linken Maustaste auf das Infobereich-Symbol, um das Fenster wieder anzuzeigen. Über das Rechtsklickmenü können Sie die App vollständig beenden.
- Wenn Sie das Infobereich-Symbol ausblenden, starten Sie die App erneut, um das vorhandene Fenster wiederherzustellen.
- Ein Sprachwechsel aktualisiert Fenstertitel, Oberfläche, Meldungen und Infobereich-Menü sofort, ohne die Zuordnungen zu unterbrechen.

## Hauptschalter für Zuordnungen {#settings-input}

- Wenn Sie den Zuordnungsschalter in der Titelleiste ausschalten, werden gehaltene Ausgaben sofort freigegeben und alle Zuordnungen deaktiviert.
- Solange der Schalter ausgeschaltet ist, verwenden alle Tastatur- und Maustasten ihre ursprüngliche Funktion. Beim erneuten Einschalten werden die ausgewählten Zuordnungen wieder aktiviert.
- Der Schalter ist nur vorübergehend und bei jedem App-Start eingeschaltet.

## Immer im Vordergrund {#settings-topmost}

- Mit der Schaltfläche mit dem Stecknadelsymbol bleibt das Fenster über normalen Fenstern. Wählen Sie sie erneut aus, um dies auszuschalten.
