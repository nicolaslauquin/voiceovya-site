#!/usr/bin/env bash
set -euo pipefail

HOST="ftp.cluster129.hosting.ovh.net"
SFTP_USER="voiceoe"          # ajuste si besoin
REMOTE_DIR="/home/voiceoe/www/"            # ajuste si besoin (racine du site sur l'hébergement OVH)
KEYCHAIN_SERVICE="voiceovya-sftp"
LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SFTP_PASS="$(security find-generic-password -a "${SFTP_USER}" -s "${KEYCHAIN_SERVICE}" -w 2>/dev/null)" || {
  echo "Aucun mot de passe trouvé dans le Trousseau. Enregistre-le d'abord avec :" >&2
  echo "  security add-generic-password -a \"${SFTP_USER}\" -s \"${KEYCHAIN_SERVICE}\" -w -U" >&2
  exit 1
}

sshpass -p "${SFTP_PASS}" sftp -o PreferredAuthentications=password -o PubkeyAuthentication=no "${SFTP_USER}@${HOST}" <<EOF
cd ${REMOTE_DIR}
put ${LOCAL_DIR}/index.html
put -r ${LOCAL_DIR}/assets
bye
EOF

unset SFTP_PASS
echo "Déploiement terminé."
