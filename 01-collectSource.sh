#!/bin/bash

# Set - Altera o comportamento do script para encerrar em caso de erros, o que é
# importante para evitar que o script continue executando se algo der errado.
# -e - Faz com que o script termine imediatamente se um comando retornar um status
# de saída diferente de zero (indicando um erro).
set -e

# Diretório base de inventário (padrão: ./inventory). Você pode passar outro
# diretório como argumento, por exemplo: ./01-collectSource.sh /opt/meuInventario
baseDir=${1:-inventory}

echo "========================================================"
echo "[INFO] Coleta de inventário do servidor ORIGEM"
echo "       Diretório de saída: $baseDir"
echo "========================================================"

# Cria o diretório base para armazenar os arquivos de inventário, se ainda não
# existir. O comando "mkdir -p" é usado para criar o diretório e quaisquer
# diretórios pai necessários, sem gerar um erro se o diretório já existir.
mkdir -p "$baseDir"

# -------------------------------------------------------------------
echo
echo "[1/10] Usuários e Grupos..."

# Coleta informações de usuários e grupos. O comando "getent" é usado para
# obter informações do banco de dados de usuários e grupos do sistema, e os
# resultados são redirecionados para arquivos de texto separados.
# Esses arquivos podem ser usados posteriormente para recriar os usuários e
# grupos no servidor de destino.
getent passwd > "$baseDir/passwd.txt"
getent group > "$baseDir/group.txt"

# Scripts auxiliares para recriação mais segura no destino. Eles leem os
# arquivos de usuários e grupos e tentam criar apenas os que não existem, com
# base em UID/GID para evitar conflitos com contas de sistema.
recreateGroups="$baseDir/recreatesGroups.sh"
recreateUsers="$baseDir/recreatesUsers.sh"

# Gerar script para recriar grupos (considerando GID >= 1000 como não-sistema,
# ajuste se necessário). O script lê o arquivo de grupos, filtra os grupos com
# GID >= 1000 (que geralmente são grupos de usuários normais), e tenta criar
# cada grupo usando "groupadd".
# Se o grupo já existir, ele pula a criação. Se houver um erro ao criar o grupo,
# ele emite um aviso. O script é salvo em "recreatesGroups.sh" e marcado como
# executável. O mesmo processo é feito para os usuários, considerando UID >=
# 1000 como não-sistema.
# O script de usuários lê o arquivo de passwd, filtra os usuários com UID >=
# 1000, e tenta criar cada usuário usando "useradd" com as opções apropriadas
# para UID, GID, diretório home e shell. Ele também verifica se o usuário já
# existe antes de tentar criar.
# invDir=$(dirname "$0") é usado para garantir que os scripts de recriação de
# grupos e usuários sempre procurem os arquivos "group.txt" e "passwd.txt" no
# mesmo diretório onde os scripts estão localizados, independentemente de onde o
# script seja executado.
# Isso torna os scripts mais portáteis e independentes do diretório de trabalho
# atual.
# groupFile="$invDir/group.txt" e passwdFile="$invDir/passwd.txt" definem os
# caminhos para os arquivos de grupos e usuários, respectivamente, garantindo
# que eles sejam lidos corretamente pelos scripts de recriação.
# awk -F: '$3 >= 1000 && $3 < 60000 {print $1":"$3}' "$groupFile" é usado para
# filtrar os grupos com GID entre 1000 e 59999, que geralmente são considerados
# grupos de usuários normais. O mesmo filtro é aplicado para os usuários com
# UID.
# O uso de "2>/dev/null" ao tentar criar grupos e usuários é para suprimir
# mensagens de erro, já que o script já verifica se o grupo ou usuário existe
# antes de tentar criar. Se ocorrer um erro inesperado, ele emite um aviso
# personalizado.
# << 'EOF' é usado para criar um "heredoc" que contém o conteúdo do script de
# recriação de grupos e usuários. O uso de aspas simples em 'EOF' garante que o
# conteúdo seja tratado literalmente, sem expansão de variáveis ou interpretação
# de caracteres especiais,
# o que é importante para preservar a integridade do script gerado. O conteúdo
# do script é escrito diretamente no arquivo especificado por "$recreateGroups"
# e "$recreateUsers". Após a criação, os scripts são marcados como executáveis
# usando "chmod +x".
# O resultado final é que, além dos arquivos de inventário de usuários e grupos,
# o script também gera scripts auxiliares que podem ser usados no servidor de
# destino para recriar os usuários e grupos de forma segura, evitando conflitos
# com contas de sistema existentes.

cat > "$recreateGroups" << 'EOF'
##### recreatesGroups.sh #####
#!/bin/bash

set -e

invDir=$(dirname "$0")
groupFile="$invDir/group.txt"

awk -F: '$3 >= 1000 && $3 < 60000 {print $1":"$3}' "$groupFile" | \
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
chmod +x "$recreateGroups"

# Gerar script para recriar usuários (considerando UID >= 1000 como
# não-sistema, ajuste se necessário). O processo é semelhante ao de grupos, mas
# inclui opções adicionais para definir o GID, diretório home e shell do
# usuário.
# O script é salvo em "recreatesUsers.sh" e marcado como executável.
cat > "$recreateUsers" << 'EOF'
##### recreatesUsers.sh #####
#!/bin/bash
set -e

invDir=$(dirname "$0")
passwdFile="$invDir/passwd.txt"

awk -F: '$3 >= 1000 && $3 < 60000 {print}' "$passwdFile" | \
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
chmod +x "$recreateUsers"

echo "  - Arquivos gerados:"
echo "    $baseDir/passwd.txt"
echo "    $baseDir/group.txt"
echo "    $recreateGroups"
echo "    $recreateUsers"

# -------------------------------------------------------------------
echo
echo "[2/10] Pacotes instalados (rpm)..."

# O comando "rpm -qa" é usado para listar todos os pacotes instalados no
# sistema, e a opção "--qf '%{NAME} %{VERSION}-%{RELEASE}\n'" formata a saída
# para mostrar apenas o nome do pacote seguido pela versão e release.
# A saída é ordenada e salva em "packages.txt" dentro do diretório de
# inventário. Este arquivo será usado posteriormente para comparar os pacotes
# instalados no servidor de origem com os do servidor de destino, ajudando a
# identificar pacotes que precisam ser instalados ou atualizados.
# O script também imprime uma mensagem indicando onde a lista de pacotes foi
# salva.
rpm -qa --qf '%{NAME} %{VERSION}-%{RELEASE}\n' | sort > "$baseDir/packages.txt"
echo "  - Lista de pacotes salva em: $baseDir/packages.txt"

# -------------------------------------------------------------------
echo
echo "[3/10] Serviços (Systemd)..."

# O comando "systemctl list-unit-files --type=service --all" lista todos os
# arquivos de unidade de serviço disponíveis no sistema, incluindo aqueles que
# estão habilitados, desabilitados ou em outros estados. A saída é salva em
# "systemd_unit_files.txt".
# O comando "systemctl list-units --type=service --all" lista o status atual de
# todas as unidades de serviço, mostrando quais estão ativas, inativas,
# falhadas, etc. A saída é salva em "systemd_units.txt".
systemctl list-unit-files --type=service --all > "$baseDir/systemd_unit_files.txt"
systemctl list-units --type=service --all > "$baseDir/systemd_units.txt"

# O comando "systemctl list-unit-files --type=service --state=enabled" lista
# apenas os arquivos de unidade de serviço que estão habilitados para iniciar
# automaticamente.
# A saída é filtrada usando "awk" para remover a primeira linha (cabeçalho) e
# extrair apenas o nome do serviço, que é salvo em "servicesEnabled.txt". Este
# arquivo será usado posteriormente para tentar recriar o estado dos serviços no
# servidor de destino.
systemctl list-unit-files --type=service --state=enabled | awk 'NR>1 {print $1}' > "$baseDir/servicesEnabled.txt"

# Gerar script para tentar recriar o estado dos serviços habilitados no destino.
# O script lê a lista de serviços habilitados, verifica se cada serviço existe
# no sistema e, se existir, tenta habilitar e reiniciar o serviço.
# Se o serviço não existir, ele emite um aviso e pula para o próximo. O script é
# salvo em "recreateServices.sh" e marcado como executável.
# O script de recriação de serviços é projetado para verificar a existência de
# cada serviço antes de tentar habilitar ou reiniciar. Ele também lida com
# falhas, emitindo avisos em vez de encerrar o script, o que é importante para
# evitar que um serviço problemático impeça a configuração dos outros serviços.
recreateServices="$baseDir/recreateServices.sh"
cat > "$recreateServices" << 'EOF'
##### recreateServices.sh #####
#!/bin/bash
set -e

invDir=$(dirname "$0")
servicesEnabledFile="$invDir/servicesEnabled.txt"

if [ ! -f "$servicesEnabledFile" ]; then
  echo "[ERRO] Arquivo $servicesEnabledFile não encontrado."
  exit 1
fi

while read -r svc; do
  [ -z "$svc" ] && continue
  # Remove sufixo .service se precisar
  svc_name="${svc%.service}"
  if systemctl list-unit-files | grep -q "^${svc_name}\.service"; then
    echo "Habilitando e tentando iniciar serviço: $svc_name"
    systemctl enable "$svc_name" || echo "[WARN] Falha ao habilitar $svc_name"
    systemctl restart "$svc_name" || echo "[WARN] Falha ao restartar $svc_name"
  else
    echo "[WARN] Serviço $svc_name não existe neste host (pulando)."
  fi
done < "$servicesEnabledFile"
EOF
chmod +x "$recreateServices"

echo "  - Arquivos gerados:"
echo "    $baseDir/systemd_unit_files.txt"
echo "    $baseDir/systemd_units.txt"
echo "    $baseDir/servicesEnabled.txt"
echo "    $recreateServices"

# -------------------------------------------------------------------
echo
echo "[4/10] fstab e mounts NFS..."

# Copia o arquivo original de fstab para "fstabOriginal.txt" e cria uma versão
# limpa sem comentários e linhas em branco em "fstabCleaned.txt".
# O uso de "grep -vE '^\s*#'" remove as linhas que começam com "#"
# (comentários) e "sed '/^\s*$/d'" remove as linhas em branco, resultando em um
# arquivo de fstab mais limpo para análise e aplicação no destino.
# O script de preparação do destino usará "fstabCleaned.txt" para tentar aplicar
# apenas as entradas NFS no /etc/fstab do destino, e o arquivo "mountsNFS.txt"
# pode ser usado para comparar os mounts NFS ativos no origem com os do destino.
# O comando "mount | grep -i nfs" captura apenas as linhas relacionadas a mounts
# NFS, e o uso de "|| true" garante que o script continue mesmo se não houver
# mounts NFS ativos, evitando que um erro de grep cause a falha do script.
cp /etc/fstab "$baseDir/fstabOriginal.txt"
grep -vE '^\s*#' /etc/fstab | sed '/^\s*$/d' > "$baseDir/fstabCleaned.txt"

mount | grep -i nfs > "$baseDir/mountsNFS.txt" || true

echo "  - fstab original: $baseDir/fstabOriginal.txt"
echo "  - fstab sem comentários: $baseDir/fstabCleaned.txt"
echo "  - mounts NFS atuais: $baseDir/mountsNFS.txt"

# -------------------------------------------------------------------
echo
echo "[5/10] Layout e ACLs de /opt, /home, /app..."

# O script percorre os diretórios /opt, /home e /app (se existirem) e gera um
# arquivo de layout para cada um, listando os subdiretórios até uma profundidade
# de 5 níveis.
# A saída é formatada para remover o prefixo do diretório base, resultando em um
# arquivo que mostra apenas a estrutura relativa dos subdiretórios.
# Além disso, o script tenta capturar as ACLs de cada diretório usando
# "getfacl -R" e salva em arquivos separados. Se o comando getfacl não estiver
# disponível ou se não houver ACLs, ele emite um aviso.
# O resultado é que, em vez de fazer um tar completo dos diretórios, o script
# gera arquivos de layout e ACLs que podem ser usados para recriar a estrutura e
# permissões no destino de forma mais leve e controlada.
# O script também verifica se cada diretório existe antes de tentar processá-lo,
# e emite mensagens informativas sobre o progresso e quaisquer problemas
# encontrados, como diretórios ausentes ou falhas na captura de ACLs.
for name in opt home app; do
  if [ -d "/$name" ]; then
    find "/$name" -mindepth 1 -maxdepth 5 -type d | sed "s|^/$name/||" | sort > "$baseDir/layout_${name}.txt"
    echo "  - Layout /$name salvo em: $baseDir/layout_${name}.txt"

    # ACLs
    getfacl -R "/$name" > "$baseDir/acl_${name}.txt" 2>/dev/null || \
      echo "  - [WARN] Não foi possível capturar ACLs de /$name (talvez sem ACLs ou sem getfacl)."
  else
    echo "  - Diretório /$name não existe, pulando."
  fi
done

# Gerar um tar.gz apenas com os diretórios principais (sem arquivos) para
# referência. Isso é opcional, mas pode ser útil para ter uma visão geral da
# estrutura dos diretórios sem incluir o conteúdo, o que pode ser pesado.
# O comando "tar czf" é usado para criar um arquivo tar.gz, e a opção
# "2>/dev/null" suprime mensagens de erro caso haja problemas de permissão ou
# espaço ao tentar incluir os diretórios. O script emite um aviso se houver uma
# falha parcial na criação do arquivo.
tar czf "$baseDir/configs.tar.gz" /opt /home /app 2>/dev/null || \
  echo "  - [WARN] Falha parcial ao gerar configs.tar.gz (verificar permissões/espaço)."
echo "  - Arquivo de dados/configs: $baseDir/configs.tar.gz (usar com cautela)."

# -------------------------------------------------------------------
echo
echo "[6/10] Autenticação (SSSD/AD/LDAP) - snapshot para análise..."

# Cria um diretório temporário para armazenar os arquivos de configuração
# relacionados à autenticação, como sssd.conf, krb5.conf, nsswitch.conf,
# ldap.conf e openldap/ldap.conf. Ele copia esses arquivos para o diretório
# temporário, suprimindo erros caso algum arquivo não exista ou haja problemas
# de permissão.
# rm -rf "$authTemp" é usado para garantir que o diretório temporário seja limpo
# antes de criar um novo, e mkdir -p "$authTemp" garante que o diretório seja
# criado se não existir. O script percorre a lista de arquivos de configuração e
# tenta copiá-los para o diretório temporário, ignorando erros para arquivos
# ausentes.
authTemp="$baseDir/authConfigs"
rm -rf "$authTemp"
mkdir -p "$authTemp"

# for é usado para iterar sobre uma lista de arquivos de configuração comuns
# relacionados à autenticação.
# if [ -f "$f" ]; then verifica se o arquivo existe antes de tentar copiá-lo. O
# comando cp "$f" "$authTemp"/ tenta copiar o arquivo para o diretório
# temporário, e "2>/dev/null || true" suprime erros caso o arquivo não exista ou
# haja problemas de permissão, permitindo que o script continue sem interrupção.
# O resultado é que, se algum desses arquivos de configuração estiver presente
# no sistema, ele será copiado para o diretório de inventário, e posteriormente
# compactado em um arquivo tar.gz para análise. Se nenhum arquivo for encontrado,
# o script emite uma mensagem informando que nenhum arquivo de autenticação
# padrão foi encontrado para o snapshot.
# 2>/dev/null é usado para redirecionar mensagens de erro para o "null device",
# ou seja, para descartar qualquer mensagem de erro que possa ocorrer durante a
# cópia dos arquivos. O uso de "|| true" garante que, mesmo que ocorra um erro
# (como o arquivo não existir), o script continue executando sem falhar.
for f in /etc/sssd/sssd.conf /etc/krb5.conf /etc/nsswitch.conf /etc/ldap.conf /etc/openldap/ldap.conf; do
  if [ -f "$f" ]; then
    cp "$f" "$authTemp"/ 2>/dev/null || true
  fi
done

# Após tentar copiar os arquivos de configuração de autenticação, o script
# verifica se o diretório temporário contém algum arquivo usando "ls -A". Se
# houver arquivos presentes, ele cria um arquivo tar.gz com esses arquivos para
# facilitar a análise.
# O comando "tar czf" é usado para criar o arquivo tar.gz, e a opção "-C" é
# usada para mudar para o diretório temporário antes de incluir os arquivos,
# garantindo que a estrutura do tar.gz seja limpa.
# rm -rf "$authTemp" é usado para limpar o diretório temporário após criar o
# arquivo tar.gz, garantindo que não haja arquivos residuais.
if [ -d "$authTemp" ] && [ "$(ls -A "$authTemp" 2>/dev/null)" ]; then
  tar czf "$baseDir/authConfigs.tar.gz" -C "$authTemp" .
  echo "  - Arquivo de configs de auth: $baseDir/authConfigs.tar.gz"
else
  echo "  - Nenhum arquivo de AUTH padrão encontrado para snapshot."
fi
rm -rf "$authTemp"

# -------------------------------------------------------------------
echo
echo "[7/10] Repositórios YUM..."

# Verifica se o diretório "/etc/yum.repos.d" existe, e se existir, ele cria um
# arquivo tar.gz contendo os arquivos de repositórios YUM. O comando "tar czf" é
# usado para criar o arquivo tar.gz, e a opção "-C /" é usada para mudar para o
# diretório raiz antes de incluir os arquivos, garantindo que a estrutura do
# tar.gz seja limpa. A opção "2>/dev/null" suprime mensagens de erro caso haja
# problemas de permissão ou arquivos ausentes, e o script emite um aviso se
# houver uma falha parcial na criação do arquivo.
# O resultado é que, se o diretório de repositórios YUM existir, ele será salvo
# em um arquivo tar.gz dentro do diretório de inventário, e o script imprime uma
# mensagem indicando onde os repositórios YUM foram salvos. Se o diretório não
# existir, ele emite uma mensagem informando que o diretório de repositórios YUM
# não foi encontrado.
if [ -d /etc/yum.repos.d ]; then
  tar czf "$baseDir/yumRepos.tar.gz" -C / etc/yum.repos.d 2>/dev/null || \
    echo "  - [WARN] Falha ao gerar yumRepos.tar.gz."
  echo "  - Repositórios YUM salvos em: $baseDir/yumRepos.tar.gz"
else
  echo "  - Diretório /etc/yum.repos.d não encontrado."
fi

# -------------------------------------------------------------------
echo
echo "[8/10] Rede: IPs, rotas, regras..."

# Coleta informações de rede usando os comandos "ip addr show", "ip route show"
# e "ip rule show". A saída de cada comando é redirecionada para arquivos
# separados dentro do diretório de inventário.
# O comando "ip rule show" pode não estar disponível em todas as distribuições
# ou versões do Linux, então o script tenta executá-lo e suprime erros caso o
# comando não exista, permitindo que o script continue sem falhar.
# O resultado é que as informações de configuração de rede, incluindo endereços
# IP, rotas e regras de roteamento, são salvas em arquivos de texto dentro do
# diretório de inventário, e o script imprime mensagens indicando onde cada tipo
# de informação foi salvo.
ip addr show > "$baseDir/ipAddr.txt"
ip route show > "$baseDir/ipRoute.txt"
ip rule show > "$baseDir/ipRule.txt" 2>/dev/null || true

# Além disso, o script verifica se o diretório "/etc/sysconfig/network-scripts"
# existe, e se existir, ele cria um arquivo tar.gz contendo os arquivos de
# configuração de rede, como ifcfg-*, route-*, etc.
# if [ -d "$routeDir" ]; then verifica a existência do diretório, e se ele
# existir, o comando "tar czf" é usado para criar o arquivo tar.gz, com a opção
# "-C" para mudar para o diretório antes de incluir os arquivos. A opção
# "2>/dev/null" suprime mensagens de erro, e o script emite um aviso se houver
# uma falha parcial na criação do arquivo. O resultado é que, se o diretório de
# scripts de rede existir, ele será salvo em um arquivo tar.gz dentro do
# diretório de inventário, e o script imprime uma mensagem indicando onde os
# arquivos de configuração de rede foram salvos.
# O script também imprime um resumo final indicando onde as informações de IPs e
# rotas foram salvas, para facilitar a referência durante a preparação do
# servidor de destino.
routeDir="/etc/sysconfig/network-scripts"
if [ -d "$routeDir" ]; then
  tar czf "$baseDir/networkRoutes.tar.gz" -C "$routeDir" . 2>/dev/null || true
  echo "  - Arquivo de rotas estáticas: $baseDir/networkRoutes.tar.gz"
fi

echo "  - IPs e rotas salvos em:"
echo "    $baseDir/ipAddr.txt"
echo "    $baseDir/ipRoute.txt"
echo "    $baseDir/ipRule.txt"

# -------------------------------------------------------------------
echo
echo "[9/10] Firewall (firewalld/iptables)..."

# Verifica se o comando "firewall-cmd" está disponível, o que indica que o
# firewalld está instalado. Se estiver disponível, ele coleta informações sobre
# as zonas, serviços e portas configurados no firewalld e salva em arquivos
# separados dentro do diretório de inventário.
# O comando "firewall-cmd --list-all-zones" lista todas as zonas configuradas no
# firewalld, "firewall-cmd --list-services" lista os serviços configurados, e
# "firewall-cmd --list-ports" lista as portas configuradas.
# A opção "2>/dev/null" suprime mensagens de erro caso haja problemas de
# permissão ou se o firewalld não estiver em execução, permitindo que o script
# continue sem falhar.
# O resultado é que, se o firewalld estiver instalado, as informações de
# configuração do firewall serão salvas em arquivos de texto dentro do diretório
# de inventário, e o script imprime mensagens indicando onde cada tipo de
# informação foi salva.
if command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --list-all-zones > "$baseDir/firewalldZones.txt" 2>/dev/null || true
  firewall-cmd --list-services > "$baseDir/firewalldServices.txt" 2>/dev/null || true
  firewall-cmd --list-ports > "$baseDir/firewalldPorts.txt" 2>/dev/null || true
  echo "  - Firewalld:"
  echo "      $baseDir/firewalldZones.txt"
  echo "      $baseDir/firewalldServices.txt"
  echo "      $baseDir/firewalldPorts.txt"
fi

# Verifica se o comando "iptables-save" está disponível, o que indica que o
# iptables está instalado. Se estiver disponível, ele salva as regras atuais do
# iptables em um arquivo de texto dentro do diretório de inventário.
# O comando "iptables-save" é usado para exportar as regras do iptables, e a
# opção "2>/dev/null" suprime mensagens de erro caso haja problemas de
# permissão ou se o iptables não estiver em execução, permitindo que o script
# continue sem falhar.
if command -v iptables-save >/dev/null 2>&1; then
  iptables-save > "$baseDir/iptablesRules.txt" 2>/dev/null || true
  echo "  - Iptables rules: $baseDir/iptablesRules.txt"
fi

# -------------------------------------------------------------------
echo
echo "[10/10] Resumo final"

# Imprime um resumo final indicando onde o inventário completo foi gerado, e
# fornece instruções para copiar o diretório de inventário para o servidor de
# destino e usar os scripts de preparação e validação.
echo "  - Inventário completo gerado em: $baseDir"
echo "  - Copie este diretório para o servidor DESTINO e use com o 02-prepareTarget.sh e 03-validateTarget.sh."

echo
echo "========================================================"
echo "[OK] Coleta de inventário do ORIGEM concluída."
echo "========================================================"

# Pontos principais:
# Mantém tudo em um diretório (por padrão inventory, ou outro se você passar
# como argumento)
# Já gera scripts “recreatesGroups.sh”, “recreatesUsers.sh” e
# “recreateServices.sh”
# Coleta layout (como os diretórios estão organizados (estrutura de pastas)) e
# ACLs (permissões e acessos (quem pode ler, escrever, executar) de /opt, /home,
# /app em vez de tar de tudo (mais leve)
# Coleta configs de auth (SSSD/AD/LDAP) e repositórios YUM
