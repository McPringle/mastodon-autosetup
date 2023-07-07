#!/bin/bash
set -e

###############################################
#        This is the settings section.        #
# You can modify the settings for your needs. #
###############################################

# You need to fill in the following information:
CONTEXT_NAME=""
SSH_KEYS=""

# Modify the server type and data center when needed
SERVER_TYPE="cpx11"
DATA_CENTER="fsn1-dc14"

# Usually you don't need to modify the following settings
SERVER_NAME="mastodon-server"
VOLUME_NAME="mastodon-volume"
FIREWALL_NAME="mastodon-firewall"

#########################################
#       This is the script section.     #
# Please do not modify the lines below. #
#########################################

# Check for the context name
if [ -z $CONTEXT_NAME ]; then
    echo "Please edit this script add your Hetzner cloud context name on line 10."
    exit 1;
fi

# Check for the SSH keys
if [ -z $SSH_KEYS ]; then
    echo "Please edit this script add your SSH key names comma separated on line 11."
    exit 1;
fi

# Select the cloud context (project)
hcloud context use $CONTEXT_NAME

# Create primary IPs if not yet done
if [ -z "$(hcloud primary-ip list -o noheader -o columns=name | grep $SERVER_NAME)" ]; then
    hcloud primary-ip create --name ${SERVER_NAME}-ipv4 --type ipv4 --datacenter $DATA_CENTER
    hcloud primary-ip create --name ${SERVER_NAME}-ipv6 --type ipv6 --datacenter $DATA_CENTER
fi

# Create firewall if not yet done
if [ -z "$(hcloud firewall list -o noheader -o columns=name | grep $FIREWALL_NAME)" ]; then
    hcloud firewall create --name $FIREWALL_NAME --rules-file firewall-config.json
fi

# Shutdown and delete server (IPs will be preserved)
if [ ! -z "$(hcloud server list -o noheader -o columns=name | grep $SERVER_NAME)" ]; then
    hcloud server shutdown $SERVER_NAME
    hcloud server delete $SERVER_NAME
fi

# Create the server instance
hcloud server create \
    --primary-ipv4 ${SERVER_NAME}-ipv4 \
    --primary-ipv6 ${SERVER_NAME}-ipv6 \
    --start-after-create=false \
    --datacenter $DATA_CENTER \
    --image debian-12 \
    --name $SERVER_NAME \
    --ssh-key $SSH_KEYS \
    --type $SERVER_TYPE \
    # --user-data-from-file ci-mastodon.yaml

## Create volume if needed or attach existing volume
if [ -z "$(hcloud volume list -o noheader -o columns=name | grep $VOLUME_NAME)" ]; then
    hcloud volume create --name $VOLUME_NAME --server $SERVER_NAME --size 10 --automount --format ext4
else
    hcloud volume attach --server $SERVER_NAME $VOLUME_NAME
fi

# Apply the firewall to the server
hcloud firewall apply-to-resource $FIREWALL_NAME --server $SERVER_NAME --type server

# Start the server
hcloud server poweron $SERVER_NAME

# Enable daily server backup
hcloud server enable-backup $SERVER_NAME