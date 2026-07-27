# voiceovya.com/modelbenchmark

Collecte et publication des mesures du benchmark VoiceOvya : « avec mon Mac, quel modèle d'IA
choisir, et combien de secondes ça coûte ? »

## Fichiers

| Fichier | Rôle |
|---|---|
| `api.php` | Reçoit un rapport JSON en POST, le valide, l'archive dans `data/` |
| `index.php` | Page publique, agrégée à la lecture depuis `data/` |
| `lib.php` | Agrégation (médianes, groupements, recommandation) |
| `config.php` | Constantes partagées : version de protocole minimale, tailles limites, seuil de fiabilité |
| `deploy.sh` | Dépôt SFTP vers `/home/voiceoe/www/modelbenchmark` (mot de passe dans le Trousseau) |

Pas de base de données : un rapport = un fichier. L'agrégation se fait à chaque affichage. À
quelques centaines de rapports c'est instantané ; au-delà, la même logique se déplace dans un
script de génération statique sans changer l'URL.

## Deux axes, parce que la donnée ne se comporte pas pareil

- **La qualité ne dépend pas du Mac** (même note, même prompt, notation déterministe) : un seul
  classement par modèle, tous rapports confondus.
- **La vitesse dépend de la puce et de la RAM** : agrégation par `puce · RAM`, puis par modèle.

Choix statistiques :

- **Médiane partout**, jamais de moyenne : un Mac en throttle ou un runtime mal configuré détruit
  une moyenne.
- Les rapports mesurés en **surchauffe** (`thermalState` `serious`/`critical`) ou en **économie
  d'énergie** sont exclus des vitesses — ils mesurent le gestionnaire d'énergie, pas le modèle.
  Leur qualité, elle, reste comptée : elle ne dépend pas de la thermique.
- Le temps affiché est celui de la **première analyse d'une note inédite**, jamais la seconde
  passe : les runtimes locaux mettent le contexte en cache et le second run est ~2× plus rapide,
  ce qu'aucun usage réel ne reproduit.
- Sous `MIN_SAMPLES_FOR_SOLID` mesures, la valeur est affichée mais le nombre de rapports est
  signalé en orange.

## Version de protocole

`MIN_PROTOCOL_VERSION` (4) est un filtre dur, à l'écriture comme à la lecture. Les rapports
antérieurs mesuraient autrement (la chauffe partageait un préfixe de cache avec le contexte
mesuré) et ne sont pas comparables. Toute évolution du protocole côté app qui change la
signification d'une mesure doit relever ce nombre.

## Vie privée

Un rapport ne contient **aucun contenu de note** : durées, compteurs de jetons, scores, et
identifiants techniques de matériel et de modèle. C'est garanti côté app par construction (voir
`docs/analytics/README.md` dans le dépôt VoiceOvya). `data/` est refusé par Apache malgré tout :
l'empreinte matérielle d'un utilisateur donné ne regarde personne.

## Déploiement

```bash
./deploy.sh
```

`.ovhconfig` demande PHP 8.3. Si le cluster ne le propose pas, baisser la version : le code
n'utilise aucune syntaxe postérieure à PHP 8.0.

## Tests locaux

```bash
php -S 127.0.0.1:8899
```

Puis envoyer un rapport réel, exporté depuis la fenêtre Diagnostic de l'app (⌘D → Copier le
JSON / Enregistrer le fichier JSON) :

```bash
curl -X POST -H "Content-Type: application/json" --data-binary @report.json http://127.0.0.1:8899/api.php
```

Le serveur intégré de PHP ne lit pas les `.htaccess` : `data/` y est accessible en local, jamais
en production.
