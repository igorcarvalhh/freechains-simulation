# 08-actions.sh -- o caderno de ações
#
# Cada ação feita na simulação (post, beg, admit, like, dislike, abandon)
# ganha um número e é anotada nas tabelas ACT_* (ver 02-state.sh):
#   - a medição (11-measure.sh) usa o caderno para saber quem já recebeu
#     cada ação;
#   - os nós (09-behavior.sh) usam para achar posts e begs.
#
# Para saber se um nó tem uma ação, o script LÊ o repositório git do nó.
# Nada é alterado: quem mexe na chain é sempre a CLI do Freechains.

# node_has_commit <nó> <id>: a ação <id> está na chain do nó?
node_has_commit () {
    git -C "${NODE_REPO[$1]}" merge-base --is-ancestor "$2" HEAD 2>/dev/null
}

# node_has_action <nó> <ação>: o nó tem a ação?
# (um beg conta também se estiver pendente, fora da chain)
node_has_action () {
    local node=$1 k=$2
    if [[ ${ACT_KIND[k]} == beg ]] &&
       git -C "${NODE_REPO[node]}" show-ref -q --verify "refs/begs/beg-${ACT_CID[k]}" 2>/dev/null; then
        return 0
    fi
    node_has_commit "$node" "${ACT_CID[k]}"
}

# compute_concurrent <autor>: CONCURRENT <- 1 se o autor ainda não recebeu
# alguma ação anterior que está se espalhando. Nesse caso, a nova ação
# vai bifurcar a chain (e mais tarde alguém terá que juntar os lados).
# Begs e descartes não mudam a chain: não contam.
compute_concurrent () {
    local author=$1 k
    CONCURRENT=0
    for k in "${SPREADING[@]}"; do
        [[ ${ACT_KIND[k]} == beg || ${ACT_KIND[k]} == abandon ]] && continue
        node_has_action "$author" "$k" || { CONCURRENT=1; return; }
    done
}

# record_action <tipo> <autor> <id> [ação alvo]: anota uma ação nova
record_action () {
    local kind=$1 author=$2 cid=$3 target=${4:-} k=$ACTION_COUNT

    # Antes de anotar: a ação anterior chegou à maioria / a todos a tempo,
    # isto é, antes de esta nascer? (um abandon é local: não conta)
    if [[ $kind != abandon ]]; then
        if [[ -n $PREVIOUS_ACTION ]]; then
            local previous=$PREVIOUS_ACTION
            [[ -n ${ACT_HALF_AT[previous]} ]] && ACT_HALF_IN_TIME[previous]=1 || ACT_HALF_IN_TIME[previous]=0
            [[ -n ${ACT_ALL_AT[previous]} ]]  && ACT_ALL_IN_TIME[previous]=1  || ACT_ALL_IN_TIME[previous]=0
        fi
        PREVIOUS_ACTION=$k
    fi

    ACT_KIND[k]=$kind
    ACT_AUTHOR[k]=$author
    ACT_CID[k]=$cid
    ACT_TARGET[k]=$target
    ACT_QUALITY[k]=              # post e beg: preenchido por publish
    ACT_CYCLE[k]=$CYCLE
    ACT_TIME[k]=$NOW
    ACT_CONCURRENT[k]=$CONCURRENT
    ACT_HALF_AT[k]=
    ACT_ALL_AT[k]=
    ACT_HALF_IN_TIME[k]=
    ACT_ALL_IN_TIME[k]=
    ACT_ADMITTED_AT[k]=
    [[ $kind == post || $kind == beg ]] && ACTION_OF_CID[$cid]=$k

    SPREADING+=( "$k" )
    ACTION_COUNT=$(( k + 1 ))
}
