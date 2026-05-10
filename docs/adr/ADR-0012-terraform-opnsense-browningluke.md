# ADR-0012 : Terraform avec le provider browningluke/opnsense pour la gestion firewall

## Status
Accepted

## Date
2026-05-10

## Contexte

La configuration des firewalls OPNsense (FW-EXT-LYON et FW-INT-LYON) couvre un perimetre etendu : regles de filtrage, aliases reseau, routes statiques, configuration IPsec IKEv2 (phase 1 et child SAs), serveur WireGuard, clients DHCP, DNS Unbound, et interfaces VLAN. Cette configuration doit satisfaire les memes exigences IaC que le reste de l'infrastructure :

- **Versionnement Git** : chaque changement de regle firewall doit etre tracable (qui, quoi, quand, pourquoi).
- **Reproductibilite** : une destruction et reconstruction des firewalls depuis zero (template + Terraform) doit produire une configuration identique.
- **Plan avant application** : le principe `terraform plan` permet de valider l'impact d'un changement avant de l'appliquer, evitant les interruptions de service accidentelles.
- **Eviter la configuration "clic-clic"** : la configuration manuelle via l'interface web OPNsense est propice aux erreurs, non reproductible et non auditable.

La contrainte technique principale est que le provider Terraform doit couvrir les fonctionnalites utilisees dans Nova Syndicate : regles firewall, aliases, IPsec, WireGuard. Les providers qui ne couvrent qu'un sous-ensemble des fonctionnalites ne sont pas utilisables.

## Decision

Adoption du provider **browningluke/opnsense** version **0.16.x** (epinglage dans `versions.tf`).

**Ressources Terraform utilisees dans le projet :**

| Resource | Utilisation |
|----------|-------------|
| `opnsense_firewall_alias` | Aliases hosts/networks/ports (src/dst dans les regles) |
| `opnsense_firewall_rule` | Regles de filtrage avec logging |
| `opnsense_route_static` | Routes statiques inter-VLANs et vers VPS |
| `opnsense_ipsec_phase1` | Tunnel IKEv2 phase 1 (Lyon-Marseille) |
| `opnsense_ipsec_phase2` | Child SAs (une par VLAN) |
| `opnsense_wireguard_server` | Interface WireGuard sur OPNsense |
| `opnsense_wireguard_peer` | Peer WireGuard (VPS Hetzner) |
| `opnsense_dhcp_server` | Serveur DHCP par interface VLAN |
| `opnsense_unbound_host` | Entrees DNS statiques (nova-syndicate.local) |

**Justification technique du choix du provider :**

Le provider `browningluke/opnsense` est le seul provider Terraform open source qui couvre l'ensemble de ces ressources de facon stable en 2024-2026. Il repose entierement sur l'API REST native d'OPNsense (pas de scraping HTML, pas de manipulation de `config.xml`). Chaque operation Terraform se traduit en appels API HTTPS authentifies par les credentials OPNsense.

**Configuration du provider :**

```hcl
terraform {
  required_providers {
    opnsense = {
      source  = "browningluke/opnsense"
      version = "~> 0.16"
    }
  }
}

provider "opnsense" {
  uri        = var.opnsense_uri
  api_key    = var.opnsense_api_key
  api_secret = var.opnsense_api_secret
}
```

Les credentials API OPNsense (key + secret) sont generes dans l'interface web OPNsense (System > Access > Users) et stockes dans `terraform.tfvars` exclu de Git (`.gitignore`).

**Structure des fichiers Terraform OPNsense :**

```
terraform/environments/opnsense/
  main.tf           -- Ressources principales (aliases, regles)
  ipsec.tf          -- Tunnels IPsec (phase 1 + phase 2)
  wireguard.tf      -- Serveur WireGuard + peers
  dhcp.tf           -- Serveurs DHCP par VLAN
  dns.tf            -- Entrees Unbound DNS
  variables.tf      -- Definitions des variables
  terraform.tfvars  -- Valeurs (exclues de Git)
  versions.tf       -- Providers et contraintes de versions
```

**Pratique de developpement retenue** : les changements de configuration firewall suivent le workflow `terraform plan` -> review -> `terraform apply`. Le `plan` est systematiquement revu avant application, en particulier pour les modifications de regles IPsec (qui coupent le tunnel inter-site le temps de la recomposition).

## Alternatives considerees

### Ansible avec collection community.opnsense

**Pour** :
- Ansible est deja utilise dans le projet pour la configuration OS (ADR-0011). Utiliser Ansible aussi pour OPNsense evite d'introduire Terraform pour cette couche.
- La collection `ansibleguy.opnsense` (community) couvre un large perimetre.
- Les playbooks Ansible sont familiers pour un administrateur Linux.

**Contre** :
- La collection `ansibleguy.opnsense` est moins complete que le provider Terraform pour les configurations avancees (IPsec IKEv2 multi-SA, WireGuard). Les modules existants pour IPsec couvrent les cas basiques mais pas toutes les options de la phase 2 (PFS group, lifetime, etc.).
- Ansible ne produit pas de "plan" avant execution. Une regle incorrecte s'applique immediatement. Le risque d'interruption de service est plus eleve.
- La separation des responsabilites (Terraform = etat de l'infrastructure, Ansible = configuration interne) est une architecture claire. Melanger les deux cree de l'ambiguite : quand utiliser Terraform, quand utiliser Ansible pour OPNsense ?
- L'idempotence Ansible avec les modules OPNsense est moins robuste que la gestion d'etat Terraform : le "state file" Terraform garantit que les ressources crees par Terraform sont grees par Terraform. Ansible ne maintient pas cet etat.
- Le `check mode` Ansible (equivalent de `terraform plan`) ne produit pas toujours des resultats fiables avec les modules de fournisseurs tiers.

### Scripts Python directs sur l'API OPNsense

**Pour** :
- Controle total : les scripts Python peuvent acceder a n'importe quel endpoint API.
- Pas de dependance a un provider tiers.
- Flexibilite maximale pour les configurations hors-perimetre du provider Terraform.

**Contre** :
- Pas de gestion d'etat. Les scripts Python ne savent pas si une ressource existe deja : il faut implementer la logique de "check before create" pour chaque ressource.
- Pas de plan avant execution. Les modifications sont appliquees immediatement.
- Maintenance lourde : chaque evolution de l'API OPNsense necessite des mises a jour des scripts.
- Code non standard, difficile a reprendre par un autre administrateur.
- Pas de versionning semantique des changements (un diff de script Python est moins lisible qu'un diff de fichiers `.tf`).
- L'objectif du portfolio est de demontrer la maitrise des outils IaC standard (Terraform), pas de reinventer des outils specifiques.

### Modification directe de config.xml OPNsense

**Pour** :
- `config.xml` est le fichier de configuration source d'OPNsense. Modifier ce fichier puis executer `configctl` est la methode "native" interne d'OPNsense.
- Pas de dependance a un provider tiers.
- Toutes les configurations OPNsense sont representees dans `config.xml`.

**Contre** :
- La structure de `config.xml` n'est pas documentee publiquement de facon exhaustive. Elle evolue entre les versions d'OPNsense.
- La manipulation directe de XML (sed, xmlstarlet, Python ElementTree) est fragile. Une erreur de XML invalide le fichier de configuration entier et peut rendre le firewall inoprerable.
- Pas de validation semantique : un XML syntaxiquement valide peut contenir une configuration logiquement incorrecte (regle qui reference un alias inexistant, par exemple).
- Inacceptable pour un contexte production ou formation : aucun auditeur ne validerait une gestion de firewall via sed sur un fichier XML.

### OPNsense Puppet module (Aurore module)

**Pour** :
- Coverage large.
- Puppet peut gerer d'autres composants de l'infrastructure en meme temps.

**Contre** :
- Puppet a ete ecarte pour la configuration OS (voir ADR-0011, meme raisonnement).
- Le module OPNsense pour Puppet est encore moins maintenu que la collection Ansible.
- Introduction de Puppet necessiterait un Puppet Master : infrastructure supplementaire disproportionnee.

## Consequences

**Positives :**
- L'ensemble de la configuration firewall est dans Git, auditable, revertable.
- `terraform plan` avant chaque modification permet de valider l'impact (ex : un `terraform apply` pour modifier une regle IPsec montre que le tunnel va etre recompose, permettant de planifier une fenetre de maintenance).
- Le state file Terraform (`terraform.tfstate`) est la source de verite sur l'etat deploye des ressources OPNsense. Il permet de detecter les modifications manuelles (drift) via `terraform plan`.
- La reproductibilite est garantie : un `terraform destroy && terraform apply` redeploie la configuration firewall complete en quelques minutes.

**Negatives et risques residuels :**
- **Provider 0.x = breaking changes potentiels** : le provider `browningluke/opnsense` est en version 0.x. Des breaking changes entre 0.14 et 0.16 ont ete rencontres (renommage de resources, changement de schema). L'epinglage `~> 0.16` dans `versions.tf` protege contre les mises a jour automatiques, mais les upgrades futurs necessiteront des adaptations.
- **Dependance a un mainteneur unique** : le provider est maintenu par un developpeur individuel (`browningluke`). En cas d'abandon, il faudra forker et maintenir le provider localement, ou migrer vers une autre solution (Ansible community.opnsense ou scripts Python).
- **State file = secret si les credentials y sont references** : le state file Terraform peut contenir en clair les valeurs des variables `sensitive`. Le state file doit etre protege avec les memes mesures que les credentials (acces restreint, pas dans Git). En local, il est exclu via `.gitignore`. En equipe, un backend S3 chiffre est recommande (hors perimetre de ce lab single-node).
- **Couverture incomplete** : certains parametres OPNsense tres specifiques (options avancees de Suricata, parametres fins d'Unbound) peuvent ne pas etre couverts par le provider. Dans ce cas, des configurations residuelles restent "hors IaC" et doivent etre documentees comme dette.
- **Temps d'apply** : chaque `terraform apply` effectue des appels API OPNsense synchrones. Sur les ressources IPsec (qui necessitent un redemarrage du tunnel), le temps d'application peut depasser 30 secondes.

## References

- Provider Terraform browningluke/opnsense : https://registry.terraform.io/providers/browningluke/opnsense/latest/docs
- GitHub browningluke/opnsense : https://github.com/browningluke/terraform-provider-opnsense
- OPNsense API reference : https://docs.opnsense.org/development/api.html
- Fichiers Terraform OPNsense : `terraform/environments/opnsense/`
- ADR-0004 (choix OPNsense) : `docs/adr/ADR-0004-opnsense-vs-pfsense.md`
- ADR-0011 (Ansible) : `docs/adr/ADR-0011-ansible-iac-config-os.md`
