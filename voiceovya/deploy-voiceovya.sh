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
ARTIFACT_SOURCE="${LOCAL_DIR}/build/dist/VoiceOvya_0.5.5.dmg"
ARTIFACT_REMOTE="build/dist/VoiceOvya_0.5.5.dmg"

# Never delete a previously published DMG without explicit user approval.
# `.ovhconfig` selects the PHP engine for the whole hosting, so OVH only reads it at the web root:
# a copy inside a subdirectory (modelbenchmark) has no effect.
# Les quatre pages légales sont vérifiées comme le reste : l'app y renvoie depuis Réglages >
# Confidentialité, et la fiche App Store réclame l'URL de la politique de confidentialité. Une
# page absente casse un lien affiché dans le produit.
# Les trois payloads de remote config sont lus en direct par l'app installée
# (docs/tech/remote-config.md du repo app) : version.json n'a plus de copie embarquée, un
# 404 laisse le contrôle de version muet.
for file in index.html robots.txt .htaccess .ovhconfig \
            confidentialite.html privacy.html cgu.html terms.html \
            config/v1/mac/version.json config/v1/mac/config.json config/v1/mac/news.json; do
  if [[ ! -r "${LOCAL_DIR}/${file}" ]]; then
    echo "Fichier manquant : ${LOCAL_DIR}/${file}" >&2
    exit 1
  fi
done

DIST_FILES=(.htaccess .htpasswd index.html)
if (( SKIP_DMG == 0 )); then
  DIST_FILES+=("$(basename "${ARTIFACT_SOURCE}")")
fi

for file in "${DIST_FILES[@]}"; do
  if [[ ! -r "${LOCAL_DIR}/build/dist/${file}" ]]; then
    echo "Fichier manquant : ${LOCAL_DIR}/build/dist/${file}" >&2
    exit 1
  fi
done

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
trap 'rm -f "${SFTP_LOG}"; unset SFTP_PASS' EXIT

sshpass -p "${SFTP_PASS}" sftp -o PreferredAuthentications=password -o PubkeyAuthentication=no "${SFTP_USER}@${HOST}" <<EOF | tee "${SFTP_LOG}"
cd ${REMOTE_DIR}
put ${LOCAL_DIR}/index.html
put ${LOCAL_DIR}/confidentialite.html
put ${LOCAL_DIR}/privacy.html
put ${LOCAL_DIR}/cgu.html
put ${LOCAL_DIR}/terms.html
put ${LOCAL_DIR}/robots.txt
put ${LOCAL_DIR}/.htaccess
put ${LOCAL_DIR}/.ovhconfig
put -r ${LOCAL_DIR}/assets
put -r ${LOCAL_DIR}/config
-mkdir build
-mkdir build/dist
put ${LOCAL_DIR}/build/dist/.htaccess build/dist/.htaccess
put ${LOCAL_DIR}/build/dist/.htpasswd build/dist/.htpasswd
put ${LOCAL_DIR}/build/dist/index.html build/dist/index.html
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
