#!/bin/bash
set -e

# Uso:
#   ./02-prepareTarget.sh                # assume diretório "inventory"
#   ./02-prepareTarget.sh outro_dir      # usa diretório passado como argumento

baseDir=${1:-inventory}

echo "========================================================"
echo "[INFO] Preparando servidor DESTINO com base em: $baseDir"
echo "========================================================"

# Verifica se o diretório de inventário existe. Se não existir, ele emite uma
# mensagem de erro e instruções para copiar o inventário do servidor de origem
# para este host, e então encerra o script com um código de saída 1, indicando
# que ocorreu um erro.
if [ ! -d "$baseDir" ]; then
  echo "[ERRO] Diretório de inventário '$baseDir' não encontrado."
  echo "       Copie o inventário do servidor origem para este host."
  exit 1
fi

# -------------------------------------------------------------------
echo
echo "[1/9] Aplicando grupos e usuários (scripts gerados no inventário)..."

# Verifica se os arquivos "recreatesGroups.sh" e "recreatesUsers.sh" existem no
# diretório de inventário. Se existirem, ele executa cada um usando "bash".
# Se algum dos arquivos não for encontrado, ele emite uma mensagem informando
# que o arquivo não foi encontrado e que a etapa de grupos ou usuários será
# pulada.
if [ -f "$baseDir/recreatesGroups.sh" ]; then
  echo "  - Executando recreatesGroups.sh"
  bash "$baseDir/recreatesGroups.sh"
else
  echo "  - Arquivo $baseDir/recreatesGroups.sh não encontrado, pulando grupos."
fi

if [ -f "$baseDir/recreatesUsers.sh" ]; then
  echo "  - Executando recreatesUsers.sh"
  bash "$baseDir/recreatesUsers.sh"
else
  echo "  - Arquivo $baseDir/recreatesUsers.sh não encontrado, pulando usuários."
fi

# -------------------------------------------------------------------
echo
echo "[2/9] Criando layout de diretórios de aplicação (/opt, /home, /app)..."

# Percorre os diretórios /opt, /home e /app, e para cada um, ele verifica se
# existe um arquivo de layout correspondente (layout_opt.txt, layout_home.txt,
# layout_app.txt) no diretório de inventário.
# Se o arquivo de layout existir, ele lê cada linha do arquivo (que representa
# um subdiretório) e cria a estrutura de diretórios correspondente em /opt,
# /home ou /app usando "mkdir -p".
# Se o arquivo de layout não for encontrado, ele emite uma mensagem informando
# que o arquivo de layout não foi encontrado e que a etapa de criação de
# diretórios para aquele nome será pulada.
# O resultado é que a estrutura de diretórios para /opt, /home e /app será
# recriada com base nos arquivos de layout fornecidos, se eles existirem.
for name in opt home app; do
  layoutFile="$baseDir/layout_${name}.txt"
  if [ -f "$layoutFile" ]; then
    echo "  - Criando diretórios para /$name (baseado em $layoutFile)"
    while read -r d; do
      [ -n "$d" ] && mkdir -p "/$name/$d"
    done < "$layoutFile"
  else
    echo "  - Arquivo de layout $layoutFile não encontrado, pulando /$name."
  fi
done

# -------------------------------------------------------------------
echo
echo "[3/9] Aplicando permissões (ACLs) em /opt, /home, /app..."

# Percorre os diretórios /opt, /home e /app, e para cada um, ele verifica se
# existe um arquivo de ACL correspondente (acl_opt.txt, acl_home.txt,
# acl_app.txt) no diretório de inventário.
# Se o arquivo de ACL existir, ele tenta aplicar as ACLs usando
# "setfacl --restore". Se o comando "setfacl" não estiver disponível ou se
# houver um problema ao aplicar as ACLs, ele emite um aviso informando que
# houve uma falha parcial ao aplicar as ACLs para aquele diretório, e sugere
# verificar manualmente.
# Se o arquivo de ACL não for encontrado, ele emite uma mensagem informando que
# o arquivo de ACL não foi encontrado e que a etapa de aplicação de ACLs para
# aquele nome será pulada.
# O resultado é que as ACLs para /opt, /home e /app serão aplicadas com base
# nos arquivos de ACL fornecidos, se eles existirem, e o script fornecerá
# feedback sobre o sucesso ou falha da aplicação das ACLs.
# O uso de "setfacl --restore" é uma maneira eficiente de aplicar um conjunto
# complexo de ACLs a um diretório e seus subdiretórios, mas requer que o arquivo
# de ACL esteja no formato correto gerado por "getfacl".
# O script também lida com a possibilidade de que o comando "setfacl" possa não
# estar disponível no sistema, ou que as ACLs possam não ser aplicáveis,
# emitindo avisos em vez de falhas críticas, o que é importante para garantir
# que o processo de preparação do servidor de destino continue mesmo se houver
# problemas com as ACLs.
for name in opt home app; do
  aclFile="$baseDir/acl_${name}.txt"
  if [ -f "$aclFile" ]; then
    echo "  - Aplicando ACLs de $aclFile"
    setfacl --restore="$aclFile" || \
      echo "    [WARN] Falha parcial ao aplicar ACLs de $aclFile (verificar manualmente)."
  else
    echo "  - Arquivo de ACL $aclFile não encontrado, pulando ACLs de /$name."
  fi
done

# -------------------------------------------------------------------
echo
echo "[4/9] Configuração de fstab e mounts NFS..."

# O script verifica se o arquivo "fstabCleaned.txt" existe no diretório de
# inventário. Se existir, ele lê o arquivo e filtra apenas as entradas
# relacionadas a NFS usando "grep".
# Ele exibe as entradas NFS encontradas e pergunta ao usuário se deseja aplicar
# essas entradas no /etc/fstab do servidor de destino. Se o usuário concordar,
# o script percorre cada linha das entradas NFS, verifica se o ponto de montagem
# existe e o cria se necessário, e então verifica se já existe uma entrada para
# aquele ponto de montagem no /etc/fstab. Se não existir, ele adiciona a entrada
# NFS ao /etc/fstab.
# Após processar as entradas NFS, o script tenta montar os sistemas de arquivos
# usando "mount -a" e fornece feedback sobre o sucesso ou falha da operação.
fstabCleaned="$baseDir/fstabCleaned.txt"
mountsNFS="$baseDir/mountsNFS.txt"

# if [ -f "$fstabCleaned" ]; then verifica se o arquivo "fstabCleaned.txt"
# existe. Se o arquivo não for encontrado, ele emite uma mensagem informando que
# o arquivo de fstab de origem não foi encontrado e que a configuração
# automática do fstab não será possível.
# Se o arquivo for encontrado, ele exibe uma mensagem indicando que o arquivo de
# fstab de origem foi encontrado e que será feita uma filtragem para incluir
# apenas as entradas NFS no destino.
# read -p é usado para solicitar ao usuário que confirme se deseja aplicar as
# entradas NFS do fstab de origem no /etc/fstab do servidor de destino. A
# resposta do usuário é processada usando um case para aceitar "s", "S", "y" ou
# "Y" como confirmação positiva, e qualquer outra resposta é considerada
# negativa, resultando na mensagem de que a aplicação das entradas NFS no fstab
# foi pulada pelo usuário.
if [ ! -f "$fstabCleaned" ]; then
  echo "  - Arquivo $fstabCleaned não encontrado. Não será possível configurar fstab automaticamente."
else
  echo "  - Arquivo de fstab de origem encontrado: $fstabCleaned"
  echo "    Será feita uma filtragem para incluir apenas entradas NFS no destino."
  read -p "    Deseja aplicar entradas NFS do fstab de origem no /etc/fstab deste servidor? [s/N]: " fstabAnswer

  # case "$fstabAnswer" in é usado para processar a resposta do usuário. Se o
  # usuário responder com "s", "S", "y" ou "Y", o script procede para filtrar
  # as entradas NFS do arquivo "fstabCleaned.txt" e processá-las para inclusão
  # no /etc/fstab do servidor de destino.
  # O comando "grep -E ' nfs[0-4]? '" é usado para filtrar linhas que contenham
  # " nfs ", " nfs3 ", " nfs4 ", etc., indicando entradas relacionadas a NFS.
  # A saída é salva em um arquivo temporário "fstabNfsTarget.txt".
  case "$fstabAnswer" in
    s|S|y|Y)
      fstabNfsTemp="/tmp/fstabNfsTarget.txt"
      grep -E ' nfs[0-4]? ' "$fstabCleaned" > "$fstabNfsTemp" || true

      # Verifica se foram encontradas entradas NFS no fstab de origem. Se não
      # forem encontradas, ele emite uma mensagem informando que nenhuma entrada
      # NFS foi encontrada e que nada será aplicado.
      # Se forem encontradas entradas NFS, ele exibe as entradas encontradas e
      # inicia o processo de inclusão dessas entradas no /etc/fstab do servidor
      # de destino.
      if [ ! -s "$fstabNfsTemp" ]; then
        echo "    - Nenhuma entrada NFS encontrada em $fstabCleaned. Nada a aplicar."
      else
        echo "    - Entradas NFS encontradas:"
        sed 's/^/      /' "$fstabNfsTemp"
        echo
        echo "    - Processando entradas NFS para inclusão no /etc/fstab..."

        # while read -r line; do é usado para ler cada linha do arquivo
        # temporário "fstabNfsTarget.txt". Para cada linha, ele verifica se a
        # linha não está vazia e, em seguida, extrai o dispositivo, ponto de
        # montagem e tipo de sistema de arquivos usando "awk".
        # awk '{print $1}' extrai o primeiro campo (dispositivo), awk
        # '{print $2}' extrai o segundo campo (ponto de montagem) e awk
        # '{print $3}' extrai o terceiro campo (tipo de sistema de arquivos).
        # -z "$line" && continue é usado para pular linhas vazias. Se o ponto de
        # montagem não existir como um diretório, ele cria o diretório usando
        # "mkdir -p".
        while read -r line; do
          [ -z "$line" ] && continue

          device=$(echo "$line" | awk '{print $1}')
          mountpoint=$(echo "$line" | awk '{print $2}')
          fstype=$(echo "$line" | awk '{print $3}')

          # if [ -n "$mountpoint" ] && [ ! -d "$mountpoint" ]; then verifica se
          # a variável "mountpoint" não está vazia e se o diretório do ponto de
          # montagem não existe.
          # Se ambos os critérios forem verdadeiros, ele emite uma mensagem
          # indicando que está criando o diretório de mount e usa "mkdir -p"
          # para criar o diretório.
          if [ -n "$mountpoint" ] && [ ! -d "$mountpoint" ]; then
            echo "      - Criando diretório de mount: $mountpoint"
            mkdir -p "$mountpoint"
          fi

          # if grep -qE "[[:space:]]$mountpoint[[:space:]]" /etc/fstab; then
          # verifica se já existe uma entrada para o ponto de montagem no
          # /etc/fstab.
          # O uso de "grep -qE" permite verificar silenciosamente se há uma
          # correspondência para o ponto de montagem, e a expressão regular
          # "[[:space:]]$mountpoint[[:space:]]" garante que o ponto de montagem
          # seja identificado como um campo separado, evitando falsos positivos.
          # -q ((quiet) não mostra nada, só indica se encontrou ou não) E
          # (ativa um “modo avançado” de busca usando expressões regulares)
          if grep -qE "[[:space:]]$mountpoint[[:space:]]" /etc/fstab; then
            echo "      - Já existe entrada para $mountpoint em /etc/fstab, pulando."
          else
            echo "      - Adicionando entrada NFS para $mountpoint em /etc/fstab"
            echo "$line" >> /etc/fstab
          fi
        done < "$fstabNfsTemp"

        echo
        echo "    - Tentando montar NFS com 'mount -a'..."

        # mount -a é usado para montar todos os sistemas de arquivos listados no
        # /etc/fstab. Se o comando for bem-sucedido, ele emite uma mensagem
        # indicando que o mount -a foi executado com sucesso.
        # Se o comando retornar um erro, ele emite um aviso indicando que houve
        # um problema ao executar o mount -a e sugere verificar o /etc/fstab e
        # os mounts NFS manualmente.
        if mount -a; then
          echo "    - mount -a executado com sucesso."
        else
          echo "    [WARN] mount -a retornou erro. Verifique /etc/fstab e os mounts NFS manualmente."
        fi
      fi
      ;;
    *)
      echo "    - Aplicação de entradas NFS no fstab foi pulada pelo usuário."
      ;;
  esac
fi

# Verifica se o arquivo "mountsNFS.txt" existe no diretório de inventário. Se
# existir, ele exibe uma mensagem indicando que o arquivo com os mounts NFS
# ativos no servidor de origem foi encontrado, e sugere usar esse arquivo para
# comparação com a saída do comando "mount | grep nfs" no servidor de destino.
if [ -f "$mountsNFS" ]; then
  echo
  echo "  - Arquivo com mounts NFS ativos no origem encontrado: $mountsNFS"
  echo "    Use para comparação com 'mount | grep nfs' neste host."
else
  echo "  - Arquivo $mountsNFS não encontrado."
fi

# -------------------------------------------------------------------
echo
echo "[5/9] Configurações de serviços (Systemd)..."

servicesEnabledFile="$baseDir/servicesEnabled.txt"
recreateServicesScript="$baseDir/recreateServices.sh"

# if [ -f "$servicesEnabledFile" ]; then verifica se o arquivo
# "servicesEnabled.txt" existe. Se existir, ele emite uma mensagem indicando
# que o arquivo de serviços habilitados foi encontrado.
# Se o arquivo não for encontrado, ele emite uma mensagem informando que o
# arquivo de serviços habilitados não foi encontrado e que a lista de serviços
# habilitados não será usada.
if [ -f "$servicesEnabledFile" ]; then
  echo "  - Arquivo de serviços habilitados encontrado: $servicesEnabledFile"
else
  echo "  - Arquivo $servicesEnabledFile não encontrado. Lista de serviços habilitados não será usada."
fi

# if [ -f "$recreateServicesScript" ]; then verifica se o arquivo
# "recreateServices.sh" existe. Se existir, ele emite uma mensagem indicando
# que o script de recriação de serviços foi encontrado.
# Ele também emite um aviso de que esse script tenta habilitar e reiniciar
# serviços, o que pode afetar o funcionamento do servidor de destino.
# read -p é usado para solicitar ao usuário que confirme se deseja executar o
# script de serviços agora. A resposta do usuário é processada usando um case
# para aceitar "s", "S", "y" ou "Y" como confirmação positiva, e qualquer outra
# resposta é considerada negativa, resultando na mensagem de que a execução do
# script de serviços foi pulada pelo usuário.
# case "$resp_serv" in é usado para processar a resposta do usuário. Se o
# usuário responder com "s", "S", "y" ou "Y", o script executa o script de
# recriação de serviços usando "bash".
# Se o usuário responder com qualquer outra coisa, ele emite uma mensagem
# indicando que a execução do script de serviços foi pulada pelo usuário.
if [ -f "$recreateServicesScript" ]; then
  echo "  - Script de recriação de serviços encontrado: $recreateServicesScript"
  echo "    ATENÇÃO: este script tenta 'enable' e 'restart' de serviços."
  read -p "    Deseja executar o script de serviços agora? [s/N]: " resp_serv
  case "$resp_serv" in
    s|S|y|Y)
      bash "$recreateServicesScript"
      ;;
    *)
      echo "    - Execução do script de serviços pulada pelo usuário."
      ;;
  esac
else
  echo "  - Script $recreateServicesScript não encontrado, pulando etapa automática de serviços."
fi

# -------------------------------------------------------------------
echo
echo "[6/9] Configurações de autenticação (SSSD/AD/LDAP)..."

# authTAR="$baseDir/authConfigs.tar.gz" verifica se o arquivo
# "authConfigs.tar.gz" existe no diretório de inventário. Se existir, ele emite
# uma mensagem indicando que o arquivo de configurações de autenticação foi
# encontrado.
# Ele também emite um aviso de que copiar configurações de autenticação
# diretamente pode quebrar o login, e solicita ao usuário que confirme se deseja
# extrair as configurações de autenticação em um diretório temporário para
# análise.
# A resposta do usuário é processada usando um case para aceitar "s", "S", "y"
# ou "Y" como confirmação positiva, e qualquer outra resposta é considerada
# negativa, resultando na mensagem de que a extração das configurações de
# autenticação foi pulada pelo usuário.
# case "$authAnswer" in é usado para processar a resposta do usuário. Se o
# usuário responder com "s", "S", "y" ou "Y", o script cria um diretório
# temporário "/tmp/authConfigsTarget", remove qualquer conteúdo existente nesse
# diretório, e então extrai o arquivo "authConfigs.tar.gz" para esse diretório
# usando "tar xzf".
# Se a extração for bem-sucedida, ele emite uma mensagem indicando que as
# configurações foram extraídas para o diretório temporário. Se o usuário
# responder com qualquer outra coisa, ele emite uma mensagem indicando que a
# extração das configurações de autenticação foi pulada pelo usuário.
authTAR="$baseDir/authConfigs.tar.gz"
if [ -f "$authTAR" ]; then
  echo "  - Arquivo de configs de autenticação encontrado: $authTAR"
  echo "    ATENÇÃO: copiar configs de auth diretamente pode quebrar login."
  read -p "    Deseja extrair configs de auth em /tmp/authConfigsTarget para análise? [s/N]: " authAnswer
  case "$authAnswer" in
    s|S|y|Y)
      tempAuthDir="/tmp/authConfigsTarget"
      rm -rf "$tempAuthDir"
      mkdir -p "$tempAuthDir"
      tar xzf "$authTAR" -C "$tempAuthDir" 2>/dev/null || true
      echo "    - Configs extraídas em: $tempAuthDir"
      ;;
    *)
      echo "    - Extração de configs de auth pulada pelo usuário."
      ;;
  esac
else
  echo "  - Arquivo $authTAR não encontrado, pulando etapa de AUTH."
fi

# -------------------------------------------------------------------
echo
echo "[7/9] Pacotes e repositórios YUM..."

# yumReposTar="$baseDir/yumRepos.tar.gz" verifica se o arquivo "yumRepos.tar.gz"
# existe no diretório de inventário. Se existir, ele emite uma mensagem
# indicando que o arquivo de repositórios YUM foi encontrado.
# read -p é usado para solicitar ao usuário que confirme se deseja aplicar
# (extrair) os repositórios YUM em /etc/yum.repos.d. A resposta do usuário é
# processada usando um case para aceitar "s", "S", "y" ou "Y" como confirmação
# positiva, e qualquer outra resposta é considerada negativa, resultando na
# mensagem de que a aplicação dos repositórios YUM foi pulada pelo usuário.
# case "$reposAnswer" in é usado para processar a resposta do usuário. Se o
# usuário responder com "s", "S", "y" ou "Y", o script extrai o arquivo
# "yumRepos.tar.gz" para a raiz do sistema usando "tar xzf". Se a extração for
# bem-sucedida, ele emite uma mensagem indicando que os repositórios YUM foram
# aplicados.
# Após a extração, o script tenta limpar o cache do YUM usando "yum clean all" e
# listar os repositórios usando "yum repolist". Se algum desses comandos
# retornar um erro, ele suprime a saída de erro e continua, garantindo que o
# processo de preparação do servidor de destino continue mesmo se houver
# problemas com o YUM.
# Se o usuário responder com qualquer outra coisa, ele emite uma mensagem
# indicando que a aplicação dos repositórios YUM foi pulada pelo usuário. Se o
# arquivo "yumRepos.tar.gz" não for encontrado, ele emite uma mensagem
# informando que o arquivo de repositórios YUM não foi encontrado e que a etapa
# de aplicação dos repositórios YUM será pulada.
# yum clean all é um comando usado para limpar o cache do YUM, removendo os
# arquivos de cache de repositórios e pacotes baixados. Isso é útil para
# garantir que o YUM use as informações mais recentes dos repositórios após a
# aplicação de novos repositórios.
# yum repolist é um comando usado para listar os repositórios habilitados e suas
# informações. Isso é útil para verificar se os repositórios foram aplicados
# corretamente e estão disponíveis para uso.
yumReposTar="$baseDir/yumRepos.tar.gz"
if [ -f "$yumReposTar" ]; then
  echo "  - Arquivo de repositórios YUM encontrado: $yumReposTar"
  read -p "    Deseja aplicar (extrair) os repositórios em /etc/yum.repos.d? [s/N]: " reposAnswer
  case "$reposAnswer" in
    s|S|y|Y)
      tar xzf "$yumReposTar" -C / 2>/dev/null || {
        echo "    [WARN] Falha ao extrair $yumReposTar. Verificar permissões e conteúdo."
      }
      echo "    - Executando 'yum clean all' e 'yum repolist'..."
      yum clean all >/dev/null 2>&1 || true
      yum repolist || true
      ;;
    *)
      echo "    - Aplicação de repositórios YUM pulada pelo usuário."
      ;;
  esac
else
  echo "  - Arquivo $yumReposTar não encontrado, pulando repositórios YUM."
fi

# sourcePackagesFile="$baseDir/packages.txt" verifica se o arquivo
# "packages.txt" existe no diretório de inventário. Se existir, ele emite uma
# mensagem indicando que o arquivo de pacotes do origem foi encontrado.
# Ele também fornece instruções detalhadas para comparar os pacotes instalados
# no servidor de origem (listados em "packages.txt") com os pacotes instalados
# no servidor de destino usando o comando "rpm -qa" para listar os pacotes
# instalados no destino, e o comando "comm" para comparar as listas de pacotes
# e identificar quais pacotes estão faltando no destino.
# O script sugere revisar o arquivo "/tmp/missingPackages.txt" antes de instalar
# os pacotes faltantes usando "yum install". Se o arquivo "packages.txt" não for
# encontrado, ele emite uma mensagem informando que o arquivo de pacotes do
# origem não foi encontrado e que a comparação de pacotes origem x destino não
# será possível.
# O comando "rpm -qa --qf '%{NAME} %{VERSION}-%{RELEASE}\n' | sort" é usado para
# listar os pacotes instalados no servidor de destino, formatando a saída para
# mostrar o nome do pacote seguido pela versão e release, e ordenando a lista.
# O comando "comm -23 <(cut -d' ' -f1 $sourcePackagesFile | sort) <(cut -d' ' -f1 /tmp/targetPackages.txt | sort)" é
# usado para comparar a lista de pacotes do origem (extraindo apenas os nomes
# dos pacotes) com a lista de pacotes do destino (também extraindo apenas os
# nomes), e identificar quais pacotes estão presentes no origem mas não no
# destino, listando esses pacotes em "/tmp/missingPackages.txt".
# O comando "yum install -y \$(cat /tmp/missingPackages.txt)" é sugerido para
# instalar os pacotes faltantes no servidor de destino, usando a lista de
# pacotes identificados como faltantes. O uso de
# "\$(cat /tmp/missingPackages.txt)" permite passar a lista de pacotes
# diretamente para o comando "yum install".
# A recomendação de revisar o arquivo "/tmp/missingPackages.txt" antes de
# instalar os pacotes é importante para garantir que apenas os pacotes desejados
# sejam instalados, evitando a instalação de pacotes desnecessários ou
# potencialmente problemáticos.
sourcePackagesFile="$baseDir/packages.txt"
if [ -f "$sourcePackagesFile" ]; then
  echo
  echo "  - Arquivo de pacotes do origem encontrado: $sourcePackagesFile"
  echo "    Para comparar pacotes origem x destino, você pode fazer:"
  echo
  echo "      rpm -qa --qf '%{NAME} %{VERSION}-%{RELEASE}\n' | sort > /tmp/targetPackages.txt"
  echo "      comm -23 <(cut -d' ' -f1 $sourcePackagesFile | sort) <(cut -d' ' -f1 /tmp/targetPackages.txt | sort) > /tmp/missingPackages.txt"
  echo "      yum install -y \$(cat /tmp/missingPackages.txt)"
  echo
  echo "    (Recomendo revisar /tmp/missingPackages.txt antes de instalar.)"
else
  echo "  - Arquivo de pacotes $sourcePackagesFile não encontrado."
fi

# -------------------------------------------------------------------
echo
echo "[8/9] Rede: IPs, rotas, firewall - snapshot para comparação..."

# Definição dos arquivos de inventário de rede que podem ter sido coletados do
# servidor de origem. O script verifica a existência desses arquivos e os copia
# para um diretório temporário "/tmp/networkInventoryTarget" para facilitar a
# comparação com os comandos de rede locais no servidor de destino.
# Os arquivos incluem informações sobre endereços IP, rotas, regras de IP, zonas
# e portas do firewalld, e regras do iptables. Se um arquivo específico não for
# encontrado, ele simplesmente não será copiado para o diretório temporário, e o
# script continuará sem falhas críticas.
# O script também verifica se um arquivo de rotas em formato tar.gz existe, e se
# existir, ele extrai o conteúdo para um subdiretório dentro do diretório
# temporário. Isso permite que o usuário compare as rotas do servidor de origem
# com as rotas do servidor de destino usando os comandos "ip route show" ou
# similares.
# O resultado é que o usuário terá um conjunto de arquivos de inventário de rede
# do servidor de origem disponíveis em "/tmp/networkInventoryTarget" para
# comparação com a configuração de rede atual do servidor de destino,
# facilitando a validação e ajuste da configuração de rede conforme necessário.
# A recomendação de comparar os arquivos de inventário de rede com os comandos
# locais como "ip addr show", "ip route show", "firewall-cmd --list-all" e
# "iptables-save" é importante para garantir que a configuração de rede do
# servidor de destino esteja alinhada com a do servidor de origem, especialmente
# em ambientes onde a configuração de rede é crítica para o funcionamento dos
# serviços.
# O script também lida com a possibilidade de que alguns arquivos de inventário
# de rede possam não estar disponíveis, e fornece feedback claro sobre quais
# arquivos foram encontrados e copiados para o diretório temporário, permitindo
# que o usuário saiba exatamente quais informações de rede estão disponíveis
# para comparação.
# A estrutura do diretório temporário e os arquivos copiados permitem uma
# comparação organizada e fácil de entender entre a configuração de rede do
# servidor de origem e do servidor de destino, facilitando a identificação de
# quaisquer discrepâncias ou ajustes necessários.
ipAddrFile="$baseDir/ipAddr.txt"
ipRouteFile="$baseDir/ipRoute.txt"
ipRuleFile="$baseDir/ipRule.txt"
routesTar="$baseDir/networkRoutes.tar.gz"
firewalldZonesFile="$baseDir/firewalldZones.txt"
firewalldPortsFile="$baseDir/firewalldPorts.txt"
iptablesRulesFile="$baseDir/iptablesRules.txt"

# Cria o diretório temporário para o inventário de rede do servidor de destino.
# O comando "rm -rf" é usado para remover qualquer conteúdo existente nesse
# diretório, garantindo que ele esteja limpo antes de copiar os arquivos de
# inventário de rede do servidor de origem. Em seguida, o comando "mkdir -p" é
# usado para criar o diretório, e a opção "-p" garante que o comando não falhe
# se o diretório já existir.
# O resultado é que o diretório "/tmp/networkInventoryTarget" estará pronto para
# receber os arquivos de inventário de rede do servidor de origem, permitindo
# que o usuário compare facilmente a configuração de rede do servidor de destino
# com a do servidor de origem usando os arquivos copiados para esse diretório.
# O uso de um diretório temporário para armazenar os arquivos de inventário de
# rede do servidor de origem é uma prática comum para facilitar a comparação e
# análise, sem afetar diretamente a configuração de rede do servidor de destino.
# Isso permite que o usuário revise as informações de rede do servidor de origem
# e faça ajustes no servidor de destino conforme necessário, com base na
# comparação dos arquivos de inventário.
tmpNetDir="/tmp/networkInventoryTarget"
rm -rf "$tmpNetDir"
mkdir -p "$tmpNetDir"

# [ -f "$ipAddrFile" ] && cp "$ipAddrFile" "$tmpNetDir/originIpAddr.txt"
# verifica se o arquivo "ipAddr.txt" existe. Se existir, ele copia o arquivo
# para o diretório temporário "/tmp/networkInventoryTarget" com o nome
# "originIpAddr.txt".
# O mesmo processo é repetido para os arquivos "ipRoute.txt", "ipRule.txt",
# "firewalldZones.txt", "firewalldPorts.txt" e "iptablesRules.txt", copiando
# cada um para o diretório temporário com um nome que indica que é o inventário
# de rede do servidor de origem.
[ -f "$ipAddrFile" ] && cp "$ipAddrFile" "$tmpNetDir/originIpAddr.txt"
[ -f "$ipRouteFile" ] && cp "$ipRouteFile" "$tmpNetDir/originIpRoute.txt"
[ -f "$ipRuleFile" ] && cp "$ipRuleFile" "$tmpNetDir/originIpRule.txt"
[ -f "$firewalldZonesFile" ] && cp "$firewalldZonesFile" "$tmpNetDir/originFirewalldZones.txt"
[ -f "$firewalldPortsFile" ] && cp "$firewalldPortsFile" "$tmpNetDir/originFirewalldPorts.txt"
[ -f "$iptablesRulesFile" ] && cp "$iptablesRulesFile" "$tmpNetDir/originIptablesRules.txt"

# Extrai o arquivo de rotas, se existir.
# O script verifica se o arquivo "networkRoutes.tar.gz" existe. Se existir, ele
# cria um subdiretório "originRoutes" dentro do diretório temporário
# "/tmp/networkInventoryTarget" e extrai o conteúdo do arquivo tar.gz para esse
# subdiretório usando "tar xzf".
# Se a extração for bem-sucedida, ele emite uma mensagem indicando que o
# inventário de rede do servidor de origem foi copiado para o diretório
# temporário, e fornece instruções para comparar os arquivos de inventário de
# rede com os comandos locais no servidor de destino, como "ip addr show",
# "ip route show", "firewall-cmd --list-all" e "iptables-save".
if [ -f "$routesTar" ]; then
  mkdir -p "$tmpNetDir/originRoutes"
  tar xzf "$routesTar" -C "$tmpNetDir/originRoutes" 2>/dev/null || true
fi

echo "  - Inventário de rede do origem copiado para: $tmpNetDir"
echo "    Compare com comandos locais como:"
echo "      ip addr show"
echo "      ip route show"
echo "      firewall-cmd --list-all   (se aplicável)"
echo "      iptables-save             (se aplicável)"

# -------------------------------------------------------------------
echo
echo "[9/9] Resumo final"

# O script exibe um resumo final das ações realizadas durante a preparação do
# servidor de destino, destacando as principais etapas e o que foi aplicado ou
# configurado. Ele também orienta o usuário a revisar os logs e validar os
# mounts NFS, serviços e configuração de rede para garantir que tudo esteja
# alinhado com o inventário do servidor de origem.
# O resultado é que o usuário terá uma visão clara do que foi feito durante a
# preparação do servidor de destino, e estará ciente das áreas críticas que
# devem ser revisadas e validadas para garantir uma migração bem-sucedida.
echo "  - Grupos/usuários: aplicados conforme scripts do inventário (se disponíveis)."
echo "  - Layout/ACLs: criados/aplicados em /opt, /home, /app (se arquivos existiam)."
echo "  - fstab/NFS: entradas NFS adicionadas ao /etc/fstab e mount -a executado (se aprovado)."
echo "  - Serviços: script de enable/restart executado apenas se aprovado."
echo "  - Auth: configs extraídas para análise apenas se aprovado."
echo "  - YUM: repositórios aplicados (se aprovado) e comandos sugeridos para pacotes."
echo "  - Rede/firewall: inventário do origem disponível em /tmp/networkInventoryTarget para comparação."

echo
echo "========================================================"
echo "[OK] Preparação do servidor DESTINO concluída."
echo "     Revise logs acima e valide mounts NFS, serviços e rede."
echo "========================================================"

# Pontos principais desse 02-prepareTarget.sh:
# Usa o mesmo layout de arquivos que o inventario_migracao.sh gera
# (usuarios_local, grupos, layout_, acl_, servicos_enabled,
# recreateServices.sh, authConfigs.tar.gz, yumRepos.tar.gz, packages.txt).
# Aplica automaticamente:
# Criação de grupos e usuários (via scripts já gerados).
# Criação do layout de diretórios em /opt, /home, /app.
# Aplicação de ACLs nesses diretórios.
# Pergunta antes de:
# Executar o script de serviços (enable/restart).
# Extrair configs de autenticação (para não quebrar login).
# Aplicar repositórios YUM.
# Só orienta, via echo, como fazer o diff de pacotes origem x destino, sem
# instalar nada automaticamente.

# Ideia geral para fstab/NFS
# Ler fstabCleaned.txt e filtrar apenas NFS (para não mexer em discos locais do
# destino).
# Verificar se os pontos de montagem existem (e criar se precisar).
# Verificar se a entrada já existe no /etc/fstab do destino (para evitar
# duplicidade).
# Adicionar as entradas NFS novas no /etc/fstab.
# Rodar mount -a ou mount apenas nesses pontos.
# Isso tudo com uma pergunta de confirmação, porque fstab é crítico.
