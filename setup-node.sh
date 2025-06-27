#!/bin/bash
set -e

#
# This script is run on a node to configure cosmovisor, systemctl,
# seda, prometheus, and seda-cosmos-accelerator.
#
# NOTE: Assumes Amazon Linux 2023

SEDA_RPC_URL_1=
SEDA_RPC_URL_2=
SEDA_NETWORK=
SEDA_VERSION=
SEDA_NODE_NAME=
ACCELERATOR_VERSION=

# Check that RPC_URL is set
if [ -z "${SEDA_RPC_URL_1}" ] || [ -z "${SEDA_RPC_URL_2}" ]; then
    echo "Error: SEDA_RPC_URL_1 and SEDA_RPC_URL_2 environment variables are not set"
    exit 1
fi

# Check that SEDA_NETWORK is set
if [ -z "${SEDA_NETWORK}" ]; then
    echo "Error: SEDA_NETWORK environment variable is not set"
    exit 1
fi

# Check that SEDA_VERSION is set
if [ -z "${SEDA_VERSION}" ]; then
    echo "Error: SEDA_VERSION environment variable is not set"
    exit 1
fi

# Check that SEDA_NODE_NAME is set
if [ -z "${SEDA_NODE_NAME}" ]; then
    echo "Error: SEDA_NODE_NAME environment variable is not set"
    exit 1
fi

# Check that ACCELERATOR_VERSION is set
if [ -z "${ACCELERATOR_VERSION}" ]; then
    echo "Warning: ACCELERATOR_VERSION environment variable is not set"
    read -p "Do you want to continue without setting ACCELERATOR_VERSION? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Exiting..."
        exit 1
    fi
fi

ARCH=$(uname -m)
if [ $ARCH != "aarch64" ]; then
	ARCH="x86_64"
fi

COSMOVISOR_URL=https://github.com/cosmos/cosmos-sdk/releases/download/cosmovisor%2Fv1.3.0/cosmovisor-v1.3.0-linux-amd64.tar.gz
if [ $ARCH = "aarch64" ]; then
	COSMOVISOR_URL=https://github.com/cosmos/cosmos-sdk/releases/download/cosmovisor%2Fv1.3.0/cosmovisor-v1.3.0-linux-arm64.tar.gz
fi

COSMOS_LDS=$HOME/COSMOS_LDS
SYSFILE=/etc/systemd/system/seda-node.service

# Set up cosmovisor if it has not been installed yet.
if ! which cosmovisor >/dev/null; then
	printf "\n\n\nSETTING UP COSMOVISOR\n\n\n\n"

	curl -LO $COSMOVISOR_URL
	mkdir -p tmp
	tar -xzvf $(basename $COSMOVISOR_URL) -C ./tmp
	sudo mv ./tmp/cosmovisor /usr/local/bin
	rm -rf ./tmp $(basename $COSMOVISOR_URL)

	echo 'export DAEMON_NAME=sedad' >> $HOME/.bashrc
	echo 'export DAEMON_HOME=$HOME/.sedad' >> $HOME/.bashrc
	echo 'export DAEMON_DATA_BACKUP_DIR=$HOME/.sedad' >> $HOME/.bashrc
	echo 'export DAEMON_ALLOW_DOWNLOAD_BINARIES=false' >> $HOME/.bashrc
	echo 'export DAEMON_RESTART_AFTER_UPGRADE=true' >> $HOME/.bashrc
	echo 'export UNSAFE_SKIP_BACKUP=false' >> $HOME/.bashrc
	echo 'export DAEMON_POLL_INTERVAL=300ms' >> $HOME/.bashrc
	echo 'export DAEMON_RESTART_DELAY=30s' >> $HOME/.bashrc
	echo 'export DAEMON_LOG_BUFFER_SIZE=512' >> $HOME/.bashrc
	echo 'export DAEMON_PREUPGRADE_MAX_RETRIES=0' >> $HOME/.bashrc
	echo 'export PATH=$PATH:$HOME/.sedad/cosmovisor/current/bin' >> $HOME/.bashrc

	source $HOME/.bashrc
fi


# Create systemctl service file if it does not exist.
if [ ! -f $SYSFILE ]; then
printf "\n\n\nSETTING UP SYSTEMCTL\n\n\n\n"

sudo tee /etc/systemd/system/seda-node.service > /dev/null <<EOF
[Unit]
Description=Seda Node Service
After=network-online.target

[Service]
Environment="DAEMON_NAME=sedad"
Environment="DAEMON_HOME=$HOME/.sedad"
Environment="DAEMON_DATA_BACKUP_DIR=$HOME/.sedad"

Environment="DAEMON_ALLOW_DOWNLOAD_BINARIES=false"
Environment="DAEMON_RESTART_AFTER_UPGRADE=true"
Environment="UNSAFE_SKIP_BACKUP=false"

Environment="DAEMON_POLL_INTERVAL=300ms"
Environment="DAEMON_RESTART_DELAY=30s"
Environment="DAEMON_LOG_BUFFER_SIZE=512"
Environment="DAEMON_PREUPGRADE_MAX_RETRIES=0"

User=$USER
ExecStart=$(which cosmovisor) run start
Restart=always
RestartSec=3
LimitNOFILE=65535
LimitMEMLOCK=200M

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable seda-node
fi

# Download and install seda-cosmos-accelerator
if [ ! -z "${ACCELERATOR_VERSION}" ]; then
    ACCELERATOR_URL=https://github.com/sedaprotocol/seda-cosmos-accelerator/releases/download/${ACCELERATOR_VERSION}/seda-cosmos-accelerator-linux-x64
    if [ $ARCH = "aarch64" ]; then
        ACCELERATOR_URL=https://github.com/sedaprotocol/seda-cosmos-accelerator/releases/download/${ACCELERATOR_VERSION}/seda-cosmos-accelerator-linux-arm64
    fi

    curl -LO $ACCELERATOR_URL
    mv $(basename $ACCELERATOR_URL) ./seda-cosmos-accelerator
    chmod +x ./seda-cosmos-accelerator

    ACCELERATOR_SYSFILE=/etc/systemd/system/seda-cosmos-accelerator.service

    if [ ! -f $ACCELERATOR_SYSFILE ]; then
        printf "\n\n\nSETTING UP SEDA COSMOS ACCELERATOR\n\n\n\n"

        sudo tee /etc/systemd/system/seda-cosmos-accelerator.service > /dev/null <<EOF
[Unit]
Description=Seda Cosmos Accelerator
Wants=network-online.target
After=network-online.target

[Service]
User=ec2-user
Type=simple
ExecStart=/home/ec2-user/seda-cosmos-accelerator start -p 5384 -s localhost:26657
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target

EOF

        sudo systemctl daemon-reload
        sudo systemctl enable seda-cosmos-accelerator
    fi
else
    echo "ACCELERATOR_VERSION environment variable is not set, skipping seda-cosmos-accelerator"
fi

# Download and install prometheus node exporter
NODE_EXPORTER_URL=https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
if [ $ARCH = "aarch64" ]; then
	NODE_EXPORTER_URL=https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-arm64.tar.gz
fi

curl -LO $NODE_EXPORTER_URL
tar -xzvf $(basename $NODE_EXPORTER_URL)
NODE_EXPORTER_DIR=$(basename $NODE_EXPORTER_URL .tar.gz)
sudo mv $NODE_EXPORTER_DIR/node_exporter /usr/local/bin/node_exporter
rm -rf $NODE_EXPORTER_DIR $(basename $NODE_EXPORTER_URL)

NODE_EXPORTER_SYSFILE=/etc/systemd/system/node-exporter.service

if [ ! -f $NODE_EXPORTER_SYSFILE ]; then
printf "\n\n\nSETTING UP NODE EXPORTER\n\n\n\n"

sudo tee /etc/systemd/system/node-exporter.service > /dev/null <<EOF
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=ec2-user
Type=simple
ExecStart=/usr/local/bin/node_exporter
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target

EOF

sudo systemctl daemon-reload
sudo systemctl enable node-exporter
fi

# Download and prepare SEDA
SEDA_URL=https://github.com/sedaprotocol/seda-chain/releases/download/${SEDA_VERSION}/sedad-amd64
if [ $ARCH = "aarch64" ]; then
	SEDA_URL=https://github.com/sedaprotocol/seda-chain/releases/download/${SEDA_VERSION}/sedad-linux-arm64
fi

curl -LO $SEDA_URL
mv $(basename $SEDA_URL) ./sedad
chmod +x ./sedad

sedad join $SEDA_NODE_NAME --network $SEDA_NETWORK
cosmovisor init ./sedad

sed 's|prometheus = false|prometheus = true|g' .sedad/config/config.toml -i
cosmovisor run config set app telemetry.enabled true
cosmovisor run config set app telemetry.prometheus-retention-time 60
cosmovisor run config set app seda.enable-seda-signer false

# Get statesync info
BLOCK_INFO=$(curl -s $SEDA_RPC_URL_1/block)
BLOCK_HEIGHT=$(echo $BLOCK_INFO | jq '.result.block.header.height' | sed 's/"//g')
BLOCK_HASH=$(echo $BLOCK_INFO | jq '.result.block_id.hash')

echo "BLOCK_HEIGHT: $BLOCK_HEIGHT"
echo "BLOCK_HASH: $BLOCK_HASH"

# Lucky that no other config has this generic attribute name
sed 's|enable = false|enable = true|g' .sedad/config/config.toml -i

sed 's|rpc_servers = ""|rpc_servers = "'$SEDA_RPC_URL_1,$SEDA_RPC_URL_2'"|g' .sedad/config/config.toml -i
sed 's|trust_height = 0|trust_height = '$BLOCK_HEIGHT'|g' .sedad/config/config.toml -i
sed 's|trust_hash = ""|trust_hash = '$BLOCK_HASH'|g' .sedad/config/config.toml -i

# Start all the services
sudo systemctl start seda-node
sudo systemctl start seda-cosmos-accelerator
sudo systemctl start node-exporter

echo "Done setting up node"
echo "Monitor progress with journalctl -u seda-node -f"

PUBLIC_IP=$(curl -s ipecho.net/plain)

echo "Don't forget to add this node to the monitoring scraping config: ['$PUBLIC_IP:26660','$PUBLIC_IP:9100']"
echo "Don't forget to add this node to the target group if it's an RPC node"
