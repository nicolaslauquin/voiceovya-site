# Mise en index de voiceovya.com

## Publication initiale

1. Publier les changements SEO avec `./deploy-voiceovya.sh --no-dmg` depuis ce dossier.
2. Vérifier publiquement :
   - `https://voiceovya.com/robots.txt` autorise l'exploration et déclare le sitemap ;
   - `https://voiceovya.com/sitemap.xml` répond en HTTP 200 ;
   - la réponse de `https://voiceovya.com/` ne contient aucun `X-Robots-Tag: noindex` ;
   - le HTML de la page d'accueil ne contient aucun `meta name="robots"` avec `noindex`.

Le script de déploiement envoie et compare `robots.txt` et `sitemap.xml` avec leurs copies publiques. Il échoue aussi si le HTML local ou les en-têtes HTTP publiés de la page d'accueil contiennent encore `noindex`.

## Google Search Console

1. Dans le sélecteur de propriétés, choisir **Ajouter une propriété** puis **Domaine**.
2. Saisir uniquement `voiceovya.com`, sans `https://` ni chemin.
3. Copier la valeur TXT fournie par Google et l'ajouter à la zone DNS du domaine. Chez OVH, utiliser la racine du domaine (`@`) comme sous-domaine/nom si l'interface le demande.
4. Revenir dans Search Console et lancer la validation. Conserver l'enregistrement TXT après validation.
5. Ouvrir **Inspection de l'URL**, saisir `https://voiceovya.com/`, lancer **Tester l'URL publiée**, puis **Demander une indexation**.
6. Ouvrir **Sitemaps**, saisir `sitemap.xml`, puis envoyer. L'URL complète attendue est `https://voiceovya.com/sitemap.xml`.

La demande ne garantit pas l'indexation immédiate. Contrôler ensuite l'état de la page dans **Inspection de l'URL** et la lecture du sitemap dans **Sitemaps**.

## Jour de la sortie Mac App Store

1. Dans `index.html`, remplacer `href="build/dist/index.html"` du lien `#download-link` par l'URL publique Mac App Store.
2. Remplacer les libellés français et anglais `hero.download` par **Télécharger sur le Mac App Store** et **Download on the Mac App Store**.
3. Tester le CTA dans les deux langues, sur ordinateur et mobile, puis republier avec `./deploy-voiceovya.sh --no-dmg`.
4. Dans Search Console, inspecter à nouveau `https://voiceovya.com/`, lancer le test en direct et demander une nouvelle indexation.

Ne renseigner l'URL App Store qu'une fois la fiche publique. Le lien direct vers le DMG reste donc actif jusque-là.

## Documentation Google

- Ajouter une propriété : https://support.google.com/webmasters/answer/34592
- Vérifier la propriété par DNS : https://support.google.com/webmasters/answer/9008080
- Inspecter une URL et demander son indexation : https://support.google.com/webmasters/answer/9012289
- Envoyer et suivre un sitemap : https://support.google.com/webmasters/answer/10351509
