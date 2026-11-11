<#
.SYNOPSIS
    Uninstall-3CX-PWA.ps1 - Desinstallation complete du deploiement 3CX PWA realise par Deploy-3CX-PWA.ps1.

.DESCRIPTION
    Concu pour etre execute via un outil RMM (ex. Atera) en contexte SYSTEM, sous Windows PowerShell 5.1.
    Le script continue meme si une etape echoue, journalise chaque etape et renvoie le code 1 s'il y a eu des erreurs.

    Ce qui est supprime :
      - la tache planifiee 3CX-PWA-Watchdog ;
      - les strategies Edge ajoutees par le deploiement : WebAppInstallForceList (entrees 3CX uniquement),
        NotificationsAllowedForUrls, AudioCaptureAllowedUrls, VideoCaptureAllowedUrls (valeurs 3CX uniquement),
        et BackgroundModeEnabled (selon le parametre) ;
      - les raccourcis de PWA 3CX (Demarrage, menu Demarrer, Bureau) dans tous les profils ;
      - le dossier C:\ProgramData\3CX-PWA (watchdog, lanceur, logs) et les fichiers 3CX-PWA-* de chaque profil.

    Ce qui n'est PAS touche : l'application de bureau 3CX, les autres strategies Edge, les autres applications web.

    Remarque : une fois la strategie d'installation retiree, Edge desinstalle lui-meme la PWA au prochain
    rafraichissement des strategies ou au prochain redemarrage. Si une fenetre 3CX est ouverte, elle
    reste ouverte jusqu'a sa fermeture.

.PARAMETER RetirerModeArrierePlan
    $true = supprime aussi BackgroundModeEnabled (Edge ne reste plus actif en arriere-plan).
    A mettre a $false si ce reglage sert a autre chose sur le poste.

.PARAMETER ConserverLogs
    $true = conserve C:\ProgramData\3CX-PWA\deploy.log et supprime le reste.

.PARAMETER MotCle
    Motif servant a reconnaitre les elements 3CX (adresses, raccourcis). "3cx" convient a tous les domaines *.3cx.* et *.on3cx.fr.
#>

# ============================ PARAMETRES ============================
$RetirerModeArrierePlan = $true     # $true = supprime aussi BackgroundModeEnabled
$ConserverLogs          = $false    # $true = conserve deploy.log
$MotCle                 = "3cx"     # motif identifiant les elements 3CX
# ====================================================================

# Relance en PowerShell 64 bits si necessaire
if ($env:PROCESSOR_ARCHITEW6432 -eq "AMD64") {
    & "$env:WINDIR\sysnative\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $MyInvocation.MyCommand.Path
    exit $LASTEXITCODE
}

$Dir      = "$env:ProgramData\3CX-PWA"
$Log      = "$env:ProgramData\3CX-PWA-uninstall.log"
$EdgeKey  = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
$TaskName = "3CX-PWA-Watchdog"
$Lists    = "NotificationsAllowedForUrls", "AudioCaptureAllowedUrls", "VideoCaptureAllowedUrls"
$Erreurs  = 0

function Write-Log($m) {
    $l = "{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $m
    Add-Content -Path $Log -Value $l -ErrorAction SilentlyContinue
    Write-Output $l
}

# Execute une etape ; en cas d'erreur, la journalise et continue
function Invoke-Etape($Nom, [scriptblock]$Bloc) {
    $ErrorActionPreference = "Stop"
    try {
        Write-Log "Etape : $Nom"
        & $Bloc
    } catch {
        $script:Erreurs++
        Write-Log "  ERREUR : $($_.Exception.Message)"
    }
}

Write-Log "=== Desinstallation 3CX PWA ==="

# ---------------------------- Tache planifiee ----------------------------
Invoke-Etape "Tache planifiee $TaskName" {
    $t = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($t) {
        Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Log "  tache supprimee"
    } else {
        Write-Log "  tache absente"
    }
}

# ------------------------------ Strategies Edge ------------------------------
Invoke-Etape "Strategie WebAppInstallForceList" {
    $p = Get-ItemProperty $EdgeKey -Name WebAppInstallForceList -ErrorAction SilentlyContinue
    if ($p -and $p.WebAppInstallForceList) {
        $items = @($p.WebAppInstallForceList | ConvertFrom-Json)
        $reste = @($items | Where-Object { $_.url -notmatch $MotCle })
        if ($reste.Count -gt 0) {
            $json = ConvertTo-Json -InputObject $reste -Compress
            Set-ItemProperty $EdgeKey -Name WebAppInstallForceList -Value $json -Type String
            Write-Log "  entrees 3CX retirees, autres applications conservees"
        } else {
            Remove-ItemProperty $EdgeKey -Name WebAppInstallForceList
            Write-Log "  strategie supprimee"
        }
    } else {
        Write-Log "  strategie absente"
    }
}

foreach ($l in $Lists) {
    Invoke-Etape "Strategie $l" {
        $k = "$EdgeKey\$l"
        if (Test-Path $k) {
            foreach ($n in (Get-Item $k).Property) {
                $v = (Get-ItemProperty $k -Name $n).$n
                if ("$v" -match $MotCle) { Remove-ItemProperty $k -Name $n }
            }
            if (-not (Get-Item $k).Property) {
                Remove-Item $k -Force
                Write-Log "  cle supprimee"
            } else {
                Write-Log "  valeurs 3CX retirees, autres valeurs conservees"
            }
        } else {
            Write-Log "  cle absente"
        }
    }
}

if ($RetirerModeArrierePlan) {
    Invoke-Etape "BackgroundModeEnabled" {
        Remove-ItemProperty $EdgeKey -Name BackgroundModeEnabled -ErrorAction SilentlyContinue
        Write-Log "  valeur retiree (si presente)"
    }
} else {
    Write-Log "BackgroundModeEnabled conserve (parametre)"
}

# --------------------------------- Raccourcis ---------------------------------
Invoke-Etape "Raccourcis de PWA 3CX (Demarrage, menu Demarrer, Bureau)" {
    $wsh = New-Object -ComObject WScript.Shell
    $dossiers = @(
        "$env:SystemDrive\Users\*\AppData\Roaming\Microsoft\Windows\Start Menu\Programs",
        "$env:SystemDrive\Users\*\Desktop",
        "$env:SystemDrive\Users\*\OneDrive*\Desktop",
        "$env:PUBLIC\Desktop",
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs"
    )
    $n = 0
    foreach ($d in $dossiers) {
        Get-ChildItem $d -Filter "*.lnk" -Recurse -Depth 2 -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $a = $wsh.CreateShortcut($_.FullName).Arguments
                if ($a -match '--app(-id)?=' -and $a -match $MotCle) {
                    Remove-Item $_.FullName -Force
                    Write-Log "  raccourci supprime : $($_.FullName)"
                    $n++
                }
            } catch { }
        }
    }
    Write-Log "  $n raccourci(s) supprime(s)"
}

# ----------------------------------- Fichiers -----------------------------------
Invoke-Etape "Dossier $Dir" {
    if (Test-Path $Dir) {
        if ($ConserverLogs) {
            Get-ChildItem $Dir | Where-Object { $_.Name -ne "deploy.log" } | Remove-Item -Recurse -Force
            Write-Log "  dossier nettoye, deploy.log conserve"
        } else {
            Remove-Item $Dir -Recurse -Force
            Write-Log "  dossier supprime"
        }
    } else {
        Write-Log "  dossier absent"
    }
}

Invoke-Etape "Fichiers 3CX-PWA-* dans les profils utilisateurs" {
    $f = @(Get-ChildItem "$env:SystemDrive\Users\*\AppData\Local" -Filter "3CX-PWA-*" -ErrorAction SilentlyContinue)
    $f | Remove-Item -Force
    Write-Log "  $($f.Count) fichier(s) supprime(s)"
}

# ------------------------------------ Bilan ------------------------------------
if ($Erreurs -gt 0) {
    Write-Log "=== Termine avec $Erreurs erreur(s). Voir $Log ==="
    exit 1
}
Write-Log "=== Desinstallation terminee sans erreur. La PWA disparait des profils au prochain rafraichissement des strategies ou redemarrage d'Edge. ==="
exit 0