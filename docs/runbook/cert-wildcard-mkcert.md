# Runbook : Cert wildcard local via mkcert (POC)

## Contexte
Pour les access dev/POC depuis le Mac admin (192.168.18.40), on utilise
un cert wildcard `*.nova-syndicate.local` signe par une mini-CA mkcert locale.

**Production : voir ADR-0022 (a creer) pour migration vers Step CA / FreeIPA.**

## Pre-requis
- Homebrew installe (Mac)
- mkcert installe (`brew install mkcert`)
- Acces SSH a app01 via Tailscale + Proxmox

## Procedure de creation du cert

```bash
# 1. Installer la CA mkcert dans le trust store Mac
mkcert -install

# 2. Generer cert wildcard
mkdir -p ~/Documents/Nova-syndicate-Code/_certs-LOCAL-DO-NOT-COMMIT
cd ~/Documents/Nova-syndicate-Code/_certs-LOCAL-DO-NOT-COMMIT
mkcert "*.nova-syndicate.local" "nova-syndicate.local"

# 3. Deployer cert + key sur app01 via Tailscale/Proxmox
CERT_B64=$(base64 -i _wildcard.nova-syndicate.local+1.pem)
KEY_B64=$(base64 -i _wildcard.nova-syndicate.local+1-key.pem)

ssh root@100.112.113.2 "qm guest exec 106 -- bash -c \"echo '$CERT_B64' | base64 -d | sudo tee /etc/ssl/certs/nova-syndicate-wildcard.crt > /dev/null && sudo chmod 644 /etc/ssl/certs/nova-syndicate-wildcard.crt\""

ssh root@100.112.113.2 "qm guest exec 106 -- bash -c \"echo '$KEY_B64' | base64 -d | sudo tee /etc/ssl/private/nova-syndicate-wildcard.key > /dev/null && sudo chmod 600 /etc/ssl/private/nova-syndicate-wildcard.key\""

# 4. Update nginx config
ssh root@100.112.113.2 'qm guest exec 106 -- bash -c "sed -i \"s|/etc/nginx/ssl/app01.crt|/etc/ssl/certs/nova-syndicate-wildcard.crt|g; s|/etc/nginx/ssl/app01.key|/etc/ssl/private/nova-syndicate-wildcard.key|g\" /etc/nginx/sites-available/nova-syndicate"'

# 5. Test syntax + reload
ssh root@100.112.113.2 'qm guest exec 106 -- bash -c "nginx -t && systemctl reload nginx"'

# 6. Verifier
ssh root@100.112.113.2 'qm guest exec 106 -- bash -c "echo | openssl s_client -connect localhost:443 -servername grafana.nova-syndicate.local 2>/dev/null | openssl x509 -noout -subject -dates"'
```

## Renouvellement
Cert mkcert valide ~2 ans. Re-executer la procedure complete avant expiration.

## Limites
- Cert ne fonctionne QUE depuis le Mac qui a la CA mkcert dans son trust store
- Autres Mac ou postes Windows ne font pas confiance (warnings browser)
- Pour acces multi-poste : migrer vers Step CA ou FreeIPA (dette T-CA-INTERNAL-PROD)

## Securite
- Cle privee NE DOIT JAMAIS etre commit
- Stockee localement dans _certs-LOCAL-DO-NOT-COMMIT/ (gitignore)
- Sur app01 : mode 600 root:root /etc/ssl/private/nova-syndicate-wildcard.key
- En cas de fuite : re-generer cert + invalider via mkcert -uninstall && mkcert -install
