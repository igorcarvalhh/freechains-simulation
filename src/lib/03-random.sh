# 03-random.sh -- sorteios reproduzíveis
#
# O bash gera números "aleatórios" na variável $RANDOM. Começando com a
# mesma SEED, a sequência é sempre a mesma: rodar de novo com a mesma SEED
# repete a simulação (os mesmos nós sorteados, na mesma ordem).

RANDOM=$SEED

# draw_number <n>: DRAWN <- um número inteiro de 0 a n-1
draw_number () {
    # junta dois $RANDOM (15 bits cada) para sortear números grandes
    DRAWN=$(( ((RANDOM << 15) | RANDOM) % $1 ))
}

# shuffle <itens...>: SHUFFLED <- os mesmos itens, em ordem aleatória
# (algoritmo de Fisher-Yates: de trás para frente, troca cada item com um
# item sorteado entre ele e os anteriores)
shuffle () {
    SHUFFLED=( "$@" )
    local i swap
    for (( i=${#SHUFFLED[@]}-1; i>0; i-- )); do
        draw_number $(( i + 1 ))
        swap=${SHUFFLED[i]}
        SHUFFLED[i]=${SHUFFLED[DRAWN]}
        SHUFFLED[DRAWN]=$swap
    done
}
