# CHANGELOG

## 1.0.0 - 2026-05-18

- Prima integrazione nel repository come `windows/network-scanner`.
- Rinominato il prototipo `lan-scanner` in `network-scanner`.
- Aggiunti profili `Fast`, `Standard`, `Deep`.
- Reverse DNS attivo di default con `-NoDns`.
- `-UpdateOui` aggiorna il database OUI IEEE e termina senza scansione.
- Aggiunti confronto con scansione precedente e inventario persistente.
- Spostati dati runtime sotto `%LOCALAPPDATA%\network-scanner` per non sporcare il repository.
- Aggiunti README essenziale ed esempi d'uso.
- Corretto `-Compare` quando non esiste ancora una scansione precedente.
- Corretto riepilogo `Added/Changed` in `StrictMode`.
- Aggiunto export dei device rimossi in HTML/CSV/JSON.
- Migliorato output console con colonne piu' compatte.
- Documentati mDNS e SNMP come proposte non ancora implementate.
- Rinominata la colonna HTML da `Change` a `Status` per stato `online`/`offline`, mantenendo `Change` come dettaglio separato.
- Evidenziate le righe `offline` nel report HTML.
- Aggiunti sort colonne, ricerca, toggle offline e resize colonne nel report HTML con JavaScript vanilla incorporato.
