# NIGHT-INCIDENT -- 2026-05-09 21:17:46

## RESOLU -- 2026-05-09 21:22

Incident resolu. Voir INCIDENT-IPSEC-RECOVERY.md pour le rapport complet.
- IPsec : 4/4 tunnels INSTALLED
- Wazuh : 7/7 agents Active
- NIGHT-INCIDENT.md genere par health-check pendant la recovery, avant resolution complete.

---

## Detecte par

health-check.sh

## Symptome (contexte au moment de la generation)

78112723-0176-40d8-905f-1c187aaf58b3: #1, ESTABLISHED, IKEv2, 3b8284263f0f255e_i* 369c31d8dfe0aa26_r
  local  '10.0.0.2' @ 10.0.0.2[500]
  remote '10.0.2.2' @ 10.0.2.2[500]
  AES_GCM_16-256/PRF_HMAC_SHA2_256/MODP_2048
  established 93s ago, rekeying in 84858s
  4bbf5017-9416-4332-8551-a0d9e77990f8: #5, reqid 1, INSTALLED, TUNNEL, ESP:AES_CBC-256/HMAC_SHA2_256_128/MODP_2048
    installed 71s ago, rekeying in 3227s, expires in 3889s
    in  ca9d0817,    504 bytes,     6 packets,    34s ago
    out c95016bd,    936 bytes,     6 packets,    34s ago
    local  192.168.20.0/28
    remote 192.168.40.0/26
  1856ee5d-842a-4008-a917-bafbfcf50072: #6, reqid 2, INSTALLED, TUNNEL, ESP:AES_CBC-256/HMAC_SHA2_256_128/MODP_2048
    installed 71s ago, rekeying in 3384s, expires in 3889s
    in  cc739425,      0 bytes,     0 packets,    70s ago
    out cacabb75,      0 bytes,     0 packets
    local  192.168.15.0/29
    remote 192.168.40.0/26
  1a71c717-2f3e-4006-99b4-5f786880c64b: #7, reqid 3, INSTALLED, TUNNEL, ESP:AES_CBC-256/HMAC_SHA2_256_128/MODP_2048
    installed 71s ago, rekeying in 3188s, expires in 3889s
    in  c3687159,      0 bytes,     0 packets,    70s ago
    out c562332d,      0 bytes,     0 packets
    local  192.168.30.0/26
    remote 192.168.40.0/26
  120d04c8-4353-4854-a95f-df0b1459b9d9: #8, reqid 4, INSTALLED, TUNNEL, ESP:AES_CBC-256/HMAC_SHA2_256_128/MODP_2048
    installed 71s ago, rekeying in 3269s, expires in 3889s
    in  ce80b187,      0 bytes,     0 packets,    70s ago
    out c793a6fb,      0 bytes,     0 packets
    local  192.168.50.0/29
    remote 192.168.40.0/26

Terraform output:
opnsense_interfaces_vlan.fwint_vlan20_servers: Refreshing state... [id=a0496db4-0bae-495d-89d2-57bce446c73b]
opnsense_firewall_filter.fwint_backup_block_all: Refreshing state... [id=ac3427cc-0011-447c-bcf3-a00e76c7329a]
opnsense_firewall_filter.fwint_wan_ipsec_decapsulated: Refreshing state... [id=11642651-920e-4a31-b4d5-fc6d2b216411]
opnsense_interfaces_vlan.fwint_vlan30_users: Refreshing state... [id=33b417cf-cc48-4ad7-99cf-979f4c9ceb7f]
opnsense_interfaces_vlan.fwint_vlan15_bastion: Refreshing state... [id=e1e3d310-dc01-4b72-b1bf-5aea14b66d4a]
opnsense_firewall_filter.fwint_bastion_to_dc_ad_udp: Refreshing state... [id=6cf41cac-7eb1-4298-9e72-2787d1ed9d29]
opnsense_firewall_filter.fwint_users_to_dc_ad_udp: Refreshing state... [id=7ced8432-29e5-4453-b544-00c26ed8f536]
opnsense_firewall_filter.fwint_bastion_to_servers_ssh: Refreshing state... [id=512f9592-3335-4d25-8324-0f60bdf399d2]
opnsense_firewall_filter.fwint_backup_to_servers_ssh: Refreshing state... [id=5e718e38-555a-47e4-a073-2e0fcafcba5a]
opnsense_firewall_filter.fwint_backup_to_internet: Refreshing state... [id=502bd253-40c2-4049-8252-34812c3f698b]
opnsense_firewall_filter.fwint_users_block_all: Refreshing state... [id=17883b5f-459d-454a-b520-206de0766b47]
opnsense_firewall_filter.fwint_servers_to_internet: Refreshing state... [id=7c8e2113-a17e-4f53-bb32-6649f2847cca]
opnsense_firewall_filter.fwint_wan_block_all: Refreshing state... [id=730f9aeb-83c3-4aee-bd99-7871da4dd08a]
opnsense_firewall_filter.fwint_users_to_internet: Refreshing state... [id=435d8df8-ef2d-4bbb-8f07-38f0db216720]
opnsense_firewall_filter.fwint_servers_block_all: Refreshing state... [id=b19da746-376d-4640-9639-6738c210923f]
opnsense_firewall_filter.fwint_users_to_dc_ad_tcp: Refreshing state... [id=597fe853-bf9a-45ee-9a21-d8007eb5377f]
opnsense_interfaces_vlan.fwint_vlan50_backup: Refreshing state... [id=bec0dcca-e45a-4111-b11d-6ad2e2e78021]
opnsense_firewall_filter.fwint_bastion_to_dc_ad_tcp: Refreshing state... [id=e934d579-ba12-41cd-89e7-ccf4f64f5e54]
opnsense_firewall_alias.fwint_network["net_lyon_users"]: Refreshing state... [id=a8cb771c-6a98-4797-8dad-1d32b99f13f4]
opnsense_firewall_alias.fwint_network["net_lyon_bastion"]: Refreshing state... [id=b71e415a-af3f-426c-a25a-13845fec74e0]
opnsense_firewall_alias.fwint_network["net_lyon_backup"]: Refreshing state... [id=c8d07f01-177d-46ae-a51a-c687cc1262df]
opnsense_firewall_alias.fwint_network["net_lyon_servers"]: Refreshing state... [id=6094bdac-e348-4297-a454-5c9b2cc2542f]
opnsense_firewall_alias.fwint_network["net_lyon_internal"]: Refreshing state... [id=e35c88d6-9060-48cb-af1c-932d0123f15c]
opnsense_firewall_alias.fwint_network["net_lan_mrs"]: Refreshing state... [id=438f5123-2952-4001-b223-fd768108d1dd]
opnsense_firewall_filter.fwint_bastion_to_internet: Refreshing state... [id=a6e2e32e-182a-4833-bebf-e5b872b94097]
opnsense_firewall_alias.fwint_port["ports_ad_tcp"]: Refreshing state... [id=a69b7d92-89a2-492e-afc5-035f36d7fb74]
opnsense_firewall_alias.fwint_port["ports_ad_udp"]: Refreshing state... [id=ce40cb51-0f8c-4387-8a16-eaafa349ae0f]
opnsense_firewall_alias.fwint_port["ports_smb"]: Refreshing state... [id=7557b87d-d981-451d-91de-30218d0c1ce4]
opnsense_firewall_filter.fwint_bastion_block_all: Refreshing state... [id=ea6cf741-fb9a-49a4-9116-ff76f8d46dce]
opnsense_firewall_alias.fwint_host["host_proxy_lyon01"]: Refreshing state... [id=115b0ff6-cc29-4e41-8315-a3e532ff3d7d]
opnsense_firewall_alias.fwint_host["host_app01"]: Refreshing state... [id=68cce022-6ec6-4914-8b14-25d106dd17b5]
opnsense_firewall_alias.fwint_host["host_backup01"]: Refreshing state... [id=1385d949-43a1-49dd-9b4c-60ae912dc991]
opnsense_firewall_alias.fwint_host["host_dc01"]: Refreshing state... [id=8804aae3-2c3b-4e13-afd7-c9a29ba35e6b]
opnsense_firewall_alias.fwint_host["host_bastion01"]: Refreshing state... [id=2737ea96-9064-47f3-b240-5a90beefb797]
opnsense_firewall_filter.fwint_users_to_servers_smb: Refreshing state... [id=55cebee1-e5f8-4ce9-9193-05ba6726d89b]
opnsense_firewall_filter.wan_to_dmz_https: Refreshing state... [id=422cb8cc-acdc-4ca7-8340-573c054cb0b0]
opnsense_firewall_filter.fwextmrs_wan_block_all: Refreshing state... [id=e16e4a40-378f-4076-bee1-0ebc5014e99c]
opnsense_firewall_alias.fwextmrs_network["net_lan_mrs"]: Refreshing state... [id=3e6bd24f-089b-4859-9323-caf571a00bba]
opnsense_firewall_alias.fwextmrs_network["net_lyon_internal"]: Refreshing state... [id=96fda3f8-1558-465a-b250-54ad5daa4442]
opnsense_firewall_filter.fwext_wan_ipsec_esp: Refreshing state... [id=f320b38c-43c0-4fda-8895-3e39f8750f12]
opnsense_firewall_filter.fwext_wan_ipsec_ike: Refreshing state... [id=dbf503c0-2b4c-48b2-adfe-ca6a746e4d3a]
opnsense_firewall_filter.wan_to_dmz_http: Refreshing state... [id=7ae59638-8fc2-4f55-9ec2-54a56f703169]
opnsense_route.fwext_to_backup: Refreshing state... [id=ffa56a3d-90bb-4ee8-a2aa-b6177f2c0fc8]
opnsense_firewall_filter.wansim_wan_block_all: Refreshing state... [id=e480ceaa-37e7-4425-a425-bbdcdd9d52a3]
opnsense_firewall_filter.fwext_wan_to_mail_submission: Refreshing state... [id=c7466310-b272-474d-a118-86a6429c701b]
opnsense_firewall_filter.dmz_to_bastion_ssh: Refreshing state... [id=ef0e9e53-184f-48de-bc6b-c135456a484f]
opnsense_route.fwext_to_servers: Refreshing state... [id=9a55165b-684e-41cd-9505-21764cbd5489]
opnsense_firewall_filter.fwext_wan_ipsec_natt: Refreshing state... [id=7831f5e7-b7f3-446f-8b07-42e56ad92231]
opnsense_firewall_alias.fwext_network["net_dmz_lyon"]: Refreshing state... [id=4508638b-3cf5-4577-8c74-993019344764]
opnsense_firewall_alias.fwext_network["net_lan_mrs"]: Refreshing state... [id=c1ff8ae9-3f6c-4838-bd84-f57a2a101ecb]
opnsense_firewall_alias.fwext_network["net_lyon_internal"]: Refreshing state... [id=34b0004c-f8ca-4434-b168-9dc180652dc6]
opnsense_route.fwext_to_bastion: Refreshing state... [id=9d625e6a-4642-434c-a898-bb8b910e6afc]
opnsense_firewall_alias.fwext_host["host_mail01"]: Refreshing state... [id=c474a308-5c48-4b52-83a6-2d5b26660fb1]
opnsense_firewall_alias.fwext_host["host_web01"]: Refreshing state... [id=c18b3e73-73a5-4df8-90d7-7a615a8eef61]
opnsense_route.fwext_to_users: Refreshing state... [id=69e1dd92-b929-43ad-96f2-2c27810fd030]
opnsense_firewall_alias.fwext_port["ports_mail_smtp"]: Refreshing state... [id=57c89604-102a-43d5-b020-bc1612ba3205]
opnsense_firewall_filter.fwextmrs_wan_ipsec_esp: Refreshing state... [id=2993468b-ef20-41d1-919c-23a405496a10]
opnsense_firewall_filter.fwextmrs_wan_ipsec_ike: Refreshing state... [id=c3e4bd3a-7138-4df9-99e7-3f75e3e4b377]
opnsense_firewall_alias.fwextmrs_host["host_proxy_mrs01"]: Refreshing state... [id=ff3cabc5-74cd-4861-9c95-5ad75edece06]
opnsense_firewall_filter.transit_to_wan: Refreshing state... [id=dca07fb4-7abd-48f6-ae75-a45c6d4cd690]
opnsense_firewall_filter.wan_to_mail: Refreshing state... [id=1a679f06-9209-45aa-b7d5-0482ba0661c0]
opnsense_firewall_alias.wansim_network["net_mrs_subnet"]: Refreshing state... [id=be2c535c-31bf-44a1-8f05-858ff2577801]
opnsense_firewall_alias.wansim_network["net_lyon_subnet"]: Refreshing state... [id=f90fb41a-45db-40f1-a136-9d2c438c5e52]
opnsense_firewall_filter.wansim_lan_to_any: Refreshing state... [id=bd7e5d54-f7f4-447c-bc77-918297748b4d]
opnsense_firewall_filter.wan_block_all: Refreshing state... [id=fa96cb54-21c0-45c6-a1fb-0b5e9a55d9ae]
opnsense_firewall_filter.wansim_opt1_to_any: Refreshing state... [id=2cfe9d54-942a-4f50-aaea-16d6c76078c5]
opnsense_firewall_filter.fwextmrs_wan_ipsec_natt: Refreshing state... [id=72751164-e11d-4804-896f-e08d1cdbeba8]
opnsense_firewall_filter.fwextmrs_lan_to_any: Refreshing state... [id=58df57ab-ff7e-4d01-878d-e9f6306c7b14]

No changes. Your infrastructure matches the configuration.

Terraform has compared your real infrastructure against your configuration
and found no differences, so no changes are needed.

## Actions requises au matin

1. Verifier swanctl --list-sas sur opn-fw-ext-lyon
2. Si tunnels down: executer rollback-ipsec-migration.sh
3. Si terraform plan montre changes: inspecter le diff avant tout apply

## Aucune action autonome prise (regle invariant)
