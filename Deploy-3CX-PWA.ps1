<#
    .SYNOPSIS
        Deploy-3CX-PWA.ps1 - Déploiement du client web 3CX en Progressive Web App (PWA) via Microsoft Edge.
    
    .DESCRIPTION
        Ce script est conçu pour être exécuté via un outil RMM (ex: Atera) en contexte SYSTEM.
        
        Fonctionnalités :
          - Installation forcée de la PWA via les stratégies de registre Microsoft Edge.
          - Maintien d'Edge en arrière-plan pour la gestion des notifications.
          - Autorisations automatiques des notifications, du micro et de la caméra pour le PBX.
          - Watchdog intégré (tâche planifiée par utilisateur) : relance discrètement la PWA si elle est fermée (fenêtre réduite, sans voler le focus).

    .PARAMETER PbxUrl
        URL complète du client web 3CX (ex: https://your-pbx.on3cx.fr/webclient).
    
    .PARAMETER AppId
        ID unique de la PWA généré par Edge (visible dans edge://web-app-internals).
    
    .NOTES
        Désinstallation : Passer la variable $Mode à "Uninstall".
        Désactivation temporaire sur un poste : Créer un fichier vide nommé C:\ProgramData\3CX-PWA\disable
#>

# ======================== PARAMÈTRES À ADAPTER ========================
$PbxUrl       = "https://your-pbx.on3cx.fr/webclient"    # URL du client web 3CX du client cible
$AppName      = "3CX"                                   # Nom affiché de l'application
$TitleMatch   = "3CX"                                   # Texte présent dans le titre de la fenêtre PWA
$NotifRelance = $false                                  # $true = affiche une notification Windows à chaque relance (par défaut : silencieux)
$RepeatSec    = 60                                      # Fréquence de vérification du watchdog (secondes, minimum 60)
$AppId        = "votre_app_id_edge_ici"                 # ID de la PWA Edge (ou laisser vide pour utiliser le mode --app=URL)
$Mode         = "Install"                               # "Install" ou "Uninstall"
# ======================================================================

# Relance en PowerShell 64 bits si nécessaire
if ($env:PROCESSOR_ARCHITEW6432 -eq "AMD64") {
    & "$env:WINDIR\sysnative\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $MyInvocation.MyCommand.Path
    exit $LASTEXITCODE
}

$ErrorActionPreference = "Stop"
$Dir      = "$env:ProgramData\3CX-PWA"
$Log      = "$Dir\deploy.log"
$EdgeKey  = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
$LnkPath  = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp\$AppName.lnk"
$TaskName = "3CX-PWA-Watchdog"
$Lists    = "NotificationsAllowedForUrls", "AudioCaptureAllowedUrls", "VideoCaptureAllowedUrls"

if (-not (Test-Path $Dir)) {
    New-Item $Dir -ItemType Directory -Force | Out-Null
}

function Write-Log($m) {
    $l = "{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $m
    Add-Content -Path $Log -Value $l -ErrorAction SilentlyContinue
    Write-Output $l
}

try {
    # ------------------------- DÉSINSTALLATION -------------------------
    if ($Mode -eq "Uninstall") {
        Write-Log "Mode Uninstall"
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
        Remove-Item $LnkPath -Force -ErrorAction SilentlyContinue
        Remove-ItemProperty $EdgeKey -Name WebAppInstallForceList -ErrorAction SilentlyContinue
        foreach ($p in $Lists) { Remove-Item "$EdgeKey\$p" -Recurse -Force -ErrorAction SilentlyContinue }
        Remove-Item "$Dir\watchdog.ps1", "$Dir\launcher.vbs", "$Dir\disable" -Force -ErrorAction SilentlyContinue
        Write-Log "Désinstallation terminée (BackgroundModeEnabled laissé en place)"
        exit 0
    }

    # ----------------------------- CONTRÔLES ---------------------------
    if ($PbxUrl -notmatch "^https://") {
        throw "PbxUrl invalide : $PbxUrl"
    }
    $Edge = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe" -ErrorAction SilentlyContinue).'(default)'
    if (-not $Edge -or -not (Test-Path $Edge)) {
        $Edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
                  "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
    }
    if (-not $Edge) { throw "Microsoft Edge introuvable" }
    $Origin = $PbxUrl -replace '^(https://[^/]+).*', '$1'

    # Argument de lancement : vraie PWA si ID connu, sinon fenêtre application
    if ($AppId) { $LaunchArgs = "--app-id=$AppId" } else { $LaunchArgs = "--app=$PbxUrl" }
    Write-Log "Edge : $Edge | PBX : $Origin | Lancement : $LaunchArgs"

    # ------------------------ STRATÉGIES EDGE --------------------------
    New-Item $EdgeKey -Force | Out-Null

    # PWA installée de force, ouverte en fenêtre dédiée
    $json = '[{"url":"' + $PbxUrl + '","default_launch_container":"window","create_desktop_shortcut":true,"fallback_app_name":"' + $AppName + '"}]'
    Set-ItemProperty $EdgeKey -Name WebAppInstallForceList -Value $json -Type String

    # Edge reste actif en arrière-plan après fermeture des fenêtres
    Set-ItemProperty $EdgeKey -Name BackgroundModeEnabled -Value 1 -Type DWord

    # Notifications, micro, caméra autorisés pour le PBX
    foreach ($p in $Lists) {
        $k = "$EdgeKey\$p"
        New-Item $k -Force | Out-Null
        Set-ItemProperty $k -Name "1" -Value $Origin -Type String
    }
    Write-Log "Stratégies Edge appliquées"

    # ----------------------- LANCEMENT AU DÉMARRAGE --------------------
    if (Test-Path $LnkPath) {
        Remove-Item $LnkPath -Force -ErrorAction SilentlyContinue
        Write-Log "Ancien raccourci Démarrage supprimé (doublon avec le watchdog)"
    }

    $wsh = New-Object -ComObject WScript.Shell
    Get-ChildItem "$env:SystemDrive\Users\*\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup" -Filter "*.lnk" -ErrorAction SilentlyContinue |
        ForEach-Object {
            try {
                $a = $wsh.CreateShortcut($_.FullName).Arguments
                if ($a -match '--app-id=' -and $a -match '3cx') {
                    Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
                    Write-Log "Raccourci Démarrage PWA supprimé : $($_.FullName)"
                }
            } catch { }
        }

    # ----------------------------- WATCHDOG ----------------------------
    $wd = @'
$LaunchArgs = '__ARGS__'
$Edge       = '__EDGE__'
$Title      = '__TITLE__'
$Notify     = __NOTIFY__
if (Test-Path '__DIR__\disable') { exit 0 }

# Anti-doublon : pas de relance si un lancement a eu lieu il y a moins de 90 s
$Stamp = Join-Path $env:LOCALAPPDATA '3CX-PWA-last.txt'
if (Test-Path $Stamp) {
    if (((Get-Date) - (Get-Item $Stamp).LastWriteTime).TotalSeconds -lt 90) { exit 0 }
}

Add-Type @"
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public class WinList {
  delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] static extern bool ShowWindowAsync(IntPtr h, int cmd);
  
  public static List<string> Titles() {
    var r = new List<string>();
    EnumWindows((h, l) => {
      if (IsWindowVisible(h)) {
        var sb = new StringBuilder(512); GetWindowText(h, sb, 512);
        if (sb.Length > 0) {
          uint pid; GetWindowThreadProcessId(h, out pid);
          try {
            var p = System.Diagnostics.Process.GetProcessById((int)pid);
            if (p.ProcessName.Equals("msedge", StringComparison.OrdinalIgnoreCase)) r.Add(sb.ToString());
          } catch { }
        }
      }
      return true; }, IntPtr.Zero);
    return r;
  }
  
  public static int MinimizeMatching(string match) {
    int n = 0;
    EnumWindows((h, l) => {
      if (IsWindowVisible(h)) {
        var sb = new StringBuilder(512); GetWindowText(h, sb, 512);
        if (sb.Length > 0 && sb.ToString().IndexOf(match, StringComparison.OrdinalIgnoreCase) >= 0) {
          uint pid; GetWindowThreadProcessId(h, out pid);
          try {
            var p = System.Diagnostics.Process.GetProcessById((int)pid);
            if (p.ProcessName.Equals("msedge", StringComparison.OrdinalIgnoreCase)) { ShowWindowAsync(h, 7); n++; }
          } catch { }
        }
      }
      return true; }, IntPtr.Zero);
    return n;
  }
}
"@

$titles = [WinList]::Titles()
$found  = $titles | Where-Object { $_ -like "*$Title*" }

$WLog = Join-Path $env:LOCALAPPDATA '3CX-PWA-watchdog.log'
try {
    if ((Test-Path $WLog) -and ((Get-Item $WLog).Length -gt 100KB)) { Remove-Item $WLog -Force }
    $decision = if ($found) { 'OK (fenetre trouvee)' } else { 'ABSENTE -> relance' }
    $cmds = ''
    try {
        $cmds = (Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" |
                   Where-Object { $_.CommandLine -and $_.CommandLine -notmatch '--type=' -and $_.CommandLine -match 'on3cx|--app|--no-startup-window' } |
                   ForEach-Object { $_.CommandLine -replace '^.*msedge(_proxy)?\.exe"?\s*', '' }) -join ' ## '
    } catch { }
    Add-Content -Path $WLog -Value ("{0} | {1} | fenetres Edge : {2} | lancements : {3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $decision, ($titles -join ' || '), $cmds)
} catch { }

if ($found) { exit 0 }

Start-Process -FilePath $Edge -ArgumentList $LaunchArgs -WindowStyle Minimized
try { Set-Content -Path $Stamp -Value (Get-Date -Format o) } catch { }

for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Seconds 1
    if ([WinList]::MinimizeMatching($Title) -gt 0) { break }
}

if ($Notify) { try {
    $e = [char]0xE9
    $msg = "3CX $($e)tait ferm$($e) : relanc$($e) automatiquement."
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime] | Out-Null
    $tpl = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent('ToastText02')
    $txt = $tpl.GetElementsByTagName('text')
    $txt.Item(0).AppendChild($tpl.CreateTextNode('3CX')) | Out-Null
    $txt.Item(1).AppendChild($tpl.CreateTextNode($msg)) | Out-Null
    $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell1.0\powershell.exe'
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show([Windows.UI.Notifications.ToastNotification]::new($tpl))
} catch { } }
'@
    $wd = $wd.Replace('__ARGS__', $LaunchArgs).Replace('__EDGE__', $Edge).Replace('__TITLE__', $TitleMatch).Replace('__DIR__', $Dir).Replace('__NOTIFY__', $(if ($NotifRelance) { '$true' } else { '$false' }))
    Set-Content -Path "$Dir\watchdog.ps1" -Value $wd -Encoding UTF8

    # Lanceur VBS pour masquer la fenêtre PowerShell
    $vbs = 'CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""' + $Dir + '\watchdog.ps1""", 0, False'
    Set-Content -Path "$Dir\launcher.vbs" -Value $vbs -Encoding ASCII

    # Tâche planifiée exécutée dans la session de chaque utilisateur
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

    $action   = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "//B //Nologo `"$Dir\launcher.vbs`""

    $logon        = New-ScheduledTaskTrigger -AtLogOn
    $logon.Delay  = "PT30S"

    if ($RepeatSec -lt 60) { $RepeatSec = 60 }
    $repeat   = New-ScheduledTaskTrigger -Once -At (Get-Date) `
                -RepetitionInterval (New-TimeSpan -Seconds $RepeatSec) `
                -RepetitionDuration (New-TimeSpan -Days 3650)

    $prin     = New-ScheduledTaskPrincipal -GroupId "S-1-5-32-545" -RunLevel Limited
    $set      = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
                -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($logon, $repeat) -Principal $prin -Settings $set -Force | Out-Null
    Write-Log "Tâche planifiée $TaskName créée"

    Write-Log "Déploiement terminé."
    exit 0
}
catch {
    Write-Log "ERREUR : $($_.Exception.Message)"
    exit 1
}
