#!/usr/bin/env bash
set -euo pipefail

HOST="ftp.cluster129.hosting.ovh.net"
SFTP_USER="voiceoe"          # ajuste si besoin
REMOTE_DIR="/home/voiceoe/www/"            # ajuste si besoin (racine du site sur l'hébergement OVH)
KEYCHAIN_SERVICE="voiceovya-sftp"
LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARTIFACT_SOURCE="${LOCAL_DIR}/build/dist/VoiceOvya_0.5.3.dmg"
ARTIFACT_REMOTE="build/dist/VoiceOvya_0.5.3.dmg"

# `.ovhconfig` selects the PHP engine for the whole hosting, so OVH only reads it at the web root:
# a copy inside a subdirectory (modelbenchmark) has no effect.
# Les quatre pages légales sont vérifiées comme le reste : l'app y renvoie depuis Réglages >
# Confidentialité, et la fiche App Store réclame l'URL de la politique de confidentialité. Une
# page absente casse un lien affiché dans le produit.
for file in index.html robots.txt .htaccess .ovhconfig \
            confidentialite.html privacy.html cgu.html terms.html; do
  if [[ ! -r "${LOCAL_DIR}/${file}" ]]; then
    echo "Fichier manquant : ${LOCAL_DIR}/${file}" >&2
    exit 1
  fi
done

for file in .htaccess .htpasswd index.html VoiceOvya_0.5.3.dmg; do
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

sshpass -p "${SFTP_PASS}" sftp -o PreferredAuthentications=password -o PubkeyAuthentication=no "${SFTP_USER}@${HOST}" <<EOF
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
-mkdir build
-mkdir build/dist
put ${LOCAL_DIR}/build/dist/.htaccess build/dist/.htaccess
put ${LOCAL_DIR}/build/dist/.htpasswd build/dist/.htpasswd
put ${LOCAL_DIR}/build/dist/index.html build/dist/index.html
put "${ARTIFACT_SOURCE}" "${ARTIFACT_REMOTE}"
bye
EOF

unset SFTP_PASS
echo "Déploiement terminé avec ${ARTIFACT_REMOTE}."
