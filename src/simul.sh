#!/usr/bin/env bash
#
# simul.sh -- simula como as ações se espalham numa rede Freechains v0.20
#
# A SIMULAÇÃO EM UMA FRASE
#   Lê a rede de um arquivo .dot, prepara um Freechains de verdade para
#   cada nó e roda CYCLES ciclos. Em cada ciclo: (1) talvez um nó sorteado
#   faça uma ação, (2) os nós puxam as novidades dos vizinhos, (3) o script
#   mede quem já recebeu cada ação. Ver README.md.
#
# COMO LER ESTE CÓDIGO
#   Este arquivo é só o roteiro (main e run_cycle, lá embaixo). Cada parte
#   está num arquivo de lib/, numerados na ordem em que vale a pena ler:
#
#     lib/01-config.sh      parâmetros (variáveis de ambiente) e regras fixas
#     lib/02-state.sh       todas as variáveis globais, explicadas
#     lib/03-random.sh      sorteios reproduzíveis (SEED)
#     lib/04-terminal.sh    como os comandos aparecem na tela
#     lib/05-freechains.sh  roda um comando da CLI e anota no log
#     lib/06-topology.sh    lê a rede do arquivo .dot
#     lib/07-setup.sh       prepara chaves, chain e servidores; desliga no fim
#     lib/08-actions.sh     caderno de ações: o que foi feito e quem já tem
#     lib/09-behavior.sh    o que o nó sorteado decide fazer (honesto/desonesto)
#     lib/10-sync.sh        os syncs entre vizinhos
#     lib/11-measure.sh     mede quem já recebeu cada ação
#     lib/12-report.sh      resultados: reps.csv, actions.csv, summary.txt
#
#   Para entender O QUE os nós fazem, leia 09-behavior.sh. Para entender
#   COMO as ações se espalham, leia 10-sync.sh e 11-measure.sh.
#
# Uso:  ./simul.sh                          (padrão: topologias/default.dot)
#       CYCLES=5400 DISHONEST=4 ./simul.sh  (parâmetros em lib/01-config.sh)

set -uo pipefail

# Mensagem de erro no formato do projeto e fim da simulação.
fail () {
    echo "ERROR : simul : $*" >&2
    exit 1
}

LIB_DIR=$(dirname "${BASH_SOURCE[0]}")/lib
for lib_file in "$LIB_DIR"/[0-9][0-9]-*.sh; do
    source "$lib_file"
done

# Um ciclo = 24 minutos simulados.
run_cycle () {
    # o relógio vai para o início do ciclo (a não ser que os comandos do
    # ciclo anterior já tenham passado desse ponto)
    local cycle_start=$(( START_TIME + CYCLE * CYCLE_SECONDS ))
    (( NOW < cycle_start )) && NOW=$cycle_start

    show_day_header
    (( SHOW_CYCLES )) && echo "---- ciclo $CYCLE ----"

    # (1) AÇÃO: com chance 1/n, UM nó sorteado age          (09-behavior.sh)
    draw_number "$NODE_COUNT"
    if (( DRAWN == 0 )); then
        draw_number "$NODE_COUNT"
        node_acts "$DRAWN"
    fi

    # (2) SYNCS: cada nó puxa dos vizinhos com novidade     (10-sync.sh)
    sync_round

    # (3) MEDIÇÃO: quem já tem cada ação                    (11-measure.sh)
    measure_spread

    # fim de um dia simulado: anota a reputação de cada nó  (12-report.sh)
    (( CYCLE % CYCLES_PER_DAY == 0 )) && record_daily_reps $(( CYCLE / CYCLES_PER_DAY ))
    return 0
}

check_requirements () {
    local program
    for program in freechains git ssh-keygen pkill; do
        command -v "$program" >/dev/null || fail "falta '$program'"
    done
    (( BASH_VERSINFO[0] >= 5 )) || fail "requer bash >= 5"
}

main () {
    check_requirements

    # a rede e os papéis
    read_topology               # nós e ligações do .dot      (06-topology.sh)
    measure_network             # diâmetro; erro se partida   (06-topology.sh)
    draw_dishonest_nodes        # quem é desonesto            (09-behavior.sh)

    # preparação
    create_workspace            # pasta de trabalho limpa     (07-setup.sh)
    start_output_files          # cabeçalhos dos .csv         (12-report.sh)
    trap shutdown EXIT          # no fim (ou erro): desliga e salva
    trap 'exit 130' INT TERM    # Ctrl-C
    setup_network               # chaves, chain, servidores   (07-setup.sh)
    record_daily_reps 0         # reputação no dia 0          (12-report.sh)

    # os ciclos
    for (( CYCLE=1; CYCLE<=CYCLES; CYCLE++ )); do
        run_cycle
    done
    CYCLE=$CYCLES

    # resultados
    record_partial_day          # último dia incompleto (ex.: 1.6)
    write_actions_csv
    SHOWN_DAY=                  # sem cabeçalhos de dia daqui em diante
    write_summary > "$WORK/summary.txt"
    print_final_reps | tee -a "$WORK/summary.txt"
}

main "$@"
