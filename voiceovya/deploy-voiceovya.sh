#!/usr/bin/env bash
set -euo pipefail

SKIP_DMG=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-dmg) SKIP_DMG=1 ;;
    --with-dmg) SKIP_DMG=0 ;;
    -h|--help)
      echo "Usage: $(basename "$0") [--with-dmg]"
      echo "  --with-dmg  Déploie le site et envoie le DMG annoncé par l'appcast."
      echo "  --no-dmg    Compatibilité : comportement par défaut, sans renvoi du DMG."
      exit 0 ;;
    *)
      echo "Option inconnue : $1" >&2
      echo "Usage: $(basename "$0") [--with-dmg]" >&2
      exit 1 ;;
  esac
  shift
done

HOST="ftp.cluster129.hosting.ovh.net"
SFTP_USER="voiceoe"          # ajuste si besoin
REMOTE_DIR="/home/voiceoe/www/"            # ajuste si besoin (racine du site sur l'hébergement OVH)
KEYCHAIN_SERVICE="voiceovya-sftp"
LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PUBLIC_URL="https://voiceovya.com"
INDEXABLE_FILES=(index.html confidentialite.html privacy.html cgu.html terms.html)
INDEXABLE_PATHS=("" confidentialite.html privacy.html cgu.html terms.html)

# A successful release keeps only its DMG and the previously published one. Cleanup happens
# after upload and HTTP verification, so a failed deployment never removes a working download.
# `.ovhconfig` selects the PHP engine for the whole hosting, so OVH only reads it at the web root:
# a copy inside a subdirectory (modelbenchmark) has no effect.
# Les quatre pages légales sont vérifiées comme le reste : l'app y renvoie depuis Réglages >
# Confidentialité, et la fiche App Store réclame l'URL de la politique de confidentialité. Une
# page absente casse un lien affiché dans le produit.
# Les deux payloads de remote config sont lus en direct par l'app installée
# (docs/tech/remote-config.md du repo app) : version.json n'a plus de copie embarquée, un
# 404 laisse le contrôle de version muet. Le changelog, lui, n'est plus servi du tout : il
# décrit le build qui le lit, donc il est embarqué avec lui.
# `appcast.xml` est produit par scripts/package-release.sh du repo app, signé avec la clé EdDSA,
# et recopié ici : c'est le flux que l'app installée interroge (SUFeedURL).
for file in "${INDEXABLE_FILES[@]}" robots.txt sitemap.xml .htaccess .ovhconfig appcast.xml \
            config/v1/mac/version.json config/v1/mac/config.json; do
  if [[ ! -r "${LOCAL_DIR}/${file}" ]]; then
    echo "Fichier manquant : ${LOCAL_DIR}/${file}" >&2
    exit 1
  fi
done

if ! xmllint --noout "${LOCAL_DIR}/sitemap.xml" "${LOCAL_DIR}/appcast.xml"; then
  echo "Le sitemap ou l'appcast n'est pas un document XML valide." >&2
  exit 1
fi
if rg -qi '^[[:space:]]*Disallow:[[:space:]]*/[[:space:]]*$' "${LOCAL_DIR}/robots.txt"; then
  echo "robots.txt interdit encore l'exploration de tout le site." >&2
  exit 1
fi
if ! rg -Fq "Sitemap: ${PUBLIC_URL}/sitemap.xml" "${LOCAL_DIR}/robots.txt"; then
  echo "robots.txt ne déclare pas le sitemap public." >&2
  exit 1
fi

for index in "${!INDEXABLE_FILES[@]}"; do
  file="${INDEXABLE_FILES[index]}"
  public_url="${PUBLIC_URL}/${INDEXABLE_PATHS[index]}"
  if rg -i "<meta[^>]*name[[:space:]]*=[[:space:]]*[\"'](robots|googlebot|bingbot)[\"'][^>]*>" \
      "${LOCAL_DIR}/${file}" | rg -qi 'noindex'; then
    echo "La page indexable ${file} contient encore une balise robots noindex." >&2
    exit 1
  fi
  if ! rg -Fq "<link rel=\"canonical\" href=\"${public_url}\">" "${LOCAL_DIR}/${file}"; then
    echo "La page indexable ${file} ne déclare pas son URL canonique ${public_url}." >&2
    exit 1
  fi
  if ! rg -Fq "<loc>${public_url}</loc>" "${LOCAL_DIR}/sitemap.xml"; then
    echo "Le sitemap ne contient pas l'URL canonique ${public_url}." >&2
    exit 1
  fi
done

# La version publiée est lue dans l'appcast plutôt que recopiée ici : l'appcast est produit et
# signé par scripts/package-release.sh du repo app, jamais édité à la main, donc il ne peut pas
# se désynchroniser du DMG qu'il annonce. Le littéral qu'il remplace, lui, restait en retard.
VERSION="$(sed -n 's/.*<sparkle:shortVersionString>\(.*\)<\/sparkle:shortVersionString>.*/\1/p' \
  "${LOCAL_DIR}/appcast.xml" | tail -1)"
if [[ -z "${VERSION}" ]]; then
  echo "appcast.xml n'annonce aucune version : recopie celui du repo app." >&2
  exit 1
fi
ARTIFACT_SOURCE="${LOCAL_DIR}/build/dist/VoiceOvya_${VERSION}.dmg"
ARTIFACT_REMOTE="build/dist/VoiceOvya_${VERSION}.dmg"

# Plus d'authentification sur build/dist : Sparkle télécharge le DMG sans pouvoir présenter
# d'identifiants, donc une Basic Auth ici casse la mise à jour automatique de l'app installée.
if (( SKIP_DMG == 0 )) && [[ ! -r "${ARTIFACT_SOURCE}" ]]; then
  echo "Fichier manquant : ${ARTIFACT_SOURCE} (l'appcast annonce ${VERSION})" >&2
  exit 1
fi


SFTP_PASS="$(security find-generic-password -a "${SFTP_USER}" -s "${KEYCHAIN_SERVICE}" -w 2>/dev/null)" || {
  echo "Aucun mot de passe trouvé dans le Trousseau. Enregistre-le d'abord avec :" >&2
  echo "  security add-generic-password -a \"${SFTP_USER}\" -s \"${KEYCHAIN_SERVICE}\" -U -w" >&2
  exit 1
}

# Le DMG ne change qu'à une nouvelle version. Par défaut, le script republie le site sans le
# renvoyer et sans appliquer la rétention. `--with-dmg` active ces deux opérations.
if (( SKIP_DMG == 0 )); then
  ARTIFACT_PUT="put \"${ARTIFACT_SOURCE}\" \"${ARTIFACT_REMOTE}\""
else
  ARTIFACT_PUT=""
fi

SFTP_LOG="$(mktemp)"
DMG_LIST="$(mktemp)"
DMG_PRUNE_LOG="$(mktemp)"
REDIRECT_PAGE="$(mktemp)"
VERIFY_FILE="$(mktemp)"
VERIFY_HEADERS="$(mktemp)"
trap 'rm -f "${SFTP_LOG}" "${DMG_LIST}" "${DMG_PRUNE_LOG}" "${REDIRECT_PAGE}" "${VERIFY_FILE}" "${VERIFY_HEADERS}"; unset SFTP_PASS' EXIT

# Page de téléchargement : générée depuis VERSION plutôt que versionnée dans le repo, où elle
# nommait le DMG une seconde fois et restait en retard d'une release.
cat > "${REDIRECT_PAGE}" <<HTML
<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow, noarchive, nosnippet">
<meta http-equiv="refresh" content="0; url=VoiceOvya_${VERSION}.dmg">
<title>Téléchargement VoiceOvya</title>
<style>
body{margin:0;min-height:100vh;display:grid;place-items:center;font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text",system-ui,sans-serif;background:#f4f8f6;color:#1d2522}
main{width:min(520px,calc(100% - 40px));text-align:center}
a{color:#157a4b;font-weight:700}
</style>
</head>
<body>
<main>
  <h1>Téléchargement VoiceOvya</h1>
  <p>Si le téléchargement ne démarre pas, <a href="VoiceOvya_${VERSION}.dmg">cliquez ici</a>.</p>
</main>
</body>
</html>
HTML

# `sftp` peut terminer avec 0 même lorsqu'une commande `put` échoue. Ses diagnostics sont écrits
# sur stderr, donc stderr doit entrer dans `tee` pour que le contrôle ci-dessous les voie. Le
# statut de la commande reste contrôlé séparément pour couvrir aussi une coupure ou un échec de
# protocole qui ne correspondrait pas encore à un message connu.
set +e
sshpass -p "${SFTP_PASS}" sftp -o PreferredAuthentications=password -o PubkeyAuthentication=no "${SFTP_USER}@${HOST}" 2>&1 <<EOF | tee "${SFTP_LOG}"
cd ${REMOTE_DIR}
put ${LOCAL_DIR}/index.html
put ${LOCAL_DIR}/confidentialite.html
put ${LOCAL_DIR}/privacy.html
put ${LOCAL_DIR}/cgu.html
put ${LOCAL_DIR}/terms.html
put ${LOCAL_DIR}/robots.txt
put ${LOCAL_DIR}/sitemap.xml
put ${LOCAL_DIR}/appcast.xml
put ${LOCAL_DIR}/.htaccess
put ${LOCAL_DIR}/.ovhconfig
put -r ${LOCAL_DIR}/assets
put -r ${LOCAL_DIR}/config
-mkdir build
-mkdir build/dist
put "${REDIRECT_PAGE}" build/dist/index.html
${ARTIFACT_PUT}
bye
EOF
SFTP_STATUS="${PIPESTATUS[0]}"
set -e

if (( SFTP_STATUS != 0 )) || \
   rg -qi 'write remote|close remote|dest open|upload .* failed|Connection closed|Permission denied' "${SFTP_LOG}"; then
  echo "Le déploiement a échoué : au moins un transfert SFTP a été refusé." >&2
  echo "Aucun message de succès ne sera affiché. Vérifie le quota et l'état FTP/SSH chez OVH." >&2
  exit 1
fi

# Le succès SFTP ne suffit pas : une réponse 2xx avec un fichier vide ou tronqué avait déjà laissé
# le site inutilisable. Relire chaque ressource publique sans cache et comparer octet par octet
# confirme à la fois le contenu envoyé, le routage du vhost et la prise en compte de `.ovhconfig`.
verify_served_file() {
  local source="$1"
  local remote_path="$2"
  local url="${PUBLIC_URL}/${remote_path}?deploy_check=$(date +%s)"

  if ! curl -fsS --retry 2 --retry-delay 1 --max-time 180 "${url}" -o "${VERIFY_FILE}"; then
    echo "Le déploiement a échoué au contrôle HTTP : ${PUBLIC_URL}/${remote_path} est inaccessible." >&2
    exit 1
  fi
  if ! cmp -s "${source}" "${VERIFY_FILE}"; then
    echo "Le déploiement a échoué au contrôle HTTP : ${remote_path} diffère du fichier local." >&2
    exit 1
  fi
  echo "Vérifié : ${remote_path}"
}

verify_served_file "${LOCAL_DIR}/index.html" "index.html"
verify_served_file "${LOCAL_DIR}/confidentialite.html" "confidentialite.html"
verify_served_file "${LOCAL_DIR}/privacy.html" "privacy.html"
verify_served_file "${LOCAL_DIR}/cgu.html" "cgu.html"
verify_served_file "${LOCAL_DIR}/terms.html" "terms.html"
verify_served_file "${LOCAL_DIR}/robots.txt" "robots.txt"
verify_served_file "${LOCAL_DIR}/sitemap.xml" "sitemap.xml"
verify_served_file "${LOCAL_DIR}/appcast.xml" "appcast.xml"
verify_served_file "${LOCAL_DIR}/assets/appicon-sm.png" "assets/appicon-sm.png"
verify_served_file "${LOCAL_DIR}/assets/appicon.png" "assets/appicon.png"
verify_served_file "${LOCAL_DIR}/assets/record-detail-full.png" "assets/record-detail-full.png"
verify_served_file "${LOCAL_DIR}/config/v1/mac/version.json" "config/v1/mac/version.json"
verify_served_file "${LOCAL_DIR}/config/v1/mac/config.json" "config/v1/mac/config.json"
verify_served_file "${REDIRECT_PAGE}" "build/dist/index.html"

for remote_path in "${INDEXABLE_PATHS[@]}"; do
  page_name="${remote_path:-index.html}"
  if ! curl -fsSI --retry 2 --retry-delay 1 --max-time 30 \
      "${PUBLIC_URL}/${remote_path}?deploy_check=$(date +%s)" -o "${VERIFY_HEADERS}"; then
    echo "Le déploiement a échoué au contrôle HTTP des en-têtes de ${page_name}." >&2
    exit 1
  fi
  if rg -qi '^x-robots-tag:.*noindex' "${VERIFY_HEADERS}"; then
    echo "Le déploiement a échoué : ${page_name} sert encore un en-tête X-Robots-Tag noindex." >&2
    exit 1
  fi
done
echo "Vérifié : les cinq pages indexables ne servent aucun en-tête X-Robots-Tag noindex."

# L'appcast annonce ce DMG, même sans `--with-dmg` : s'il manque ou diffère, Sparkle ne peut pas
# mettre les installations existantes à jour. Le fichier local est normalement conservé avec la
# release ; quand il est présent, vérifier son contenu complet plutôt qu'un simple HTTP 200.
if [[ -r "${ARTIFACT_SOURCE}" ]]; then
  verify_served_file "${ARTIFACT_SOURCE}" "${ARTIFACT_REMOTE}"
else
  if ! curl -fsS --retry 2 --retry-delay 1 --max-time 180 \
      "${PUBLIC_URL}/${ARTIFACT_REMOTE}?deploy_check=$(date +%s)" -o /dev/null; then
    echo "Le déploiement a échoué au contrôle HTTP : ${ARTIFACT_REMOTE} est inaccessible." >&2
    exit 1
  fi
  echo "Vérifié : ${ARTIFACT_REMOTE} est accessible (copie locale absente, contenu non comparé)."
fi

# Le quota OVH est partagé avec le reste de l'hébergement. Après la vérification du nouvel
# artefact, garder les deux DMG les plus récemment envoyés, le nouveau et son prédécesseur, et
# supprimer tous les plus anciens. Les noms extraits suivent un motif strict avant d'être injectés
# dans les commandes SFTP.
prune_remote_dmgs() {
  local list_status
  set +e
  sshpass -p "${SFTP_PASS}" sftp \
    -o PreferredAuthentications=password \
    -o PubkeyAuthentication=no \
    "${SFTP_USER}@${HOST}" > "${DMG_LIST}" 2>&1 <<EOF
cd ${REMOTE_DIR}
ls -1t build/dist/VoiceOvya_*.dmg
bye
EOF
  list_status=$?
  set -e

  if (( list_status != 0 )) || \
     rg -qi 'Connection closed|Permission denied|Couldn.t stat remote file' "${DMG_LIST}"; then
    echo "Impossible de lister les DMG distants ; aucun ancien artefact n'a été supprimé." >&2
    return 1
  fi

  local remote_dmgs=()
  local remote_dmg
  while IFS= read -r remote_dmg; do
    remote_dmgs+=("${remote_dmg}")
  done < <(
    rg -o 'VoiceOvya_[0-9]+(\.[0-9]+){1,2}\.dmg' "${DMG_LIST}" | awk '!seen[$0]++'
  )

  if (( ${#remote_dmgs[@]} <= 2 )); then
    echo "Rétention DMG vérifiée : ${#remote_dmgs[@]} fichier(s) distant(s)."
    return
  fi

  local remove_commands=""
  local index
  for (( index = 2; index < ${#remote_dmgs[@]}; index++ )); do
    remove_commands+="rm \"build/dist/${remote_dmgs[index]}\""$'\n'
  done

  local prune_status
  set +e
  sshpass -p "${SFTP_PASS}" sftp \
    -o PreferredAuthentications=password \
    -o PubkeyAuthentication=no \
    "${SFTP_USER}@${HOST}" 2>&1 <<EOF | tee "${DMG_PRUNE_LOG}"
cd ${REMOTE_DIR}
${remove_commands}bye
EOF
  prune_status="${PIPESTATUS[0]}"
  set -e

  if (( prune_status != 0 )) || \
     rg -qi 'Couldn.t delete|No such file|Failure|Connection closed|Permission denied' "${DMG_PRUNE_LOG}"; then
    echo "La publication a réussi, mais la rétention des anciens DMG a échoué." >&2
    return 1
  fi

  echo "Rétention DMG appliquée : ${remote_dmgs[0]} et ${remote_dmgs[1]} conservés."
}

if (( SKIP_DMG == 0 )); then
  prune_remote_dmgs
fi

if (( SKIP_DMG == 0 )); then
  echo "Déploiement terminé avec ${ARTIFACT_REMOTE}."
else
  echo "Déploiement terminé sans le DMG (${ARTIFACT_REMOTE} inchangé sur le serveur)."
fi
