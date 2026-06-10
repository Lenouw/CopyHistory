# Lessons — CopyHistory

## 2026-04-29 | App ad-hoc + Hardened Runtime + framework tiers → blocage au lancement

**Symptôme** : `Library not loaded: @rpath/Sparkle.framework — different Team IDs`

**Cause** : Library Validation (composant du Hardened Runtime) refuse de charger un framework tiers (signé ad-hoc ou par un autre Team ID) quand l'app principale n'est pas signée Developer ID. Le check est strict même quand TOUS les binaires sont ad-hoc, parce que Library Validation exige soit (1) le même Team ID partout, soit (2) une exception explicite.

**Règle** : pour toute app macOS distribuée **sans certificat Apple Developer ID** (signature ad-hoc, `Sign to Run Locally`) qui embarque des frameworks externes (Sparkle, Sentry, etc.), AJOUTER dans le fichier `.entitlements` :

```xml
<key>com.apple.security.cs.disable-library-validation</key>
<true/>
```

Sans ça, l'app **se lance correctement sur la machine de build** (cache de signatures local) mais **plante sur n'importe quelle autre machine** avec ce message dyld.

**Test obligatoire** avant tout release : copier le `.app` zippé sur une autre machine (ou supprimer la quarantaine + Gatekeeper bypass) et vérifier qu'elle se lance vraiment. `xcodebuild` qui dit "BUILD SUCCEEDED" et un test local NE SUFFISENT PAS.

## 2026-06-11 | CGEventTap meurt silencieusement → features qui "marchent plus des fois"

**Symptôme** : déclencheur bord-bas ou file de collage cesse de fonctionner aléatoirement, sans crash ni log. Redémarrage de l'app = ça remarche.

**Cause** : macOS désactive un CGEventTap s'il est trop lent à répondre (`tapDisabledByTimeout`) ou pendant une saisie sécurisée (`tapDisabledByUserInput`). L'événement de désactivation est envoyé AU CALLBACK du tap lui-même — si le callback ne le gère pas, le tap reste mort pour toujours.

**Règle** : TOUT callback CGEventTap doit gérer ces deux types et ré-armer :

```swift
if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
    CGEvent.tapEnable(tap: tap, enable: true)
    return Unmanaged.passUnretained(event)
}
```

Pattern appliqué dans HotEdgeTrigger.swift et PasteQueueManager.swift (v1.2.0).

## 2026-06-11 | SwiftData + chiffrement : cacher le déchiffrement, sinon CPU explose

Toute propriété calculée qui déchiffre (`decryptedText`) est appelée à CHAQUE accès : recherche (1000 items × chaque frappe), rendu de liste, dédoublonnage. Cache mémoire obligatoire via `@Transient` sur le @Model. Idem pour les ressources coûteuses en vue (icônes NSWorkspace, miniatures d'images) → `NSCache` statique.

## 2026-06-11 | SwiftData @Model : JAMAIS muter une propriété dans un getter pendant le render

**Symptôme** : latence énorme au clic sur une ligne. Régression v1.2.0 → fix v1.2.1.

**Cause** : cache de déchiffrement stocké en `@Transient` SUR le @Model, écrit dans le getter `decryptedText`. SwiftData (macro `@Observable`) track les mutations de TOUTE propriété stockée, y compris `@Transient`. Écrire le cache pendant l'évaluation du `body` SwiftUI → invalide la vue → re-render → getter rappelé → ré-écrit le cache → boucle. Chaque clic reconstruit la liste entière.

**Règle** : un getter sur un `@Model` SwiftData doit être PUR (aucune écriture de propriété du modèle). Pour cacher un résultat coûteux (déchiffrement, etc.), utiliser un cache EXTERNE (`NSCache` statique keyé par `id`), jamais une propriété du modèle. `@Transient` n'exclut PAS de l'observation — seulement de la persistance.

## Workflow release CopyHistory (référence)

1. Bump `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` dans `project.yml`
2. `xcodegen generate`
3. `rm -rf build && xcodebuild -project CopyHistory.xcodeproj -scheme CopyHistory -configuration Release -derivedDataPath build ONLY_ACTIVE_ARCH=NO build`
4. `ditto -c -k --keepParent build/Build/Products/Release/CopyHistory.app releases/CopyHistory-X.Y.Z.zip`
5. Sign : `~/Library/Developer/Xcode/DerivedData/CopyHistory-*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update releases/CopyHistory-X.Y.Z.zip`
6. Mettre à jour `appcast.xml` avec la signature et la taille (en bytes)
7. Commit + push
8. `gh release create vX.Y.Z releases/CopyHistory-X.Y.Z.zip --title ... --notes ...`
