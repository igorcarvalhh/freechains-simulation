# 09-behavior.sh -- o que o nó sorteado decide fazer
#
# Tudo começa em node_acts (logo abaixo). O nó consulta os próprios pontos
# e, conforme o valor:
#
#   menos de 100     post --beg (pede entrada)
#   100 a 499        1/2 vota · 1/2 post --beg
#   500 ou mais      honesto: primeiro MODERA (post ruim recente -> dislike
#                    no autor; se achou, a ação do ciclo é essa). Senão:
#                    1/3 admite um beg · 1/3 vota · 1/3 post assinado
#
# HONESTOS E DESONESTOS (IS_DISHONEST)
#   A qualidade fica no próprio texto do post ("bom: ..." ou "ruim: ...").
#
#                 honesto                        desonesto
#   beg           bom                            bom (disfarce: só assim é admitido)
#   post          bom                            sempre ruim
#   admitir       lê; só admite beg bom          admite qualquer um, sem ler
#   votar         bom  -> like 100               ruim -> like 100 (ajuda os comparsas)
#                 ruim -> dislike 500 no autor   nunca dá dislike
#   moderar       sim (com >= 500 pontos)        não
#
# Variáveis da decisão: ACTOR_REPS (pontos do nó que age), REPS e QUALITY
# (resultados das consultas, no fim do arquivo).

# --- quem é desonesto --------------------------------------------------------

# Sorteia DISHONEST nós, entre todos (pioneiros também podem ser sorteados).
draw_dishonest_nodes () {
    [[ $DISHONEST =~ ^[0-9]+$ ]] || fail "DISHONEST deve ser um número"
    (( DISHONEST > NODE_COUNT )) && DISHONEST=$NODE_COUNT
    local node all=()
    for (( node=0; node<NODE_COUNT; node++ )); do
        all+=( "$node" )
        IS_DISHONEST[node]=0
    done
    shuffle "${all[@]}"
    for node in "${SHUFFLED[@]:0:DISHONEST}"; do
        IS_DISHONEST[node]=1
    done
}

# node_type <nó>: "honesto" ou "desonesto"
node_type () {
    (( IS_DISHONEST[$1] )) && echo desonesto || echo honesto
}

# --- a decisão ---------------------------------------------------------------

node_acts () {
    local node=$1
    compute_concurrent "$node"          # a ação vai bifurcar a chain? (08-actions.sh)
    get_reps "$node" "$node"
    ACTOR_REPS=$REPS

    if (( ACTOR_REPS < LIKE_AMOUNT )); then
        # menos de 100: não pode nem votar
        publish "$node" beg

    elif (( ACTOR_REPS < POST_MIN_REPS )); then
        # 100 a 499: vota, mas não pode postar assinado
        draw_number 2
        case $DRAWN in
            0) vote_on_some_post "$node" || publish "$node" beg ;;
            1) publish "$node" beg ;;
        esac

    else
        # 500 ou mais: pode tudo
        if (( ! IS_DISHONEST[node] )) && moderate "$node"; then
            return                      # achou um post ruim e deu dislike
        fi
        hidden run_freechains "$node" chain "$CHAIN" list begs
        local pending_begs=$CLI_OUTPUT
        draw_number 3
        case $DRAWN in
            0) admit_recent_beg "$node" "$pending_begs" ;;
            1) vote_on_some_post "$node" || publish "$node" post ;;
            2) publish "$node" post ;;
        esac
    fi
}

# --- postar ------------------------------------------------------------------

# publish <nó> post|beg
# Texto: "<qualidade>: <tipo> <nº da ação> de <nó> no ciclo <ciclo>"
# O desonesto posta sempre ruim, mas faz beg bom (disfarce).
publish () {
    local node=$1 kind=$2 quality=bom beg_flag=()
    [[ $kind == beg ]] && beg_flag=( --beg )
    [[ $kind == post ]] && (( IS_DISHONEST[node] )) && quality=ruim

    run_freechains "$node" chain "$CHAIN" post inline \
        "$quality: $kind $ACTION_COUNT de ${NODE_NAME[node]} no ciclo $CYCLE" \
        "${beg_flag[@]}" --sign="${KEY_FILE[node]}" || return
    record_action "$kind" "$node" "$CLI_RESULT"
    ACT_QUALITY[ACTION_COUNT-1]=$quality

    # para o resumo: quando quem entrou por beg postou assinado pela 1ª vez
    if [[ $kind == post ]] && (( ! IS_PIONEER[node] )) && [[ -z ${FIRST_SIGNED_POST[node]:-} ]]; then
        FIRST_SIGNED_POST[node]=$CYCLE
    fi
}

# --- votar -------------------------------------------------------------------

# vote_on_some_post <nó>
# Sorteia (até VOTE_TRIES vezes) um post, ou beg já admitido, de OUTRO nó
# que o nó já recebeu; lê o conteúdo e vota:
#   honesto:   bom  -> like 100
#              ruim -> dislike 500 no autor (se tem >= 500 pontos e ainda
#                      não puniu esse post; senão, sorteia outro)
#   desonesto: ruim -> like 100; só achou bons -> like 100 no primeiro deles
# Retorna 1 se não achou em quem votar (quem chamou, então, posta).
vote_on_some_post () {
    local node=$1 candidates=() cid k try fallback=
    for cid in "${!ACTION_OF_CID[@]}"; do
        k=${ACTION_OF_CID[$cid]}
        (( ACT_AUTHOR[k] != node )) && candidates+=( "$k" )
    done

    for (( try=0; try<VOTE_TRIES && ${#candidates[@]}>0; try++ )); do
        draw_number ${#candidates[@]}
        k=${candidates[DRAWN]}
        node_has_commit "$node" "${ACT_CID[k]}" || continue    # ainda não chegou a este nó
        read_quality "$node" "${ACT_CID[k]}" || continue

        if (( IS_DISHONEST[node] )); then
            if [[ $QUALITY == ruim ]]; then
                vote "$node" like "$LIKE_AMOUNT" "$k"; return 0
            fi
            fallback=${fallback:-$k}
        elif [[ $QUALITY == bom ]]; then
            vote "$node" like "$LIKE_AMOUNT" "$k"; return 0
        elif (( ACTOR_REPS >= DISLIKE_AMOUNT )) && [[ -z ${ALREADY_PUNISHED[$node,$k]:-} ]]; then
            dislike_author "$node" "$k"; return 0
        fi
    done

    if [[ -n $fallback ]]; then
        vote "$node" like "$LIKE_AMOUNT" "$fallback"; return 0
    fi
    return 1
}

# vote <nó> like|dislike <pontos> <ação>: voto NO POST
vote () {
    local node=$1 kind=$2 amount=$3 k=$4
    run_freechains "$node" chain "$CHAIN" "$kind" "$amount" action "${ACT_CID[k]}" \
        --sign="${KEY_FILE[node]}" || return 0
    record_action "$kind" "$node" "$CLI_RESULT" "$k"
}

# dislike_author <nó> <ação ruim>: dislike NO AUTOR do post ruim
#   `dislike 500 author <chave pública do autor>`
# Tira 450 do autor (500 − 10% de taxa). Um dislike no post tiraria só 225
# do autor (a outra metade sairia do post, que não vale nada na v0.20).
# Cada honesto pune cada post ruim uma vez só. No caderno, o alvo anotado
# é o post ruim que motivou o voto.
dislike_author () {
    local node=$1 k=$2
    local author=${ACT_AUTHOR[k]}
    ALREADY_PUNISHED[$node,$k]=1
    run_freechains "$node" chain "$CHAIN" dislike "$DISLIKE_AMOUNT" author "${PUB_FILE[author]}" \
        --sign="${KEY_FILE[node]}" || return 0
    record_action dislike "$node" "$CLI_RESULT" "$k"
}

# --- moderar (só honesto com >= 500) -----------------------------------------

# moderate <nó>
# Lê, do mais recente para o mais antigo, os posts de outros nós das
# últimas 24h que o nó já recebeu e ainda não leu. No primeiro ruim que
# ainda não puniu, dá dislike no autor. Retorna 1 se não achou nenhum.
moderate () {
    local node=$1 k
    for (( k=ACTION_COUNT-1; k>=0; k-- )); do
        (( ACT_TIME[k] < NOW - RECENT_SECONDS )) && break       # daqui para trás, tudo é velho
        [[ ${ACT_KIND[k]} == post ]] && (( ACT_AUTHOR[k] != node )) || continue
        [[ -z ${ALREADY_READ[$node,$k]:-} ]] && node_has_commit "$node" "${ACT_CID[k]}" || continue
        read_quality "$node" "${ACT_CID[k]}" || continue
        ALREADY_READ[$node,$k]=1
        if [[ $QUALITY == ruim && -z ${ALREADY_PUNISHED[$node,$k]:-} ]]; then
            dislike_author "$node" "$k"
            return 0
        fi
    done
    return 1
}

# --- admitir um beg ----------------------------------------------------------

# admit_recent_beg <nó> <saída de `list begs`>
# Olha os begs pendentes de OUTROS nós feitos nas últimas 24h, do mais
# recente para o mais antigo:
#   honesto:   lê e admite o primeiro BOM
#   desonesto: admite o mais recente, sem ler
# Nenhum beg para admitir: vota (sem post para votar: posta).
admit_recent_beg () {
    local node=$1 pending_begs=$2 cid k recent=()
    for cid in $pending_begs; do
        k=${ACTION_OF_CID[$cid]:-}
        [[ -n $k ]] || continue
        (( ACT_AUTHOR[k] != node && ACT_TIME[k] >= NOW - RECENT_SECONDS )) || continue
        recent+=( "${ACT_TIME[k]} $cid" )      # "<hora> <id>", para ordenar pela hora
    done

    if (( ${#recent[@]} )); then
        for cid in $(printf '%s\n' "${recent[@]}" | sort -rn | cut -d' ' -f2); do
            if (( IS_DISHONEST[node] )) || { read_quality "$node" "$cid" && [[ $QUALITY == bom ]]; }; then
                admit_or_abandon "$node" "$cid"
                return
            fi
        done
    fi

    NO_RECENT_BEG=$(( NO_RECENT_BEG + 1 ))
    vote_on_some_post "$node" || publish "$node" post
}

# admit_or_abandon <nó> <id do beg>
# Confere antes os pontos do autor do beg (na visão deste nó):
#   menos de 500: like 500 no beg -> o beg entra na chain (admitido)
#   500 ou mais:  o beg "venceu": o autor já ganhou pontos por outro
#                 caminho, e a v0.20 recusaria esse beg. É descartado com
#                 abandon (o que só apaga o beg neste nó).
admit_or_abandon () {
    local node=$1 cid=$2 k=${ACTION_OF_CID[$2]:-}
    [[ -n $k ]] || return 1
    get_reps "$node" "${ACT_AUTHOR[k]}"
    if (( REPS >= POST_MIN_REPS )); then
        run_freechains "$node" chain "$CHAIN" abandon "$cid" && record_action abandon "$node" "$cid" "$k"
        STALE_BEGS=$(( STALE_BEGS + 1 ))
    else
        run_freechains "$node" chain "$CHAIN" like "$ADMIT_LIKE" action "$cid" \
            --sign="${KEY_FILE[node]}" || return 0
        record_action admit "$node" "$CLI_RESULT" "$k"
        ACT_ADMITTED_AT[k]=$CYCLE
    fi
    return 0
}

# --- consultas (escondidas no terminal) --------------------------------------

# get_reps <quem olha> <autor>: REPS <- pontos do autor, na visão do nó
get_reps () {
    local viewer=$1 author=$2
    REPS=0
    hidden run_freechains "$viewer" chain "$CHAIN" reps author "${PUB_FILE[author]}" &&
        [[ $CLI_RESULT =~ ^-?[0-9]+$ ]] && REPS=$CLI_RESULT
    return 0
}

# read_quality <nó> <id>: QUALITY <- bom | ruim, lendo o conteúdo (`get payload`)
read_quality () {
    local node=$1 cid=$2
    QUALITY=
    hidden run_freechains "$node" chain "$CHAIN" get payload "$cid" || return 1
    case $CLI_OUTPUT in
        bom:*)  QUALITY=bom ;;
        ruim:*) QUALITY=ruim ;;
    esac
    [[ -n $QUALITY ]]
}
