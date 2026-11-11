# Déploiement de la PWA 3CX via Atera RMM

Script PowerShell qui déploie le **client web 3CX** sous forme de **Progressive Web App (PWA)** dans Microsoft Edge, depuis un outil RMM comme **Atera** (contexte `SYSTEM`), et qui s'assure ensuite qu'elle reste ouverte, discrètement, sur les postes.

## Pourquoi ce script

Installer la PWA 3CX poste par poste est long, et les utilisateurs la ferment ou l'oublient : les appels entrants sont alors manqués. Ce script automatise l'installation et garantit que l'application est disponible en continu, sans gêner l'utilisateur.

## Ce qu'il fait

**Stratégies Edge (registre `HKLM`)**
- Installation forcée de la PWA (`WebAppInstallForceList`), ouverte dans une fenêtre dédiée.
- Edge reste actif en arrière-plan (`BackgroundModeEnabled`) pour que les notifications continuent d'arriver même sans fenêtre ouverte.
- Notifications, micro et caméra autorisés pour l'adresse du PBX.

**Watchdog (tâche planifiée exécutée dans la session de chaque utilisateur)**
- Lance la PWA à l'ouverture de session (environ 30 secondes après la connexion), puis vérifie toutes les 60 secondes (réglable) qu'une fenêtre 3CX est ouverte.
- Si elle est fermée, il la relance en **fenêtre réduite, sans prendre le focus** (API `user32.dll` appelée depuis PowerShell). Edge peut afficher la fenêtre brièvement avant qu'elle soit réduite.
- Anti-doublon : aucune relance dans les 90 secondes qui suivent un lancement.
- Supprime les raccourcis de démarrage de PWA 3CX créés par Edge dans les profils, qui feraient double emploi avec le watchdog.
- Notification Windows à chaque relance disponible en option (`$NotifRelance`), désactivée par défaut.

**Exploitation**
- Journal de déploiement : `C:\ProgramData\3CX-PWA\deploy.log`.
- Journal de diagnostic du watchdog, par utilisateur : `%LOCALAPPDATA%\3CX-PWA-watchdog.log` (titres des fenêtres Edge vues, décision prise, lignes de commande des lancements).
- Désactivation temporaire sur un poste : créer un fichier vide `C:\ProgramData\3CX-PWA\disable`.
- Désinstallation : mode `Uninstall` intégré au script, et script dédié `Uninstall-3CX-PWA.ps1` pour un retrait complet (voir plus bas).

## Prérequis

- Windows 10 ou 11 avec Microsoft Edge (Chromium), Windows PowerShell 5.1.
- Un outil RMM capable d'exécuter un script PowerShell en `SYSTEM` (testé avec Atera sous Windows 11).
- L'adresse du client web 3CX de votre PBX.

## Paramètres

À adapter en haut de `Deploy-3CX-PWA.ps1` :

| Paramètre | Description | Valeur par défaut |
|---|---|---|
| `$PbxUrl` | URL complète du client web 3CX | `https://your-pbx.on3cx.fr/webclient` (à remplacer, le script refuse le placeholder) |
| `$AppName` | Nom affiché de l'application | `3CX` |
| `$TitleMatch` | Texte présent dans le titre de la fenêtre PWA (le watchdog s'en sert pour savoir si elle est ouverte) | `3CX` |
| `$NotifRelance` | `$true` pour afficher une notification à chaque relance | `$false` |
| `$RepeatSec` | Fréquence de vérification du watchdog, en secondes (minimum 60 : limite du Planificateur de tâches) | `60` |
| `$AppId` | ID de la PWA installée (voir ci-dessous). Vide = fenêtre `--app=URL` | vide |
| `$Mode` | `Install` ou `Uninstall` | `Install` |

## Utilisation

1. Importer `Deploy-3CX-PWA.ps1` dans la bibliothèque de scripts du RMM.
2. Renseigner `$PbxUrl` avec l'adresse du PBX, puis l'exécuter une première fois sur un **poste pilote**, en `SYSTEM`.
3. Fermer complètement Edge, le rouvrir, puis vérifier dans `edge://policy` (bouton « Recharger les stratégies ») que `WebAppInstallForceList` est bien appliquée.
4. Ouvrir `edge://web-app-internals`, repérer l'application 3CX et copier son **ID** (32 lettres).
5. Renseigner `$AppId` avec cet ID et relancer le script : le watchdog ouvre alors la vraie PWA installée, et non une simple fenêtre `--app=URL`. Sans cette étape, une PWA installée par la stratégie et la fenêtre du watchdog peuvent coexister.
6. Contrôler le résultat : fermer la fenêtre 3CX, elle doit revenir réduite en une minute environ. Puis déployer sur le reste du parc.

L'ID de la PWA dépend du site : il est identique sur tous les postes d'un même PBX, mais différent d'un PBX à l'autre. Il faut donc une valeur de `$PbxUrl` et de `$AppId` par client.

Le script peut être relancé sans risque sur un poste déjà configuré : les valeurs de registre sont réécrites, la tâche planifiée est recréée et les fichiers du watchdog sont remplacés.

## Désinstallation

Deux possibilités, selon le niveau de nettoyage voulu.

### Option 1 : mode `Uninstall` du script de déploiement

Passer `$Mode` à `"Uninstall"` dans `Deploy-3CX-PWA.ps1` et l'exécuter. Il supprime la tâche planifiée, les stratégies d'installation et d'autorisation, et les fichiers du watchdog. `BackgroundModeEnabled`, le dossier de logs et la PWA déjà installée dans les profils sont laissés en place.

### Option 2 : script de désinstallation complet `Uninstall-3CX-PWA.ps1`

À utiliser pour retirer **tout** le déploiement, y compris la PWA dans Edge. À exécuter via le RMM en contexte `SYSTEM`.

**Ce qu'il supprime**

| Élément | Détail |
|---|---|
| Tâche planifiée | `3CX-PWA-Watchdog` |
| Stratégies Edge | `WebAppInstallForceList`, `NotificationsAllowedForUrls`, `AudioCaptureAllowedUrls`, `VideoCaptureAllowedUrls` : seules les entrées 3CX sont retirées, les autres applications et URLs sont conservées |
| `BackgroundModeEnabled` | Supprimé, sauf si `$RetirerModeArrierePlan = $false` |
| PWA dans Edge | Désinstallée dans la session de chaque utilisateur connecté (voir limites ci-dessous) |
| Raccourcis | Raccourcis de PWA 3CX du dossier Démarrage, du menu Démarrer et du Bureau, dans tous les profils |
| Fichiers | `C:\ProgramData\3CX-PWA` et les fichiers `3CX-PWA-*` de chaque profil |

Il ne touche pas à l'application de bureau 3CX, ni aux autres réglages d'Edge.

**Paramètres**

| Paramètre | Description | Valeur par défaut |
|---|---|---|
| `$RetirerModeArrierePlan` | Supprime aussi `BackgroundModeEnabled` (à désactiver si ce réglage sert à autre chose sur le poste) | `$true` |
| `$DesinstallerPWAUtilisateurs` | Lance la désinstallation de la PWA dans la session de chaque utilisateur connecté | `$true` |
| `$FermerEdge` | Ferme Edge pour tous les utilisateurs à la fin, ce qui force la prise en compte immédiate des changements. Les fenêtres Edge ouvertes sont perdues | `$false` |
| `$ConserverLogs` | Conserve `C:\ProgramData\3CX-PWA\deploy.log` | `$false` |
| `$MotCle` | Motif servant à reconnaître les éléments 3CX (adresses, raccourcis, noms d'application) | `3cx` |
| `$DelaiMaxUtilisateurSec` | Attente maximale par utilisateur pour la désinstallation de sa PWA, en secondes | `180` |

**Utilisation**

1. Importer `Uninstall-3CX-PWA.ps1` dans la bibliothèque de scripts du RMM.
2. L'exécuter d'abord sur un **poste pilote**, en `SYSTEM`, avec une session utilisateur ouverte.
3. Consulter le résultat dans la sortie du RMM ou dans `C:\ProgramData\3CX-PWA-uninstall.log`. Le code de sortie vaut `1` si une étape a échoué.
4. Vérifier dans Edge que `edge://apps` ne liste plus 3CX, puis déployer sur le reste du parc.

Le script continue même si une étape échoue, journalise chaque étape et peut être relancé sans risque sur un poste déjà nettoyé.

**Comment la PWA est retirée d'Edge**

Une PWA appartient au profil de l'utilisateur : un script en `SYSTEM` ne peut pas la désinstaller directement. Pour chaque utilisateur connecté, le script crée donc une tâche temporaire qui s'exécute dans sa session, lance la désinstallation à partir de l'entrée « Applications installées » de la PWA, attend la fin, puis supprime la tâche.

**Limites**

- Utilisateurs **non connectés** au moment de l'exécution : la PWA installée par la stratégie est retirée par Edge lui-même à leur prochaine session, puisque la stratégie n'existe plus. Une PWA installée manuellement par l'utilisateur reste en place : relancer le script quand il est connecté, ou la retirer dans `edge://apps`.
- La désinstallation peut afficher une **fenêtre de confirmation** à l'utilisateur.
- Ce mécanisme repose sur l'enregistrement des PWA d'Edge dans les applications installées de Windows, à valider sur un poste pilote : si le journal indique `0 application(s) PWA 3CX traitée(s)` alors que la PWA existe, la retirer manuellement dans `edge://apps`.
- Avec `$FermerEdge = $true`, tous les processus Edge sont arrêtés : à réserver à une plage de maintenance.

## Limites connues

- Une **confirmation avant fermeture** de l'application ne peut pas être imposée par une stratégie Edge : c'est un comportement du site.
- Edge peut ralentir une fenêtre réduite. Les appels et notifications fonctionnent, mais un test d'appel entrant sur le poste pilote reste recommandé.
- Le watchdog repère la fenêtre par son titre : si le titre ne contient pas `$TitleMatch`, il relancera l'application en boucle. Le journal de diagnostic montre les titres réellement vus.
- Le script modifie des stratégies Edge en machine : Edge affiche alors « Géré par votre organisation ».

## Avertissement

Script fourni tel quel, sans garantie. Il modifie le registre et crée une tâche planifiée : le tester sur un poste pilote avant tout déploiement à grande échelle.

## Licence

[MIT](LICENSE)
