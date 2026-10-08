FROM ubuntu:24.04

# Freechains runtime deps (+ procps: pkill usado por src/simul.sh)
RUN apt-get update && apt-get install -y \
        git \
        openssh-client \
        lua5.4 \
        liblua5.4-dev \
        xxd \
        telnet \
        curl \
        procps \
        luarocks && \
    rm -rf /var/lib/apt/lists/*

# versão fixa da CLI usada pela simulação
ARG FREECHAINS_VERSION=0.20-1
RUN luarocks --lua-version=5.4 install freechains ${FREECHAINS_VERSION}

# a simulação (src/) não entra na imagem: o compose.yaml monta a pasta

CMD ["bash"]
