#!/bin/bash

# MongoDB Restore Script
# This script restores MongoDB databases from backup using mongorestore

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "======================================"
echo "MongoDB Restore Script"
echo "======================================"
echo ""

# Function to read input
read_input() {
    local prompt="$1"
    local var_name="$2"
    read -p "$prompt" $var_name
}

# Function to read password (hidden input)
read_password() {
    local prompt="$1"
    local var_name="$2"
    read -sp "$prompt" $var_name
    echo ""
}

# Ask for backup file/directory location
while true; do
    echo "Enter the path to backup file or directory:"
    echo "  (Can be a directory or .tar.gz/.zip file)"
    read_input "> " BACKUP_PATH

    if [ -z "$BACKUP_PATH" ]; then
        echo -e "${RED}Error: Backup path is required!${NC}"
        echo ""
        continue
    fi

    # Expand tilde to home directory
    BACKUP_PATH="${BACKUP_PATH/#\~/$HOME}"

    if [ ! -e "$BACKUP_PATH" ]; then
        echo -e "${RED}Error: Path does not exist: $BACKUP_PATH${NC}"
        echo ""
        continue
    fi

    break
done

echo ""
echo -e "${GREEN}Selected: $BACKUP_PATH${NC}"
echo ""

# Check if it's a compressed file and extract if needed
BACKUP_DIR="$BACKUP_PATH"
TEMP_EXTRACT=false

if [ -f "$BACKUP_PATH" ]; then
    # It's a file, check if it's compressed
    if [[ "$BACKUP_PATH" == *.tar.gz ]] || [[ "$BACKUP_PATH" == *.tgz ]]; then
        echo "Detected tar.gz archive. Extracting..."
        TEMP_DIR="/tmp/mongodb_restore_$$"
        mkdir -p "$TEMP_DIR"

        if tar -xzf "$BACKUP_PATH" -C "$TEMP_DIR"; then
            echo -e "${GREEN}Archive extracted successfully${NC}"
            BACKUP_DIR="$TEMP_DIR"
            TEMP_EXTRACT=true
        else
            echo -e "${RED}Failed to extract tar.gz archive${NC}"
            rm -rf "$TEMP_DIR"
            exit 1
        fi
    elif [[ "$BACKUP_PATH" == *.zip ]]; then
        echo "Detected zip archive. Extracting..."
        TEMP_DIR="/tmp/mongodb_restore_$$"
        mkdir -p "$TEMP_DIR"

        if unzip -q "$BACKUP_PATH" -d "$TEMP_DIR"; then
            echo -e "${GREEN}Archive extracted successfully${NC}"
            BACKUP_DIR="$TEMP_DIR"
            TEMP_EXTRACT=true
        else
            echo -e "${RED}Failed to extract zip archive${NC}"
            rm -rf "$TEMP_DIR"
            exit 1
        fi
    else
        echo -e "${RED}Error: Unsupported file format. Use .tar.gz, .tgz, or .zip${NC}"
        exit 1
    fi
    echo ""
elif [ ! -d "$BACKUP_PATH" ]; then
    echo -e "${RED}Error: Path is neither a file nor a directory${NC}"
    exit 1
fi

# List databases in the backup
echo -e "${BLUE}Databases in this backup:${NC}"
db_count=0
declare -a db_names

for db_dir in "$BACKUP_DIR"/*; do
    if [ -d "$db_dir" ]; then
        db_count=$((db_count + 1))
        db_name=$(basename "$db_dir")
        db_names[$db_count]="$db_name"
        db_size=$(du -sh "$db_dir" 2>/dev/null | cut -f1)
        echo "  [$db_count] $db_name ($db_size)"
    fi
done

if [ $db_count -eq 0 ]; then
    echo -e "${RED}No database directories found in backup!${NC}"
    [ "$TEMP_EXTRACT" = true ] && rm -rf "$TEMP_DIR"
    exit 1
fi

echo ""

# Ask if user wants to restore all or specific databases
echo "Restore options:"
echo "  [1] Restore all databases"
echo "  [2] Restore specific database(s)"
echo ""
read_input "Select option (1 or 2): " RESTORE_OPTION

RESTORE_ALL=true
declare -a SELECTED_DBS

if [ "$RESTORE_OPTION" = "2" ]; then
    RESTORE_ALL=false
    echo ""
    echo "Enter database numbers to restore (e.g., 1,2,3 or 1 2 3):"
    read_input "> " DB_SELECTION

    # Parse input - handle both comma-separated and space-separated
    DB_SELECTION=$(echo "$DB_SELECTION" | tr ',' ' ')

    # Validate and collect selected databases
    for num in $DB_SELECTION; do
        if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "$db_count" ]; then
            SELECTED_DBS+=("${db_names[$num]}")
        else
            echo -e "${RED}Warning: Invalid selection '$num' ignored${NC}"
        fi
    done

    if [ ${#SELECTED_DBS[@]} -eq 0 ]; then
        echo -e "${RED}Error: No valid databases selected!${NC}"
        [ "$TEMP_EXTRACT" = true ] && rm -rf "$TEMP_DIR"
        exit 1
    fi

    echo ""
    echo -e "${GREEN}Selected databases:${NC}"
    for db in "${SELECTED_DBS[@]}"; do
        echo "  - $db"
    done
fi

echo ""

# Prompt for authentication database name
echo "Enter authentication database name (press Enter to skip):"
read_input "> " AUTH_DB

# Prompt for username
echo "Enter username (press Enter to skip):"
read_input "> " USERNAME

# Prompt for password only if username is provided
if [ ! -z "$USERNAME" ]; then
    echo "Enter password:"
    read_password "> " PASSWORD
fi

# Optional: Prompt for host and port
echo ""
echo "Enter MongoDB host (press Enter for default: localhost):"
read_input "> " MONGO_HOST
MONGO_HOST=${MONGO_HOST:-localhost}

echo "Enter MongoDB port (press Enter for default: 27017):"
read_input "> " MONGO_PORT
MONGO_PORT=${MONGO_PORT:-27017}

# Ask about drop option
echo ""
echo -e "${YELLOW}Warning: Do you want to drop existing databases before restoring?${NC}"
echo "  This will DELETE existing data in the target database(s)!"
read_input "Drop before restore? (y/n): " DROP_OPTION

DROP_FLAG=""
if [ "$DROP_OPTION" = "y" ] || [ "$DROP_OPTION" = "Y" ]; then
    DROP_FLAG="--drop"
    echo -e "${RED}Will drop existing collections before restore${NC}"
else
    echo "Will merge with existing data (may cause conflicts)"
fi

echo ""
echo "======================================"
echo "Restore Configuration:"
echo "======================================"
echo "Host: $MONGO_HOST"
echo "Port: $MONGO_PORT"
echo "Backup source: $BACKUP_PATH"
if [ "$RESTORE_ALL" = true ]; then
    echo "Databases to restore: ALL ($db_count databases)"
else
    echo "Databases to restore: ${#SELECTED_DBS[@]} selected"
    for db in "${SELECTED_DBS[@]}"; do
        echo "  - $db"
    done
fi
if [ ! -z "$USERNAME" ]; then
    echo "Username: $USERNAME"
    echo "Authentication DB: ${AUTH_DB:-admin}"
    echo "Password: ********"
else
    echo "Authentication: None"
fi
if [ ! -z "$DROP_FLAG" ]; then
    echo -e "${RED}Drop before restore: YES${NC}"
else
    echo "Drop before restore: NO"
fi
echo "======================================"
echo ""

# Final confirmation
echo -e "${YELLOW}⚠️  WARNING: This will modify your MongoDB database!${NC}"
read_input "Are you sure you want to proceed? (type 'yes' to continue): " FINAL_CONFIRM

if [ "$FINAL_CONFIRM" != "yes" ]; then
    echo -e "${YELLOW}Restore cancelled.${NC}"
    [ "$TEMP_EXTRACT" = true ] && rm -rf "$TEMP_DIR"
    exit 0
fi

# Execute mongorestore
echo ""
echo "Starting restore..."
echo ""

RESTORE_SUCCESS=true

if [ "$RESTORE_ALL" = true ]; then
    # Restore all databases
    MONGORESTORE_CMD="mongorestore --host=$MONGO_HOST --port=$MONGO_PORT $DROP_FLAG $BACKUP_DIR"

    # Add authentication parameters if provided
    if [ ! -z "$USERNAME" ]; then
        MONGORESTORE_CMD="$MONGORESTORE_CMD --username=$USERNAME --password=$PASSWORD"

        # Add authentication database if provided, otherwise use 'admin'
        if [ ! -z "$AUTH_DB" ]; then
            MONGORESTORE_CMD="$MONGORESTORE_CMD --authenticationDatabase=$AUTH_DB"
        else
            MONGORESTORE_CMD="$MONGORESTORE_CMD --authenticationDatabase=admin"
        fi
    fi

    if eval $MONGORESTORE_CMD; then
        echo ""
        echo -e "${GREEN}All databases restored successfully!${NC}"
    else
        RESTORE_SUCCESS=false
    fi
else
    # Restore selected databases one by one
    restored_count=0
    failed_count=0

    for db in "${SELECTED_DBS[@]}"; do
        echo "Restoring database: $db"

        MONGORESTORE_CMD="mongorestore --host=$MONGO_HOST --port=$MONGO_PORT --db=$db $DROP_FLAG $BACKUP_DIR/$db"

        # Add authentication parameters if provided
        if [ ! -z "$USERNAME" ]; then
            MONGORESTORE_CMD="$MONGORESTORE_CMD --username=$USERNAME --password=$PASSWORD"

            # Add authentication database if provided, otherwise use 'admin'
            if [ ! -z "$AUTH_DB" ]; then
                MONGORESTORE_CMD="$MONGORESTORE_CMD --authenticationDatabase=$AUTH_DB"
            else
                MONGORESTORE_CMD="$MONGORESTORE_CMD --authenticationDatabase=admin"
            fi
        fi

        if eval $MONGORESTORE_CMD; then
            echo -e "${GREEN}✓ $db restored successfully${NC}"
            restored_count=$((restored_count + 1))
        else
            echo -e "${RED}✗ Failed to restore $db${NC}"
            failed_count=$((failed_count + 1))
            RESTORE_SUCCESS=false
        fi
        echo ""
    done

    echo "======================================"
    echo "Restore Summary:"
    echo "======================================"
    echo "Total selected: ${#SELECTED_DBS[@]}"
    echo -e "${GREEN}Successfully restored: $restored_count${NC}"
    if [ $failed_count -gt 0 ]; then
        echo -e "${RED}Failed: $failed_count${NC}"
    fi
fi

if [ "$RESTORE_SUCCESS" = true ]; then
    echo ""
    echo -e "${GREEN}======================================"
    echo "Restore completed successfully!"
    echo "======================================${NC}"
else
    echo ""
    echo -e "${RED}======================================"
    echo "Restore completed with errors!"
    echo "======================================${NC}"
    echo "Please check the error messages above."
    [ "$TEMP_EXTRACT" = true ] && rm -rf "$TEMP_DIR"
    exit 1
fi

# Cleanup temporary extraction if needed
if [ "$TEMP_EXTRACT" = true ]; then
    echo ""
    echo "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
fi

echo ""
echo "Done!"
