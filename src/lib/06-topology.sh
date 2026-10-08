# 06-topology.sh -- lê a rede de um arquivo Graphviz (.dot)
#
# Formato aceito (um subconjunto simples do Graphviz):
#
#   graph rede {
#     n0; n1; n2;        <- nós, na ordem em que aparecem (n0 = nó 0, ...)
#     n0 -- n1;          <- uma ligação, nos dois sentidos
#     n1 -- n2 -- n0;    <- várias ligações de uma vez
#   }
#
# Atributos [...] e comentários (//, #, /* */) são ignorados.
#
# Preenche: NODE_COUNT, NODE_NAME, NODE_INDEX, NEIGHBORS, EDGE_COUNT,
#           IS_PIONEER e DIAMETER (ver 02-state.sh)

# Imprime o .dot com uma instrução por linha ("n0", "n0 -- n1", ...):
#   1. apaga comentários de linha (// e #)
#   2. junta tudo numa linha só
#   3. apaga comentários /* */, atributos [...] e o "graph nome {" ... "}"
#   4. quebra a linha em cada ";" (e "{", "}" de subgrafos)
dot_statements () {
    sed -e 's://.*$::' -e 's:#.*$::' "$TOPOLOGY" \
        | tr '\n' ' ' \
        | sed -e 's:/\*[^*]*\*/::g' -e 's:\[[^]]*\]::g' -e 's:^[^{]*{::' -e 's:}[^}]*$::' \
        | tr ';{}' '\n\n\n'
}

# add_node <nome>: cria o nó, se ainda não existe
add_node () {
    [[ -n ${NODE_INDEX[$1]:-} ]] && return
    NODE_INDEX[$1]=$NODE_COUNT
    NODE_NAME[NODE_COUNT]=$1
    NEIGHBORS[NODE_COUNT]=
    NODE_COUNT=$(( NODE_COUNT + 1 ))
}

# add_edge <nome> <nome>: liga os dois nós (nos dois sentidos)
add_edge () {
    local a=${NODE_INDEX[$1]} b=${NODE_INDEX[$2]}
    (( a == b )) && return                              # laço: ignora
    [[ " ${NEIGHBORS[a]} " == *" $b "* ]] && return     # já ligados
    NEIGHBORS[a]+=" $b"
    NEIGHBORS[b]+=" $a"
    EDGE_COUNT=$(( EDGE_COUNT + 1 ))
}

read_topology () {
    [[ -f $TOPOLOGY ]] || fail "topologia não encontrada: $TOPOLOGY"
    local statement names name i
    while IFS= read -r statement; do
        statement=${statement//\"/}                         # tira aspas
        [[ $statement =~ ^[[:space:]]*$ ]] && continue      # linha vazia
        read -ra names <<< "${statement//--/ }"             # "a -- b" -> (a b)
        # atributos globais (node [...], edge [...], graph [...]) e
        # atribuições (ex.: rankdir=LR): não são nós
        [[ ${#names[@]} -eq 1 && ${names[0]} =~ ^(node|edge|graph)$ ]] && continue
        [[ $statement == *=* ]] && continue
        for name in "${names[@]}"; do
            [[ $name =~ ^[A-Za-z0-9_.]+$ ]] || fail "$TOPOLOGY : não entendi: $statement"
            add_node "$name"
        done
        for (( i=1; i<${#names[@]}; i++ )); do
            add_edge "${names[i-1]}" "${names[i]}"
        done
    done < <(dot_statements)

    (( NODE_COUNT >= 2 )) || fail "$TOPOLOGY : precisa de pelo menos 2 nós"
    mark_pioneers
}

# Os primeiros PIONEERS nós do .dot são pioneiros.
mark_pioneers () {
    [[ $PIONEERS =~ ^[0-9]+$ ]] && (( PIONEERS >= 1 && PIONEERS <= 100 )) \
        || fail "PIONEERS deve estar entre 1 e 100"
    (( PIONEERS > NODE_COUNT )) && PIONEERS=$NODE_COUNT
    (( PIONEERS == NODE_COUNT )) && echo "aviso: todos os $NODE_COUNT nós são pioneiros; não haverá begs" >&2
    local node
    for (( node=0; node<NODE_COUNT; node++ )); do
        IS_PIONEER[node]=$(( node < PIONEERS ))
    done
}

# Distância (em ligações) de cada nó a todos os outros, por busca em
# largura. DIAMETER = a maior distância: o pior caso, em ciclos, para uma
# ação cruzar a rede. Se algum nó não alcança todos, a rede está partida
# e a simulação para (a ação nunca chegaria a todos).
measure_network () {
    local source queue head node neighbor
    DIAMETER=0
    for (( source=0; source<NODE_COUNT; source++ )); do
        local -A distance=( [$source]=0 )
        queue=( "$source" ); head=0
        while (( head < ${#queue[@]} )); do
            node=${queue[head]}; head=$(( head + 1 ))
            for neighbor in ${NEIGHBORS[node]}; do
                [[ -n ${distance[$neighbor]:-} ]] && continue
                distance[$neighbor]=$(( distance[$node] + 1 ))
                queue+=( "$neighbor" )
                (( distance[$neighbor] > DIAMETER )) && DIAMETER=${distance[$neighbor]}
            done
        done
        (( ${#distance[@]} == NODE_COUNT )) \
            || fail "$TOPOLOGY : grafo desconexo (${NODE_NAME[source]} não alcança todos)"
        unset distance
    done
}
