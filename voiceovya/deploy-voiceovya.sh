#!/usr/bin/env bash
set -euo pipefail

SKIP_DMG=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-dmg) SKIP_DMG=1 ;;
    -h|--help)
      echo "Usage: $(basename "$0") [--no-dmg]"
      echo "  --no-dmg  Déploie le site sans réenvoyer le DMG (déjà en ligne)."
      exit 0 ;;
    *)
      echo "Option inconnue : $1" >&2
      echo "Usage: $(basename "$0") [--no-dmg]" >&2
      exit 1 ;;
  esac
  shift
done

HOST="ftp.cluster129.hosting.ovh.net"
SFTP_USER="voiceoe"          # ajuste si besoin
REMOTE_DIR="/home/voiceoe/www/"            # ajuste si besoin (racine du site sur l'hébergement OVH)
KEYCHAIN_SERVICE="voiceovya-sftp"
LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Never delete a previously published DMG without explicit user approval.
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
for file in index.html robots.txt .htaccess .ovhconfig appcast.xml \
            confidentialite.html privacy.html cgu.html terms.html \
            config/v1/mac/version.json config/v1/mac/config.json; do
  if [[ ! -r "${LOCAL_DIR}/${file}" ]]; then
    echo "Fichier manquant : ${LOCAL_DIR}/${file}" >&2
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
  echo "  security add-generic-password -a \"${SFTP_USER}\" -s \"${KEYCHAIN_SERVICE}\" -w -U" >&2
  exit 1
}

# Le DMG pèse plusieurs centaines de Mo et ne change qu'à une nouvelle version : `--no-dmg` republie
# le site sans le renvoyer. Le fichier distant reste en place, jamais supprimé.
if (( SKIP_DMG == 0 )); then
  ARTIFACT_PUT="put \"${ARTIFACT_SOURCE}\" \"${ARTIFACT_REMOTE}\""
else
  ARTIFACT_PUT=""
fi

SFTP_LOG="$(mktemp)"
REDIRECT_PAGE="$(mktemp)"
trap 'rm -f "${SFTP_LOG}" "${REDIRECT_PAGE}"; unset SFTP_PASS' EXIT

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

sshpass -p "${SFTP_PASS}" sftp -o PreferredAuthentications=password -o PubkeyAuthentication=no "${SFTP_USER}@${HOST}" <<EOF | tee "${SFTP_LOG}"
cd ${REMOTE_DIR}
put ${LOCAL_DIR}/index.html
put ${LOCAL_DIR}/confidentialite.html
put ${LOCAL_DIR}/privacy.html
put ${LOCAL_DIR}/cgu.html
put ${LOCAL_DIR}/terms.html
put ${LOCAL_DIR}/robots.txt
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

if rg -q 'write remote|close remote|dest open|upload .* failed|Connection closed|Permission denied' "${SFTP_LOG}"; then
  echo "Le déploiement a échoué : le serveur a refusé au moins un transfert." >&2
  exit 1
fi

if (( SKIP_DMG == 0 )); then
  echo "Déploiement terminé avec ${ARTIFACT_REMOTE}."
else
  echo "Déploiement terminé sans le DMG (${ARTIFACT_REMOTE} inchangé sur le serveur)."
fi
