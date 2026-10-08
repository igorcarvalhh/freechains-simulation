# 05-freechains.sh -- roda um comando da CLI do Freechains
#
#   run_freechains <nó> <argumentos da CLI...>
#
#   1. avança o relógio simulado (--now) em COMMAND_SECONDS
#   2. mostra o comando no terminal (a não ser que esteja escondido)
#   3. roda, mede o tempo e guarda o resultado:
#        CLI_OUTPUT   a saída completa
#        CLI_RESULT   a última linha (ex.: o id do post criado)
#        CLI_MS       quanto demorou, em milissegundos
#   4. anota no commands.log
#
#   hidden run_freechains ...
#     Roda sem mostrar no terminal (usado para syncs e consultas). Se o
#     comando falhar, aparece mesmo assim. Com FULL_LOG=1, tudo aparece.

HIDE_COMMAND=0

hidden () {
    HIDE_COMMAND=$(( ! FULL_LOG ))
    "$@"
    local status=$?
    HIDE_COMMAND=0
    return $status
}

# as_command_line <args...>: COMMAND_LINE <- os argumentos escritos como se
# digita no terminal: os simples sem aspas, os outros entre aspas simples.
#   ex.: freechains chain '#topo' post inline 'bom: post 3 de n4'
as_command_line () {
    local arg line= quote="'" escaped="'\\''"
    for arg in "$@"; do
        if [[ $arg =~ ^[A-Za-z0-9_./:=@%+,-]+$ ]]; then
            line+=" $arg"
        else
            line+=" $quote${arg//$quote/$escaped}$quote"
        fi
    done
    COMMAND_LINE=${line# }
}

run_freechains () {
    local node=$1; shift
    NOW=$(( NOW + COMMAND_SECONDS ))
    local command=( freechains --root="${NODE_ROOT[node]}" --now="$NOW" "$@" )
    as_command_line "${command[@]}"
    local text="\$ $COMMAND_LINE"

    # 1. mostra a linha (sem a duração ainda)
    local visible=$(( ! HIDE_COMMAND ))
    if (( visible )); then
        [[ -n $SHOWN_DAY ]] && show_day_header
        show_command "$text"
    fi

    # 2. roda em segundo plano; enquanto isso, o cronômetro atualiza a tela
    local start=${EPOCHREALTIME/[.,]/} pid timer= status
    "${command[@]}" > "$WORK/.out" 2>&1 &
    pid=$!
    if (( visible && IS_TERMINAL )); then
        live_timer "$pid" &
        timer=$!
        disown "$timer"
    fi
    wait "$pid"; status=$?
    [[ -n $timer ]] && kill "$timer" 2>/dev/null

    # 3. resultado
    CLI_MS=$(( (${EPOCHREALTIME/[.,]/} - start) / 1000 ))
    CLI_OUTPUT=$(< "$WORK/.out")
    CLI_RESULT=${CLI_OUTPUT##*$'\n'}

    # escondido, mas falhou: mostra a linha inteira de uma vez
    if (( ! visible && status != 0 )); then
        visible=1
        [[ -n $SHOWN_DAY ]] && show_day_header
        local IS_TERMINAL=0      # sem animação: a linha sai pronta
        show_command "$text"
    fi
    if (( visible )); then
        show_duration "$(format_ms "$CLI_MS")" final
        (( status == 0 )) || printf '%*s└ %s\n' "$PREFIX_WIDTH" '' "$CLI_RESULT"
    fi

    # 4. log
    log_command "$node" "$status" "$CLI_MS" "$text"
    return $status
}

# commands.log, uma linha por comando:
#   ciclo  --now  nó  rc=<código de saída>  ms=<duração>  comando
# Se falhou, uma segunda linha com a saída ("-> ...").
log_command () {
    local node=$1 status=$2 ms=$3 text=$4
    printf '%s\t%s\t%s\trc=%d\tms=%d\t%s\n' "$CYCLE" "$NOW" "${NODE_NAME[node]}" \
        "$status" "$ms" "${text#\$ }" >> "$WORK/commands.log"
    (( status == 0 )) || printf '\t-> %s\n' "${CLI_OUTPUT//$'\n'/ | }" >> "$WORK/commands.log"
}
