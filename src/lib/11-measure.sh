# 11-measure.sh -- depois dos syncs: quem já recebeu cada ação?
#
# 1. Para cada ação ainda se espalhando (SPREADING), conta quantos nós já
#    a têm. Anota o ciclo em que chegou a mais da metade (ACT_HALF_AT) e a
#    todos (ACT_ALL_AT). Quem chegou a todos sai de SPREADING.
# 2. Olha a forma das chains: quantos nós estão com a mesma ponta, quantas
#    ações e quantos merges.
# 3. Escreve uma linha em cycles.csv.
#
# Tudo é só leitura dos repositórios git.

measure_spread () {
    update_spread
    measure_chains
    write_cycle_row
}

update_spread () {
    local k node have still_spreading=()
    for k in "${SPREADING[@]}"; do
        if [[ ${ACT_KIND[k]} == abandon ]]; then
            have=$NODE_COUNT                # descarte é local: não se espalha
        else
            have=0
            for (( node=0; node<NODE_COUNT; node++ )); do
                node_has_action "$node" "$k" && have=$(( have + 1 ))
            done
        fi
        (( have * 2 > NODE_COUNT )) && [[ -z ${ACT_HALF_AT[k]} ]] && ACT_HALF_AT[k]=$CYCLE
        if (( have == NODE_COUNT )); then
            ACT_ALL_AT[k]=$CYCLE
        else
            still_spreading+=( "$k" )
        fi
    done
    SPREADING=( "${still_spreading[@]}" )
}

# HEADS_EQUAL: tamanho do maior grupo de nós com a mesma ponta da chain
# COMMITS, MERGES: tamanho da maior chain (ações e merges)
measure_chains () {
    local node head commits merges
    local -A nodes_with_head=()
    HEADS_EQUAL=0; COMMITS=0; MERGES=0
    for (( node=0; node<NODE_COUNT; node++ )); do
        head=$(git -C "${NODE_REPO[node]}" rev-parse HEAD 2>/dev/null)
        head=${head:-sem-head}
        nodes_with_head[$head]=$(( ${nodes_with_head[$head]:-0} + 1 ))
        (( nodes_with_head[$head] > HEADS_EQUAL )) && HEADS_EQUAL=${nodes_with_head[$head]}
        commits=$(git -C "${NODE_REPO[node]}" rev-list --count HEAD 2>/dev/null)
        merges=$(git -C "${NODE_REPO[node]}" rev-list --merges --count HEAD 2>/dev/null)
        (( commits > COMMITS )) && { COMMITS=$commits; MERGES=$merges; }
    done
}

# cycles.csv: uma linha por ciclo (cabeçalho em 12-report.sh)
write_cycle_row () {
    local sync_avg_ms=$(( SYNCS_DONE ? SYNC_SUM_MS / SYNCS_DONE : 0 ))
    printf '%d,%s,%d,%d,%d,%d,%d,%d,%d,%d\n' "$CYCLE" "${SYNC_ORDER# }" \
        "$SYNCS_DONE" "$SYNCS_SKIPPED" "$SYNC_MAX_MS" "$sync_avg_ms" "$SYNC_ERRORS" \
        "$HEADS_EQUAL" "$COMMITS" "$MERGES" >> "$WORK/cycles.csv"
}
