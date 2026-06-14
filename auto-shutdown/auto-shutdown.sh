#!/bin/bash

# Install script for auto shutdown

# Move the main script to the script directory and make it executable
readonly SCRIPT_DIR='/usr/local/sbin'

# function to create the main script with the provided parameters
create_script() {
    cat << EOF > "$SCRIPT_DIR/auto-shutdown.sh"
#!/bin/bash
set -euo pipefail

readonly ROUTER_IP='$1'
readonly DELAY_IN_SECOND=$2
readonly DROP_LIMIT=$3
readonly LOG_FILE='/var/log/auto-shutdown.log'

log() {
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$*" >> "\$LOG_FILE"
}

DROP_COUNT=0

while true; do
    sleep "\$DELAY_IN_SECOND"

    if ping -q -c1 -w5 "\$ROUTER_IP" > /dev/null 2>&1; then
        DROP_COUNT=0
    else
        if [ "\$DROP_COUNT" -eq 0 ]; then
            log "********** Connection lost to \$ROUTER_IP at \$(date '+%Y-%m-%d %H:%M:%S') **********"
        fi
        DROP_COUNT=\$((DROP_COUNT + 1))
        log "Connection drop #\${DROP_COUNT}"
    fi

    if [ "\$DROP_COUNT" -ge "\$DROP_LIMIT" ]; then
        log "*** Shutting down after \${DROP_LIMIT} consecutive failures ***"
        sudo shutdown -h now
        break
    fi
done
EOF

    chmod +x "$SCRIPT_DIR/auto-shutdown.sh"
}

# create a service file for auto shutdown
create_service() {
    SERVICE_FILE="[Unit]
Description= Script Auto Shutdown

[Service]
Type=simple
ExecStart=/usr/bin/bash "$SCRIPT_DIR/auto-shutdown.sh"
Restart=always

[Install]
WantedBy=default.target"

    echo "$SERVICE_FILE" | tee /etc/systemd/system/autoshutdown.service > /dev/null
    chmod 644 /etc/systemd/system/autoshutdown.service

    systemctl daemon-reload
    systemctl start autoshutdown.service
    systemctl enable autoshutdown.service
}

# function to uninstall the auto shutdown script and service
uninstall() {
    echo "Stopping and disabling auto shutdown service..."
    systemctl stop autoshutdown.service
    systemctl disable autoshutdown.service

    echo "Removing service file and script..."
    rm /etc/systemd/system/autoshutdown.service
    rm "$SCRIPT_DIR/auto-shutdown.sh"
    systemctl daemon-reload

    echo "Auto shutdown script and service uninstalled successfully."
}

# check requirement before installation
check_requirements() {
    echo "Checking requirements..."
    if ! command -v ping > /dev/null 2>&1; then
        echo "Error: ping command not found. Please install the 'iputils-ping' package."
        exit 1
    else
        echo "All requirements are met."
    fi
}

# Main function to execute the installation steps
main() {
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root or use sudo. Thanks!"
        exit 1
    fi
    
    if [ "$1" = "uninstall" ] && [ "$#" -eq 1 ]; then
        uninstall
    elif [ "$1" = "install" ] && [ "$#" -eq 4 ]; then
        check_requirements
        create_script "$2" "$3" "$4"
        create_service
        echo "Auto shutdown script installed and service created successfully."
    else
        clear
        echo "Usage: $0 install/uninstall <ROUTER-IP-ADDRESS> <DELAY-IN-SECOND> <DROP-LIMIT>"
        echo "Example: $0 install 192.168.1.1 60 5"
        echo "This will check the connection to the specified router every 60 seconds and shut down the system after 5 consecutive failures."
    fi

    exit 1

}

main "$@"