#!/bin/bash
# Nova Syndicate — Import utilisateurs AD depuis CSV
# Usage : ./import_users_csv.sh users.csv
# Format CSV : prenom,nom,groupe,email
# Exemple : Jean,Dupont,Commerciaux,j.dupont@nova-syndicate.fr
set -euo pipefail

CSV_FILE="${1:?Usage: $0 fichier.csv}"
ADMIN_PASS="${SAMBA_ADMIN_PASS:?Variable SAMBA_ADMIN_PASS requise}"
DOMAIN="nova-syndicate.local"

if [[ ! -f "${CSV_FILE}" ]]; then
    echo "ERREUR : Fichier ${CSV_FILE} introuvable"
    exit 1
fi

# Ignorer la ligne d'entete
tail -n +2 "${CSV_FILE}" | while IFS=',' read -r prenom nom groupe email; do
    username=$(echo "${prenom:0:1}.${nom}" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
    fullname="${prenom} ${nom}"

    # Generer un mot de passe temporaire
    temp_pass="Nova@$(openssl rand -hex 4)!"

    echo "--- Creation de ${username} (${fullname}) dans ${groupe}"

    samba-tool user create "${username}" "${temp_pass}" \
        --given-name="${prenom}" \
        --surname="${nom}" \
        --mail-address="${email}" \
        --use-username-as-cn \
        -U Administrator --password="${ADMIN_PASS}" 2>/dev/null \
    && echo "  [OK] Utilisateur cree" \
    || echo "  [SKIP] Utilisateur existe deja"

    # Forcer le changement de mot de passe a la premiere connexion
    samba-tool user setexpiry "${username}" --days=0 \
        -U Administrator --password="${ADMIN_PASS}" 2>/dev/null

    # Ajouter au groupe
    samba-tool group addmembers "${groupe}" "${username}" \
        -U Administrator --password="${ADMIN_PASS}" 2>/dev/null \
    && echo "  [OK] Ajoute au groupe ${groupe}" \
    || echo "  [SKIP] Deja membre de ${groupe}"

    echo "  Mot de passe temporaire : ${temp_pass}"
done

echo "=== Import termine ==="
