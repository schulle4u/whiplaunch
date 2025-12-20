# ATMIRAL
Barrierefreies textbasiertes Menü zum Starten von Programmen unter Linux

<span align="right">🌐 [Deutsch](./README-de.md) | [English](./README.md)</span>

## Beschreibung

[![Screenshot](./screenshot.png)](./screenshot.png)

ATMIRAL (Abkürzung für "Accessible text-based menu interface for running applications on Linux") ist ein benutzerfreundliches Startmenü für die Linux-Shell zum schnellen Aufrufen häufig verwendeter Programme und Befehle. Über eine Ordnerstruktur mit menschenlesbaren Textdateien kann das Menü individuell zusammengestellt werden und ist somit an jedes Linux-System anpassbar. Es eignet sich sowohl für Anfänger, um ihnen die Scheu vor Befehlseingaben zu nehmen, als auch für Menschen, die für bestimmte Abläufe bewusst eine eingeschränkte Arbeitsumgebung bevorzugen. Es soll dabei weder die Befehlseingabe noch eine komplette grafische Oberfläche auf Shellebene ersetzen. Derzeit sind folgende Module enthalten: 

* ATMIRAL (`atmiral.sh`): Das Hauptprogramm mit individuell anpassbaren Befehlssammlungen. 
* ATMIRAL Dateibrowser (`atmiralfm.sh`): Ein einfacher Dateibrowser zum Auflisten und Öffnen von Dateien. 

## Installation

Das Repository clonen und `install.sh` ausführbar machen. 

```
chmod +x ./install.sh
```

Folgende Installationsoptionen sind verfügbar: 

* `./install.sh --user`: Installation nur für den aktuellen Benutzer.
* `sudo ./install.sh --system`: Systemweite Installation, benötigt Root-Rechte. 
* `sudo ./install.sh --both`: Installation systemweit und für den aktuellen Benutzer, benötigt Root-Rechte. 
* `sudo ./install.sh --uninstall`: ATMIRAL vom System entfernen, benötigt je nach vorheriger Installation Root-Rechte. 

Nach der Installation sind die einzelnen Module in der gewählten Installationsumgebung aufrufbar, z. B. `atmiral` für das Hauptprogramm oder `atmiralfm` für den dateibrowser. ATMIRAL kann durch Aufruf von `atmiral.sh` auch direkt aus dem Quellcode-Verzeichnis ausgeführt werden, sollte keine Installation gewünscht sein. 

## Verwendung des Hauptprogramms

### Menüverzeichnisse

Die Menüdateien werden in folgenden Ordnern gefunden, aufgeführt in absteigender Priorität: 

* Benutzerdefiniert: Aufruf `atmiral <Pfad>`
* Im Benutzerordner: `$HOME/.local/share/atmiral/menu/`
* Systemweit: `/usr/local/share/atmiral/menu/`
* Im Skriptverzeichnis (letztes Fallbackverzeichnis): `./menu/`

### Menüs erstellen

Eine Menüdatei besteht aus Konfigurationsabschnitten, die durch eine leerzeile voneinander getrennt sind. Jeder Konfigurationsabschnitt kann folgende Felder enthalten: 

* Name: Anzeigename des Programms oder Befehls (nicht der eigentliche Befehl)
* Beschreibung: Kurze Beschreibung, wird rechts neben dem Namen angezeigt.
* Befehl: Der eigentliche Befehl, welcher beim Bestätigen des Menüeintrags aufgerufen wird. 
* Argumente: jede Art von festen oder dynamischen Befehlsoptionen. Der Text zwischen `<` und `>` wird als Platzhalter erkannt und im Menü beim Aufrufen abgefragt. 

Folgende Platzhalter können verwendet werden, um spezielle Dialogboxen während der Abfrage aufzurufen: 

* `<Datei>`: Öffnet einen Dateiauswahldialog
* `<Verzeichnis>`: Öffnet eine Verzeichnisauswahl.
* `<Passwort>`: Eingabefeld für Passwörter.

**Hinweis**: Die oben genannten Feldnamen und Platzhalter sind für jede Sprache übersetzbar. Wird ATMIRAL in einer anderen Sprache als deutch verwendet, müssen auch die Feldnamen und Platzhalter in dieser Sprache angegeben werden, sofern sie in der Sprachdatei übersetzt wurden. 

### Beispiel

Hier ist eine Menüdatei mit verschiedenen Systembefehlen.

```
Name: Top
Beschreibung: Systemmonitor
Befehl: top

# Hier nutzen wir Dialog, um die Systemlaufzeit in einer Hinweisbox anzuzeigen
Name: Uptime
Beschreibung: Zeigt Systemlaufzeit
Befehl: dialog --no-lines --title "uptime" --msgbox "$(uptime)" 10 70

Name: Updates
Beschreibung: Nach Updates suchen
Befehl: sudo apt update && sudo apt upgrade

# Im nachfolgenden Beispiel wird <Text> als Argumentvorlage hinterlegt und beim Aufruf abgefragt
Name: Sprachausgabe
Beschreibung: Eingegebenen Text sprechen
Befehl: espeak-ng
Argumente: -v de -a 100 -s 300 "<Text>"

# Es sind auch mehrere Platzhalter möglich, die dann nacheinander vor dem Befehlsaufruf abgefragt werden
Name: Dienststeuerung
Beschreibung: Dienststeuerung
Befehl: sudo systemctl
Argumente: <Aktion> <Dienst>
```

### Das Interface

Nach dem Starten von ATMIRAL werden die im Menüverzeichnis angelegten Dateien und Unterordner als zweispaltige Liste mit Namen und Beschreibung angezeigt. Mit Pfeiltasten hoch und runter kann durch die Listen navigiert werden, mit Enter bestätigt man die Auswahl. Am Beginn jeder Liste befindet sich ein Eintrag, um ins übergeordnete Menü zurückzukehren. Solange ATMIRAL geöffnet ist, werden alle Befehle in dessen Umgebung ausgeführt. Dadurch landet man nach jedem Aufruf eines Befehls wieder im aktuellen Menü. Escape beendet das ATMIRAL-Interface und man kehrt zurück in die normale Shell-Umgebung. 

### Konfiguration

Einige Konfigurationsoptionen lassen sich in der Datei `atmiral.conf` festlegen: 

* `ATMIRAL_LANG`: Die für das Interface verwendete Sprache, entspricht dem Namen der Sprachdatei ohne Erweiterung, z. B. `de`. 
* `COMMAND_DEBUG`: Auf 1 setzen, um die Ausgabe der Befehle einzuschalten.

Wer für das Menü eine dunkle Farbgebung bevorzugt, findet im Ordner eine `.dialogrc` Beispieldatei, welche in das Home-Verzeichnis kopiert werden kann. Sie enthält Darkmode-Farben und setzt auch die Option `visit_items` auf `ON`, um eine bessere Tastaturbedienung zu ermöglichen. Letztere Option wird jedoch bereits im Script beim Definieren des Menüs festgelegt. 

## Dateibrowser

Der ATMIRAL-Dateibrowser wird mit dem Befehl `atmiralfm` bzw. `atmiralfm.sh` im Skriptverzeichnis aufgerufen. Das Homeverzeichnis des aktuellen Benutzers ist standardmäßig als Startverzeichnis festgelegt. Ein anderes Startverzeichnis kann als Argument an `atmiralfm` übergeben werden. Die Navigation durch Dateien und Ordner ist selbsterklärend und funktioniert entweder mittels Pfeiltasten hoch und runter oder durch die Eingabe des Anfangsbuchstabens eines Eintrags sowie der Bestätigung mit Enter. Wie in vielen Dateimanagern üblich befindet sich am Anfang jeder Liste die Möglichkeit in den nächsthöheren Ordner zu wechseln. Am linken oberen Bildschirmrand ist eine dem Shell-Prompt ähnliche Statuszeile hinterlegt, welche den Benutzer und Hostnamen sowie den aktuellen Ordnerpfad anzeigt. 

Nach der Auswahl einer datei oder durch Drücken der Aktionen-Schaltfläche öffnet sich ein Aktionsmenü, welches verschiedene Optionen zum Umgang mit Dateien und Ordnern anbietet. Je nach Dateityp und installierten Paketen kann die Anzeige variieren. Folgende Auswahlmöglichkeiten sind möglich: 

* Verzeichnis öffnen
* Datei öffnen (Text, Audio/Video, Bilder)
* Benutzerdefiniert: Erlaubt die Eingabe eines benutzerdefinierten Befehls zum Betrachten der Datei.
* Ausführen: Prüft, ob die Datei ausführbar ist und startet sie direkt. 
* Kopieren nach: Datei an einen anderen Ort kopieren
* Verschieben nach: Datei an einen anderen Ort verschieben.
* Löschen: Datei nach Bestätigung löschen.
* Info: Zeigt Dateiinformationen an.
* Abbruch: Schließt das menü und kehrt in die Dateiliste zurück. 

### Konfiguration des Dateibrowsers

Folgende Optionen sind in der Datei `atmiral.conf` verfügbar: 

* `SHOW_HIDDEN`: Versteckte Dateien und Verzeichnisse anzeigen
* `DEFAULT_EDITOR`: Standard-Texteditor, z. B. nano oder vim
* `DEFAULT_VIEWER`: Standard-Dateibetrachter, z. B. less, more, w3m.
* `DEFAULT_PLAYER`: Standard-Medienwiedergabe, z. B.  mpv, vlc. 
* `DEFAULT_IMG_VIEWER`: Standard-Bildbetrachter, z. B. feh. 

## Entwicklung

Copyright (C) 2025 Steffen Schultz, freigegeben unter den Bedingungen der MIT-Lizenz. 
