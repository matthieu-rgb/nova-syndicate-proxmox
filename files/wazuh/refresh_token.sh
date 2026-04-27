TOKEN=$(curl -k -s -u wazuh:wazuh -X POST https://localhost:55000/security/user/authenticate?raw=true)
curl -k -s -H "Authorization: Bearer $TOKEN" https://localhost:55000/agents?limit=20 > /var/www/html/wazuh_agents.json
curl -k -s -H "Authorization: Bearer $TOKEN" https://localhost:55000/manager/info > /var/www/html/wazuh_info.json
