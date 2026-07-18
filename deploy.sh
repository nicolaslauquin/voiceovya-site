#!/usr/bin/env bash
set -euo pipefail

HOST="ftp.cluster129.hosting.ovh.net"
SFTP_USER="voiceoe"          # ajuste si besoin
REMOTE_DIR="/home/voiceoe/www/"            # ajuste si besoin (racine du site sur l'hébergement OVH)
SSH_KEY="${HOME}/.ssh/voiceovya_ovh"
LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -r "${SSH_KEY}" ]]; then
  echo "Clé SSH introuvable ou illisible : ${SSH_KEY}" >&2
  exit 1
fi

sftp \
  -o IdentitiesOnly=yes \
  -o IdentityFile="${SSH_KEY}" \
  -o PreferredAuthentications=publickey \
  "${SFTP_USER}@${HOST}" <<EOF
cd ${REMOTE_DIR}
put ${LOCAL_DIR}/index.html
put -r ${LOCAL_DIR}/assets
bye
EOF

echo "Déploiement terminé."
