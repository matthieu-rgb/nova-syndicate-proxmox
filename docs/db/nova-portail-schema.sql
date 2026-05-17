CREATE DATABASE IF NOT EXISTS nova_portail
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE nova_portail;

DROP TABLE IF EXISTS devis_lignes;
DROP TABLE IF EXISTS devis;
DROP TABLE IF EXISTS audit_consultations;
DROP TABLE IF EXISTS clients;
DROP TABLE IF EXISTS tarifs;

CREATE TABLE tarifs (
  id INT PRIMARY KEY AUTO_INCREMENT,
  reference VARCHAR(50) UNIQUE NOT NULL,
  libelle VARCHAR(255) NOT NULL,
  description TEXT,
  categorie ENUM('medical','aerospace','defense','standard') NOT NULL,
  unite ENUM('piece','kg','m3','heure','jour','mois','forfait') NOT NULL,
  prix_ht DECIMAL(10,2) NOT NULL,
  tva DECIMAL(4,2) DEFAULT 20.00,
  delai_jours INT DEFAULT 1,
  certifications TEXT,
  date_creation TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  date_modif TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  actif BOOLEAN DEFAULT TRUE,
  INDEX idx_categorie (categorie),
  INDEX idx_reference (reference)
) ENGINE=InnoDB;

CREATE TABLE clients (
  id INT PRIMARY KEY AUTO_INCREMENT,
  raison_sociale VARCHAR(255) NOT NULL,
  siret VARCHAR(14) UNIQUE,
  secteur ENUM('medical','aerospace','defense','industriel','public') NOT NULL,
  adresse_ligne1 VARCHAR(255),
  adresse_ligne2 VARCHAR(255),
  code_postal VARCHAR(5),
  ville VARCHAR(100),
  pays VARCHAR(50) DEFAULT 'France',
  email_contact VARCHAR(255),
  telephone VARCHAR(20),
  habilitation_defense BOOLEAN DEFAULT FALSE,
  date_creation TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  actif BOOLEAN DEFAULT TRUE,
  INDEX idx_secteur (secteur)
) ENGINE=InnoDB;

CREATE TABLE devis (
  id INT PRIMARY KEY AUTO_INCREMENT,
  numero VARCHAR(20) UNIQUE NOT NULL,
  client_id INT NOT NULL,
  date_emission TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  date_validite DATE NOT NULL,
  montant_ht DECIMAL(12,2) NOT NULL,
  montant_ttc DECIMAL(12,2) NOT NULL,
  statut ENUM('brouillon','envoye','accepte','refuse','expire') DEFAULT 'brouillon',
  user_ad_createur VARCHAR(100),
  notes TEXT,
  FOREIGN KEY (client_id) REFERENCES clients(id),
  INDEX idx_statut (statut)
) ENGINE=InnoDB;

CREATE TABLE devis_lignes (
  id INT PRIMARY KEY AUTO_INCREMENT,
  devis_id INT NOT NULL,
  tarif_id INT NOT NULL,
  quantite DECIMAL(10,2) NOT NULL,
  prix_unitaire_ht DECIMAL(10,2) NOT NULL,
  remise_pourcent DECIMAL(5,2) DEFAULT 0,
  total_ht DECIMAL(12,2) NOT NULL,
  FOREIGN KEY (devis_id) REFERENCES devis(id) ON DELETE CASCADE,
  FOREIGN KEY (tarif_id) REFERENCES tarifs(id)
) ENGINE=InnoDB;

CREATE TABLE audit_consultations (
  id INT PRIMARY KEY AUTO_INCREMENT,
  user_ad VARCHAR(100) NOT NULL,
  user_groups TEXT,
  timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  action VARCHAR(50) NOT NULL,
  resource_type VARCHAR(50),
  resource_id INT,
  ip_source VARCHAR(45),
  user_agent TEXT,
  INDEX idx_user (user_ad),
  INDEX idx_timestamp (timestamp)
) ENGINE=InnoDB;

INSERT INTO tarifs (reference, libelle, description, categorie, unite, prix_ht, delai_jours, certifications) VALUES
('MED-001', 'Livraison express 24h dispositif medical', 'Transport sous temperature controlee 2-8 deg C, tracabilite GPS continue', 'medical', 'piece', 145.00, 1, 'ISO 13485, GDP'),
('MED-002', 'Stockage frigorifique 2-8 deg C', 'Espace certifie pharmaceutique, sondes calibrees', 'medical', 'm3', 89.00, 1, 'ISO 13485'),
('MED-003', 'Transport cryogenique echantillons -80 deg C', 'Containers azote liquide, autonomie 72h', 'medical', 'piece', 320.00, 2, 'ISO 13485, NF S99-170'),
('MED-004', 'Logistique implants chirurgicaux', 'Stockage sterile, livraison J0 si dispo', 'medical', 'piece', 89.00, 1, 'ISO 13485, MDR EU'),
('MED-005', 'Transport organes (urgence)', 'Service prioritaire 24/7, escorte', 'medical', 'forfait', 2450.00, 1, 'Agreement EFG'),
('MED-006', 'Stockage produits radiopharmaceutiques', 'Caisson plombe, agrement ASN', 'medical', 'mois', 1850.00, 7, 'ASN, INB'),
('MED-007', 'Distribution medicaments hopital', 'Tournee H+4, tracabilite lot', 'medical', 'jour', 480.00, 1, 'BPDG'),
('MED-008', 'Transport dispositifs implantables', 'IIa/IIb/III, conformite MDR', 'medical', 'piece', 175.00, 2, 'MDR EU 2017/745'),
('MED-009', 'Livraison vaccins chaine du froid', 'Containers passifs valides 96h', 'medical', 'piece', 65.00, 1, 'OMS PQS'),
('MED-010', 'Transport equipements imagerie medicale', 'Manutention specialisee anti-vibration', 'medical', 'forfait', 4200.00, 5, 'IRM/SCANNER'),
('AERO-001', 'Transport composants moteur aviation civile', 'Conditionnement ESD, tracabilite Part 145', 'aerospace', 'piece', 285.00, 3, 'EASA Part 145, AS9120'),
('AERO-002', 'Livraison pieces aeronautiques certifiees', 'Documentation 8130-3 ou EASA Form 1', 'aerospace', 'piece', 195.00, 2, 'AS9120'),
('AERO-003', 'Stockage composants satellite', 'Salle propre ISO 8, controle humidite', 'aerospace', 'm3', 425.00, 1, 'ISO 8'),
('AERO-004', 'Transport capteurs embarques', 'Conditionnement anti-statique, blindage EMI', 'aerospace', 'piece', 145.00, 2, 'AS9100'),
('AERO-005', 'Logistique sous-ensembles structuraux', 'Manutention specialisee anti-vibration', 'aerospace', 'piece', 580.00, 4, 'AS9100, NADCAP'),
('AERO-006', 'Stockage carburants speciaux aviation', 'Cuves ATEX, ventilation', 'aerospace', 'm3', 320.00, 1, 'ATEX'),
('AERO-007', 'Transport equipements avionique', 'Cage Faraday, traceurs GPS', 'aerospace', 'piece', 240.00, 2, 'DO-160'),
('AERO-008', 'Distribution pieces maintenance aeronefs', 'Hub Lyon-St Exupery + Marignane', 'aerospace', 'jour', 750.00, 1, 'EASA Part 145'),
('DEF-001', 'Transport conteneur defense classifie', 'Escorte armee, GPS chiffre', 'defense', 'forfait', 8950.00, 5, 'IGI 1300, SECRET'),
('DEF-002', 'Stockage equipements habilites CD', 'Zone sous habilitation Confidentiel Defense', 'defense', 'm3', 580.00, 1, 'CD'),
('DEF-003', 'Distribution composants electroniques militaires', 'MIL-STD-883, conditionnement renforce', 'defense', 'piece', 425.00, 3, 'MIL-STD-883'),
('DEF-004', 'Transport materiel HABILITATION SD', 'Convoi habilite, double validation', 'defense', 'forfait', 12500.00, 7, 'IGI 1300, SD'),
('DEF-005', 'Logistique pieces detachees vehicules blindes', 'Stockage zone protegee', 'defense', 'piece', 320.00, 4, 'IGI 1300'),
('DEF-006', 'Stockage munitions inertes', 'Soutes ATEX, controle d acces', 'defense', 'm3', 1250.00, 1, 'IGI 1300, ATEX'),
('DEF-007', 'Transport equipements communication chiffrement', 'Chiffrement physique, escorte', 'defense', 'piece', 1850.00, 5, 'ANSSI, IGI 1300'),
('STD-001', 'Transport standard palette Europe', 'Livraison J+1, suivi colis', 'standard', 'piece', 38.00, 1, ''),
('STD-002', 'Stockage entrepot standard', 'Aire couverte, gardiennage 24/7', 'standard', 'm3', 24.00, 1, ''),
('STD-003', 'Livraison express 24h national', 'Service prioritaire', 'standard', 'forfait', 95.00, 1, ''),
('STD-004', 'Transport longue distance routier', 'Tracteur + remorque, 2 conducteurs', 'standard', 'jour', 480.00, 1, ''),
('STD-005', 'Stockage securise standard', 'Acces controle, video 24/7', 'standard', 'mois', 145.00, 1, '');

INSERT INTO clients (raison_sociale, siret, secteur, adresse_ligne1, code_postal, ville, email_contact, telephone, habilitation_defense) VALUES
('Centre Hospitalier Lyon Sud', '26690000001234', 'medical', '165 Chemin du Grand Revoyet', '69310', 'Pierre-Benite', 'logistique@chu-lyon.fr', '+33472678000', FALSE),
('Sanofi Pasteur Marcy l Etoile', '67301000005678', 'medical', '1541 Avenue Marcel Merieux', '69280', 'Marcy l Etoile', 'achats@sanofi.com', '+33437370101', FALSE),
('AP-HM Marseille', '26130000009012', 'medical', '264 Rue Saint-Pierre', '13005', 'Marseille', 'centrale-achats@ap-hm.fr', '+33491384000', FALSE),
('Boiron Laboratoires', '95781111111234', 'medical', '2 Avenue de l Ouest Lyonnais', '69510', 'Messimy', 'logistique@boiron.fr', '+33478566800', FALSE),
('bioMerieux Marcy', '67301000005679', 'medical', '376 Chemin de l Orme', '69280', 'Marcy l Etoile', 'supply-chain@biomerieux.com', '+33478876000', FALSE),
('Airbus Helicopters Marignane', '38128571111234', 'aerospace', 'Aeroport Marseille-Provence', '13725', 'Marignane', 'logistique@airbus.com', '+33442853333', FALSE),
('Safran Aircraft Engines Villaroche', '38068111111234', 'aerospace', 'Rond-Point Rene Ravaud', '77550', 'Reau', 'achats@safran-aircraft-engines.com', '+33160598200', FALSE),
('Thales Alenia Space Cannes', '34141422228765', 'aerospace', '100 Boulevard du Midi', '06150', 'Cannes', 'logistique@thalesaleniaspace.com', '+33492926000', FALSE),
('ArianeGroup Les Mureaux', '41977888889876', 'aerospace', '78 Rue Verdun', '78130', 'Les Mureaux', 'achats@ariane.group', '+33134881000', FALSE),
('Daher Aerospace Saint-Nazaire', '34141111114321', 'aerospace', 'Boulevard de l Atlantique', '44600', 'Saint-Nazaire', 'logistique@daher.com', '+33240007000', FALSE),
('DGA Maitrise NRBC Vert le Petit', '11000601000017', 'defense', '5 Rue Lavoisier', '91710', 'Vert-le-Petit', 'logistique@intradef.gouv.fr', '+33169908900', TRUE),
('Naval Group Lorient', '54110111114567', 'defense', '40-42 Rue du Bac', '75007', 'Paris', 'achats@naval-group.com', '+33140597070', TRUE),
('MBDA Le Plessis-Robinson', '34022711118901', 'defense', '1 Avenue Reaumur', '92350', 'Le Plessis-Robinson', 'logistique@mbda-systems.com', '+33171544000', TRUE),
('Nexter Versailles Satory', '38080711115432', 'defense', '13 Route de la Miniere', '78034', 'Versailles', 'achats@nexter-group.fr', '+33130979400', TRUE),
('Ministere des Armees', '11000201100074', 'public', '60 Boulevard du General Martial Valin', '75509', 'Paris', 'sga.sphere-economique@def.gouv.fr', '+33144421515', FALSE);

FLUSH PRIVILEGES;

SELECT 'Tarifs:' AS info, COUNT(*) AS count FROM tarifs
UNION ALL
SELECT 'Clients:', COUNT(*) FROM clients;


-- ===========================================================================
-- Utilisateur applicatif (a creer separement avec un mot de passe vault-ed)
-- ===========================================================================
-- CREATE USER 'nova_portail'@'192.168.20.13' IDENTIFIED BY '<vault portail_db_password>';
-- GRANT SELECT, INSERT, UPDATE ON nova_portail.* TO 'nova_portail'@'192.168.20.13';
-- FLUSH PRIVILEGES;
