#!/bin/bash
set -e

# ==============================================================================
# KVision Configuration Backup Setup Script
# ==============================================================================
#
# DESCRIPTION:
#   This script sets up a systemd user-level timer and service to automatically
#   back up the KVision configuration file every 3 hours and clean up any backup
#   files older than 60 days.
#
# INSTRUCTIONS FOR USE:
#   1. Make the script executable:
#      chmod +x setup-backup.sh
#
#   2. Run the script as a regular user (DO NOT run as root/sudo):
#      ./setup-backup.sh
#
#   3. To manually run a backup immediately:
#      systemctl --user start kvision-backup.service
#
#   4. To check the timer status and when the next backup is scheduled:
#      systemctl --user status kvision-backup.timer
#
#   5. To view the backups:
#      ls -la ~/.config/KVision/backups/
#
# ==============================================================================

CONFIG_DIR="${HOME}/.config/KVision"
BACKUP_DIR="${CONFIG_DIR}/backups"
BACKUP_SCRIPT="${CONFIG_DIR}/backup.sh"
SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"

# 1. Create config and backups directories
echo "Creating directories..."
mkdir -p "${BACKUP_DIR}"
mkdir -p "${SYSTEMD_USER_DIR}"

# 2. Create the backup script
echo "Creating backup script at ${BACKUP_SCRIPT}..."
cat << 'EOF' > "${BACKUP_SCRIPT}"
#!/bin/bash
CONFIG_DIR="${HOME}/.config/KVision"
BACKUP_DIR="${CONFIG_DIR}/backups"
CONFIG_FILE="${CONFIG_DIR}/KVision.conf"

# Create backup directory if missing
mkdir -p "${BACKUP_DIR}"

# Copy configuration file if it exists
if [ -f "${CONFIG_FILE}" ]; then
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    cp "${CONFIG_FILE}" "${BACKUP_DIR}/KVision_${TIMESTAMP}.conf"
    echo "Backup created: KVision_${TIMESTAMP}.conf"
else
    echo "Config file not found: ${CONFIG_FILE}"
fi

# Clean up backups older than 60 days
find "${BACKUP_DIR}" -name "KVision_*.conf" -type f -mtime +60 -delete
echo "Old backups cleaned up."
EOF

# 3. Make the backup script executable
chmod +x "${BACKUP_SCRIPT}"

# 4. Create the systemd user service
SERVICE_FILE="${SYSTEMD_USER_DIR}/kvision-backup.service"
echo "Creating systemd service at ${SERVICE_FILE}..."
cat << EOF > "${SERVICE_FILE}"
[Unit]
Description=KVision configuration backup service

[Service]
Type=oneshot
ExecStart=${BACKUP_SCRIPT}
EOF

# 5. Create the systemd user timer
TIMER_FILE="${SYSTEMD_USER_DIR}/kvision-backup.timer"
echo "Creating systemd timer at ${TIMER_FILE}..."
cat << EOF > "${TIMER_FILE}"
[Unit]
Description=KVision configuration backup timer

[Timer]
OnCalendar=*-*-* 00/3:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

# 6. Reload systemd user daemon and enable/start timer
echo "Reloading systemd user daemon and enabling timer..."
systemctl --user daemon-reload
systemctl --user enable --now kvision-backup.timer

# 7. Check status
echo "Checking timer status..."
systemctl --user status kvision-backup.timer | head -n 15

echo "Setup completed successfully!"
