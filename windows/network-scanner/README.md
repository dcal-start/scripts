# network-scanner

Scanner PowerShell standalone per discovery di LAN e subnet IPv4 locali.

Compatibile con Windows PowerShell 5.1 e PowerShell 7+. Non richiede Active Directory e non richiede moduli PowerShell esterni obbligatori.

## Funzionalita'

- Scan veloce di subnet IPv4 in formato CIDR.
- ICMP sweep parallelo con runspace pool.
- TCP probe opzionale.
- Profili `Fast`, `Standard`, `Deep`.
- Reverse DNS attivo di default, disattivabile con `-NoDns`.
- NetBIOS opzionale con `-NetBios`.
- Lettura MAC da ARP/neighbor cache locale.
- Vendor lookup da database OUI locale.
- Aggiornamento OUI dal database ufficiale IEEE con `-UpdateOui`.
- Export HTML predefinito, CSV/JSON opzionali.
- Confronto con scansione precedente tramite `-Compare`.
- Inventario persistente dei device rilevati.
- Versione interna tramite `-Version`.

Nota: il MAC address reale e' affidabile normalmente solo sullo stesso segmento Layer 2. mDNS e SNMP sono stati valutati, ma non inclusi in questa prima integrazione per mantenere il tool senza probe UDP aggiuntivi oltre a NetBIOS e senza traffico non necessario; se aggiunti, devono restare opt-in.

## Uso rapido

```powershell
# Versione
.\network-scanner.ps1 -Version

# Scansione standard con DNS reverse e report HTML
.\network-scanner.ps1 -Subnet 192.168.1.0/24

# Scansione veloce senza DNS
.\network-scanner.ps1 -Subnet 192.168.1.0/24 -Profile Fast -NoDns

# TCP probe leggero
.\network-scanner.ps1 -Subnet 192.168.1.0/24 -TcpProbe

# Profilo deep con TCP probe su piu' porte
.\network-scanner.ps1 -Subnet 192.168.1.0/24 -Profile Deep

# NetBIOS opzionale
.\network-scanner.ps1 -Subnet 192.168.1.0/24 -NetBios

# Export multipli
.\network-scanner.ps1 -Subnet 192.168.1.0/24 -ExportCsv -ExportJson

# Confronto con la scansione precedente
.\network-scanner.ps1 -Subnet 192.168.1.0/24 -Compare

# Aggiorna OUI database e termina senza scansione
.\network-scanner.ps1 -UpdateOui
```

## Dati runtime

Per default il tool scrive configurazione, OUI database, inventario e report sotto:

```text
%LOCALAPPDATA%\network-scanner
```

Si puo' cambiare percorso con:

```powershell
.\network-scanner.ps1 -Subnet 192.168.1.0/24 -DataPath C:\Temp\network-scanner-data
```

## Profili

| Profilo | Uso | TCP probe |
|---------|-----|-----------|
| `Fast` | Scansione rapida, timeout ridotti | Disattivo salvo `-TcpProbe` |
| `Standard` | Default bilanciato | Disattivo salvo `-TcpProbe` |
| `Deep` | Scansione piu' lenta e completa | Attivo, con `-TcpScanAllPorts` |

## Output

- Report HTML: attivo di default; include sort colonne, ricerca, toggle offline e resize colonne senza dipendenze esterne.
- CSV: `-ExportCsv`; include `Status` con valori `online`/`offline`.
- JSON: `-ExportJson`; esporta `Current` e `Removed`, con `Status` `online`/`offline`.
- Stato ultima scansione: `%LOCALAPPDATA%\network-scanner\state\latest-scan.json`.
- Inventario persistente: `%LOCALAPPDATA%\network-scanner\state\inventory.json`.

## Proposte non ancora implementate

- mDNS opzionale per discovery `.local`.
- SNMP base opzionale per `sysName` e `sysDescr`.

Entrambe restano candidate per versioni successive e devono rimanere opt-in, con timeout conservativi.
