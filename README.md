# Scripts

Script operativi per amministrazione sistemi - Soiware S.n.c.

## Indice

### Windows
- [Get-PendingReboot.ps1](windows/Get-PendingReboot.ps1) - Verifica se un server Windows richiede riavvio

### Linux
- (in arrivo)

### Cross-Platform
- (in arrivo)

## Struttura

| Cartella | Contenuto |
|----------|-----------|
| `windows/` | Script PowerShell per Windows Server e Client |
| `linux/` | Script Bash per Debian, Ubuntu, Proxmox |
| `cross-platform/` | Script Python o altri linguaggi multi-piattaforma |
| `_private/` | Script locali non committati |

## Utilizzo

### Windows (PowerShell)

```powershell
# Esecuzione diretta
.\windows\Get-PendingReboot.ps1

# Con parametri
.\windows\Get-PendingReboot.ps1 -ShowPendingFiles -Verbose
```

### Linux (Bash)

```bash
# Rendi eseguibile
chmod +x linux/script.sh

# Esegui
./linux/script.sh
```

## Sicurezza

**ATTENZIONE:** Prima di committare qualsiasi script, verificare che:

1. Non contenga IP, hostname o domini reali dell'infrastruttura
2. Non contenga credenziali, password o token
3. Non contenga path assoluti con nomi utente o dati sensibili

Il file `.gitignore` è configurato per escludere automaticamente file potenzialmente sensibili, ma la verifica manuale è sempre necessaria.

## Correlazione con Knowledge Base

Gli script di questo repository possono essere referenziati nella [Knowledge Base](https://github.com/dcal-start/kb) quando servono come parte di procedure documentate.
