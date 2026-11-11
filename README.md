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
- Mode désinstallation intégré.

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

Passer `$Mode` à `"Uninstall"` et exécuter le script. Il supprime la tâche planifiée, les stratégies d'installation et d'autorisation, et les fichiers du watchdog. `BackgroundModeEnabled` et le dossier de logs sont laissés en place.

## Limites connues

- Une **confirmation avant fermeture** de l'application ne peut pas être imposée par une stratégie Edge : c'est un comportement du site.
- Edge peut ralentir une fenêtre réduite. Les appels et notifications fonctionnent, mais un test d'appel entrant sur le poste pilote reste recommandé.
- Le watchdog repère la fenêtre par son titre : si le titre ne contient pas `$TitleMatch`, il relancera l'application en boucle. Le journal de diagnostic montre les titres réellement vus.
- Le script modifie des stratégies Edge en machine : Edge affiche alors « Géré par votre organisation ».

## Avertissement

Script fourni tel quel, sans garantie. Il modifie le registre et crée une tâche planifiée : le tester sur un poste pilote avant tout déploiement à grande échelle.

## Licence

[MIT](LICENSE)
