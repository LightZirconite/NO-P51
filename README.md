# NO-P51

NO-P51 est un utilitaire Windows portable qui permet de masquer rapidement une application choisie et de la restaurer à l'aide de raccourcis clavier globaux, sans privilèges administrateur. Une action optionnelle peut s'exécuter lorsqu'on masque l'application (ouvrir un site web ou lancer un autre programme) afin de détourner l'attention.

## Fonctionnalités principales

- Choix libre du processus à masquer, par nom d'exécutable (`notepad.exe`) ou directement via son PID.
- Infobulles et rappels intégrés pour privilégier les noms d'exécutables stables (les PID changent à chaque lancement).
- Filtrage instantané de la liste des processus et indication du niveau de privilège (standard/administrateur).
- Sélection de la stratégie de masquage : simple dissimulation ou tentative de terminaison immédiate, selon les autorisations disponibles.
- Deux touches de raccourci indépendantes : l'une pour masquer, l'autre pour restaurer.
- Bouton de repli rapide (flèche) pour masquer immédiatement le panneau de contrôle dans la zone de notification.
- Icône dédiée dans la zone de notification, avec menu contextuel (ouvrir l'interface / quitter complètement).
- Chargement automatique du logo `logo.png` fourni avec l'application pour l'icône du panneau et du tray.
- Action "Kill target now" pour forcer l'arrêt de l'application choisie, sans passer par les raccourcis.
- Bouton "Exit NO-P51" pour fermer complètement l'outil (service, UI, lanceur) en un clic.
- Redémarrage automatique du service en arrière-plan en cas de plantage, avec notifications discrètes.
- Action secondaire optionnelle au moment du masquage : ouverture d'une URL ou lancement d'un autre logiciel, avec fermeture automatique lors de la restauration.
- Déclenchement du fallback avant le masquage pour limiter le temps “écran vide”, avec option plein écran (F11) automatique.
- Fonctionne avec les droits standards (pas besoin d'élévation UAC).

## Contenu du projet

- `scripts/no-p51.ps1` : moteur PowerShell principal (service en arrière-plan).
- `scripts/no-p51-gui.ps1` : interface graphique pour configurer et piloter NO-P51.
- `NO-P51.bat` : unique lanceur (ouvre l'interface graphique et gère le service).
- `config.json` : configuration utilisateur (processus, raccourcis, action fallback).
- `songs/` : fichiers audio pour le feedback sonore (click.mp3, notif.mp3).
- `tests/no-p51.Tests.ps1` : tests unitaires Pester pour les fonctions critiques.
- `CHANGELOG.md` : historique détaillé des versions et améliorations.

## Prérequis

- Windows 10 ou plus récent.
- PowerShell 5.1 (inclus par défaut) ou PowerShell 7.
- [Pester](https://github.com/pester/Pester) (pour exécuter les tests, optionnel pour l'utilisation basique).
- [Git for Windows](https://git-scm.com/download/win) pour permettre la mise à jour automatique à chaque lancement.

## Configuration

Modifiez `config.json` pour adapter le comportement :

```json
{
  "targetProcessName": "notepad.exe",
  "hideStrategy": "hide",
  "hideHotkey": "=",
  "restoreHotkey": "Ctrl+Alt+R",
  "fallback": null
}
```

- `targetProcessName` : nom du processus (avec ou sans `.exe`) ou PID numérique. Les identifiants de processus (PID) changent à chaque lancement : préférez le nom d'exécutable pour une configuration durable.
- `hideStrategy` : `hide` pour simplement masquer la fenêtre, `terminate` pour tenter de tuer le processus. La réussite dépend des autorisations courantes de Windows et ne permet pas de restauration automatique.
- `hideHotkey` / `restoreHotkey` : combinaisons sous la forme `=`, `Ctrl+Alt+R`, `Shift+F12`, `Win+2`, etc. Par défaut, la touche de masquage est `=`.
- `fallback` (facultatif) :
  - `mode` : `app` pour lancer un exécutable, `url` pour ouvrir une adresse web.
  - `value` : chemin de l'application ou URL à ouvrir.
  - `autoClose` : `true` pour fermer automatiquement l'application fallback au moment de la restauration.
  - `fullscreen` : `true` pour envoyer `F11` à la fenêtre fallback dès son apparition (pratique pour un navigateur en plein écran).

Si vous ne voulez pas d'action secondaire, supprimez l'objet `fallback` ou mettez-le à `null`.

## Utilisation

### Interface graphique

> À chaque démarrage, NO-P51 vérifie la présence de Git et exécute automatiquement `git pull` dans le dossier du projet. Si une mise à jour est récupérée, l'application redémarre immédiatement pour charger la nouvelle version. Les personnalisations locales de `config.json` sont conservées automatiquement.

1. Double-cliquez sur `NO-P51.bat` pour ouvrir le panneau de contrôle.
2. Double-cliquez sur un processus dans la liste (ou tapez dans **Filter** pour filtrer en direct) afin de remplir le champ cible. Les noms sont affichés avec leur extension `.exe`; cochez *Use PID when selecting* uniquement si vous devez cibler un PID ponctuel. Le panneau rappelle que les PID changent à chaque lancement et qu'il est donc recommandé d'utiliser le nom (`notepad.exe`, etc.). Une étiquette indique également si l'application tourne avec des droits administrateur.
3. Utilisez le bouton flèche (en haut à droite) pour envoyer immédiatement le panneau dans la zone de notification si vous devez disparaître en urgence.
4. Choisissez la stratégie dans la liste **Hide strategy** : *Hide window* (par défaut) conserve le processus en arrière-plan, tandis que *Terminate process* tente de l'arrêter immédiatement. Selon vos autorisations Windows, l'arrêt peut échouer ; aucune relance automatique n'est effectuée par la touche de restauration.
5. Choisissez l'action fallback éventuelle (aucune, lancement d'une application, ouverture d'une URL) : vous pouvez activer **Close fallback app on restore** et/ou **Toggle fullscreen (F11) after launch** pour contrôler le comportement automatique. La bascule plein écran déclenche F11 dès que la nouvelle fenêtre apparaît. Les champs jaunes sont synchronisés automatiquement avec `config.json` dès qu'ils sont valides.
6. Cliquez sur **Start service** pour activer le service. La fenêtre peut être fermée : l'application reste active dans la zone de notification (icône flèche), qui reste visible à tout moment. Le menu contextuel du tray propose **Open interface** et **Exit NO-P51**. Les boutons **Kill target now** et **Exit NO-P51** restent disponibles pour les actions rapides.

### Ligne de commande (optionnel)

L'interface graphique reste la porte d'entrée principale. Pour un usage automatisé sans UI, exécutez directement `scripts\no-p51.ps1` avec vos propres paramètres PowerShell.

## Exécution des tests

Depuis une console PowerShell positionnée à la racine du projet :

```powershell
Invoke-Pester -Path "tests"
```

Les tests valident la lecture des combinaisons de touches et la cohérence de la configuration.

## Dépannage

- Assurez-vous que le processus ciblé possède bien une fenêtre principale visible.
- Certains logiciels protégés peuvent ignorer l'appel `ShowWindow`. Essayez un autre mode ou un autre logiciel pour confirmer.
- Si un raccourci ne se déclenche pas, vérifiez qu'il n'est pas déjà réservé par Windows ou par un autre outil.
- Si PowerShell refuse d'exécuter les scripts (`PSSecurityException` / `ExecutionPolicy`), lancez l'application via `NO-P51.bat` ou ouvrez une console PowerShell et exécutez :
  ```powershell
  Set-ExecutionPolicy -Scope Process Bypass
  scripts\no-p51-gui.ps1
  ```
  Vous pouvez également démarrer directement avec :
  ```powershell
  powershell -NoLogo -ExecutionPolicy Bypass -File "scripts\no-p51-gui.ps1"
  ```

## Prochaines évolutions possibles

- Prise en charge de plusieurs profils simultanés.
- Historique des actions pour audit rapide.
- Détection automatique du processus actif au moment du masquage.





