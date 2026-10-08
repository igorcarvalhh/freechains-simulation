# topo-sim: reputação de honestos e desonestos numa rede Freechains

Uma pequena rede de participantes (**nós**) usa o Freechains v0.20 de
verdade, por vários dias simulados. Alguns participantes são
**desonestos**: entram com uma boa aparência e depois publicam conteúdo
ruim.

A pergunta principal:

> **Como a reputação de cada participante muda ao longo do tempo quando
> alguns agem de má-fé?** Os honestos conseguem fazer os desonestos perder
> pontos, a ponto de não conseguirem mais publicar?

O resultado principal é o arquivo `reps.csv`: os pontos de cada nó, dia a
dia.

---

## 1. Freechains em um minuto

O Freechains é um fórum sem servidor central: cada participante guarda uma
cópia da conversa (a **chain**) e troca novidades com os outros. Quem pode
publicar é decidido por **pontos de reputação**.

A simulação usa só estes comandos da CLI:

| Comando | Para quê |
|---|---|
| `post inline <texto> --sign=<chave>` | publicar (post assinado) |
| `post inline <texto> --beg` | pedir entrada (**beg**), para quem não tem pontos |
| `like <n> action <id>` | votar a favor de um post (ou admitir um beg) |
| `dislike <n> author <chave>` | votar contra um participante |
| `reps author <chave>` / `reps authors` | consultar pontos |
| `list begs` / `get payload <id>` | ver os pedidos pendentes / ler um post |
| `sync recv <vizinho>` | puxar as novidades de um vizinho |

As regras de pontos que importam aqui:

```
  início           os PIONEIROS dividem 50000 pontos (5 pioneiros = 10000 cada);
                   os outros começam com 0
  postar           precisa ter >= 500 (fica 500 mais baixo por até 12h);
                   quem tem menos só pode pedir entrada (beg)
  beg              fica pendente até alguém dar um like de >= 500 nele
  votar N pontos   precisa ter >= N; custa N a quem vota
  like num post    o autor ganha cerca de metade do valor
  dislike no autor o autor perde o valor quase todo (−10% de taxa)
  com o tempo      quem posta ganha até 1000 pontos por dia
```

Repare: postar **rende** pontos com o tempo, mesmo que o conteúdo seja
ruim. Só os votos contra fazem um autor perder pontos.

---

## 2. A simulação em uma figura

```
  rede (.dot)  ──►  preparação  ──►  ciclos (24 min cada)  ──►  resultados
  quem fala         chaves, chain,     1. talvez um nó age        reps.csv (por dia)
  com quem          pioneiros          2. todos puxam dos         reputação final
                                          vizinhos                resumo
```

- **A rede** vem de um arquivo Graphviz: cada linha `a -- b;` diz que `a`
  e `b` são vizinhos. Cada nó só troca novidades com seus vizinhos.
- **Um ciclo** = 24 minutos simulados; **60 ciclos = 1 dia**.
- **Em cada ciclo**, com chance 1/n (n = número de nós), **um** nó
  sorteado faz uma ação. Depois, todos os nós puxam as novidades dos
  vizinhos.
- **No fim de cada dia**, o script anota os pontos de todos.

---

## 3. Os participantes

Os primeiros `PIONEERS` nós do `.dot` (padrão 5) são **pioneiros**. Os
outros entram por beg. No início, `DISHONEST` nós (padrão 2) são
sorteados como **desonestos**, inclusive entre os pioneiros.

Todo post é **bom** ou **ruim**, e a qualidade está escrita no próprio
texto (`'bom: ...'` ou `'ruim: ...'`).

| | honesto | desonesto |
|---|---|---|
| **pede entrada (beg)** | com conteúdo bom | com conteúdo bom (disfarce) |
| **posta** | sempre bom | sempre ruim |
| **admite um beg** | lê; só admite se for bom | admite sem ler |
| **vota** | like 100 no bom; dislike 500 no autor do ruim | like 100 no ruim (ajuda os comparsas); nunca dá dislike |
| **modera** | sim: procura posts ruins recentes | não |

```
  desonesto pede entrada com post bom ──► é admitido ──► ganha pontos
       ▲                                                     │
       │                                                     ▼
  sem pontos, pede entrada de novo        posta conteúdo ruim
       ▲                                                     │
       │                                                     ▼
  abaixo de 500, não posta mais ◄── honestos dão dislike no autor
```

---

## 4. O que o nó sorteado faz

Primeiro ele consulta os próprios pontos (`reps author`):

```
  menos de 100      pede entrada (post --beg)

  100 a 499         metade das vezes vota, metade pede entrada

  500 ou mais       honesto: primeiro MODERA: lê os posts das últimas 24h;
                    achou um ruim? dislike 500 no autor e pronto.
                    senão, sorteia:
                      1/3 admite o beg mais recente das últimas 24h
                      1/3 vota em um post
                      1/3 posta
```

- **Votar**: escolhe um post de outro nó, lê e vota conforme a tabela da
  seção 3. Sem post em que votar, posta.
- **Admitir**: sem beg recente para admitir, vota.
- Cada honesto pune cada post ruim **uma vez só**.

---

## 5. Por que o desonesto deveria perder pontos

Cada post ruim rende cerca de **+1000** ao autor com o tempo. Cada dislike
de 500 no autor tira **−450**. Então:

```
  1 post ruim + 1 dislike    1000 − 450       = +550   (ainda compensa)
  1 post ruim + 3 dislikes   1000 − 3 × 450   = −350   (já não compensa)
  1 post ruim + 8 dislikes   1000 − 8 × 450   = −2600
```

Por isso os honestos **moderam** (procuram ativamente posts ruins) e votam
contra o **autor**. Um dislike no post tiraria só metade disso do autor.
Para o honesto, punir custa 500, pagos com o que ele ganha postando.

---

## 6. Premissas adotadas

1. **Freechains real.** Toda ação é um comando da CLI v0.20. O tempo é
   simulado com `--now`.
2. **Rede fixa.** Os vizinhos não mudam e todos os nós estão sempre
   ligados.
3. **Ritmo fixo.** No máximo uma ação por ciclo, com chance 1/n. Todo
   ciclo, cada nó puxa as novidades de cada vizinho, em ordem sorteada.
   Quando o vizinho não tem nada novo, o sync é pulado (não muda o
   resultado).
4. **Pioneiros**: os primeiros `PIONEERS` nós do `.dot`. Os demais
   começam com 0 pontos.
5. **Desonestos sorteados** no início, com comportamento fixo: beg bom,
   depois sempre posts ruins, curtem posts ruins e nunca dão dislike.
6. **Qualidade objetiva.** O texto diz se o post é bom ou ruim, e os
   honestos sempre acertam.
7. **Valores fixos**: like 100, dislike 500, admissão 500.
8. **"Recente" = últimas 24h**, para moderar e para admitir begs.
9. **Beg vencido.** Se o autor de um beg já tem 500 ou mais quando alguém
   vai admiti-lo, o beg é descartado (`abandon`) em vez de admitido.
10. **A reputação é medida na visão do primeiro nó** (`n0`). Os outros
    podem enxergar números um pouco diferentes até receberem todas as
    novidades.
11. **Reprodutível.** A mesma `SEED` gera a mesma simulação.

---

## 7. Resultados

No terminal aparecem as ações, dia a dia:

```
==== dia 1 ====
[dia 01 04:48:15] (   95ms) $ freechains ... chain '#topo' post inline 'bom: beg 4 de n7 no ciclo 12' --beg ...
```

No fim aparece só a reputação final:

```
==== reputação final (visão de n0) ====
   17145  n3 (honesto)
   12250  n2 (desonesto)
    3410  n5 (desonesto)
     ...
```

Arquivos em `./output/<data-hora>/`:

| Arquivo | Conteúdo |
|---|---|
| **`reps.csv`** | **pontos de cada nó, um registro por dia** (o resultado principal) |
| `summary.txt` | resumo: ações, posts ruins e dislikes, admissões, reputação final |
| `actions.csv` | uma linha por ação: tipo, autor (honesto/desonesto), qualidade, ciclo, alvo |
| `cycles.csv` | uma linha por ciclo: syncs feitos e tempos |
| `commands.log` | todos os comandos exatos, inclusive syncs e consultas |

O `reps.csv` traz o tipo de cada nó no cabeçalho. Dá para abrir numa
planilha e fazer um gráfico de linhas, uma por nó:

```
dia,ciclo,n0:honesto,n1:honesto,n2:desonesto,...
0,0,10000,10000,10000,...
1,60,10000,10000,9500,...
```

O `summary.txt` e o `cycles.csv` também medem se cada ação chega a todos
os nós antes da próxima. Isso ajuda a ver se a rede "dá conta", mas não é
o foco.

---

## 8. Como rodar

Na raiz do projeto, com Docker:

```bash
docker compose run --rm sim                 # padrão: 100 ciclos
CYCLES=5400 docker compose run --rm sim     # 90 dias
DISHONEST=4 SEED=7 docker compose run --rm sim
FULL_LOG=1 docker compose run --rm sim      # mostra também syncs e consultas
```

Sem Docker (precisa de `freechains` 0.20, bash ≥ 5, `git`, `ssh-keygen`):

```bash
cd src && ./simul.sh
```

| Variável | Padrão | Para quê |
|---|---|---|
| `TOPOLOGY` | `topologias/default.dot` | a rede, relativa a `src/` (`default.dot`: 10 nós; também `linha.dot`, `estrela.dot`) |
| `CYCLES` | `100` | quantos ciclos (60 = 1 dia) |
| `SEED` | `42` | mesma seed = mesma simulação |
| `PIONEERS` | `5` | quantos dos primeiros nós são pioneiros |
| `DISHONEST` | `2` | quantos nós desonestos |
| `SHOW_CYCLES` | `0` | `1`: separa o terminal também por ciclo |
| `FULL_LOG` | `0` | `1`: mostra syncs e consultas no terminal |

Os valores fixos (like 100, dislike 500, 24 min por ciclo, ...) ficam em
`src/lib/01-config.sh`.

---

## 9. O código

O código fica em `src/`. `src/simul.sh` é o roteiro; cada parte está em
`src/lib/`, numerada na ordem de
leitura. O comportamento dos nós (seções 3 e 4) está em
**`src/lib/09-behavior.sh`**, a partir da função `node_acts`. Todas as
variáveis estão explicadas em `src/lib/02-state.sh`.

| Arquivo (em `src/lib/`) | O que faz |
|---|---|
| `01-config.sh`, `02-state.sh` | parâmetros, valores fixos e variáveis |
| `03-random.sh` | sorteios com `SEED` |
| `04-terminal.sh`, `05-freechains.sh` | roda e mostra os comandos da CLI |
| `06-topology.sh`, `07-setup.sh` | lê o `.dot`, prepara chaves, chain e servidores |
| `08-actions.sh` | o caderno de ações (quem fez o quê) |
| `09-behavior.sh` | **o que cada nó decide fazer** |
| `10-sync.sh`, `11-measure.sh` | syncs e medição |
| `12-report.sh` | `reps.csv`, `summary.txt`, reputação final |

---

## 10. Melhorias e o que não foi coberto

**Comportamento dos desonestos**
- **Desonesto esperto**: alternar posts bons e ruins, ou postar ruim só de
  vez em quando, para escapar dos dislikes.
- **Contra-ataque**: dar dislike nos honestos.
- **Várias identidades** (Sybil): um mesmo atacante com várias chaves.
- **Conluio organizado**: hoje os desonestos só curtem posts ruins ao acaso.

**Comportamento dos honestos**
- **Erros de julgamento**: hoje os honestos sempre acertam a qualidade.
  Na vida real, julgar é subjetivo.
- **Honestos com menos de 500** não conseguem punir. Votos menores não
  foram testados.
- **Valores dos votos** fixos (100 e 500). Variar esses valores mostraria o
  efeito de punir mais forte ou mais fraco.
- **Revoke** (esconder o conteúdo de um post ruim) não é usado.

**Rede e tempo**
- **Rede estática**: nós sempre ligados, sem gente entrando ou saindo e
  sem falhas.
- **Ritmo de ações fixo** (1/n por ciclo). Não há dias mais ou menos
  movimentados.
- **Uma máquina só**: sem atrasos reais de rede.
- **Beg vencido**: o `abandon` descarta o beg só no nó que o roda, e os
  vizinhos podem devolvê-lo. "Simplesmente não admitir" seria mais fiel.

**Análise**
- **Rodar em lote** várias seeds e redes, e comparar as curvas de
  reputação.
- **Gráficos gerados automaticamente** a partir do `reps.csv`.
- **Reputação na visão de cada nó**, não só na do primeiro.
