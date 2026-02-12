# powershell-aliases

Alias PowerShell personalizzati per uso operativo, in stile Linux.

## Alias disponibili

| Alias | Descrizione | Flag |
|-------|-------------|------|
| `ll`  | Lista file dettagliata (equivalente `ls -la` su Linux) | `-s` nome, `-t` data, `-r` reverse, `-a` nascosti, combinabili (es. `-tr`, `-sta`) |

## Installazione

```powershell
.\Install-Aliases.ps1
```

Lo script installa tutti gli alias nel profilo PowerShell dell'utente corrente (`$PROFILE`).
Gli alias vengono inseriti in un blocco marcato, sovrascrivibile con esecuzioni successive.

## Aggiornamento

Per aggiornare o aggiungere nuovi alias:

1. Aggiungere il file `.ps1` con la funzione in questa cartella
2. Rieseguire `.\Install-Aliases.ps1`

## Disinstallazione

Rimuovere dal proprio `$PROFILE` il blocco compreso tra:

```
# >>> powershell-aliases (infra-ops) >>>
# <<< powershell-aliases (infra-ops) <<<
```
