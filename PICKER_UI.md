# ChromaFlow Picker UI

> Stand: aktueller UI-Entwurf  
> Fokus dieses Dokuments: **Bedienung und Aufbau der Picker-Oberfläche**.  
> **Nicht enthalten:** Resolve-Logik, Ermittlung der Treffer unter dem Cursor, Zuordnung von Vim/TS/LSP-Gruppen, Schreibpfade oder interne CF-Auflösung.

---

## 1. Grundaufbau

Der spätere **Picker** besteht aus mehreren kleinen UI-Bausteinen.

- **Pick-Menü**  
  Auswahl des semantischen Ziels, das bearbeitet werden soll.

- **Edit-Menü**  
  Kleine Auswahl nach Type/TypeMod: `Pipeline`, `Style`; bei einem Type zusätzlich `TypeMods`.

- **Pipeline-Editor**  
  Eigene 2D-Ansicht für `FG`, `BG`, `SP`, `CFG`, `CBG`, Farbausgänge und Manipulations-Pipelines.

- **Color-Menü**  
  Ein einziges wiederverwendbares Auswahlmenü für Farben aus `color.cf`.

- **Manipulation-Menü**  
  Auswahl einer neuen Pipeline-Manipulation.

- **Style-Menü**  
  Drei-Zustands-Auswahl für Style-Flags wie `bold`, `italic`, `undercurl`, `nocombine`, ...

- **TypeMods-Menü**  
  Verwaltung, welche TypeMods dieselben Farben/Styles wie der Type erhalten oder ausgeschlossen werden.

Die kleinen Listen-Menüs sollen auf dem generischen `menu.lua` aufbauen.
Der **Pipeline-Editor** ist ein eigener Float-Consumer, weil er eine 2D-Darstellung und Extmarks braucht.

---

## 2. Pick-Menü

Der Picker wird an einer Codeposition ausgelöst und erhält eine vorbereitete Liste der dort relevanten semantischen Ziele.

Beispiel:

```text
╭──────────── Pick ────────────╮
│ variable                     │
│ readonly                     │
│ declaration                  │
╰──────────────────────────────╯
```

### Bedienung

```text
j / ↓      nächster Eintrag
k / ↑      vorheriger Eintrag
<CR>       Eintrag auswählen
<BS>       eine Menüebene zurück
q / Esc    schließen
```

Nach Auswahl eines Types oder TypeMods folgt das kleine **Edit-Menü**.

---

## 3. Edit-Menü

Für einen **TypeMod**:

```text
╭──── Edit: readonly ────╮
│ Pipeline               │
│ Style                  │
╰────────────────────────╯
```

Für einen **Type** zusätzlich:

```text
╭──── Edit: variable ────╮
│ Pipeline               │
│ Style                  │
│ TypeMods               │
╰────────────────────────╯
```

### Bedeutung

- `Pipeline` öffnet den Pipeline-Editor.
- `Style` öffnet das Style-Multi-Select.
- `TypeMods` öffnet die TypeMod-Verwaltung und existiert nur dort, wo sie sinnvoll ist.

---

# 4. Pipeline-Editor

Der Pipeline-Editor ist die zentrale Farbansicht.

Er hat fünf Farbspalten:

```text
1 = FG
2 = BG
3 = SP
4 = CFG (ctermfg)
5 = CBG (ctermbg)
```

Beispiel:

```text
╭─ Pipeline: variable.readonly ───────────────────────────────────────────╮
│         1 FG          2 BG          3 SP         4 CFG        5 CBG     │
│         ████ c.text   ████ c.surface — unset    ████ c.text  ████ c.bg │
│         inherited                      [from FG]    [from BG] │
│                                                                      │
│ 1       ████ mix 30   ████ darken 5              new          new      │
│ 2       ████ opacity 80 new                                           │
│ 3       new                                                          │
╰──────────────────────────────────────────────────────────────────────╯
```

## 4.1 Aktive Zelle

Der Zustand des Editors ist nur:

```text
aktive Zeile + aktive Spalte = aktive Zelle
```

Eine aktive Zelle entspricht genau **einer** Manipulation bzw. einer Zelle der oberen Farbzeile.

Es gibt **keine zusätzliche Parameter-Fokus-Ebene**.

Die Spaltenauswahl wird visuell über Extmarks/Highlights dargestellt.  
Der Buffer kann technisch zeilenorientiert bleiben; die 2D-Struktur entsteht durch Extmarks / Virt-Text.

---

## 4.2 Navigation

```text
j / ↓      eine Pipeline-Zeile nach unten
k / ↑      eine Pipeline-Zeile nach oben

h / ←      vorherige Spalte
l / →      nächste Spalte

1          FG
2          BG
3          SP
4          CFG
5          CBG
```

Die Spaltennavigation zyklisiert zwischen allen fünf Kanälen. Auf schmalen
Fenstern folgt der horizontale Ausschnitt der gewählten Spalte; lange Pipelines
scrollen vertikal, während Farbzeile und Herkunft sichtbar bleiben.

---

## 4.3 Farb-Swatches

Jede Zelle der oberen Farbzeile und jede Pipeline-Manipulation kann zwei direkt aneinanderliegende Farbfelder anzeigen:

```text
████
^^^^
││└┴─ Output
└┴─── Input
```

Gedacht als:

```text
██ = Input
██ = Output
```

**Keine Lücke und kein Pfeil dazwischen.**

Dadurch lassen sich kleine Farbunterschiede direkt vergleichen.

Für aufeinanderfolgende Manipulationen gilt:

```text
Output von Schritt N = Input von Schritt N+1
```

Die obere Farbzeile zeigt entsprechend den aktuellen Ausgangszustand des Kanals.

---

## 4.4 Farbzeile

Alle fünf Kanäle benutzen **dasselbe Color-Menü**.

Beispiel:

```text
           ████ red      ████ surface      ████ blue
```

Auf einer Zelle der Farbzeile öffnet die Farbauswahl das gemeinsame `color.cf`-Menü.

`<CR>` auf der ersten Zeile wählt ausschließlich aus der für das aktive Theme
geladenen Palette (`hl.colors`/`c.*`), einschließlich verschachtelter Farbwerte.
CFG/CBG konvertieren diese Farben über den bestehenden Cterm-Pfad.

Ohne eigene oder geerbte Farbe bleibt die Spalte ausgegraut; ihre Zelle in der
Farbzeile ist weiter anwählbar und aktiviert die Spalte nach einer Farbauswahl.
Geerbte Farben werden normal aktiv angezeigt, mit `inherited` in der Display-Zeile
darunter. Bei einem Type, der nur über `types = { ... }` einer anderen Group
versorgt wird, ist diese Farbe das fertige Ergebnis der dortigen Pipeline; die
eigene Pipeline bleibt leer. Bloßes Öffnen/Übernehmen erzeugt keinen Override.
CFG/CBG-Fallbacks erhalten stattdessen `[from FG]` bzw. `[from BG]`.
Eine explizite Farbauswahl entfernt den Herkunftshinweis.

Es gibt keine separate Farbauswahl für FG/BG/SP.

---

## 4.5 Neue Manipulation

`n` bedeutet **new**.

```text
n          neue Manipulation an der aktuellen Position einfügen
```

Eine neue Manipulation darf **an jeder Position** eingefügt werden, nicht nur am Pipeline-Ende.

Das sichtbare Pipeline-Ende wird als:

```text
new
```

dargestellt.

Kein `+` als Endmarker, weil `+/-` bereits für Werte reserviert ist.

`n` öffnet das Manipulation-Menü.
`<CR>` auf `new` ebenfalls. Auf einer bestehenden Operation fügt `n` davor ein;
am Ende einer Spalte direkt nach deren letzter Operation. Die globale Reihenfolge
der vorhandenen Operationen bleibt erhalten, insbesondere BG vor FG-Opacity.

---

## 4.6 Manipulation löschen

```text
d          aktuelle Manipulation löschen
```

`d` gilt für echte Pipeline-Manipulationen, nicht für die Farbzeile.

---

## 4.7 Numerische Werte

Numerische Parameter werden direkt auf der aktiven Manipulation verändert.

```text
+          Wert +1
-          Wert -1

Alt-+      Wert +10
Alt--      Wert -10
```

Es gibt dafür **keinen zusätzlichen Edit-Modus**.

Gamma wird in Hundertsteln angezeigt: `gamma 110` entspricht DSL-Wert `1.10`.
Der kleinste Gamma-Wert ist `0.01`. Mix/Opacity/Lighten/Darken werden im Editor
zwischen 0 und 100 begrenzt; Brightness und ShiftHue behalten vorzeichenbehaftete Werte.

Die Darstellung und die Input/Output-Swatches sollen sich unmittelbar aktualisieren.

---

## 4.8 Farbreferenz innerhalb einer Manipulation

Manipulationen wie `mix`, die zusätzlich eine Farbe benötigen, verwenden **dasselbe Color-Menü wie die Farbzeile**.

Also:

```text
FG        ─┐
BG         ├──► gemeinsames Color-Menü
SP         │
mix color ┘
```

Es gibt keinen zweiten Farbpicker und keine freie RGB-Eingabe in dieser UI.

## 4.9 Übernehmen / Verwerfen

```text
a          gesamte Pipeline-Vorschau übernehmen, zurück zu Edit
<BS>       gesamte Vorschau verwerfen, zurück zu Edit
q / Esc    gesamte Vorschau verwerfen, schließen
CFSave     bestätigte Änderungen in die Theme-Datei schreiben
```

Abbrechen einer untergeordneten Farb-/Manipulationsauswahl kehrt unverändert
zum Pipeline-Editor zurück. Ein Theme-Reload macht einen geöffneten Entwurf
ungültig; er darf danach keine alten Farben zurückschreiben.

---

# 5. Color-Menü

Das Color-Menü zeigt ausschließlich Farben aus `color.cf`.

Beispiel:

```text
╭──────────── Color ────────────╮
│ ██ red                        │
│ ██ orange                     │
│ ██ accent                     │
│ ██ surface                    │
│ ██ muted                      │
╰───────────────────────────────╯
```

Jeder Eintrag kann direkt einen kleinen Farbswatch anzeigen.

### Verwendung

Dasselbe Menü wird benutzt für:

- Farbe von `FG`
- Farbe von `BG`
- Farbe von `SP`
- Farbe von `CFG` und `CBG`
- zusätzliche Farbreferenz einer Manipulation, z. B. `mix`

### Bedienung

```text
j / ↓      nächster Eintrag
k / ↑      vorheriger Eintrag
<CR>       Farbe übernehmen
<BS>       eine Menüebene zurück
q / Esc    abbrechen / schließen
```

---

# 6. Manipulation-Menü

Wird durch `n` im Pipeline-Editor geöffnet.

Beispiel:

```text
╭──── New manipulation ────╮
│ mix                       │
│ opacity                   │
│ brightness                │
│ lighten                   │
│ darken                    │
│ shiftHue                  │
│ gamma                     │
╰───────────────────────────╯
```

Die konkrete Liste kommt später aus den tatsächlich unterstützten Operationen.

### Bedienung

```text
j / ↓      nächster Eintrag
k / ↑      vorheriger Eintrag
<CR>       auswählen und einfügen
<BS>       eine Menüebene zurück
q / Esc    abbrechen / schließen
```

---

# 7. Style-Menü

Styles sind **keine Pipeline** und werden deshalb separat bearbeitet.

Nach:

```text
Type / TypeMod
      ↓
    Edit
      ↓
    Style
```

öffnet sich ein Drei-Zustands-Menü. Jeder Style kann explizit `true`, explizit `false` oder gar nicht gesetzt sein. Der nicht gesetzte Zustand lässt Neovim den Style aus anderen gleichzeitig wirkenden Highlights übernehmen.

Beispiel:

```text
╭──────────── Styles ───────────╮
│ [x] bold                      │
│ [-] italic                    │
│ [ ] underline                 │
│ [x] undercurl                 │
│ [ ] strikethrough             │
│ [ ] nocombine                 │
╰───────────────────────────────╯
```

Dabei gilt:

```text
[x] = true
[-] = false
[ ] = nicht gesetzt / von anderen Highlights übernehmen
```

### Bedienung

```text
j / ↓      nächster Style
k / ↑      vorheriger Style
Space      Zustand zyklisch wechseln: unset -> true -> false -> unset; Vorschau sofort anwenden
<CR>       aktuelle Vorschau übernehmen
<BS>       Vorschau verwerfen und eine Menüebene zurück
q / Esc    Vorschau verwerfen und schließen
```

Die Style-Liste enthält `bold`, `italic`, `underline`, `undercurl`,
`underdouble`, `underdotted`, `underdashed`, `strikethrough`, `overline`,
`reverse`, `standout`, `nocombine`, `altfont`, `blink`, `dim` und `conceal`.
Die sichtbare Darstellung hängt von der Unterstützung durch Terminal/GUI ab.
`conceal` bezeichnet hier das Highlight-Attribut, nicht Syntax-Conceal.

Zusätzlich gibt es die numerische Zeile `blend`: `unset` oder ein Integer von
0 bis 100. Auf dieser Zeile ändern `-`/`+` den Wert um 1 und
`<M-->`/`<M-+>` (Alt-Minus/Alt-Plus) um 10. Die Grenzen werden eingehalten;
ausgehend von `unset` wird mit 0 gerechnet. Space setzt `blend` wieder auf
`unset`; explizites `0` bleibt davon verschieden. Änderungen werden sofort
vorgezeigt und wie die übrigen Styles übernommen, verworfen und gespeichert.
`blend` wirkt nur in Darstellungskontexten, die Highlight-Blending unterstützen,
nicht als allgemeine Transparenz für beliebigen Buffertext.

---

# 8. TypeMods-Menü

Bei einem **Type** kann zusätzlich die TypeMod-Verwaltung geöffnet werden.

Das Menü bekommt eine vorbereitete Liste aller TypeMods dieses Types.  
**Wie diese Liste ermittelt wird, gehört nicht in dieses UI-Dokument.**

Wichtig ist die Trennung zwischen:

- `=` → dieser TypeMod benutzt exakt den fertigen Style / die fertigen Farben des Types
- `x` → dieser TypeMod ist explizit ausgeschlossen
- kein Marker → keine `true`/`false`-Regel auf Gruppenebene; daneben kann der tatsächliche vorhandene Zustand angezeigt werden

Beispiel:

```text
╭──── TypeMods: variable ─────────────────╮
│ =  readonly                             │
│    declaration          global          │
│ x  deprecated           excluded        │
│    async                empty           │
│    static               group: Pipeline │
│    builtin              group: Style    │
│    defaultLibrary       group: Style+Pipeline
╰─────────────────────────────────────────╯
```

## 8.1 `=` — exakt wie der Type

`=` entspricht der Gruppenregel:

```lua
typemods = {
    readonly = true,
}
```

Der TypeMod verwendet den **exakt fertigen Style des Types**.

Damit ist für diesen Eintrag kein zusätzlicher `Style`-/`Pipeline`-Status möglich.  
`=` und eine eigene Gruppen-Definition schließen sich gegenseitig aus.

```text
=  readonly
```

Mehr Information braucht diese Zeile nicht.

---

## 8.2 `x` — explizit ausgeschlossen

`x` entspricht der Gruppenregel:

```lua
typemods = {
    deprecated = false,
}
```

Der TypeMod wird auf Gruppenebene explizit ausgeschlossen / gecleart.

```text
x  deprecated    excluded
```

Auch hier ist `x` selbst ein eigener, eindeutiger Zustand.  
Eine eigene Style-/Pipeline-Tabelle kann nicht gleichzeitig derselbe Gruppenwert sein.

---

## 8.3 Kein `=` und kein `x`

Wenn für den TypeMod **keine `true`-/`false`-Regel** gesetzt ist, zeigt die rechte Seite rein informativ, was bereits vorhanden ist.

Mögliche Anzeigen:

```text
global
empty
group: Style
group: Pipeline
group: Style+Pipeline
```

Beispiele:

```text
   declaration       global
   async             empty
   static            group: Pipeline
   builtin           group: Style
```

Bedeutung:

- `global`  
  Der TypeMod hat keine eigene Gruppenregel und wird über den globalen TypeMod-Zustand ohne konkreten Type bedient.

- `empty`  
  Es gibt weder eine Gleichbehandlung mit dem Type noch eine eigene Gruppen-Definition noch einen vorhandenen allgemeineren Style.

- `group: Style`  
  Für diesen konkreten Type+TypeMod existiert bereits eine eigene Style-Definition in `*:group(...).typemods`.

- `group: Pipeline`  
  Für diesen konkreten Type+TypeMod existiert bereits eine eigene Pipeline in `*:group(...).typemods`.

- `group: Style+Pipeline`  
  Beides existiert in derselben eigenen Gruppen-Definition.

Diese rechte Spalte ist **nur Statusanzeige**.  
Eine eigene Pipeline oder ein eigener Style wird nicht über einen künstlichen TypeMod-Zustand erzeugt; das ergibt sich automatisch aus dem normalen `*:group`-Aufbau.

---

## 8.4 Bedienung

```text
j / ↓      nächster TypeMod
k / ↑      vorheriger TypeMod

<CR>       bestehendes Edit-Menü für diesen TypeMod öffnen (Pipeline / Style)

=          „gleich wie Type“ toggeln
x          „ausgeschlossen“ toggeln

<BS>       eine Menüebene zurück
q / Esc    schließen
```

`=` und `x` toggeln ihren jeweiligen Zustand direkt:

```text
[ ] + =    → [=]
[=] + =    → [ ]

[ ] + x    → [x]
[x] + x    → [ ]

[x] + =    → [=]
[=] + x    → [x]
```

Es braucht dafür keine weitere Taste und kein Untermenü.

`=` und `x` wirken direkt als ausstehende Änderungen; Zurück/Schließen verwirft
sie nicht. `CFSave` schreibt sie in die ursprüngliche `typemods`-Tabelle.
Das Style-Untermenü behält sein eigenes Vorschau-/Abbrechen-Verhalten.

Die Liste wird bei jedem Öffnen aus den gerade vorhandenen Highlight-Gruppen
der Session ermittelt, nicht aus einer festen Liste möglicher LSP-Modifier.
Angezeigt werden nur Kombinationen des gewählten Types, generisch oder passend
zum ursprünglichen Buffer-Dateityp. Fremde Dateityp-Suffixe sind keine Mods.
`group: Link` kennzeichnet zusätzlich eine eigene Link-Definition.

Die erste `CFPick`-Auswahl stammt weiterhin ausschließlich aus den Tokens bzw.
Captures am Cursor (LSP vor Tree-sitter vor Vim). Die Bearbeitungsmenüs übernehmen
diese Einträge ohne erneute Verfügbarkeitssuche. Nur `Type -> TypeMods` erweitert
die Auswahl auf alle verfügbaren Kombinationen dieses Types in der Session.
Der Einstieg `Mod -> Style` bearbeitet bestehende Theme-Deklarationen. Fehlt die
Mod-Regel, wird sie im bereits über den Cursor-Type zugeordneten Modul angelegt.
Es gibt dafür keine separate Modulauswahl oder erneute Session-Suche.
Der Menü-Float ändert den ursprünglichen Datei-/Sprachkontext nicht.

# 9. UI-Fluss

Der komplette UI-Fluss sieht damit grob so aus:

```text
Pick
 │
 ├─ Type
 │   │
 │   └─ Edit
 │       ├─ Pipeline
 │       │   ├─ FG/BG/SP/CFG/CBG → Color-Menü
 │       │   ├─ n → Manipulation-Menü
 │       │   ├─ +/- → Zahlenwert
 │       │   └─ mix-Farbe → Color-Menü
 │       │
 │       ├─ Style
 │       │   └─ Style-Multi-Select
 │       │
 │       └─ TypeMods
 │           ├─ = gleicher Style/Farben
 │           └─ x ausgeschlossen
 │
 └─ TypeMod
     │
     └─ Edit
         ├─ Pipeline
         │   ├─ FG/BG/SP/CFG/CBG → Color-Menü
         │   ├─ n → Manipulation-Menü
         │   ├─ +/- → Zahlenwert
         │   └─ mix-Farbe → Color-Menü
         │
         └─ Style
             └─ Style-Multi-Select
```

---

# 10. Bewusst nicht Teil dieses Dokuments

Noch **keine** Festlegung für:

- wie Treffer unter dem Cursor gesammelt werden
- wie Vim-, Treesitter- und LSP-Gruppen auf CF-Semantik abgebildet werden
- Resolver-Logik
- Quell-/Fallback-Auswahl
- wohin Änderungen geschrieben werden
- Persistenz / Speichern
- genaue Datenmodelle
- konkrete Pipeline-Operationen und deren erlaubte Wertebereiche
- konkrete Style-Liste
- konkrete Implementierung der Menü-Stacks

Dieses Dokument beschreibt nur **UI, Bedienung und sichtbaren Aufbau**.
