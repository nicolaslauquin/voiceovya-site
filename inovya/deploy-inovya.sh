#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 1 ]]; then
  echo "Usage: $0 [répertoire-distant-inovya]" >&2
  exit 2
fi

HOST="${OVH_SFTP_HOST:-ftp.cluster129.hosting.ovh.net}"
SFTP_USER="${OVH_SFTP_USER:-inovyar}"
KEYCHAIN_SERVICE="${OVH_KEYCHAIN_SERVICE:-inovya-sftp}"
REMOTE_DIR="${1:-/home/inovyar/www}"
REMOTE_DIR="${REMOTE_DIR%/}/"
LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${REMOTE_DIR}" == "/" || "${REMOTE_DIR}" == "/home/" ]]; then
  echo "Répertoire distant trop large : ${REMOTE_DIR}" >&2
  exit 2
fi

for file in index.html robots.txt .htaccess og-consulting-capitalized.png; do
  if [[ ! -r "${LOCAL_DIR}/${file}" ]]; then
    echo "Fichier manquant : ${LOCAL_DIR}/${file}" >&2
    exit 1
  fi
done

SFTP_PASS="$(security find-generic-password -a "${SFTP_USER}" -s "${KEYCHAIN_SERVICE}" -w 2>/dev/null)" || {
  echo "Aucun mot de passe trouvé dans le Trousseau pour ${SFTP_USER}/${KEYCHAIN_SERVICE}." >&2
  echo "Enregistre-le avec :" >&2
  echo "  security add-generic-password -a \"${SFTP_USER}\" -s \"${KEYCHAIN_SERVICE}\" -w -U" >&2
  exit 1
}

sshpass -p "${SFTP_PASS}" sftp \
  -o PreferredAuthentications=password \
  -o PubkeyAuthentication=no \
  "${SFTP_USER}@${HOST}" <<EOF
cd ${REMOTE_DIR}
put ${LOCAL_DIR}/index.html
put ${LOCAL_DIR}/robots.txt
put ${LOCAL_DIR}/.htaccess
put ${LOCAL_DIR}/og-consulting-capitalized.png
bye
EOF

unset SFTP_PASS
echo "Inovya a été déployé dans ${REMOTE_DIR}"
