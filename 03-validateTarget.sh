#!/bin/bash
set -e

# Uso:
#   ./03-validateTarget.sh                # assume "inventory"
#   ./03-validateTarget.sh outro_dir      # usa diretório passado

baseDir=${1:-inventory}

echo "========================================================"
echo "[INFO] Validação pós-preparação do servidor DESTINO"
echo "       Usando inventário em: $baseDir"
echo "========================================================"

if [ ! -d "$baseDir" ]; then
  echo "[ERRO] Diretório de inventário '$baseDir' não encontrado."
  exit 1
fi

# Defina aqui os serviços, ports, usuários e grupos críticos que devem ser validados.
# Ajuste as listas abaixo conforme a realidade do seu ambiente e o que é considerado "crítico" para a operação do servidor.
# Exemplo: se o servidor é um app server, WebLogic e ControlM podem ser considerados críticos. Se for um servidor de arquivos, talvez seja o NFS ou Samba.
criticalServices=(
  "controlm"
  "weblogic"
)

# Exemplo de ports críticas (ajuste conforme necessário):
# - WebLogic geralmente usa 7001 (HTTP) e 7002 (HTTPS) por padrão, mas isso pode
# variar.
# - ControlM pode usar uma variedade de ports dependendo da configuração, mas
# 12345 é um exemplo comum para o agente.
# Ajuste as ports abaixo conforme a configuração real dos serviços no seu
# ambiente. Se não tiver certeza, consulte a documentação ou o administrador do
# ambiente para confirmar quais ports são críticos.
criticalPorts=(
  "7001"   # exemplo WebLogic
  # "7002"
  # "12345" # exemplo controlm
)

# Exemplo de usuários/grupos críticos:
# - "weblogic" é um usuário comum para instalações de WebLogic.
# - "controlm" pode ser um usuário para o agente ControlM.
# Ajuste os nomes de usuários e grupos abaixo conforme a configuração real do
# seu ambiente. Se não tiver certeza, consulte a documentação ou o administrador
# do ambiente para confirmar quais usuários e grupos são críticos para a
# operação dos serviços no seu ambiente.
criticalUsers=(
  "weblogic"
  "controlm"
)

# Exemplo de grupos críticos:
# - "weblogic" pode ser um grupo associado ao usuário WebLogic.
# - "controlm" pode ser um grupo associado ao usuário ControlM.
# Ajuste os nomes de grupos abaixo conforme a configuração real do seu ambiente.
# Se não tiver certeza, consulte a documentação ou o administrador do ambiente
# para confirmar quais grupos são críticos para a operação dos serviços no seu
# ambiente.
criticalGroups=(
  "weblogic"
  "controlm"
)

# -------------------------------------------------------------------
echo
echo "[1/4] Validando serviços críticos..."

# Para cada serviço crítico listado, o script verifica se ele existe como uma
# unit do systemd e se está ativo.
# Se o serviço não for encontrado como uma unit do systemd, o script emite um
# aviso para verificar a nomenclatura ou o nome do serviço, pois pode haver
# variações (ex: "weblogic" pode ser "weblogic.service" ou algo similar
# dependendo da instalação).
# Se o serviço for encontrado mas não estiver ativo, o script marca como FAIL.
# Se estiver ativo, marca como OK.
for svc in "${criticalServices[@]}"; do
  if systemctl list-unit-files | grep -q "^${svc}\.service"; then
    if systemctl is-active --quiet "$svc"; then
      echo "  - Serviço $svc: OK (active)"
    else
      echo "  - Serviço $svc: FAIL (não está active)"
    fi
  else
    echo "  - Serviço $svc: não encontrado como unit systemd (verificar nome/nomenclatura)."
  fi
done

# -------------------------------------------------------------------
echo
echo "[2/4] Validando mounts NFS esperados..."

# O script procura por entradas NFS no arquivo fstab limpo (gerado no passo
# anterior) e valida se os pontos de montagem estão realmente montados.
# Se o arquivo fstab limpo não for encontrado, o script emite um aviso e não
# realiza a validação de NFS, pois depende do inventário para identificar quais
# mounts NFS deveriam existir.
# Se o arquivo fstab limpo for encontrado, o script extrai as linhas que contêm
# "nfs" e verifica se os pontos de montagem correspondentes estão montados usando
# o comando mount. O resultado é exibido como OK ou FAIL para cada ponto de
# montagem NFS encontrado.
fstabCleaned="$baseDir/fstabCleaned.txt"
if [ -f "$fstabCleaned" ]; then
  grep -E ' nfs[0-4]? ' "$fstabCleaned" > /tmp/fstabNfsValidation.txt || true

  # Se não houver entradas NFS, o arquivo temporário ficará vazio, e o script
  # informará que não há nada a validar. Caso contrário, ele lerá cada linha do
  # arquivo temporário, extrairá o ponto de montagem e verificará se está
  # montado usando o comando mount. O resultado para cada ponto de montagem NFS
  # será exibido como OK ou FAIL.
  # Se o arquivo fstab limpo não for encontrado, o script informará que não será
  # possível validar NFS com base no inventário, pois depende do arquivo para
  # identificar quais mounts NFS deveriam existir.
  if [ ! -s /tmp/fstabNfsValidation.txt ]; then
    echo "  - Nenhuma entrada NFS encontrada no inventário de fstab. Nada a validar."
  else
    while read -r line; do
      [ -z "$line" ] && continue
      mp=$(echo "$line" | awk '{print $2}')
      if mount | grep -qE "[[:space:]]$mp[[:space:]]"; then
        echo "  - NFS $mp: OK (montado)"
      else
        echo "  - NFS $mp: FAIL (não montado)"
      fi
    done < /tmp/fstabNfsValidation.txt
  fi
else
  echo "  - Arquivo $fstabCleaned não encontrado. Não será possível validar NFS com base no inventário."
fi

# -------------------------------------------------------------------
echo
echo "[3/4] Validando usuários/grupos críticos..."

# O script verifica se os grupos críticos listados existem usando o comando
# getent group. Se um grupo for encontrado, é marcado como OK; caso contrário, é
# marcado como FAIL.
# Em seguida, o script verifica se os usuários críticos listados existem usando
# o comando id. Se um usuário for encontrado, é marcado como OK; caso contrário,
# é marcado como FAIL.
# Se os nomes de usuários ou grupos não corresponderem exatamente aos esperados,
# o script pode marcar como FAIL, mesmo que o serviço funcione, então é
# importante garantir que os nomes listados nas variáveis criticalUsers e
# criticalGroups estejam corretos e correspondam à configuração real do
# servidor.
for grp in "${criticalGroups[@]}"; do
  if getent group "$grp" >/dev/null 2>&1; then
    echo "  - Grupo $grp: OK"
  else
    echo "  - Grupo $grp: FAIL (não encontrado)"
  fi
done

# O script verifica se os usuários críticos listados existem usando o comando
# id. Se um usuário for encontrado, é marcado como OK; caso contrário, é marcado
# como FAIL.
# Se um usuário crítico não for encontrado, o script emite um aviso para
# verificar a nomenclatura ou o nome do usuário, pois pode haver variações (ex:
# "weblogic" pode ser "weblogicUser" ou algo similar dependendo da instalação).
# Se os nomes de usuários não corresponderem exatamente aos esperados, o script
# pode marcar como FAIL, mesmo que o serviço funcione, então é importante
# garantir que os nomes listados na variável criticalUsers estejam corretos e
# correspondam à configuração real do servidor.
for usr in "${criticalUsers[@]}"; do
  if id "$usr" >/dev/null 2>&1; then
    echo "  - Usuário $usr: OK"
  else
    echo "  - Usuário $usr: FAIL (não encontrado)"
  fi
done

# -------------------------------------------------------------------
echo
echo "[4/4] Validando ports críticas (TCP)..."

# O script verifica se as ports críticas listadas estão em escuta usando o
# comando ss (se disponível) ou netstat. Ele procura por linhas que correspondam
# ao formato ":port " para identificar se a port está em escuta. Se uma port
# crítica for encontrada em escuta, é marcada como OK; caso contrário, é marcada
# como FAIL.
# Se as ports listadas não corresponderem exatamente às ports configuradas para
# os serviços, o script pode marcar como FAIL, mesmo que o serviço funcione,
# então é importante garantir que as ports listadas na variável criticalPorts
# estejam corretas e correspondam à configuração real do servidor.
# O script usa o comando ss para verificar as ports em escuta, pois é mais
# moderno e geralmente mais rápido que netstat. No entanto, se ss não estiver
# disponível, ele recorre ao netstat. O resultado para cada port crítica será
# exibido como OK ou FAIL com base na presença da port em escuta.
if command -v ss >/dev/null 2>&1; then
  cmdNetSockets="ss -tulnp"
else
  cmdNetSockets="netstat -tulnp"
fi

# O script verifica se as ports críticas listadas estão em escuta usando o
# comando ss (se disponível) ou netstat. Ele procura por linhas que correspondam
# ao formato ":port " para identificar se a port está em escuta. Se uma port
# crítica for encontrada em escuta, é marcada como OK; caso contrário, é marcada
# como FAIL.
# Se as ports listadas não corresponderem exatamente às ports configuradas para
# os serviços, o script pode marcar como FAIL, mesmo que o serviço funcione,
# então é importante garantir que as ports listadas na variável criticalPorts
# estejam corretas e correspondam à configuração real do servidor.
for port in "${criticalPorts[@]}"; do
  if $cmdNetSockets 2>/dev/null | grep -q ":$port "; then
    echo "  - Porta $port: OK (em escuta)"
  else
    echo "  - Porta $port: FAIL (não encontrada em escuta)"
  fi
done

echo
echo "========================================================"
echo "[OK] Validação concluída (verifique os FAILs acima, se houver)."
echo "========================================================"

# Valida serviços “críticos” com base em uma lista (que você pode editar).
# Confere se NFS que deveriam estar montados realmente estão.
# Confere se alguns usuários/grupos chave existem.
# Confere se ports esperadas estão escutando.
