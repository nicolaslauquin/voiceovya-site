# Mise en index de voiceovya.com

## Publication initiale

1. Publier les changements SEO avec `./deploy-voiceovya.sh` depuis ce dossier.
2. Vérifier publiquement :
   - `https://voiceovya.com/robots.txt` autorise l'exploration et déclare le sitemap ;
   - `https://voiceovya.com/sitemap.xml` répond en HTTP 200 ;
   - la réponse de `https://voiceovya.com/` ne contient aucun `X-Robots-Tag: noindex` ;
   - le HTML des cinq pages du sitemap ne contient aucun `meta name="robots"` avec `noindex`.

Le script de déploiement envoie et compare `robots.txt` et `sitemap.xml` avec leurs copies publiques. Il échoue aussi si l'une des cinq pages indexables contient une balise `noindex`, si une URL canonique manque au sitemap, ou si l'une de ces pages sert encore un en-tête HTTP `noindex`.

La page d'accueil propose huit langues dans une seule URL canonique. Elle reste donc une page multilingue unique, avec le français comme contenu HTML et métadonnées par défaut. Ne pas ajouter de `hreflang` pour ces variantes tant qu'elles ne disposent pas d'URL distinctes. Les politiques de confidentialité et conditions d'utilisation ont, elles, des URL françaises et anglaises distinctes, reliées par des liens `hreflang` réciproques et un `x-default` français.

## Google Search Console

1. Dans le sélecteur de propriétés, choisir **Ajouter une propriété** puis **Domaine**.
2. Saisir uniquement `voiceovya.com`, sans `https://` ni chemin.
3. Copier la valeur TXT fournie par Google et l'ajouter à la zone DNS du domaine. Chez OVH, utiliser la racine du domaine (`@`) comme sous-domaine/nom si l'interface le demande.
4. Revenir dans Search Console et lancer la validation. Conserver l'enregistrement TXT après validation.
5. Ouvrir **Inspection de l'URL**, saisir `https://voiceovya.com/`, lancer **Tester l'URL publiée**, puis **Demander une indexation**.
6. Ouvrir **Sitemaps**, saisir `sitemap.xml`, puis envoyer. L'URL complète attendue est `https://voiceovya.com/sitemap.xml`.

La demande ne garantit pas l'indexation immédiate. Contrôler ensuite l'état de la page dans **Inspection de l'URL** et la lecture du sitemap dans **Sitemaps**.

## Jour de la sortie Mac App Store

1. Dans `index.html`, remplacer l'adresse `mailto:` du lien principal `#beta-cta` par l'URL publique Mac App Store, en conservant ses classes et `data-i18n="hero.download"`.
2. Adapter le suivi TelemetryDeck du CTA principal pour mesurer les ouvertures de la fiche Mac App Store. Décider si le CTA secondaire `#updates-cta` reste utile.
3. Remplacer les libellés liés à la bêta ou à la sortie prochaine dans `hero.download`, `ct.p` et `compat.notmac` pour les huit langues. Supprimer les textes et le code de génération d'e-mail devenus inutilisés.
4. Dans `config/v1/mac/version.json`, renseigner la même URL dans `appStoreURL`. Ne pas modifier le canal Sparkle direct ni son `appcast.xml` dans cette opération.
5. Tester le CTA dans les huit langues, sur ordinateur et mobile, puis republier avec `./deploy-voiceovya.sh`.
6. Dans Search Console, inspecter à nouveau `https://voiceovya.com/`, lancer le test en direct et demander une nouvelle indexation.

Ne renseigner l'URL App Store qu'une fois la fiche publique. Jusque-là, le site propose deux CTA cliquables par e-mail, pour rejoindre la bêta et recevoir les actualités. Le DMG reste disponible uniquement pour le canal de mise à jour directe et sa page technique n'est pas incluse dans le sitemap.

## Documentation Google

- Ajouter une propriété : https://support.google.com/webmasters/answer/34592
- Vérifier la propriété par DNS : https://support.google.com/webmasters/answer/9008080
- Inspecter une URL et demander son indexation : https://support.google.com/webmasters/answer/9012289
- Envoyer et suivre un sitemap : https://support.google.com/webmasters/answer/10351509
