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

## Workflow release CopyHistory (référence)

1. Bump `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` dans `project.yml`
2. `xcodegen generate`
3. `rm -rf build && xcodebuild -project CopyHistory.xcodeproj -scheme CopyHistory -configuration Release -derivedDataPath build ONLY_ACTIVE_ARCH=NO build`
4. `ditto -c -k --keepParent build/Build/Products/Release/CopyHistory.app releases/CopyHistory-X.Y.Z.zip`
5. Sign : `~/Library/Developer/Xcode/DerivedData/CopyHistory-*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update releases/CopyHistory-X.Y.Z.zip`
6. Mettre à jour `appcast.xml` avec la signature et la taille (en bytes)
7. Commit + push
8. `gh release create vX.Y.Z releases/CopyHistory-X.Y.Z.zip --title ... --notes ...`
