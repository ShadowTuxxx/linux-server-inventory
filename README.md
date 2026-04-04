# Linux Server Inventory and Migration Helper

Conjunto de scripts Bash para apoiar migração, preparação e validação de servidores Linux entre um host de origem e um host de destino. Esse projeto nasceu da nessecidade em realizar um "snapshot" de um servidor virtual para clonarmos em um servidor físico.

O fluxo foi pensado para três etapas:

1. Coletar o inventário do servidor de origem.
2. Preparar o servidor de destino com base nesse inventário.
3. Validar se os itens críticos do destino ficaram alinhados com a origem.

## Estrutura

- [01-collectSource.sh]: coleta informações do servidor de origem e gera arquivos auxiliares.
- [02-prepareTarget.sh]: usa o inventário para preparar o servidor de destino.
- [03-validateTarget.sh]: valida serviços, NFS, usuários, grupos e portas críticas no destino.

## Objetivo

Esses scripts ajudam a acelerar atividades comuns de migração ou reconstrução de servidores, como:

- levantamento de usuários, grupos e serviços
- coleta de pacotes, mounts NFS, ACLs e configurações de autenticação
- recriação de estrutura básica no servidor de destino
- apoio à validação pós-preparação

Eles não substituem análise técnica do ambiente. A proposta é reduzir trabalho manual e organizar a comparação entre origem e destino.

## Pré-requisitos

Execute os scripts com um usuário que tenha permissões compatíveis com as ações realizadas. Em vários cenários, será necessário `root`.

Ferramentas/comandos esperados no ambiente:

- `bash`
- `getent`
- `awk`
- `sed`
- `find`
- `tar`
- `systemctl`
- `mount`
- `rpm`
- `ip`
- `getfacl` e `setfacl` para ACLs
- `firewall-cmd` e `iptables-save` quando aplicável
- `ss` ou `netstat` para validações de portas
- `yum` em ambientes baseados em RHEL/CentOS com esse gerenciador

## Fluxo recomendado

### 1. Coleta no servidor de origem

```bash
chmod +x 01-collectSource.sh
./01-collectSource.sh
```

Ou informando outro diretório:

```bash
./01-collectSource.sh /opt/meuInventario
```

O script gera um diretório de inventário com arquivos como:

- `passwd.txt` e `group.txt`
- `packages.txt`
- `systemd_unit_files.txt` e `systemd_units.txt`
- `servicesEnabled.txt`
- `fstabOriginal.txt`, `fstabCleaned.txt` e `mountsNFS.txt`
- `layout_opt.txt`, `layout_home.txt`, `layout_app.txt`
- `acl_opt.txt`, `acl_home.txt`, `acl_app.txt`
- `authConfigs.tar.gz`
- `yumRepos.tar.gz`
- `ipAddr.txt`, `ipRoute.txt`, `ipRule.txt`
- `firewalldZones.txt`, `firewalldServices.txt`, `firewalldPorts.txt`
- `iptablesRules.txt`

Também gera scripts auxiliares:

- `recreatesGroups.sh`
- `recreatesUsers.sh`
- `recreateServices.sh`

### 2. Copiar o inventário para o servidor de destino

Copie o diretório gerado na origem para o host de destino usando o método de sua preferência, por exemplo `scp`, `rsync` ou ferramenta corporativa equivalente.

### 3. Preparação no servidor de destino

```bash
chmod +x 02-prepareTarget.sh
./02-prepareTarget.sh
```

Ou apontando para um diretório específico:

```bash
./02-prepareTarget.sh /opt/meuInventario
```

O script pode:

- recriar grupos e usuários com base nos scripts gerados
- recriar layout de diretórios em `/opt`, `/home` e `/app`
- aplicar ACLs, quando disponíveis
- sugerir e aplicar entradas NFS do `fstab`
- executar a recriação de serviços habilitados, mediante confirmação
- extrair configurações de autenticação para análise, mediante confirmação
- aplicar repositórios YUM, mediante confirmação
- organizar arquivos de rede para comparação no destino

### 4. Validação no servidor de destino

```bash
chmod +x 03-validateTarget.sh
./03-validateTarget.sh
```

Ou com diretório customizado:

```bash
./03-validateTarget.sh /opt/meuInventario
```

O script valida:

- serviços críticos definidos em lista
- mounts NFS esperados
- usuários e grupos críticos
- portas TCP críticas em escuta

## O que personalizar antes do uso

O arquivo [03-validateTarget.sh](/Users/tex/Documents/New project/03-validateTarget.sh) possui listas editáveis para refletir seu ambiente:

- `criticalServices`
- `criticalPorts`
- `criticalUsers`
- `criticalGroups`

Antes de validar, ajuste esses itens com base na realidade do servidor que está sendo migrado.

## Cuidados importantes

- O script de preparação pode alterar `/etc/fstab`, aplicar ACLs, recriar contas e habilitar/reiniciar serviços.
- A extração de configurações de autenticação deve ser tratada com cautela, porque mudanças incorretas podem impactar login e integração com AD/LDAP/SSSD.
- O script não instala pacotes automaticamente. Ele orienta como comparar origem x destino para instalação controlada.
- Nem toda diferença entre origem e destino representa erro. Alguns itens podem variar por arquitetura, papel do servidor ou política operacional.

## Exemplo de uso ponta a ponta

No servidor de origem:

```bash
./01-collectSource.sh inventory
```

Copie o diretório `inventory` para o destino.

No servidor de destino:

```bash
./02-prepareTarget.sh inventory
./03-validateTarget.sh inventory
```

## Cenários em que esses scripts ajudam

- migração de servidor legado para novo host
- preparação de ambiente de homologação semelhante à produção
- reconstrução controlada de servidor após incidente
- checklist operacional de comparação entre origem e destino

## Limitações

- O foco é Linux com ferramentas comuns em distribuições baseadas em RHEL/CentOS.
- Serviços customizados podem exigir ajustes manuais de nome, porta, usuário, grupo ou unit file.
- O script de serviços depende de nomenclatura compatível com `systemd`.
- ACLs, firewall, rede e autenticação podem variar bastante entre ambientes e podem exigir validação manual complementar.

## Boas práticas recomendadas

- execute primeiro em ambiente de laboratório ou homologação
- revise o conteúdo do inventário antes de aplicar no destino
- mantenha backup de arquivos críticos, especialmente `/etc/fstab` e configurações de autenticação
- valide serviços, mounts e portas após cada mudança
- ajuste as listas de validação para o contexto real do servidor

## Licença

Se desejar publicar o projeto, você pode adicionar aqui a licença escolhida, como MIT, Apache-2.0 ou uso interno corporativo.

