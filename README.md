# 🚀 Déploiement Automatisé 3CX PWA via Atera RMM

Script PowerShell conçu pour industrialiser et automatiser le déploiement de la Progressive Web App (PWA) **3CX** via Microsoft Edge, piloté par l'outil RMM **Atera** en contexte `SYSTEM`.

## 📌 Contexte & Objectifs

Dans le cadre d'un parc informatique en collectivité, ce script permet d'éviter les interventions manuelles poste par poste en garantissant :
* Une installation propre et silencieuse de la PWA.
* Une persistance et une disponibilité continue du client de téléphonie pour les agents.
* La gestion transparente des autorisations matérielles (micro, caméra, notifications).

---

## ⚙️ Fonctionnalités principales

1. **Stratégies de Registre Edge (`HKLM`) :**
   * Force l'installation de l'application web (`WebAppInstallForceList`)[cite: 1].
   * Active le mode arrière-plan (`BackgroundModeEnabled`) pour s'assurer que les notifications et appels restent actifs même si la fenêtre principale est fermée[cite: 1].
   * Autorise automatiquement les URLs pour les **notifications**, le **microphone** et la **caméra**[cite: 1].

2. **Watchdog Résilient & Discret (Tâche Planifiée) :**
   * Vérifie régulièrement (toutes les 60 secondes par défaut) si la fenêtre 3CX est ouverte dans la session de l'utilisateur[cite: 1].
   * Si l'application est fermée, le watchdog la relance automatiquement en arrière-plan de façon totalement transparente[cite: 1].
   * **Anti-vol de focus :** Utilise une API C# intégrée (`user32.dll`) pour forcer l'affichage de la fenêtre en mode réduit (`SW_SHOWMINNOACTIVE`) sans perturber l'utilisateur dans sa saisie en cours[cite: 1].

3. **Sécurité & Maintenance :**
   * **Mode Désinstallation :** Permet de nettoyer proprement toutes les clés de registre, tâches planifiées et fichiers associés en modifiant simplement un paramètre dans le script[cite: 1].
   * **Contournement local :** Possibilité de désactiver temporairement le watchdog sur un poste en créant simplement un fichier vide `disable` dans le répertoire d'installation (`C:\ProgramData\3CX-PWA\disable`)[cite: 1].
   * **Journalisation (Logs) :** Suivi détaillé des actions et des erreurs dans `C:\ProgramData\3CX-PWA\deploy.log`[cite: 1].

---

## 🛠️ Paramètres du Script

En haut du fichier `Deploy-3CX-PWA.ps1`, tu peux configurer les variables selon ton client / ton instance :

| Paramètre | Description | Valeur par défaut / Exemple |
| :--- | :--- | :--- |
| `$PbxUrl` | URL complète du client web 3CX | `"https://your-pbx.on3cx.fr/webclient"`[cite: 1] |
| `$AppName` | Nom affiché de l'application | `"3CX"`[cite: 1] |
| `$RepeatSec` | Fréquence de vérification du watchdog (en secondes) | `60`[cite: 1] |
| `$AppId` | ID unique de la PWA Edge (optionnel) | `"votre_app_id_edge_ici"`[cite: 1] |
| `$Mode` | Mode d'exécution (`Install` ou `Uninstall`) | `"Install"`[cite: 1] |

---

## 📦 Utilisation via Atera RMM

1. Télécharge ou importe le script `Deploy-3CX-PWA.ps1` dans la bibliothèque de scripts d'**Atera**.
2. Adapte l'URL de ton PBX (`$PbxUrl`) dans les paramètres.
3. Exécute le script sur les postes cibles en contexte **SYSTEM**.
