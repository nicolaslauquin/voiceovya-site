#!/usr/bin/env bash
set -euo pipefail

HOST="ftp.cluster129.hosting.ovh.net"
SFTP_USER="voiceoe"       # ajuste si besoin
REMOTE_DIR="/www"         # ajuste si besoin (racine du site sur l'hébergement OVH)
LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Connexion à ${SFTP_USER}@${HOST} — le mot de passe sera demandé par sftp."

sftp -o PreferredAuthentications=password -o PubkeyAuthentication=no "${SFTP_USER}@${HOST}" <<EOF
cd ${REMOTE_DIR}
put ${LOCAL_DIR}/index.html
put -r ${LOCAL_DIR}/assets
bye
EOF

echo "Déploiement terminé."
