# Contexte du projet

## Projet
**App CopyHistory** — Clone de CopyLess 2 (https://copyless.net/) pour usage personnel sur plusieurs Mac. Gestionnaire d'historique presse-papier macOS : capture automatique de tout ce qui est copié, accès rapide, favoris, recherche, raccourcis globaux.

## Stack technique
- **Langage :** Swift 5 (SWIFT_VERSION=5.0, compatible Xcode 16)
- **UI :** SwiftUI + AppKit (NSPanel pour la fenêtre flottante)
- **Persistance :** SwiftData (macOS 14+)
- **Hotkeys globaux :** librairie `KeyboardShortcuts` (Sindre Sorhus, MIT, via SPM)
- **Génération projet :** `xcodegen` (project.yml à la racine)
- **Distribution :** Direct download (.dmg) — hors sandbox App Store
- **Target macOS :** 14+ (Sonoma)

## Dernière mise à jour
2026-04-29 11:00

## Ce qu'on a fait
- 2026-04-29 : Initialisation du dépôt Git et création du CONTEXT.md.
- 2026-04-29 : Recherche complète sur CopyLess 2 (fonctionnalités, UX) et sur l'implémentation technique macOS.
- 2026-04-29 : **MVP complet codé et compilé (BUILD SUCCEEDED).** Structure projet complète avec xcodegen, tous les fichiers Swift écrits, build Xcode fonctionnel.

## Où on en est
**MVP compilé et prêt à tester.** L'app peut être ouverte dans Xcode et lancée. Fonctionnalités implémentées :
- Surveillance presse-papier en arrière-plan (polling 0.5s)
- Capture texte, images, fichiers, URLs
- Historique persistant SwiftData (max 1000 entrées, dédoublonnage)
- App menu bar (icône presse-papier, aucun Dock icon)
- Fenêtre flottante NSPanel au-dessus de tout
- Liste des clips avec icône app source, aperçu, temps relatif, type
- Recherche live
- Single-clic = Direct Paste (copie + ferme panel + simule ⌘V dans l'app précédente)
- Raccourci global ⇧⌘V (configurable via KeyboardShortcuts)
- Filtre données sensibles (mots de passe, ConcealedType, 1Password, LastPass...)
- Favoris (épingler via menu contextuel, jamais supprimés)
- Context menu : coller / copier seulement / épingler / supprimer
- Trim automatique à 1000 clips (clips épinglés préservés)

## Architecture et décisions

### Structure des fichiers
```
CopyHistory/
├── App/
│   ├── CopyHistoryApp.swift      — @main App, @NSApplicationDelegateAdaptor
│   └── AppDelegate.swift         — NSStatusItem, FloatingPanel, ClipboardMonitor, Direct Paste
├── Models/
│   └── ClipboardItem.swift       — @Model SwiftData (type, texte, imageData, appBundleID, isPinned...)
├── Services/
│   └── ClipboardMonitor.swift    — Polling NSPasteboard.changeCount toutes les 0.5s
├── Views/
│   ├── FloatingPanel.swift       — NSPanel subclass (.nonactivatingPanel, .floating level)
│   ├── ContentView.swift         — Liste + barre de recherche + footer
│   └── ClipRowView.swift         — Row : icône app, aperçu, temps relatif, badge type
└── Resources/
    └── Assets.xcassets/          — AppIcon (placeholder vide)
project.yml                       — xcodegen config
```

### Décision 1 — Swift natif, pas Electron/Tauri
Electron = 150-300 MB RAM au repos + bundle 120-180 MB → inacceptable pour une app utilitaire menu bar. Swift = ~5-8 MB de bundle, ~15-30 MB RAM.

### Décision 2 — Hors sandbox App Store
Sandbox empêche `CGEventTap` (hotkey global) et la simulation de ⌘V (Direct Paste). Distribution en direct download.

### Décision 3 — Direct Paste via simulation CGEvent
Quand l'utilisateur clique sur un clip : copier dans NSPasteboard → fermer le panel → activer l'app précédente → simuler ⌘V via CGEvent. Nécessite la permission Accessibility (demandée au premier lancement).

### Décision 4 — NSPanel .nonactivatingPanel
Le panel ne vole pas le focus de l'app active. On track `previousApp = NSWorkspace.shared.frontmostApplication` AVANT d'ouvrir le panel, puis on rappelle `previousApp?.activate()` au moment du paste.

### Décision 5 — xcodegen pour générer le .xcodeproj
`project.yml` à la racine permet de régénérer le projet Xcode à tout moment avec `xcodegen generate`. Ne pas committer le `.xcodeproj` dans git (ou le committer pour faciliter l'ouverture dans Xcode — à décider).

---

## Fonctionnalités à implémenter (par priorité)

### MVP — Core ✅ (tout compilé)
- [x] Surveillance presse-papier en arrière-plan (polling NSPasteboard.changeCount, 0.5s)
- [x] Capture texte, images, fichiers, URLs
- [x] Historique persistant (SwiftData) — 1000 entrées max
- [x] App menu bar (NSStatusItem)
- [x] Fenêtre flottante (NSPanel niveau .floating, au-dessus de tout)
- [x] Liste des clips avec : app source (icône), aperçu contenu, temps écoulé, type
- [x] Recherche live dans l'historique
- [x] Single-clic = Direct Paste (colle dans la dernière app active via simulation ⌘V)
- [x] Raccourci global ⇧⌘V pour ouvrir/fermer la fenêtre
- [x] Filtre données sensibles (mots de passe, concealed type)
- [x] Persistance au redémarrage (SwiftData sur disque)
- [x] Favoris (épingler/désépingler via context menu)
- [x] Dédoublonnage (ne pas enregistrer si identique au dernier clip)

### Prochaine priorité — À tester et améliorer
- [ ] Tester le Direct Paste dans des apps réelles (Notion, Slack, Terminal...)
- [ ] Tester la capture d'images (screenshots, copie depuis navigateur)
- [ ] Vérifier le comportement sur macOS 15.4 (pasteboard privacy alert)
- [ ] Ajouter un indicateur visuel quand Accessibility n'est pas accordée
- [ ] Raccourci global configurable (UI dans les préférences)

### V2 — Polish & UX
- [ ] Labels/renommage personnalisés sur les clips
- [ ] Plain Text mode (strip formatting) — raccourci Ctrl+Option+T
- [ ] Raccourcis directs pour 10 clips récents sans ouvrir la fenêtre
- [ ] Quick Look (voir le clip complet en plein)
- [ ] Drag & drop depuis CopyHistory vers n'importe quelle app
- [ ] Thèmes / personnalisation apparence
- [ ] Préférences : liste noire d'apps, intervalle polling, limite historique

### V3 — Avancé
- [ ] Serial Paste : buffer séquentiel (⌥⌘Y / ⌥⌘X)
- [ ] iCloud sync des favoris
- [ ] Export de l'historique

---

## Permissions requises (à accorder au premier lancement)
1. **Accessibility** : Réglages Système > Confidentialité > Accessibilité → ajouter CopyHistory
   → Nécessaire pour simuler ⌘V (Direct Paste)
2. L'app demande automatiquement cette permission au premier lancement via `AXIsProcessTrustedWithOptions`

---

## Problèmes connus
- Le `.xcodeproj` est généré par xcodegen mais pas encore dans le .gitignore — à décider si on le committe.
- Sur macOS 15.4+ : Apple a ajouté une alerte quand une app lit le presse-papier sans geste utilisateur. Impact à surveiller.

## Notes pour la prochaine session
- **Ouvrir** `CopyHistory.xcodeproj` dans Xcode, lancer sur le Mac, tester le comportement réel
- **Première chose à tester** : le Direct Paste fonctionne-t-il ? (Accessibility permission granted ?)
- **Si le panel ne s'ouvre pas** : vérifier que NSApp.setActivationPolicy(.accessory) ne bloque pas
- **Fichiers clés** :
  - `CopyHistory/App/AppDelegate.swift` — logique centrale (statusItem, panel, monitor, paste)
  - `CopyHistory/Services/ClipboardMonitor.swift` — capture presse-papier
  - `CopyHistory/Views/ContentView.swift` — UI principale
  - `project.yml` — config xcodegen (lancer `xcodegen generate` après modifs)
- **Régénérer le projet** : `cd "App CopyHistory" && xcodegen generate`
