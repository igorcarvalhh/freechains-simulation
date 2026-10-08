# 12-report.sh -- os resultados
#
#   reps.csv       pontos de cada nó, um registro por dia simulado
#   cycles.csv     uma linha por ciclo (escrita em 11-measure.sh)
#   actions.csv    uma linha por ação (escrito no fim)
#   summary.txt    o resumo completo (escrito no fim)
#   terminal       só a reputação final de cada nó

# Cria os arquivos de resultado, só com o cabeçalho.
start_output_files () {
    : > "$WORK/commands.log"
    echo 'cycle,order,sync_count,sync_skipped,sync_max_ms,sync_avg_ms,sync_errors,heads_equal,commits,merges' \
        > "$WORK/cycles.csv"
    echo 'id,kind,author,author_type,quality,cycle,cid,target,concurrent,cycle_50,cycle_100,majority_in_time,all_in_time' \
        > "$WORK/actions.csv"
    local node header=dia,ciclo
    for (( node=0; node<NODE_COUNT; node++ )); do
        header+=",${NODE_NAME[node]}:$(node_type "$node")"
    done
    echo "$header" > "$WORK/reps.csv"
}

# --- reputação ---------------------------------------------------------------

# NODE_REPS[nó] <- pontos de cada nó, na visão do CREATOR (`reps authors`).
# Quem não aparece na lista tem 0.
read_all_reps () {
    local node line
    for (( node=0; node<NODE_COUNT; node++ )); do NODE_REPS[node]=0; done
    hidden run_freechains "$CREATOR" chain "$CHAIN" reps authors || return 0
    while IFS= read -r line; do                 # cada linha: "<chave pública> <pontos>"
        for (( node=0; node<NODE_COUNT; node++ )); do
            [[ $line == *"${PUB_KEY[node]}"* ]] && NODE_REPS[node]=${line##* }
        done
    done <<< "$CLI_OUTPUT"
}

# record_daily_reps <dia>: uma linha em reps.csv
record_daily_reps () {
    local day=$1 node row
    read_all_reps
    row=$day,$CYCLE
    for (( node=0; node<NODE_COUNT; node++ )); do row+=,${NODE_REPS[node]}; done
    echo "$row" >> "$WORK/reps.csv"
}

# Se a simulação terminou no meio de um dia, registra esse dia parcial
# (ex.: 100 ciclos = dia 1.6).
record_partial_day () {
    (( CYCLE % CYCLES_PER_DAY )) || return 0
    local tenths=$(( CYCLE * 10 / CYCLES_PER_DAY ))
    record_daily_reps "$(( tenths / 10 )).$(( tenths % 10 ))"
}

# Terminal: a reputação final, do maior para o menor.
print_final_reps () {
    local node
    read_all_reps
    echo
    echo "==== reputação final (visão de ${NODE_NAME[CREATOR]}) ===="
    for (( node=0; node<NODE_COUNT; node++ )); do
        printf '%8d  %s (%s)\n' "${NODE_REPS[node]}" "${NODE_NAME[node]}" "$(node_type "$node")"
    done | sort -rn
}

# --- actions.csv -------------------------------------------------------------

write_actions_csv () {
    local k
    for (( k=0; k<ACTION_COUNT; k++ )); do
        printf '%d,%s,%s,%s,%s,%d,%s,%s,%d,%s,%s,%s,%s\n' "$k" "${ACT_KIND[k]}" \
            "${NODE_NAME[${ACT_AUTHOR[k]}]}" "$(node_type "${ACT_AUTHOR[k]}")" "${ACT_QUALITY[k]}" \
            "${ACT_CYCLE[k]}" "${ACT_CID[k]}" "${ACT_TARGET[k]}" "${ACT_CONCURRENT[k]}" \
            "${ACT_HALF_AT[k]}" "${ACT_ALL_AT[k]}" "${ACT_HALF_IN_TIME[k]}" "${ACT_ALL_IN_TIME[k]}" \
            >> "$WORK/actions.csv"
    done
}

# --- summary.txt -------------------------------------------------------------

percent () { (( $2 )) && echo "$(( 100 * $1 / $2 ))%" || echo -; }   # percent 3 4 -> 75%
tenths () { echo "$(( $1 / 10 )).$(( $1 % 10 ))"; }                    # tenths 23 -> 2.3

write_summary () {
    # 1. contagens, percorrendo o caderno de ações
    local k kind node delay beg_author
    local -A count_of=() disliked_post=() admits_of_dishonest=()
    local bad_posts=0 concurrent=0
    local reached_all=0 delay_sum=0 delay_max=0
    local judged=0 half_in_time=0 all_in_time=0
    local begs=0 admitted=0 admit_delay_sum=0
    for (( k=0; k<ACTION_COUNT; k++ )); do
        kind=${ACT_KIND[k]}
        count_of[$kind]=$(( ${count_of[$kind]:-0} + 1 ))
        [[ $kind == post && ${ACT_QUALITY[k]} == ruim ]] && bad_posts=$(( bad_posts + 1 ))
        [[ $kind == dislike ]] && disliked_post[${ACT_TARGET[k]}]=1
        if [[ $kind == admit ]]; then
            beg_author=${ACT_AUTHOR[${ACT_TARGET[k]}]}
            (( IS_DISHONEST[beg_author] )) &&
                admits_of_dishonest[$beg_author]=$(( ${admits_of_dishonest[$beg_author]:-0} + 1 ))
        fi

        [[ $kind == abandon ]] && continue      # descarte é local: fica fora da propagação
        concurrent=$(( concurrent + ACT_CONCURRENT[k] ))
        if [[ -n ${ACT_ALL_AT[k]} ]]; then
            reached_all=$(( reached_all + 1 ))
            delay=$(( ACT_ALL_AT[k] - ACT_CYCLE[k] ))
            delay_sum=$(( delay_sum + delay ))
            (( delay > delay_max )) && delay_max=$delay
        fi
        if [[ -n ${ACT_ALL_IN_TIME[k]} ]]; then  # só ações que já tiveram uma "próxima"
            judged=$(( judged + 1 ))
            half_in_time=$(( half_in_time + ACT_HALF_IN_TIME[k] ))
            all_in_time=$(( all_in_time + ACT_ALL_IN_TIME[k] ))
        fi
        if [[ $kind == beg ]]; then
            begs=$(( begs + 1 ))
            if [[ -n ${ACT_ADMITTED_AT[k]} ]]; then
                admitted=$(( admitted + 1 ))
                admit_delay_sum=$(( admit_delay_sum + ACT_ADMITTED_AT[k] - ACT_CYCLE[k] ))
            fi
        fi
    done

    # 2. o texto
    local dishonest_list=
    for (( node=0; node<NODE_COUNT; node++ )); do
        (( IS_DISHONEST[node] )) && dishonest_list+=" ${NODE_NAME[node]}"
    done

    echo "==== resumo ===="
    echo "topologia:  $TOPOLOGY  ($NODE_COUNT nós, $EDGE_COUNT arestas, diâmetro $DIAMETER)  ciclos: $CYCLES  seed: $SEED  pioneiros: $PIONEERS"
    echo "desonestos: ${dishonest_list:- nenhum}"

    printf 'ações:     '
    for kind in post beg admit like dislike abandon; do printf ' %s=%d' "$kind" "${count_of[$kind]:-0}"; done
    printf '   (admitir sem beg nas últimas 24h, virou like: %d)\n' "$NO_RECENT_BEG"

    echo "chegaram à maioria antes da próxima ação:  $half_in_time de $judged  ($(percent "$half_in_time" "$judged"))"
    echo "chegaram a todos antes da próxima ação:    $all_in_time de $judged  ($(percent "$all_in_time" "$judged"))"
    if (( reached_all )); then
        printf 'ciclos até chegar a todos:  médio %s, máximo %d\n' \
            "$(tenths $(( delay_sum * 10 / reached_all )))" "$delay_max"
    fi
    echo "ações concorrentes (autor ainda sem uma ação anterior): $concurrent"

    if (( admitted )); then
        printf 'begs admitidos: %d de %d, ciclos até a admissão: médio %d\n' "$admitted" "$begs" $(( admit_delay_sum / admitted ))
    else
        echo "begs admitidos: 0 de $begs"
    fi

    printf 'posts ruins: %d, receberam dislike: %d' "$bad_posts" "${#disliked_post[@]}"
    (( bad_posts )) && printf ', dislikes por post ruim: médio %s' "$(tenths $(( 10 * ${count_of[dislike]:-0} / bad_posts )))"
    echo

    printf 'admissões de desonestos:'
    for (( node=0; node<NODE_COUNT; node++ )); do
        (( IS_DISHONEST[node] )) && printf ' %s=%d' "${NODE_NAME[node]}" "${admits_of_dishonest[$node]:-0}"
    done
    echo

    echo "begs vencidos descartados: $STALE_BEGS   syncs rejeitados por beg vencido: $STALE_SYNC_ERRORS"

    printf 'primeiro post assinado (sem beg):'
    for (( node=0; node<NODE_COUNT; node++ )); do
        (( IS_PIONEER[node] )) && continue
        printf ' %s=%s' "${NODE_NAME[node]}" "${FIRST_SIGNED_POST[node]:--}"
    done
    echo

    # o último ciclo, lido de cycles.csv
    local max_ms avg_ms heads commits merges
    IFS=, read -r _ _ _ _ max_ms avg_ms _ heads commits merges < <(tail -n 1 "$WORK/cycles.csv")
    echo "syncs: $SYNC_TOTAL executados, $SYNC_SKIPPED_TOTAL pulados (vizinho sem novidade)"
    echo "último ciclo: sync máx $(format_ms "$max_ms"), médio $(format_ms "$avg_ms"), HEADs iguais $heads/$NODE_COUNT, $commits commits, $merges merges"
}
