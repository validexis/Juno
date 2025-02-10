#!/bin/bash
sudo apt update && apt upgrade -y
sudo apt install -y curl git jq lz4 build-essential

sudo rm -rf /usr/local/go
curl -Ls https://go.dev/dl/go1.23.0.linux-amd64.tar.gz | sudo tar -xzf - -C /usr/local
eval $(echo 'export PATH=$PATH:/usr/local/go/bin' | sudo tee /etc/profile.d/golang.sh)
eval $(echo 'export PATH=$PATH:$HOME/go/bin' | tee -a $HOME/.profile)
echo "export PATH=$PATH:/usr/local/go/bin:/usr/local/bin:$HOME/go/bin" >> $HOME/.bash_profile
source $HOME/.bash_profile

cd $HOME
rm -rf juno
git clone https://github.com/CosmosContracts/juno juno
cd juno
git checkout v27.0.0
make install

junod config chain-id juno-1
junod config keyring-backend file
junod config node tcp://localhost:26657

junod init Node --chain-id=juno-1

wget -L -O $HOME/.juno/config/genesis.json https://server-1.stavr.tech/Mainnet/Juno/genesis.json
wget -O $HOME/.juno/config/addrbook.json "https://server-1.stavr.tech/Mainnet/Juno/addrbook.json"

sed -i -e "s/^filter_peers *=.*/filter_peers = \"true\"/" $HOME/.juno/config/config.toml
external_address=$(wget -qO- eth0.me) 
sed -i.bak -e "s/^external_address *=.*/external_address = \"$external_address:26656\"/" $HOME/.juno/config/config.toml
peers=""
sed -i.bak -e "s/^persistent_peers *=.*/persistent_peers = \"$peers\"/" $HOME/.juno/config/config.toml
seeds=""

sed -i.bak -e "s/^minimum-gas-prices *=.*/minimum-gas-prices = \"0.025ujuno\"/;" $HOME/.juno/config/app.toml
sed -i -e "s/prometheus = false/prometheus = true/" $HOME/.juno/config/config.toml
sed -i -e "s/^indexer *=.*/indexer = \"null\"/" $HOME/.juno/config/config.toml

pruning="custom"
pruning_keep_recent="1000"
pruning_keep_every="0"
pruning_interval="10"
sed -i -e "s/^pruning *=.*/pruning = \"$pruning\"/" $HOME/.juno/config/app.toml
sed -i -e "s/^pruning-keep-recent *=.*/pruning-keep-recent = \"$pruning_keep_recent\"/" $HOME/.juno/config/app.toml
sed -i -e "s/^pruning-keep-every *=.*/pruning-keep-every = \"$pruning_keep_every\"/" $HOME/.juno/config/app.toml
sed -i -e "s/^pruning-interval *=.*/pruning-interval = \"$pruning_interval\"/" $HOME/.juno/config/app.toml

CUSTOM_PORT=165

sed -i -e "s%^proxy_app = \"tcp://127.0.0.1:26658\"%proxy_app = \"tcp://127.0.0.1:${CUSTOM_PORT}58\"%; s%^laddr = \"tcp://127.0.0.1:26657\"%laddr = \"tcp://127.0.0.1:${CUSTOM_PORT}57\"%; s%^pprof_laddr = \"localhost:6060\"%pprof_laddr = \"localhost:${CUSTOM_PORT}60\"%; s%^laddr = \"tcp://0.0.0.0:26656\"%laddr = \"tcp://0.0.0.0:${CUSTOM_PORT}56\"%; s%^prometheus_listen_addr = \":26660\"%prometheus_listen_addr = \":${CUSTOM_PORT}66\"%" $HOME/.juno/config/config.toml
sed -i -e "s%^address = \"tcp://localhost:1317\"%address = \"tcp://localhost:${CUSTOM_PORT}17\"%; s%^address = \":8080\"%address = \":${CUSTOM_PORT}80\"%; s%^address = \"localhost:9090\"%address = \"localhost:${CUSTOM_PORT}90\"%; s%^address = \"localhost:9091\"%address = \"localhost:${CUSTOM_PORT}91\"%; s%^address = \"0.0.0.0:8545\"%address = \"0.0.0.0:${CUSTOM_PORT}45\"%; s%^ws-address = \"0.0.0.0:8546\"%ws-address = \"0.0.0.0:${CUSTOM_PORT}46\"%" $HOME/.juno/config/app.toml

junod config node tcp://localhost:${CUSTOM_PORT}57

sudo tee /etc/systemd/system/junod.service > /dev/null <<EOF
[Unit]
Description=juno
After=network-online.target

[Service]
User=$USER
ExecStart=$(which junod) start
Restart=on-failure
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

LATEST_SNAPSHOT=$(curl -s https://server-1.stavr.tech/Mainnet/Juno/ | grep -oE 'juno-snap-[0-9]+\.tar\.lz4' | while read SNAPSHOT; do HEIGHT=$(curl -s "https://server-1.stavr.tech/Mainnet/Juno/${SNAPSHOT%.tar.lz4}-info.txt" | awk '/Block height:/ {print $3}'); echo "$SNAPSHOT $HEIGHT"; done | sort -k2 -nr | head -n 1 | awk '{print $1}')
curl -o - -L https://server-1.stavr.tech/Mainnet/Juno/$LATEST_SNAPSHOT | lz4 -c -d - | tar -x -C $HOME/.juno

sudo systemctl daemon-reload
sudo systemctl enable junod
sudo systemctl restart junod && sudo journalctl -u junod -fo cat
