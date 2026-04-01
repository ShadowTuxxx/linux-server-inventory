# Script de Inventário de Servidor Linux

Este documento contém um **script Bash** para coletar inventário de um servidor Linux, acompanhado de **comentários didáticos** explicando cada comando, parâmetro e construção.  
A ideia é que mesmo quem nunca viu Linux consiga acompanhar.

---

## 📜 O Script

```bash
#!/bin/bash
# Este script será interpretado pelo Bash (o "tradutor" de comandos).
# Se rodar com outro interpretador (como sh), pode dar erro.

set -e
# Regra de segurança: se QUALQUER comando falhar, o script para imediatamente.
# Isso evita que continue rodando e faça coisas erradas sem perceber.

# ---------------------------------------------------------
# Diretório onde vamos salvar os arquivos coletados
BASE_DIR=${1:-inventory}
# ${1:-inventory} significa:
# - Se você passar um argumento ao rodar o script, ele usa esse nome.
# - Se não passar nada, usa "inventory" como padrão.

echo "========================================================"
echo "[INFO] Coleta de inventário do servidor ORIGEM"
echo "       Diretório de saída: $BASE_DIR"
echo "========================================================"

mkdir -p "$BASE_DIR"
# mkdir -p → cria a pasta de saída (e subpastas se necessário).
# Se já existir, não dá erro.

# ---------------------------------------------------------
echo
echo "[1/10] Usuários e grupos..."

getent passwd > "$BASE_DIR/passwd.txt"
# Lista todos os usuários do sistema e salva em passwd.txt

getent group > "$BASE_DIR/group.txt"
# Lista todos os grupos e salva em group.txt

RECRIA_GRUPOS="$BASE_DIR/recriar_grupos.sh"
RECRIA_USUARIOS="$BASE_DIR/recriar_usuarios.sh"

cat > "$RECRIA_GRUPOS" << 'EOF'
#!/bin/bash
set -e

INV_DIR=$(dirname "$0")
GROUP_FILE="$INV_DIR/group.txt"

awk -F: '$3 >= 1000 && $3 < 60000 {print $1":"$3}' "$GROUP_FILE" | \
while IFS=: read -r name gid; do
  if getent group "$name" >/dev/null 2>&1; then
    echo "Grupo '$name' já existe, pulando."
  else
    echo "Criando grupo '$name' (GID $gid)"
    groupadd -g "$gid" "$name" 2>/dev/null || \
      echo "[WARN] Falha ao criar grupo '$name' (GID $gid)."
  fi
done
EOF

chmod +x "$RECRIA_GRUPOS"

# ---------------------------------------------------------
cat > "$RECRIA_USUARIOS" << 'EOF'
#!/bin/bash
set -e

INV_DIR=$(dirname "$0")
PASSWD_FILE="$INV_DIR/passwd.txt"

awk -F: '$3 >= 1000 && $3 < 60000 {print}' "$PASSWD_FILE" | \
while IFS=: read -r user x uid gid desc home shell; do
  if id "$user" >/dev/null 2>&1; then
    echo "Usuário '$user' já existe, pulando."
  else
    echo "Criando usuário '$user' (UID $uid, GID $gid, home $home, shell $shell)"
    useradd -u "$uid" -g "$gid" -d "$home" -s "$shell" "$user" 2>/dev/null || \
      echo "[WARN] Falha ao criar usuário '$user' (UID $uid)."
  fi
done
EOF

chmod +x "$RECRIA_USUARIOS"

# ---------------------------------------------------------
echo
echo "[2/10] Pacotes instalados (rpm)..."

rpm -qa --qf '%{NAME} %{VERSION}-%{RELEASE}\n' | sort > "$BASE_DIR/pacotes.txt"
# rpm -qa → lista todos os pacotes instalados
# --qf → "query format", define formato da saída
# %{NAME} → nome do pacote
# %{VERSION} → versão
# %{RELEASE} → release
# sort → ordena alfabeticamente

# ---------------------------------------------------------
echo
echo "[3/10] Serviços (systemd)..."

systemctl list-unit-files --type=service --all > "$BASE_DIR/systemd_unit_files.txt"
systemctl list-units --type=service --all > "$BASE_DIR/systemd_units.txt"
systemctl list-unit-files --type=service --state=enabled | awk 'NR>1 {print $1}' > "$BASE_DIR/servicos_enabled.txt"

# ---------------------------------------------------------
echo
echo "[4/10] fstab e mounts NFS..."

cp /etc/fstab "$BASE_DIR/fstab_original.txt"
grep -vE '^\s*#' /etc/fstab | sed '/^\s*$/d' > "$BASE_DIR/fstab_limpado.txt"
mount | grep -i nfs > "$BASE_DIR/mounts_nfs.txt" || true

# ---------------------------------------------------------
echo
echo "[5/10] Layout e ACLs..."

for nome in opt home app; do
  if [ -d "/$nome" ]; then
    find "/$nome" -mindepth 1 -maxdepth 5 -type d | sed "s|^/$nome/||" | sort > "$BASE_DIR/layout_${nome}.txt"
    getfacl -R "/$nome" > "$BASE_DIR/acl_${nome}.txt" 2>/dev/null || \
      echo "WARN ACL"
  fi
done

tar czf "$BASE_DIR/configs.tar.gz" /opt /home /app 2>/dev/null || \
echo "WARN TAR"

# ---------------------------------------------------------
echo
echo "[6/10] Autenticação..."

AUTH_TMP="$BASE_DIR/auth_configs"
rm -rf "$AUTH_TMP"
mkdir -p "$AUTH_TMP"

for f in /etc/sssd/sssd.conf /etc/krb5.conf /etc/nsswitch.conf; do
  if [ -f "$f" ]; then
    cp "$f" "$AUTH_TMP"/
  fi
done

# ---------------------------------------------------------
echo
echo "[8/10] Rede..."

ip addr show > "$BASE_DIR/ip_addr.txt"
ip route show > "$BASE_DIR/ip_route.txt"

# ---------------------------------------------------------
echo
echo "[9/10] Firewall..."

if command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --list-all-zones > "$BASE_DIR/firewalld_zones.txt"
fi

# ---------------------------------------------------------
echo
echo "[OK] Coleta concluída"
# ---------------------------------------------------------
echo
echo "[10/10] Informações adicionais do sistema..."

uname -a > "$BASE_DIR/uname.txt"
# uname -a → mostra informações do kernel e do sistema operacional
# Inclui versão do Linux, arquitetura, nome da máquina

df -h > "$BASE_DIR/discos.txt"
# df -h → mostra uso de disco em formato legível (GB/MB)
# h = human-readable

free -h > "$BASE_DIR/memoria.txt"
# free -h → mostra uso de memória RAM
# h = human-readable

uptime > "$BASE_DIR/uptime.txt"
# uptime → mostra há quanto tempo o servidor está ligado
# Também mostra carga média do sistema

# ---------------------------------------------------------
echo
echo "[OK] Coleta concluída"
# Mensagem final avisando que terminou com sucesso
