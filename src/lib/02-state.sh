# 02-state.sh -- todas as variáveis globais da simulação
#
# CONVENÇÃO
#   Um nó é um número: 0, 1, 2, ... na ordem em que aparece no .dot.
#   Uma ação também é um número: 0, 1, 2, ... na ordem em que acontece.
#   As tabelas abaixo são listas indexadas por esses números, por exemplo:
#     NODE_NAME[3]   o nome do nó 3 (ex.: "n3")
#     ACT_KIND[12]   o tipo da ação 12 (ex.: "post")

# --- relógio -----------------------------------------------------------------
NOW=$START_TIME     # --now do próximo comando
CYCLE=0             # ciclo atual

# --- a rede (06-topology.sh) --------------------------------------------------
NODE_COUNT=0
EDGE_COUNT=0
DIAMETER=0                # maior distância entre dois nós, em ligações
NODE_NAME=()              # nó -> nome no .dot
declare -A NODE_INDEX     # nome -> nó
NEIGHBORS=()              # nó -> vizinhos, separados por espaço (ex.: " 1 4 6")
IS_PIONEER=()             # nó -> 1 se é pioneiro (começa com pontos)
IS_DISHONEST=()           # nó -> 1 se é desonesto (09-behavior.sh)
CREATOR=0                 # nó que cria a chain; os outros a copiam dele

# --- arquivos de cada nó (07-setup.sh) ----------------------------------------
NODE_ROOT=()              # pasta do Freechains do nó (--root)
NODE_REPO=()              # repositório git da chain (o script só LÊ dele)
NODE_PORT=()              # porta do servidor do nó
KEY_FILE=()               # chave privada (usada em --sign)
PUB_FILE=()               # chave pública (arquivo .pub)
PUB_KEY=()                # chave pública em base64, como sai em `reps authors`

# --- caderno de ações (08-actions.sh) -----------------------------------------
ACTION_COUNT=0
ACT_KIND=()               # post | beg | admit | like | dislike | abandon
ACT_AUTHOR=()             # nó que fez a ação
ACT_CID=()                # id da ação (o commit que a CLI devolveu)
ACT_TARGET=()             # ação alvo (de um voto, admissão ou descarte)
ACT_QUALITY=()            # bom | ruim (só post e beg)
ACT_CYCLE=()              # ciclo em que a ação nasceu
ACT_TIME=()               # --now em que a ação nasceu
ACT_CONCURRENT=()         # 1: o autor ainda não tinha recebido uma ação anterior
ACT_HALF_AT=()            # ciclo em que chegou a mais da metade dos nós
ACT_ALL_AT=()             # ciclo em que chegou a todos os nós
ACT_HALF_IN_TIME=()       # 1: chegou à maioria antes de nascer a próxima ação
ACT_ALL_IN_TIME=()        # 1: chegou a todos antes de nascer a próxima ação
ACT_ADMITTED_AT=()        # (só begs) ciclo em que foi admitido
declare -A ACTION_OF_CID  # id de um post/beg -> número da ação
SPREADING=()              # ações que ainda não chegaram a todos
PREVIOUS_ACTION=          # última ação anotada (sem contar descartes)
CONCURRENT=0              # calculado logo antes de cada ação

# --- memória de cada nó (09-behavior.sh); chave "nó,ação" -----------------------
declare -A ALREADY_READ       # post que o nó já leu na moderação
declare -A ALREADY_PUNISHED   # post ruim pelo qual o nó já deu dislike no autor
FIRST_SIGNED_POST=()          # nó -> ciclo do primeiro post assinado (só quem entrou por beg)

# --- contadores para o resumo (12-report.sh) -----------------------------------
STALE_BEGS=0              # begs vencidos descartados com abandon
STALE_SYNC_ERRORS=0       # syncs recusados por causa de um beg vencido
NO_RECENT_BEG=0           # vezes que "admitir" não achou beg recente e virou voto
SYNC_TOTAL=0              # syncs feitos na simulação toda
SYNC_SKIPPED_TOTAL=0      # syncs pulados (vizinho sem novidade)
