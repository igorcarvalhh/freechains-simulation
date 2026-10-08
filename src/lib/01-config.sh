# 01-config.sh -- parâmetros da simulação e regras fixas
#
# PARÂMETROS: podem ser trocados por variável de ambiente, sem editar nada:
#   CYCLES=5400 DISHONEST=4 ./simul.sh

TOPOLOGY=${TOPOLOGY:-topologias/default.dot}   # a rede (arquivo Graphviz)
CYCLES=${CYCLES:-100}                          # quantos ciclos (60 = 1 dia)
SEED=${SEED:-42}                               # mesma SEED = mesma simulação
PIONEERS=${PIONEERS:-5}                        # os primeiros PIONEERS nós do .dot são pioneiros
DISHONEST=${DISHONEST:-2}                      # quantos nós desonestos (sorteados no início)
SHOW_CYCLES=${SHOW_CYCLES:-0}                  # 1: cabeçalho de cada ciclo no terminal
FULL_LOG=${FULL_LOG:-0}                        # 1: mostra também syncs e consultas
WORK=${WORK:-/tmp/fc-topo-sim}                 # pasta de trabalho (tmpfs no Docker)
OUT=${OUT:-}                                   # se definido: resultados copiados para lá

# REDE
CHAIN='#topo'                   # nome da chain (um fórum público)
BASE_PORT=8350                  # o servidor do nó i escuta em BASE_PORT + i

# RELÓGIO SIMULADO (--now)
START_TIME=1780000000           # --now do início: "dia 01 00:00"
DAY_SECONDS=86400
CYCLE_SECONDS=1440              # cada ciclo avança 24 minutos
CYCLES_PER_DAY=$(( DAY_SECONDS / CYCLE_SECONDS ))   # = 60
COMMAND_SECONDS=5               # cada comando avança 5 segundos (as ações ficam em ordem)
RECENT_SECONDS=$DAY_SECONDS     # "recente" = últimas 24h (para admitir e para moderar)

# PONTOS (regras da v0.20 usadas pela simulação)
POST_MIN_REPS=500               # post assinado precisa de >= 500; abaixo disso, só --beg
ADMIT_LIKE=500                  # like que admite um beg (o mínimo da v0.20)
LIKE_AMOUNT=100                 # like comum (quem tem menos que isso nem vota)
DISLIKE_AMOUNT=500              # dislike de um honesto no autor de um post ruim

# COMPORTAMENTO
VOTE_TRIES=5                    # quantos posts o nó sorteia procurando em quem votar
