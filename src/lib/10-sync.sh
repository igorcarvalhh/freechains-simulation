# 10-sync.sh -- os syncs de cada ciclo
#
# Cada nó, numa ordem sorteada a cada ciclo, PUXA (`sync recv`) de cada
# vizinho que tenha novidade. Ninguém empurra. Sem novidade, o sync é
# pulado: o Freechains não mudaria nada, e pular economiza tempo.
#
# A ordem importa: se n7 puxa de n9 e logo depois n3 puxa de n7, uma ação
# de n9 chega a n3 no mesmo ciclo. Na ordem inversa, leva dois ciclos.
#
# Estatísticas do ciclo (vão para cycles.csv, em 11-measure.sh):
#   SYNC_ORDER, SYNCS_DONE, SYNCS_SKIPPED, SYNC_MAX_MS, SYNC_SUM_MS, SYNC_ERRORS

# neighbor_has_news <eu> <vizinho>: o vizinho tem algo que eu não tenho?
# (lê os dois repositórios git, que estão na mesma máquina)
#   - a ponta da chain dele não está na minha       -> novidade
#   - ele tem um beg pendente que eu não tenho
#     (nem pendente, nem já admitido na chain)      -> novidade
neighbor_has_news () {
    local mine=${NODE_REPO[$1]} theirs=${NODE_REPO[$2]} their_head beg
    their_head=$(git -C "$theirs" rev-parse HEAD 2>/dev/null) || return 0
    git -C "$mine" merge-base --is-ancestor "$their_head" HEAD 2>/dev/null || return 0
    for beg in $(git -C "$theirs" for-each-ref --format='%(objectname)' refs/begs/); do
        git -C "$mine" show-ref -q --verify "refs/begs/beg-$beg" 2>/dev/null && continue
        git -C "$mine" merge-base --is-ancestor "$beg" HEAD 2>/dev/null && continue
        return 0
    done
    return 1
}

sync_round () {
    local me neighbor all=()
    for (( me=0; me<NODE_COUNT; me++ )); do all+=( "$me" ); done
    shuffle "${all[@]}"

    SYNC_ORDER=; SYNCS_DONE=0; SYNCS_SKIPPED=0; SYNC_MAX_MS=0; SYNC_SUM_MS=0; SYNC_ERRORS=0
    for me in "${SHUFFLED[@]}"; do
        SYNC_ORDER+=" ${NODE_NAME[me]}"
        for neighbor in ${NEIGHBORS[me]}; do
            if neighbor_has_news "$me" "$neighbor"; then
                pull_from "$me" "$neighbor"
            else
                SYNCS_SKIPPED=$(( SYNCS_SKIPPED + 1 ))
                SYNC_SKIPPED_TOTAL=$(( SYNC_SKIPPED_TOTAL + 1 ))
            fi
        done
    done
}

# pull_from <eu> <vizinho>: `sync recv` do servidor do vizinho
pull_from () {
    local me=$1 neighbor=$2
    if ! hidden run_freechains "$me" chain "$CHAIN" sync recv "localhost:${NODE_PORT[neighbor]}"; then
        SYNC_ERRORS=$(( SYNC_ERRORS + 1 ))
        # recusado por um beg vencido (ver admit_or_abandon em 09-behavior.sh)
        [[ $CLI_OUTPUT == *"author has sufficient reputation"* ]] && STALE_SYNC_ERRORS=$(( STALE_SYNC_ERRORS + 1 ))
    fi
    SYNCS_DONE=$(( SYNCS_DONE + 1 ))
    SYNC_TOTAL=$(( SYNC_TOTAL + 1 ))
    SYNC_SUM_MS=$(( SYNC_SUM_MS + CLI_MS ))
    (( CLI_MS > SYNC_MAX_MS )) && SYNC_MAX_MS=$CLI_MS
    return 0
}
