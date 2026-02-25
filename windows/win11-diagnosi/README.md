# win11-diagnosi

Script di diagnostica completa per Windows 10/11, progettato per produrre un report Markdown analizzabile da AI (Claude Code, ChatGPT, ecc.).

## Requisiti

- Windows 10 o 11
- PowerShell 5.1+ (preinstallato)
- Nessuna dipendenza esterna

## Utilizzo

1. Copiare `win11-diagnosi.bat` e `win11-diagnosi.ps1` nella stessa cartella
2. **Tasto destro** su `win11-diagnosi.bat` > **Esegui come amministratore**
3. Il report viene salvato nella cartella di esecuzione come `diagnosi_<HOSTNAME>_<TIMESTAMP>.md`

> **Nota**: eseguire come Amministratore per risultati completi. Senza elevazione mancano: stato Defender, temperature, dettagli servizi svchost.

## Cosa analizza

| Sezione | Dettagli |
|---------|----------|
| Sistema | OS, modello, BIOS, uptime |
| Hardware | CPU, GPU, batteria |
| Memoria | RAM, commit charge, paging file, pool |
| Dischi | Spazio per drive, analisi cartelle, file grandi, spazio recuperabile |
| Processi | Top 25 per RAM e CPU, raggruppamento per nome |
| Handle | Handle count per processo, identificazione handle leak |
| Servizi svchost | Identificazione servizi con handle elevati |
| Shell Overlays | Icon overlay handlers (causa frequente di lentezza explorer) |
| Explorer DLL | DLL non-Microsoft caricate in explorer.exe |
| Startup | Programmi in avvio automatico con stato enabled/disabled |
| Scheduled Tasks | Task non-Microsoft attivi |
| Servizi | Servizi Automatic non in esecuzione |
| Defender | Stato protezione, firme, ultime scansioni |
| Event Log | Errori Application e System delle ultime 24h |
| Power Plan | Piano energetico attivo |
| Rete | Interfacce attive, DNS |
| Raccomandazioni | Anomalie rilevate automaticamente |

## Output

Il report e' un file Markdown strutturato con tabelle, pronto per essere sottoposto a un'AI per analisi e raccomandazioni.

Esempio di nome file: `diagnosi_DESKTOP-ABC123_2026-02-25_10-30-00.md`
