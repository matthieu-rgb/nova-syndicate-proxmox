# AD Cleanup -- Groupes en doublon

## Date

2026-05-09

## Invariants avant

- Domaine : nova-syndicate.local (DC01 actif)
- Groupes total : 52
- Auth AD : OK

---

## CHECKPOINT 1 -- Inventaire complet

### IT_Admins (garder)

- dn : CN=IT_Admins,CN=Users,DC=nova-syndicate,DC=local
- Cree : 2026-05-07
- GUID : abd4cc62-0c4a-403b-809b-0ee5df91f131
- SID : S-1-5-21-161755245-968811667-3203788843-1103
- Description : Administrateurs infrastructure
- Membres (3) : admin-t0, admin-t1, admin-t2

### IT-Admins (doublon a supprimer)

- dn : CN=IT-Admins,CN=Users,DC=nova-syndicate,DC=local
- Cree : 2026-05-08
- GUID : 02ceb1c9-459e-4c9e-a55b-3a1cbb03b597
- SID : S-1-5-21-161755245-968811667-3203788843-1111
- Description : IT Administrators
- Membres (12) :
  - clara.fleury (OU=Marseille)
  - helene.legrand (OU=Lyon)
  - isabelle.lopez (OU=Agents)
  - arthur.mercier (OU=Agents)
  - quentin.robert (OU=Lyon)
  - patrick.roger (OU=Marseille)
  - mathilde.dumont (OU=Lyon)
  - camille.gauthier (OU=Lyon)
  - isabelle.gilles (OU=Lyon)
  - baptiste.roger (OU=Marseille)
  - Administrator (CN=Users)
  - jerome.schneider (OU=Lyon)

### Logistique (garder)

- dn : CN=Logistique,CN=Users,DC=nova-syndicate,DC=local
- Cree : 2026-05-07
- GUID : 4379df9e-d610-404a-905e-0e13d1834bc5
- SID : S-1-5-21-161755245-968811667-3203788843-1106
- Description : Equipe logistique
- Membres (0) : VIDE

### Logistics (doublon a supprimer)

- dn : CN=Logistics,CN=Users,DC=nova-syndicate,DC=local
- Cree : 2026-05-08
- GUID : b4ad3e83-bc41-498e-8a43-d13d367fac8d
- SID : S-1-5-21-161755245-968811667-3203788843-1117
- Description : Departement Logistique
- Membres (19) :
  - quentin.dumont, claire.lambert, clara.simon, philippe.fontaine
  - laurent.vincent, helene.francois, helene.boyer, mathilde.remy
  - sophie.poirier, caroline.muller, claire.joly, nathalie.lefebvre
  - nathalie.joly, marine.muller, manon.dupont, cedric.chevalier
  - aurelie.muller, lucas.morin, isabelle.fernandez

### Commerciaux (garder)

- dn : CN=Commerciaux,CN=Users,DC=nova-syndicate,DC=local
- Cree : 2026-05-07
- GUID : 0c8b4ba3-6a8e-47fe-ba7b-d10151398a4b
- SID : S-1-5-21-161755245-968811667-3203788843-1105
- Description : Equipe commerciale et agents distants
- Membres (0) : VIDE

### Sales (doublon a supprimer)

- dn : CN=Sales,CN=Users,DC=nova-syndicate,DC=local
- Cree : 2026-05-08
- GUID : abb53ec7-81fd-4958-afa4-ef1ab64f4c67
- SID : S-1-5-21-161755245-968811667-3203788843-1116
- Description : Departement Commercial
- Membres (19) :
  - lucie.lefevre, sebastien.guerin, sebastien.lemaire, thomas.garcia
  - cedric.dubois, charles.morel, sebastien.colin, clement.gilles
  - marie.vincent, gaetan.morin, lucie.richard, camille.roger
  - fabien.bonnet, romain.garnier, florian.michel, david.roussel
  - kevin.michel, pauline.poirier, elodie.david

---

## ALERTE -- IT-Admins / IT_Admins : PAS des doublons fonctionnels

Les groupes IT_Admins et IT-Admins ont des fonctions DIFFERENTES :

| Groupe | Role reel | Membres |
|--------|-----------|---------|
| IT_Admins | Admins infra tiers (T0/T1/T2) | admin-t0, admin-t1, admin-t2 |
| IT-Admins | Groupe d'acces aux shares SMB | 12 users metiers + Administrator |

IT-Admins est reference dans /etc/samba/smb.conf sur FS01 :

```
[lyon]        valid users = @Lyon-Staff @IT-Admins  /  write list = @Lyon-Staff @IT-Admins
[marseille]   valid users = @Marseille-Staff @IT-Admins  /  write list = ...
[commun]      valid users = @"Domain Users" @IT-Admins  /  write list = @IT-Admins
[finance]     valid users = @Finance @IT-Admins  /  write list = @Finance @IT-Admins
[it-restricted] valid users = @IT-Admins  /  write list = @IT-Admins (SEUL groupe autorise)
```

Consequence de la suppression sans action complementaire :
- Les 12 users IT-Admins perdent acces a tous les shares SMB
- [it-restricted] devient inaccessible (plus aucun groupe valide)

Strategie requise avant suppression IT-Admins :
- Option A : Mettre a jour smb.conf sur FS01 (@IT-Admins -> @IT_Admins) + migrer les 12 users dans IT_Admins
- Option B : Renommer IT-Admins en IT_Admins via LDAP (mais IT_Admins existe deja)
- Option C : Creer un 3eme groupe (ex: Share-Admins) pour les 12 users dans smb.conf

Decision requise par l'operateur.

---

## Plan de migration (groupes sans risque : Logistique + Commerciaux)

Ces 2 paires sont de vrais doublons (FR vide, EN avec membres, aucune ref smb.conf).
Migration propre possible sans impact.

| Migration | Membres a ajouter | Risque smb.conf |
|-----------|-------------------|-----------------|
| Logistics -> Logistique | 19 users | Aucun |
| Sales -> Commerciaux | 19 users | Aucun |

---

---

## REVISION STRATEGIQUE -- 2026-05-09 (post-analyse smb.conf)

### Findings Phase 1 etendue

| Verification | Resultat |
|---|---|
| samba-tool group rename | SUPPORTE (renomme sAMAccountName + CN) |
| smb.conf refs @Logistics | AUCUNE |
| smb.conf refs @Sales | AUCUNE |
| smb.conf refs @Logistique | AUCUNE |
| smb.conf refs @Commerciaux | AUCUNE |
| smb.conf refs @IT-Admins | 5 shares references |

### Plan valide par operateur -- en attente GO

#### Cas 1 : IT-Admins / IT_Admins

Strategie : RENOMMER IT-Admins en FS-IT-Users (clarte semantique).
IT_Admins reste inchange (3 admins infra).

Etapes :
1. Backup smb.conf : sudo cp /etc/samba/smb.conf /etc/samba/smb.conf.bak-$(date +%Y%m%d-%H%M)
2. Rename AD : sudo samba-tool group rename "IT-Admins" --samaccountname="FS-IT-Users"
3. Patch smb.conf : sudo sed -i 's/@IT-Admins/@FS-IT-Users/g' /etc/samba/smb.conf
4. Reload : sudo systemctl reload smbd
5. Verifier shares et members via wbinfo

Aucune suppression de groupe. Aucune migration de membres.

#### Cas 2 : Logistique (vide) / Logistics (19 membres) -- aucun ref smb.conf

Strategie : MIGRATION membres + DELETE Logistics.
Rename impossible car Logistique existe deja.

Etapes :
1. addmembers x19 de Logistics vers Logistique (idempotent)
2. Verifier que Logistique a bien 19 membres
3. Delete Logistics

#### Cas 3 : Commerciaux (vide) / Sales (19 membres) -- aucun ref smb.conf

Meme strategie que Cas 2.

1. addmembers x19 de Sales vers Commerciaux (idempotent)
2. Verifier que Commerciaux a bien 19 membres
3. Delete Sales

### Invariants apres

- Groupes total : 52 - 2 = 50 (IT-Admins renomme pas supprime, Logistics + Sales supprimes)
- IT_Admins : 3 membres inchanges
- FS-IT-Users : 12 membres (ex-IT-Admins)
- Logistique : 19 membres (ex-Logistics)
- Commerciaux : 19 membres (ex-Sales)
- smb.conf FS01 : @FS-IT-Users dans les 5 shares
- Auth AD : toujours fonctionnelle

---

## EXECUTION -- 2026-05-09

### Phase A -- Backup smb.conf

```
/etc/samba/smb.conf.bak-20260509-2225 cree sur FS01
```

### Phase B -- IT-Admins renomme en FS-IT-Users

| Etape | Resultat |
|-------|---------|
| samba-tool group rename IT-Admins --samaccountname=FS-IT-Users | OK -- CN + sAMAccountName renommes |
| SID preserve | S-1-5-21-161755245-968811667-3203788843-1111 (inchange) |
| Membres apres rename | 12/12 OK |
| smb.conf patch (sed) | 10 occurrences remplacees (5 shares x 2 lignes) |
| testparm | Loaded services file OK |
| systemctl reload smbd nmbd | OK |
| smbclient -L localhost | lyon, marseille, commun visibles (finance/it-restricted = browseable=no) |
| wbinfo -n FS-IT-Users | SID 1111 retourne |
| wbinfo -r clara.fleury | GID 21112 (RID 1111 via idmap_rid) confirme |

### Phase C -- Logistics -> Logistique

| Etape | Resultat |
|-------|---------|
| Membres Logistics captures | 19 users |
| addmembers Logistique x19 | 19/19 OK |
| Logistique count post-migration | 19 |
| samba-tool group delete Logistics | Deleted |
| Validation group list | Logistique present, Logistics absent |

### Phase D -- Sales -> Commerciaux

| Etape | Resultat |
|-------|---------|
| Membres Sales captures | 19 users |
| addmembers Commerciaux x19 | 19/19 OK |
| Commerciaux count post-migration | 19 |
| samba-tool group delete Sales | Deleted |
| Validation group list | Commerciaux present, Sales absent |

### Phase E -- Validation finale

| Invariant | Avant | Apres | OK |
|-----------|-------|-------|----|
| Total groupes | 52 | 50 | OK |
| Domaine actif | yes | yes | OK |
| wbinfo --domain-info | OK | OK | OK |
| Wazuh agents Active | 7 | 7 | OK |
| IT_Admins membres | 3 | 3 | OK (inchange) |
| FS-IT-Users membres | - | 12 | OK |
| Logistique membres | 0 | 19 | OK |
| Commerciaux membres | 0 | 19 | OK |

---

## ROLLBACK -- Procedure si necessaire

### Rollback IT-Admins (rename inverse)

```bash
# Sur DC1
sudo samba-tool group rename "FS-IT-Users" --samaccountname="IT-Admins"

# Sur FS01
sudo cp /etc/samba/smb.conf.bak-20260509-2225 /etc/samba/smb.conf
sudo systemctl reload smbd nmbd
```

### Rollback Logistics

```bash
# Sur DC1 -- recreer Logistics et remettre les 19 membres
sudo samba-tool group add Logistics --description="Departement Logistique"
for user in quentin.dumont claire.lambert clara.simon philippe.fontaine \
  laurent.vincent helene.francois helene.boyer mathilde.remy \
  sophie.poirier caroline.muller claire.joly nathalie.lefebvre \
  nathalie.joly marine.muller manon.dupont cedric.chevalier \
  aurelie.muller lucas.morin isabelle.fernandez; do
  sudo samba-tool group addmembers Logistics $user
done
# Optionnel : retirer ces membres de Logistique si souhaite
```

### Rollback Sales

```bash
# Sur DC1 -- recreer Sales et remettre les 19 membres
sudo samba-tool group add Sales --description="Departement Commercial"
for user in lucie.lefevre sebastien.guerin sebastien.lemaire thomas.garcia \
  cedric.dubois charles.morel sebastien.colin clement.gilles \
  marie.vincent gaetan.morin lucie.richard camille.roger \
  fabien.bonnet romain.garnier florian.michel david.roussel \
  kevin.michel pauline.poirier elodie.david; do
  sudo samba-tool group addmembers Sales $user
done
```

Note : les nouveaux groupes Logistics/Sales auront des SIDs differents
des originaux supprimes (SIDs non recuperables).

---

## STATUT : COMPLETE -- 2026-05-09
