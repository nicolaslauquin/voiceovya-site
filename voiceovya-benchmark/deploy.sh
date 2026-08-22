#!/usr/bin/env bash
# Deploys the benchmark page and endpoint to voiceovya.com/modelbenchmark.
# Never pushes data/: the reports live on the server and are only ever written there.
set -euo pipefail

HOST="ftp.cluster129.hosting.ovh.net"
SFTP_USER="voiceoe"
REMOTE_DIR="/home/voiceoe/www/modelbenchmark"
KEYCHAIN_SERVICE="voiceovya-sftp"
LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FILES=(index.php lib.php api.php config.php .htaccess)
for file in "${FILES[@]}"; do
  if [[ ! -r "${LOCAL_DIR}/${file}" ]]; then
    echo "Fichier manquant : ${LOCAL_DIR}/${file}" >&2
    exit 1
  fi
done

if ! php -l "${LOCAL_DIR}/index.php" >/dev/null; then
  echo "index.php ne compile pas." >&2
  exit 1
fi

SFTP_PASS="$(security find-generic-password -a "${SFTP_USER}" -s "${KEYCHAIN_SERVICE}" -w 2>/dev/null)" || {
  echo "Aucun mot de passe trouvé dans le Trousseau. Enregistre-le d'abord avec :" >&2
  echo "  security add-generic-password -a \"${SFTP_USER}\" -s \"${KEYCHAIN_SERVICE}\" -w -U" >&2
  exit 1
}

# `-mkdir` on the first deploy; the error on an existing directory is harmless, hence `-`.
# The PHP engine version is not shipped here: `.ovhconfig` is hosting-wide and OVH only reads it at
# the web root, so it travels with ../voiceovya/deploy-voiceovya.sh.
sshpass -p "${SFTP_PASS}" sftp -o PreferredAuthentications=password -o PubkeyAuthentication=no "${SFTP_USER}@${HOST}" <<EOF
-mkdir ${REMOTE_DIR}
-mkdir ${REMOTE_DIR}/data
-mkdir ${REMOTE_DIR}/rate
cd ${REMOTE_DIR}
put ${LOCAL_DIR}/index.php
put ${LOCAL_DIR}/lib.php
put ${LOCAL_DIR}/api.php
put ${LOCAL_DIR}/config.php
put ${LOCAL_DIR}/.htaccess
put ${LOCAL_DIR}/data/.htaccess data/.htaccess
put ${LOCAL_DIR}/rate/.htaccess rate/.htaccess
bye
EOF

unset SFTP_PASS
echo "Déploiement terminé : https://voiceovya.com/modelbenchmark"
