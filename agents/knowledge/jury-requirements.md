# Knowledge Base : Exigences jury RNCP37680 + Nova Syndicate

Base de connaissances de reference pour la production du dossier projet et des
livrables jury. Source : referentiel AIS RNCP37680, modalites d'evaluation Jedha,
cahier des charges Nova Syndicate, cours BCP/DRP et conformite (NIS2, RGPD).

## 1. Referentiel AIS RNCP37680 (Niveau 6)

Titre "Administrateur d'Infrastructures Securisees" (AIS), niveau 6 (bac+3/4).
3 CCP regroupant 10 competences professionnelles (CP).

- **CCP1 -- Administrer et securiser les infrastructures**
  - CP1 : appliquer les bonnes pratiques d'administration securisee
  - CP2 : administrer et securiser les reseaux
  - CP3 : administrer et securiser les systemes
  - CP4 : administrer et securiser les infrastructures virtualisees
- **CCP2 -- Concevoir et mettre en oeuvre une solution d'evolution de l'infrastructure**
  - CP5 : concevoir une solution d'evolution
  - CP6 : mettre en production une solution
  - CP7 : superviser l'infrastructure
- **CCP3 -- Participer a la gestion de la cybersecurite**
  - CP8 : mesurer et analyser le niveau de securite
  - CP9 : contribuer a la politique de securite (PSSI, conformite)
  - CP10 : detecter et traiter les incidents de securite

## 2. Modalites d'evaluation jury

- Mode formation : projet realise dans le cadre de la formation.
- Presentation orale : 40 minutes.
- Entretien technique : 1 heure.
- Temps total devant le jury : 2 heures.
- Le dossier projet est imprime et le jury y a acces AVANT la presentation.

## 3. Structure du dossier projet (mode formation)

Pour chaque projet realise dans le cadre de la formation :

- Liste des competences mises en oeuvre dans le cadre du projet.
- Expression des besoins du projet.
- Environnement technique.
- Realisations permettant la mise en oeuvre des competences obligatoires.

## 4. Structure de la presentation orale

- Presentation de l'entreprise et du service.
- Cahier des charges, contraintes, livrables attendus.
- Solution retenue (criteres d'evaluation, argumentation des choix).
- Specifications techniques (avec schema d'infrastructure).
- Presentation de la mise en oeuvre.
- Synthese et conclusion.

## 5. Cahier des charges Nova Syndicate

### Contexte

- ESN logistique, 85 employes (40 Lyon, 25 Marseille, 20 agents distants).
- Secteurs servis : medical, aerospatial, defense.
- Siege a Lyon, bureau regional a Marseille.
- Chiffre d'affaires : 48 M EUR.

### Objectifs generaux (section 4.1)

Le futur systeme doit etre : centralise, virtualise, securise, evolutif (scalable),
resilient, automatise.

### Exigences fonctionnelles (sections 5.1 a 5.7)

- 5.1 IAM : Active Directory ou LDAP, utilisateurs groupes par role, acces base sur
  les roles, acces VPN pour les agents distants.
- 5.2 Services de fichiers : serveur de fichiers structure par departement,
  versioning et sauvegarde.
- 5.3 Base de donnees : MySQL / PostgreSQL / MSSQL, acces restreint et supervise,
  sauvegardes planifiees et verifiees.
- 5.4 Virtualisation : minimum 4 VMs (DC + File + SQL + App reservee).
- 5.5 Supervision : CPU / memoire / disque + uptime des services + connectivite reseau.
- 5.6 BCP + DRP avec RTO/RPO + sauvegardes automatisees stockees de maniere securisee.
- 5.7 Automatisation : au minimum 1 script admin (creation d'utilisateurs depuis un
  CSV OU supervision d'un seuil disque).

### Exigences non-fonctionnelles (section 6)

- Tout doit etre documente et reproductible.
- Open source prefere.
- Linux ou Windows Server accepte.
- Maintenable par une petite equipe IT.
- Approche pragmatique, sans surdimensionnement (no overengineering).

### Contraintes (section 7)

- Reseaux physiques separes Lyon / Marseille (pas de lien direct).
- Agents distants via VPN ou passerelle securisee.
- Pas de cloud (mais la cloud-readiness est un plus).
- Budget licence limite, standards ouverts preferes.

### Livrables (section 8)

- Phase 1 : synthese + esquisse d'architecture proposee.
- Phase 2 : diagramme d'architecture + rapport de conception technique + captures / demo.
- Phase 3 : BCP + DRP + mise en place de la supervision + scripts d'automatisation
  (commentes).

## 6. BCP / DRP -- structure attendue (cours Jedha)

### Plan de Continuite d'Activite (PCA / BCP)

1. Introduction et objectifs (portee, fonctions critiques).
2. Analyse d'Impact sur l'Activite (AIA / BIA).
3. Plan de communication (contacts d'urgence, chemins d'escalade).
4. Procedures de continuite operationnelle (travail a distance, alternatives).
5. Formation et tests (calendrier, scenarios).

### Plan de Reprise apres Sinistre (PRS / DRP)

1. Vue d'ensemble et perimetre (systemes / services couverts).
2. Equipe de reponse a incident (roles, responsabilites, contacts).
3. Procedures de restauration (etape par etape, prerequis materiel / logiciel).
4. Sauvegarde et restauration des donnees (emplacements, types, processus).
5. Strategies de bascule et de retour (triggers definis).
6. Tests et validation (tests reguliers).

### RTO / RPO

- RTO (Recovery Time Objective) : duree d'arret acceptable, du sinistre a la
  restauration complete.
- RPO (Recovery Point Objective) : volume de donnees acceptable de perdre, soit
  l'intervalle entre deux sauvegardes.
- Exemples cibles Nova :
  - AD (dc01) : RTO 4h / RPO 1h
  - File server (fs01) : RTO 4h / RPO 1h
  - Base de donnees (db01) : RTO 2h / RPO 15 min
  - Supervision (app01) : RTO 8h / RPO 1h

## 7. Quatre piliers du design d'infrastructure (cours Jedha)

- Disponibilite (availability)
- Securite (security)
- Evolutivite (scalability)
- Maintenabilite (maintainability)

## 8. NIS2 article 21 -- mesures techniques attendues

- Controle d'acces et RBAC.
- Segmentation reseau.
- Supervision et journalisation (logging).
- Sauvegarde.
- Reponse a incident (NIS2 art.23 pour la notification).
- Chiffrement au repos et en transit.
- Separation des taches (separation of duties, role d'audit).
- Authentification multi-facteurs (MFA).
- Securite de la chaine d'approvisionnement (supply chain).

## 9. RGPD article 32 -- securite des traitements

- Pseudonymisation et chiffrement.
- Confidentialite, integrite, disponibilite, resilience des traitements.
- Capacite a retablir l'acces aux donnees dans des delais appropries.
- Procedure de test, d'analyse et d'evaluation reguliere de l'efficacite des mesures.
- Mesures proportionnees au risque.
