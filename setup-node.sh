#!/bin/bash
set -e

#
# This script is run on a node to configure cosmovisor, systemctl,
# seda, prometheus, and seda-cosmos-accelerator.
#
# Usage: ./setup-node.sh [OPTIONS]
# Options:
#   --all                    Run all setup steps
#   --cosmovisor            Setup cosmovisor only
#   --accelerator           Setup seda-cosmos-accelerator only
#   --node-exporter         Setup prometheus node exporter only
#   --seda                  Setup SEDA node only
#   --help                  Show this help message
#
# NOTE: Assumes Amazon Linux 2023

# Set these variables to the values you want to use in the script
# or provide them as environment variables
# SEDA_RPC_URL_1=
# SEDA_RPC_URL_2=
# SEDA_NETWORK=mainnet|testnet|devnet
# SEDA_VERSION=v1.0.0|v0.1.10|...
# SEDA_NODE_NAME=
# ACCELERATOR_VERSION=v...

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

This script sets up a SEDA node with various components.

OPTIONS:
    --all                    Run all setup steps
    --cosmovisor            Setup cosmovisor only
    --accelerator           Setup seda-cosmos-accelerator only
    --node-exporter         Setup prometheus node exporter only
    --seda                  Setup SEDA node only
    --help                  Show this help message

ENVIRONMENT VARIABLES:
    SEDA_RPC_URL_1          Primary RPC URL for SEDA
    SEDA_RPC_URL_2          Secondary RPC URL for SEDA
    SEDA_NETWORK            SEDA network name
    SEDA_VERSION            SEDA version to install
    SEDA_NODE_NAME          SEDA node name
    ACCELERATOR_VERSION     SEDA cosmos accelerator version (optional)

EXAMPLES:
    $0 --all                           # Run all steps
    $0 --cosmovisor                    # Setup cosmovisor and its service
    $0 --seda                          # Setup SEDA node and its service
EOF
}

# Function to validate environment variables
validate_env_vars() {
    local missing_vars=()
    local required_steps=("$@")
    
    # Check for variables needed by specific steps
    for step in "${required_steps[@]}"; do
        case $step in
            "seda")
                if [ -z "${SEDA_RPC_URL_1}" ]; then missing_vars+=("SEDA_RPC_URL_1"); fi
                if [ -z "${SEDA_RPC_URL_2}" ]; then missing_vars+=("SEDA_RPC_URL_2"); fi
                if [ -z "${SEDA_NETWORK}" ]; then missing_vars+=("SEDA_NETWORK"); fi
                if [ -z "${SEDA_VERSION}" ]; then missing_vars+=("SEDA_VERSION"); fi
                if [ -z "${SEDA_NODE_NAME}" ]; then missing_vars+=("SEDA_NODE_NAME"); fi
                ;;
            "accelerator")
                if [ -z "${ACCELERATOR_VERSION}" ]; then missing_vars+=("ACCELERATOR_VERSION"); fi
                ;;
        esac
    done
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        print_error "Missing required environment variables for the requested steps:"
        for var in "${missing_vars[@]}"; do
            echo "  - $var"
        done
        exit 1
    fi
}

# Function to get architecture
get_architecture() {
    ARCH=$(uname -m)
    if [ $ARCH != "aarch64" ]; then
        ARCH="x86_64"
    fi
    echo $ARCH
}

# Function to setup cosmovisor
setup_cosmovisor() {
    print_status "Setting up cosmovisor..."
    
    if which cosmovisor >/dev/null; then
        print_success "Cosmovisor is already installed"
    else
        ARCH=$(get_architecture)
        COSMOVISOR_URL=https://github.com/cosmos/cosmos-sdk/releases/download/cosmovisor%2Fv1.3.0/cosmovisor-v1.3.0-linux-amd64.tar.gz
        if [ $ARCH = "aarch64" ]; then
            COSMOVISOR_URL=https://github.com/cosmos/cosmos-sdk/releases/download/cosmovisor%2Fv1.3.0/cosmovisor-v1.3.0-linux-arm64.tar.gz
        fi
        
        curl -LO $COSMOVISOR_URL
        mkdir -p tmp
        tar -xzvf $(basename $COSMOVISOR_URL) -C ./tmp
        sudo mv ./tmp/cosmovisor /usr/local/bin
        rm -rf ./tmp $(basename $COSMOVISOR_URL)
        
        # Add environment variables to bashrc
        cat >> $HOME/.bashrc << 'EOF'
export DAEMON_NAME=sedad
export DAEMON_HOME=$HOME/.sedad
export DAEMON_DATA_BACKUP_DIR=$HOME/.sedad
export DAEMON_ALLOW_DOWNLOAD_BINARIES=false
export DAEMON_RESTART_AFTER_UPGRADE=true
export UNSAFE_SKIP_BACKUP=false
export DAEMON_POLL_INTERVAL=300ms
export DAEMON_RESTART_DELAY=30s
export DAEMON_LOG_BUFFER_SIZE=512
export DAEMON_PREUPGRADE_MAX_RETRIES=0
export PATH=$PATH:$HOME/.sedad/cosmovisor/current/bin
EOF
        
        source $HOME/.bashrc
        print_success "Cosmovisor installation completed"
    fi
    
    # Setup systemctl service for SEDA node
    setup_seda_systemctl_service
}

# Function to setup SEDA systemctl service
setup_seda_systemctl_service() {
    print_status "Setting up SEDA systemctl service..."
    
    SYSFILE=/etc/systemd/system/seda-node.service
    
    if [ -f $SYSFILE ]; then
        print_success "SEDA systemctl service file already exists"
        return 0
    fi
    
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
    print_success "SEDA systemctl service setup completed"
}

# Function to setup seda-cosmos-accelerator
setup_accelerator() {
    print_status "Setting up seda-cosmos-accelerator..."
    
    ARCH=$(get_architecture)
    ACCELERATOR_URL=https://github.com/sedaprotocol/seda-cosmos-accelerator/releases/download/${ACCELERATOR_VERSION}/seda-cosmos-accelerator-linux-x64
    if [ $ARCH = "aarch64" ]; then
        ACCELERATOR_URL=https://github.com/sedaprotocol/seda-cosmos-accelerator/releases/download/${ACCELERATOR_VERSION}/seda-cosmos-accelerator-linux-arm64
    fi
    
    curl -LO $ACCELERATOR_URL
    mv $(basename $ACCELERATOR_URL) ./seda-cosmos-accelerator
    chmod +x ./seda-cosmos-accelerator
    
    # Setup systemctl service for accelerator
    setup_accelerator_systemctl_service
    
    print_success "Seda cosmos accelerator setup completed"
}

# Function to setup accelerator systemctl service
setup_accelerator_systemctl_service() {
    print_status "Setting up accelerator systemctl service..."
    
    ACCELERATOR_SYSFILE=/etc/systemd/system/seda-cosmos-accelerator.service
    
    if [ -f $ACCELERATOR_SYSFILE ]; then
        print_success "Accelerator systemctl service file already exists"
        return 0
    fi
    
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
    print_success "Accelerator systemctl service setup completed"
}

# Function to setup prometheus node exporter
setup_node_exporter() {
    print_status "Setting up prometheus node exporter..."

    # Check if SEDA is enabled, if not warn user
    if [ "$run_seda" != true ] && [ "$run_all_steps" != true ]; then
        print_warning "Node exporter is being set up without SEDA. You will need to edit SEDA settings later to enable metrics collection."
    fi
    
    ARCH=$(get_architecture)
    NODE_EXPORTER_URL=https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
    if [ $ARCH = "aarch64" ]; then
        NODE_EXPORTER_URL=https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-arm64.tar.gz
    fi
    
    curl -LO $NODE_EXPORTER_URL
    tar -xzvf $(basename $NODE_EXPORTER_URL)
    NODE_EXPORTER_DIR=$(basename $NODE_EXPORTER_URL .tar.gz)
    sudo mv $NODE_EXPORTER_DIR/node_exporter /usr/local/bin/node_exporter
    rm -rf $NODE_EXPORTER_DIR $(basename $NODE_EXPORTER_URL)
    
    # Setup systemctl service for node exporter
    setup_node_exporter_systemctl_service
    
    print_success "Node exporter setup completed"
}

# Function to setup node exporter systemctl service
setup_node_exporter_systemctl_service() {
    print_status "Setting up node exporter systemctl service..."
    
    NODE_EXPORTER_SYSFILE=/etc/systemd/system/node-exporter.service
    
    if [ -f $NODE_EXPORTER_SYSFILE ]; then
        print_success "Node exporter systemctl service file already exists"
        return 0
    fi
    
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
    print_success "Node exporter systemctl service setup completed"
}

# Function to setup SEDA node
setup_seda() {
    print_status "Setting up SEDA node..."
    
    ARCH=$(get_architecture)
    SEDA_URL=https://github.com/sedaprotocol/seda-chain/releases/download/${SEDA_VERSION}/sedad-amd64
    if [ $ARCH = "aarch64" ]; then
        print_status "Using ARM64 architecture for SEDA node setup"
        SEDA_URL=https://github.com/sedaprotocol/seda-chain/releases/download/${SEDA_VERSION}/sedad-arm64
    fi
    
    curl -LO $SEDA_URL
    mv $(basename $SEDA_URL) ./sedad
    chmod +x ./sedad
    
    ./sedad join $SEDA_NODE_NAME --network $SEDA_NETWORK
    cosmovisor init ./sedad
    
    # Configure telemetry if node exporter is enabled
    if $run_node_exporter || $run_all_steps; then
        sed 's|prometheus = false|prometheus = true|g' .sedad/config/config.toml -i
        cosmovisor run config set app telemetry.enabled true
        cosmovisor run config set app telemetry.prometheus-retention-time 60
    fi

    # Disable seda signer as we're not spinning up a validator if the version is 1.0.0 or higher
    if [[ $SEDA_VERSION == v1* ]]; then
        print_status "Disabling SEDA signer as version is 1.0.0 or higher"
        cosmovisor run config set app seda.enable-seda-signer false
    fi

    # Get statesync info
    BLOCK_INFO=$(curl -s $SEDA_RPC_URL_1/block)
    BLOCK_HEIGHT=$(echo $BLOCK_INFO | jq '.result.block.header.height' | sed 's/"//g')
    BLOCK_HASH=$(echo $BLOCK_INFO | jq '.result.block_id.hash')
    
    echo "BLOCK_HEIGHT: $BLOCK_HEIGHT"
    echo "BLOCK_HASH: $BLOCK_HASH"
    
    # Configure statesync
    sed 's|enable = false|enable = true|g' .sedad/config/config.toml -i
    sed 's|rpc_servers = ""|rpc_servers = "'$SEDA_RPC_URL_1,$SEDA_RPC_URL_2'"|g' .sedad/config/config.toml -i
    sed 's|trust_height = 0|trust_height = '$BLOCK_HEIGHT'|g' .sedad/config/config.toml -i
    sed 's|trust_hash = ""|trust_hash = '$BLOCK_HASH'|g' .sedad/config/config.toml -i
    
    print_success "SEDA node setup completed"
}

# Function to start all services
start_services() {
    print_status "Starting configured services..."
    
    if $run_seda || $run_all_steps; then
        sudo systemctl start seda-node
        print_status "Monitor progress with: journalctl -u seda-node -f"
    fi
    
    if $run_accelerator || $run_all_steps; then
        sudo systemctl start seda-cosmos-accelerator
    fi
    
    if $run_node_exporter || $run_all_steps; then
        sudo systemctl start node-exporter
    fi
    
    print_success "Services started"
    
    if $run_node_exporter || $run_all_steps; then
        PUBLIC_IP=$(curl -s ipecho.net/plain)
        echo ""
        print_status "Don't forget to add this node to the monitoring scraping config: ['$PUBLIC_IP:26660', '$PUBLIC_IP:9100']"
    fi

    if $run_seda || $run_all_steps; then
        print_status "Don't forget to add this node to the target group if it's an RPC node"
    fi
}

# Function to run all setup steps
run_all() {
    print_status "Running all setup steps..."
    setup_cosmovisor
    setup_accelerator
    setup_node_exporter
    setup_seda
    start_services
    print_success "All setup steps completed successfully!"
}

# Main script logic
main() {
    # Parse command line arguments
    if [ $# -eq 0 ]; then
        show_help
        exit 1
    fi
    
    # Track which steps to run
    run_cosmovisor=false
    run_accelerator=false
    run_node_exporter=false
    run_seda=false
    run_all_steps=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --all)
                run_all_steps=true
                shift
                ;;
            --cosmovisor)
                run_cosmovisor=true
                shift
                ;;
            --accelerator)
                run_accelerator=true
                shift
                ;;
            --node-exporter)
                run_node_exporter=true
                shift
                ;;
            --seda)
                run_seda=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Determine which steps need environment variable validation
    local steps_needing_validation=()
    if [ "$run_all_steps" = true ]; then
        steps_needing_validation=("seda" "accelerator")
    else
        if [ "$run_seda" = true ]; then
            steps_needing_validation+=("seda")
        fi
        if [ "$run_accelerator" = true ]; then
            steps_needing_validation+=("accelerator")
        fi
    fi
    
    # Validate environment variables only for required steps
    if [ ${#steps_needing_validation[@]} -gt 0 ]; then
        validate_env_vars "${steps_needing_validation[@]}"
    fi
    
    # Execute requested steps
    if [ "$run_all_steps" = true ]; then
        run_all
    else
        if [ "$run_cosmovisor" = true ]; then
            setup_cosmovisor
        fi
        
        if [ "$run_accelerator" = true ]; then
            setup_accelerator
        fi
        
        if [ "$run_node_exporter" = true ]; then
            setup_node_exporter
        fi
        
        if [ "$run_seda" = true ]; then
            setup_seda
        fi
        
        # If any services were set up, offer to start them
        if [ "$run_cosmovisor" = true ] || [ "$run_accelerator" = true ] || [ "$run_node_exporter" = true ] || [ "$run_seda" = true ]; then
            echo ""
            read -p "Do you want to start the configured services now? (y/n) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                start_services
            fi
        fi
    fi
}

# Run main function with all arguments
main "$@"
