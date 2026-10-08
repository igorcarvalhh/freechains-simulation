# 04-terminal.sh -- como os comandos aparecem na tela
#
# Cada comando mostrado ocupa uma linha:
#
#   [dia 01 04:48:25] (   95ms) $ freechains --root=... chain '#topo' post ...
#    relógio simulado   duração   o comando exato, como se digita na CLI
#
# Enquanto o comando roda, a duração é atualizada a cada segundo ("1s...",
# "2s..."). Os comandos são agrupados por dia simulado, com uma linha em
# branco e "==== dia N ====" antes de cada dia.

# Largura da tela, para saber quantas linhas um comando longo ocupa.
# (No Docker, `stty size` pode responder "0 0": tenta outras formas.)
terminal_width () {
    local width
    for width in "$(stty size 2>/dev/null </dev/tty | cut -d' ' -f2)" \
                 "$(tput cols 2>/dev/null)" "${COLUMNS:-}"; do
        [[ $width =~ ^[0-9]+$ ]] && (( width >= 40 )) && { echo "$width"; return; }
    done
    echo 160
}

SCREEN_COLUMNS=$(terminal_width)
IS_TERMINAL=0; [[ -t 1 ]] && IS_TERMINAL=1   # 0: saída redirecionada, sem animação
SHOWN_DAY=                                    # último dia que ganhou cabeçalho

# 812 -> "812ms" ; 4210 -> "4.2s"
format_ms () {
    if (( $1 < 1000 )); then
        echo "${1}ms"
    else
        printf '%d.%ds' $(( $1 / 1000 )) $(( $1 % 1000 / 100 ))
    fi
}

# Dia simulado do relógio atual (o primeiro dia é o 1).
day_number () {
    echo $(( (NOW - START_TIME) / DAY_SECONDS + 1 ))
}

# "[dia 03 14:24:05]"
clock_stamp () {
    local seconds=$(( (NOW - START_TIME) % DAY_SECONDS ))
    printf '[dia %02d %02d:%02d:%02d]' "$(day_number)" \
        $(( seconds / 3600 )) $(( seconds % 3600 / 60 )) $(( seconds % 60 ))
}

# Linha em branco + "==== dia N ====", só quando o dia muda.
show_day_header () {
    local day; day=$(day_number)
    [[ $day == "$SHOWN_DAY" ]] && return
    SHOWN_DAY=$day
    printf '\n==== dia %d ====\n' "$day"
}

# Começo da linha: "[dia 01 04:48:25] (   95ms) "
time_column () {
    printf '%s (%7s) ' "$STAMP" "$1"
}

# show_command <texto>: escreve a linha do comando, ainda sem a duração.
show_command () {
    COMMAND_TEXT=$1
    STAMP=$(clock_stamp)
    PREFIX_WIDTH=$(( ${#STAMP} + 11 ))     # largura de "[...] (%7s) "
    COMMAND_ROWS=$(( (PREFIX_WIDTH + ${#COMMAND_TEXT} - 1) / SCREEN_COLUMNS + 1 ))
    (( IS_TERMINAL )) && printf '%s%s' "$(time_column '')" "$COMMAND_TEXT"
}

# show_duration <duração> [final]: reescreve a duração no começo da linha
# do comando (o cursor sobe, se o comando ocupou várias linhas).
# Com "final", termina a linha.
show_duration () {
    local duration=$1 final=${2:-}
    if (( IS_TERMINAL )); then
        printf '\r'
        (( COMMAND_ROWS > 1 )) && printf '\033[%dA' $(( COMMAND_ROWS - 1 ))
        time_column "$duration"
        (( COMMAND_ROWS > 1 )) && printf '\033[%dB' $(( COMMAND_ROWS - 1 ))
    elif [[ $final == final ]]; then
        printf '%s%s' "$(time_column "$duration")" "$COMMAND_TEXT"
    fi
    [[ $final == final ]] && printf '\n'
}

# live_timer <pid>: roda em segundo plano, atualizando a duração a cada
# segundo, até o processo <pid> terminar.
live_timer () {
    local seconds=0
    while sleep 1; do
        kill -0 "$1" 2>/dev/null || exit 0
        seconds=$(( seconds + 1 ))
        show_duration "${seconds}s..."
    done
}
