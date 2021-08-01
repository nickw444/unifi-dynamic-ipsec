#!/bin/bash
set -eu

# Hack for dynamic DNS IPSec Site-to-Site VPN
# This script should be scheduled to run periodically re-establish VPN on IP change
# See https://blog.azureinfra.com/2018/12/31/usg-vpns-and-dynamic-ips/
# 
# IKE Group is used to identify existing configuration entry. It can be found
# initially via `configure; show vpn ipsec site-to-site peer`

cfg=/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper

help_and_exit() {
    echo "Usage: $0 --peer-domain foo.dyn.com --ike-group IKE_127.0.0.1 [-h|--help] [-d|--dryrun] [-c|--config]";
    exit 1;
}

main() {
    local newLocal;
    local newPeer;
    local currentPeer;
    local currentLocal;
    local newConfig;
    local extraArgs="";

    local peerDomain="";
    local ikeGroup="";
    local force=false;

    while [[ $# -gt 0 ]]; do
        key="$1"
        case $key in
            -d|--dryrun)
                cfg="echo cfg";
                shift;
                ;;
            -h|--help)
                help_and_exit;
                ;;
            -c|--config)
                extraArgs="--config-json $2"
                shift;
                shift;
                ;;
            -p|--peer-domain)
                peerDomain="$2";
                shift;
                shift;
                ;;
            -i|--ike-group)
                ikeGroup="$2";
                shift;
                shift;
                ;;
            -f|--force)
                force=true
                shift;
                ;;
            *)
                echo "Unknown argument: $key";
                help_and_exit;
                ;;
        esac
    done

    if [[ -z "$peerDomain" ]] || [[ -z "$ikeGroup" ]]; then
        echo "--peer-domain and --ike-group must be specified";
        help_and_exit;
    fi

    currentPeer=$(set -eu; ./dynamic-ipsec-utils.py get-peer-address "$ikeGroup" $extraArgs)
    currentLocal=$(set -eu; ./dynamic-ipsec-utils.py get-local-address "$ikeGroup" $extraArgs)

    newPeer=$(set -eu; ./dynamic-ipsec-utils.py lookup "$peerDomain");
    newLocal=$(set -eu; curl -s --retry 3 https://api.ipify.org/);

    if [[ "$currentLocal" == "$newLocal" ]] && [[ "$currentPeer" == "$newPeer" ]] && [ $force == false ]; then
        echo "Everything up to date."
        exit 0;
    fi

    echo "Config outdated. Updating..."
    echo "Current Peer: '$currentPeer'";
    echo "Current Local: '$currentLocal'";
    echo "New Peer: '$newPeer'";
    echo "New Local: '$newLocal'";

    newConfig=$(set -eu; ./dynamic-ipsec-utils.py get-config "$ikeGroup" $extraArgs --new-local-address "$newLocal" --new-peer-address "$newPeer")

    $cfg begin
    $cfg delete vpn ipsec site-to-site peer "$currentPeer";
    xargs -L 1 $cfg < <(printf '%s\n' "$newConfig")

    $cfg commit
    $cfg save
    $cfg end
}

main "$@"
