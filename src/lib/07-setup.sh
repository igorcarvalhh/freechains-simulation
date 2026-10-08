# 07-setup.sh -- prepara a rede antes do primeiro ciclo e desliga tudo no fim
#
# Preparação:
#   1. pasta de trabalho limpa (WORK)
#   2. uma chave por nó (ssh-keygen)
#   3. o nó CREATOR cria a chain com os pioneiros (`chains add ... init`)
#   4. um servidor (daemon) por nó, para os vizinhos puxarem dele
#   5. os outros nós copiam a chain do CREATOR (`chains add ... clone`)

create_workspace () {
    # segurança: só apaga uma pasta que o próprio script criou
    if [[ -e $WORK && ! -e $WORK/.topo-sim ]]; then
        fail "$WORK existe e não foi criado por simul.sh"
    fi
    rm -rf "$WORK"
    mkdir -p "$WORK"
    touch "$WORK/.topo-sim"
}

create_keys () {
    local node
    for (( node=0; node<NODE_COUNT; node++ )); do
        NODE_ROOT[node]=$WORK/${NODE_NAME[node]}
        NODE_REPO[node]=${NODE_ROOT[node]}/chains/$CHAIN
        NODE_PORT[node]=$(( BASE_PORT + node ))
        KEY_FILE[node]=$WORK/${NODE_NAME[node]}.key
        PUB_FILE[node]=${KEY_FILE[node]}.pub
        ssh-keygen -t ed25519 -C '' -N '' -q -f "${KEY_FILE[node]}"
        PUB_KEY[node]=$(cut -d' ' -f2 "${PUB_FILE[node]}")
    done
}

# start_server <nó>: o daemon do nó, para os vizinhos fazerem sync dele
start_server () {
    local node=$1
    freechains --root="${NODE_ROOT[node]}" daemon start --port="${NODE_PORT[node]}" \
        -- --listen=127.0.0.1 --reuseaddr > "$WORK/daemon-${NODE_NAME[node]}.log" 2>&1 &
    sleep 1
}

setup_network () {
    create_keys
    echo "==== preparação ===="

    local node pioneer_keys=()
    for (( node=0; node<PIONEERS; node++ )); do
        pioneer_keys+=( --pioneer="${PUB_FILE[node]}" )
    done
    run_freechains "$CREATOR" chains add "$CHAIN" init "${pioneer_keys[@]}" || exit 1
    start_server "$CREATOR"

    # o clone inicial vem direto do CREATOR, mesmo que ele não seja
    # vizinho: é só preparação (não conta como sync)
    for (( node=0; node<NODE_COUNT; node++ )); do
        (( node == CREATOR )) && continue
        run_freechains "$node" chains add "$CHAIN" clone "localhost:${NODE_PORT[CREATOR]}" || exit 1
        start_server "$node"
    done
}

# Roda ao sair (fim normal, erro ou Ctrl-C): desliga os servidores e
# salva os resultados.
shutdown () {
    local node
    for (( node=0; node<NODE_COUNT; node++ )); do
        [[ -n ${NODE_ROOT[node]:-} ]] && freechains --root="${NODE_ROOT[node]}" daemon stop >/dev/null 2>&1
    done
    pkill -f "base-path=$WORK" 2>/dev/null
    save_results
}

# Copia os resultados para OUT/<data-hora> (se OUT estiver definido).
# Arquivos que não chegaram a ser gravados (Ctrl-C) ficam de fora.
save_results () {
    [[ -n $OUT && -e $WORK/.topo-sim ]] || return 0
    local destination file
    destination=$OUT/$(date +%Y%m%d-%H%M%S)
    mkdir -p "$destination" || return 0
    for file in "$WORK"/{summary.txt,reps.csv,cycles.csv,actions.csv,commands.log} "$TOPOLOGY"; do
        [[ -e $file ]] && cp "$file" "$destination"/
    done
    echo "resultados em $destination"
}
