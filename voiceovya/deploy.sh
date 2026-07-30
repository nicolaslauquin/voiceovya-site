#!/usr/bin/env bash
set -euo pipefail

HOST="ftp.cluster129.hosting.ovh.net"
SFTP_USER="voiceoe"          # ajuste si besoin
REMOTE_DIR="/home/voiceoe/www/"            # ajuste si besoin (racine du site sur l'hébergement OVH)
KEYCHAIN_SERVICE="voiceovya-sftp"
LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SITE_ROOT="$(cd "${LOCAL_DIR}/.." && pwd)"
DMG_SOURCE="${SITE_ROOT}/../VoiceOvya/build/dist/VoiceOvya.dmg"

# `.ovhconfig` selects the PHP engine for the whole hosting, so OVH only reads it at the web root:
# a copy inside a subdirectory (modelbenchmark) has no effect.
for file in index.html robots.txt .htaccess .ovhconfig; do
  if [[ ! -r "${LOCAL_DIR}/${file}" ]]; then
    echo "Fichier manquant : ${LOCAL_DIR}/${file}" >&2
    exit 1
  fi
done

for file in .htaccess .htpasswd; do
  if [[ ! -r "${LOCAL_DIR}/downloads/${file}" ]]; then
    echo "Fichier manquant : ${LOCAL_DIR}/downloads/${file}" >&2
    exit 1
  fi
done

SFTP_PASS="$(security find-generic-password -a "${SFTP_USER}" -s "${KEYCHAIN_SERVICE}" -w 2>/dev/null)" || {
  echo "Aucun mot de passe trouvé dans le Trousseau. Enregistre-le d'abord avec :" >&2
  echo "  security add-generic-password -a \"${SFTP_USER}\" -s \"${KEYCHAIN_SERVICE}\" -w -U" >&2
  exit 1
}

sshpass -p "${SFTP_PASS}" sftp -o PreferredAuthentications=password -o PubkeyAuthentication=no "${SFTP_USER}@${HOST}" <<EOF
cd ${REMOTE_DIR}
put ${LOCAL_DIR}/index.html
put ${LOCAL_DIR}/robots.txt
put ${LOCAL_DIR}/.htaccess
put ${LOCAL_DIR}/.ovhconfig
put -r ${LOCAL_DIR}/assets
-mkdir downloads
put ${LOCAL_DIR}/downloads/.htaccess downloads/.htaccess
put ${LOCAL_DIR}/downloads/.htpasswd downloads/.htpasswd
$(if [[ -r "${DMG_SOURCE}" ]]; then printf '%s\n' "put ${DMG_SOURCE} downloads/VoiceOvya.dmg"; fi)
bye
EOF

unset SFTP_PASS
if [[ -r "${DMG_SOURCE}" ]]; then
  echo "Déploiement terminé avec le DMG."
else
  echo "Déploiement terminé sans DMG : ${DMG_SOURCE} est absent."
fi
