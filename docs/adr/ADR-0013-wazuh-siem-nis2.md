# ADR-0013 : Wazuh comme SIEM centralise pour la conformite NIS2 art. 21.f

## Status
Accepted

## Date
2026-05-10

## Contexte

La directive NIS2 (UE 2022/2555), Article 21, alinea f, impose aux entites concernees de disposer de capacites de detection des incidents, de surveillance des systemes et de gestion des journaux de securite. Plus specifiquement, un SIEM (Security Information and Event Management) remplit les fonctions suivantes requises par NIS2 :

- **Collecte centralisee des logs** : tous les systemes du SI envoient leurs evenements de securite a un point central.
- **Correlation des evenements** : la detection d'attaques implique souvent de croiser des evenements de sources differentes (echec d'authentification sur bastion01 + connexion reussie sur dc01 depuis la meme IP = lateral movement potentiel).
- **Retention des logs** : les logs doivent etre conserves suffisamment longtemps pour permettre une investigation post-incident (NIS2 ne fixe pas de duree, les guidelines ENISA recommandent 12 mois minimum pour les entites critiques).
- **Alertes et reponse** : le SIEM doit pouvoir declencher des alertes sur des patterns d'attaque connus.

Le contexte specifique de Nova Syndicate Phase II :

- **7 VMs a monitorer** : dc01, fs01, db01, app01, bastion01, backup01, et potentiellement les firewalls OPNsense via syslog.
- **Contrainte de ressources** : le SIEM tourne sur `app01` (une VM Proxmox). La memoire disponible pour Wazuh doit etre compatible avec les autres services sur app01 (Prometheus, Grafana).
- **Contexte formation AIS** : Wazuh est un outil open source reconnu dans l'industrie, avec une documentation de qualite et un ecosysteme de regles NIS2/CIS.
- **Integration avec le portfolio** : la configuration Wazuh (regles custom, agents) doit etre documentee et demonstrable lors de la soutenance.

## Decision

Adoption de **Wazuh 4.11.2** (version community open source) comme SIEM centralise.

**Architecture de deploiement :**

```
app01 (10.0.20.x) -- VLAN SERVERS
  +-- wazuh-manager    : serveur central, correlateur, indexer
  +-- wazuh-dashboard  : interface Kibana-based (port 443)
  +-- prometheus       : metriques systeme
  +-- grafana          : visualisation metriques
```

```
Agents Wazuh (port 1514/UDP ou 1514/TCP vers app01) :
  dc01, fs01, db01, bastion01, backup01
  OPNsense : syslog UDP/514 vers app01 (pas d'agent Wazuh natif FreeBSD)
```

**Fonctionnalites activees :**

- **File integrity monitoring (FIM)** : surveillance des fichiers critiques (`/etc/passwd`, `/etc/sudoers`, `/etc/ssh/sshd_config`, `/var/ossec/etc/`) sur toutes les VMs.
- **Rootcheck** : detection de rootkits et de configurations anormales.
- **Regles CIS** : audit de conformite CIS Benchmark via les modules de vulnerability detection.
- **Regles NIS2 custom** : regles Wazuh specifiques au perimetre NIS2 (authentification, acces root, modifications de politique de securite).
- **Alertes sur echecs d'authentification** : integration avec fail2ban via les logs d'audit.
- **Retention** : 90 jours dans le lab (contrainte disque), 365 jours comme objectif production.

**Justification du choix Wazuh :**

Wazuh est une plateforme SIEM open source issue du fork d'OSSEC. Elle combine :
- Un agent leger (C/C++, ~50 MB RAM) deployable sur toutes les distributions Linux.
- Un manager qui centralise la collecte, applique les regles et genere les alertes.
- Un indexer (OpenSearch/Elasticsearch) pour la recherche et la retention des logs.
- Un dashboard (Kibana-based) pour la visualisation et l'investigation.

La couverture des regles out-of-the-box est large (plus de 3000 regles par defaut) et couvre les cas d'usage NIS2 directement. Des "ruleset packs" NIS2 specifiques sont disponibles dans la documentation Wazuh.

Wazuh 4.x a remplace la dependance a Elasticsearch par OpenSearch (license Apache 2.0), eliminant le probleme de la license SSPL d'Elasticsearch.

**Regles NIS2 custom implementees (exemples) :**

```xml
<!-- Authentification SSH depuis IP non-bastion -->
<rule id="100001" level="12">
  <if_sid>5715</if_sid>
  <srcip>!10.0.15.0/29</srcip>
  <description>SSH login not via bastion - NIS2 21.f violation</description>
  <group>authentication,nis2</group>
</rule>

<!-- Modification de politique sshd_config -->
<rule id="100002" level="14">
  <if_sid>550</if_sid>
  <match>/etc/ssh/sshd_config</match>
  <description>sshd_config modified - NIS2 21.i policy change</description>
  <group>fim,nis2</group>
</rule>
```

## Alternatives considerees

### Elastic SIEM (Elasticsearch + Kibana + Fleet)

**Pour** :
- Elastic est le standard de facto pour les SIEMs open source.
- Ecosysteme tres riche : Beats (Filebeat, Auditbeat, Packetbeat), Elastic Agent, Fleet.
- Interface Kibana mature, visualisations avancees.
- Detection rules basees sur EQL (Event Query Language), tres expressif.
- Integrations natives avec de nombreuses sources de logs.

**Contre** :
- La license Elasticsearch a change en SSPL en 2021 (puis Basic License pour certains usages). La version self-hosted necessite une comprehension fine des licences pour eviter les violations.
- Consommation de ressources elevee : Elasticsearch requiert au minimum 4-8 GB de RAM pour une configuration stable. Sur `app01` (VM partagee), cela laisserait peu de place pour Prometheus et Grafana.
- La complexite de configuration est plus elevee que Wazuh pour obtenir les memes fonctionnalites de SIEM (alertes, FIM, rootcheck) : il faut assembler Elasticsearch + Kibana + Fleet + Detection Engine + custom rules.
- Wazuh offre "SIEM + agents + FIM + rootcheck + compliance" dans un package coherent, tandis qu'Elastic SIEM necessite d'assembler plusieurs composants.

### Splunk (version free)

**Pour** :
- Standard de l'industrie dans les grands comptes et les SOC.
- Langage SPL (Search Processing Language) tres puissant.
- Marketplace d'apps riche (CIM, Enterprise Security).
- Valeur portfolio elevee si on peut demontrer la maitrise de SPL.

**Contre** :
- Splunk Free limite l'ingestion a 500 MB/jour. Au-dela, les logs ne sont plus indexes. Pour un lab avec 7 agents qui generent des logs de securite detailles, 500 MB/jour peut etre atteint.
- Splunk est entierement proprieataire (Splunk Inc., racheite par Cisco en 2024). L'utilisation en production necessite une licence commerciale significative.
- Splunk Free n'a pas d'interface de configuration d'alertes native (alertes desactivees dans la version free).
- La version free ne supporte pas les Saved Searches automatisees ni le SOAR.
- La valeur pedagogique est reelle mais Splunk ne repond pas aux criteres d'un lab open source reproductible.

### Graylog (version community)

**Pour** :
- Graylog est specialise dans la gestion de logs (syslog, GELF). Interface claire.
- Version community open source (SSPL, mais gratuite pour usage non-commercial).
- Moins gourmand en ressources qu'Elasticsearch + Kibana pour les fonctionnalites de base.

**Contre** :
- Graylog est un agregateur de logs, pas un SIEM complet. Les fonctionnalites de correlation d'evenements, FIM, rootcheck et detection de vulnerabilites ne sont pas natives : elles necessitent des plugins supplementaires.
- Pas de notion d'agent Graylog (les agents systeme sont des outils tiers : rsyslog, Filebeat). La configuration de la collecte est plus fragmentee que Wazuh.
- La detection de patterns d'attaque (brute force, lateral movement) necessite un developpement de regles personnalisees en GELF Processing Pipeline, moins mature que les regles XML Wazuh.
- Graylog Enterprise est necessaire pour certaines fonctionnalites de conformite.

### Suricata standalone (sans SIEM)

**Pour** :
- Suricata est un IDS/IPS reseau tres performant, capable d'inspecter le trafic inter-VLAN.
- Signatures Suricata couvrent de nombreux patterns d'attaque reseau.
- Peut etre deploye sur OPNsense sans VM supplementaire.

**Contre** :
- Suricata est un IDS reseau, pas un SIEM. Il ne collecte pas les logs des systemes (connexions SSH, modifications de fichiers, processus) : seulement le trafic reseau.
- Suricata seul ne satisfait pas NIS2 Art. 21.f : la directive requiert un monitoring des systemes d'information, pas seulement du reseau.
- La correlation entre evenements reseau (Suricata) et evenements systeme (syslog) necessiterait un agregateur separE.
- Suricata en mode IPS inline sur OPNsense cree un point de defaillance unique sur le firewall.

### Collecte syslog manuelle (rsyslog central)

**Pour** :
- Extreme simplicite : rsyslog sur toutes les VMs, transfert vers un serveur central, stockage dans des fichiers.
- Pas de daemon supplementaire sur les VMs (rsyslog est deja installe sur Ubuntu).
- Pas de ressources supplementaires pour un serveur central lourd.

**Contre** :
- Pas de correlation d'evenements.
- Pas de FIM, pas de rootcheck.
- Pas d'interface de recherche et de visualisation.
- Les logs texte bruts dans des fichiers ne satisfont pas NIS2 Art. 21.f (necessite une capacite de detection et d'alerte, pas seulement de collecte).
- Pas de valeur portfolio : demontrer une collecte rsyslog lors d'une soutenance AIS n'est pas equivalent a demontrer une maitrise d'un SIEM.

## Consequences

**Positives :**
- Wazuh centralise les logs de toutes les VMs et d'OPNsense (via syslog), offrant une vue complete de l'infrastructure.
- Les regles FIM alertent immediatement sur les modifications de fichiers critiques, satisfaisant partiellement NIS2 Art. 21.f.
- Le dashboard Wazuh permet de demontrer visuellement la posture de securite lors de la soutenance.
- La retention de 90 jours dans le lab est suffisante pour les exercices d'investigation (drill T-RESTORE-DRILL, investigation d'incidents documentes).
- L'integration avec Prometheus/Grafana sur app01 (meme VM) permet de corrreler les evenements de securite avec les metriques systeme (pic CPU au moment d'une alerte = activite suspecte ?).

**Negatives et risques residuels :**
- **Consommation de ressources** : Wazuh manager + indexer (OpenSearch) consomme 2-4 GB de RAM en conditions normales. app01 doit avoir suffisamment de RAM pour cohabiter avec Prometheus et Grafana. Si la RAM est insuffisante, OpenSearch peut OOM-killer. Configuration necessaire : `vm.max_map_count=262144` via sysctl.
- **Complexite de maintenance** : Wazuh inclut plusieurs composants (manager, indexer, dashboard). Les mises a jour doivent etre coordonnees entre les composants pour eviter les incompatibilites. Les major upgrades (4.x -> 5.x) sont potentiellement destructifs.
- **Retention limitee en lab** : 90 jours est insuffisant pour une entite NIS2 reelle. La dette de retention (passage a 365 jours) necessite soit un disque plus grand sur app01, soit une exportation vers un stockage externe.
- **OPNsense via syslog uniquement** : les firewalls OPNsense (FreeBSD) ne peuvent pas executer l'agent Wazuh (compile pour Linux). La collecte des logs firewall passe par syslog UDP/514 vers app01. Cela est moins riche que la telemetrie agent (pas de FIM ni de rootcheck sur OPNsense).
- **Faux positifs** : les regles Wazuh par defaut generent des faux positifs dans un environnement de lab (activite normale d'Ansible interpretee comme suspecte, scans Prometheus comme brute force). Un tuning des seuils et des regles est necessaire mais chronophage.

## References

- Wazuh documentation : https://documentation.wazuh.com/
- Directive NIS2 Article 21 : https://eur-lex.europa.eu/legal-content/FR/TXT/?uri=CELEX%3A32022L2555
- ENISA NIS2 guidance : https://www.enisa.europa.eu/topics/cybersecurity-policy/nis-directive
- Configuration Wazuh agents : `ansible/roles/wazuh_agent/`
- Configuration Wazuh manager : `ansible/roles/app01/` (tasks wazuh)
- ADR-0014 (bastion Teleport) : `docs/adr/ADR-0014-bastion-teleport-mfa.md`
