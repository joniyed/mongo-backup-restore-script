#!/bin/bash

# MongoDB Backup Script
# This script creates a backup of MongoDB databases using mongodump

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "======================================"
echo "MongoDB Backup Script"
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

# Get list of databases from MongoDB
echo ""
echo "Fetching database list from MongoDB..."

# Build mongo command to list databases
if [ ! -z "$USERNAME" ]; then
    if [ ! -z "$AUTH_DB" ]; then
        DB_LIST=$(mongosh --host=$MONGO_HOST --port=$MONGO_PORT --username=$USERNAME --password=$PASSWORD --authenticationDatabase=$AUTH_DB --quiet --eval "db.adminCommand('listDatabases').databases.map(d => d.name).join('\n')" 2>/dev/null)
    else
        DB_LIST=$(mongosh --host=$MONGO_HOST --port=$MONGO_PORT --username=$USERNAME --password=$PASSWORD --authenticationDatabase=admin --quiet --eval "db.adminCommand('listDatabases').databases.map(d => d.name).join('\n')" 2>/dev/null)
    fi
else
    DB_LIST=$(mongosh --host=$MONGO_HOST --port=$MONGO_PORT --quiet --eval "db.adminCommand('listDatabases').databases.map(d => d.name).join('\n')" 2>/dev/null)
fi

if [ -z "$DB_LIST" ]; then
    echo -e "${YELLOW}Warning: Could not fetch database list automatically.${NC}"
    echo "You can still enter database name(s) manually."
    echo ""

    # Manual database entry
    echo "Backup options:"
    echo "  [1] Backup all databases"
    echo "  [2] Enter database name(s) manually"
    echo ""
    read_input "Select option (1 or 2): " BACKUP_OPTION

    BACKUP_ALL=true
    declare -a SELECTED_DBS

    if [ "$BACKUP_OPTION" = "2" ]; then
        BACKUP_ALL=false
        echo ""
        echo "Enter database name(s) to backup (comma or space separated):"
        read_input "> " DB_INPUT

        # Parse input - handle both comma-separated and space-separated
        DB_INPUT=$(echo "$DB_INPUT" | tr ',' ' ')

        for db in $DB_INPUT; do
            SELECTED_DBS+=("$db")
        done

        if [ ${#SELECTED_DBS[@]} -eq 0 ]; then
            echo -e "${RED}Error: No databases specified!${NC}"
            exit 1
        fi

        echo ""
        echo -e "${GREEN}Databases to backup:${NC}"
        for db in "${SELECTED_DBS[@]}"; do
            echo "  - $db"
        done
    fi
else
    # Display available databases
    echo -e "${BLUE}Available databases:${NC}"
    echo ""

    db_count=0
    declare -a db_names

    while IFS= read -r db; do
        if [ ! -z "$db" ]; then
            db_count=$((db_count + 1))
            db_names[$db_count]="$db"
            echo "  [$db_count] $db"
        fi
    done <<< "$DB_LIST"

    echo ""

    # Ask backup option
    echo "Backup options:"
    echo "  [1] Backup all databases"
    echo "  [2] Backup specific database(s)"
    echo ""
    read_input "Select option (1 or 2): " BACKUP_OPTION

    BACKUP_ALL=true
    declare -a SELECTED_DBS

    if [ "$BACKUP_OPTION" = "2" ]; then
        BACKUP_ALL=false
        echo ""
        echo "Enter database numbers to backup (e.g., 1,2,3 or 1 2 3):"
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
            exit 1
        fi

        echo ""
        echo -e "${GREEN}Selected databases:${NC}"
        for db in "${SELECTED_DBS[@]}"; do
            echo "  - $db"
        done
    fi
fi

# Create backup directory with timestamp
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
if [ "$BACKUP_ALL" = true ]; then
    BACKUP_DIR="./mongodb_backups/all_databases_${TIMESTAMP}"
else
    if [ ${#SELECTED_DBS[@]} -eq 1 ]; then
        BACKUP_DIR="./mongodb_backups/${SELECTED_DBS[0]}_${TIMESTAMP}"
    else
        BACKUP_DIR="./mongodb_backups/selected_databases_${TIMESTAMP}"
    fi
fi

echo ""
echo "======================================"
echo "Backup Configuration:"
echo "======================================"
echo "Host: $MONGO_HOST"
echo "Port: $MONGO_PORT"
if [ "$BACKUP_ALL" = true ]; then
    echo "Databases: ALL"
else
    echo "Databases: ${#SELECTED_DBS[@]} selected"
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
echo "Backup Location: $BACKUP_DIR"
echo "======================================"
echo ""

# Confirm before proceeding
read -p "Proceed with backup? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo -e "${YELLOW}Backup cancelled.${NC}"
    exit 0
fi

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Execute backup
echo ""
echo "Starting backup..."
echo ""

BACKUP_SUCCESS=true

if [ "$BACKUP_ALL" = true ]; then
    # Backup all databases
    MONGODUMP_CMD="mongodump --host=$MONGO_HOST --port=$MONGO_PORT --out=$BACKUP_DIR"

    # Add authentication parameters if provided
    if [ ! -z "$USERNAME" ]; then
        MONGODUMP_CMD="$MONGODUMP_CMD --username=$USERNAME --password=$PASSWORD"

        # Add authentication database if provided, otherwise use 'admin'
        if [ ! -z "$AUTH_DB" ]; then
            MONGODUMP_CMD="$MONGODUMP_CMD --authenticationDatabase=$AUTH_DB"
        else
            MONGODUMP_CMD="$MONGODUMP_CMD --authenticationDatabase=admin"
        fi
    fi

    if eval $MONGODUMP_CMD; then
        echo ""
        echo -e "${GREEN}All databases backed up successfully!${NC}"
    else
        BACKUP_SUCCESS=false
    fi
else
    # Backup selected databases one by one
    backed_up_count=0
    failed_count=0

    for db in "${SELECTED_DBS[@]}"; do
        echo "Backing up database: $db"

        MONGODUMP_CMD="mongodump --host=$MONGO_HOST --port=$MONGO_PORT --db=$db --out=$BACKUP_DIR"

        # Add authentication parameters if provided
        if [ ! -z "$USERNAME" ]; then
            MONGODUMP_CMD="$MONGODUMP_CMD --username=$USERNAME --password=$PASSWORD"

            # Add authentication database if provided, otherwise use 'admin'
            if [ ! -z "$AUTH_DB" ]; then
                MONGODUMP_CMD="$MONGODUMP_CMD --authenticationDatabase=$AUTH_DB"
            else
                MONGODUMP_CMD="$MONGODUMP_CMD --authenticationDatabase=admin"
            fi
        fi

        if eval $MONGODUMP_CMD; then
            echo -e "${GREEN}✓ $db backed up successfully${NC}"
            backed_up_count=$((backed_up_count + 1))
        else
            echo -e "${RED}✗ Failed to backup $db${NC}"
            failed_count=$((failed_count + 1))
            BACKUP_SUCCESS=false
        fi
        echo ""
    done

    echo "======================================"
    echo "Backup Summary:"
    echo "======================================"
    echo "Total selected: ${#SELECTED_DBS[@]}"
    echo -e "${GREEN}Successfully backed up: $backed_up_count${NC}"
    if [ $failed_count -gt 0 ]; then
        echo -e "${RED}Failed: $failed_count${NC}"
    fi
fi

if [ "$BACKUP_SUCCESS" = true ]; then
    echo ""
    echo -e "${GREEN}======================================"
    echo "Backup completed successfully!"
    echo "======================================${NC}"
    echo "Backup location: $BACKUP_DIR"

    # Show backup size
    BACKUP_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)
    echo "Backup size: $BACKUP_SIZE"

    # List backed up databases
    if [ "$BACKUP_ALL" = true ] || [ ${#SELECTED_DBS[@]} -gt 1 ]; then
        echo ""
        echo "Databases backed up:"
        ls -1 "$BACKUP_DIR" | while read db; do
            if [ -d "$BACKUP_DIR/$db" ]; then
                db_size=$(du -sh "$BACKUP_DIR/$db" 2>/dev/null | cut -f1)
                echo "  - $db ($db_size)"
            fi
        done
    fi

    # Optional: Create compressed archive
    echo ""
    read -p "Create compressed archive? (y/n): " COMPRESS
    if [ "$COMPRESS" = "y" ] || [ "$COMPRESS" = "Y" ]; then
        if [ "$BACKUP_ALL" = true ]; then
            ARCHIVE_NAME="all_databases_${TIMESTAMP}.tar.gz"
        elif [ ${#SELECTED_DBS[@]} -eq 1 ]; then
            ARCHIVE_NAME="${SELECTED_DBS[0]}_${TIMESTAMP}.tar.gz"
        else
            ARCHIVE_NAME="selected_databases_${TIMESTAMP}.tar.gz"
        fi

        echo "Creating archive: $ARCHIVE_NAME"
        tar -czf "./mongodb_backups/$ARCHIVE_NAME" -C "$BACKUP_DIR" .

        archive_size=$(du -sh "./mongodb_backups/$ARCHIVE_NAME" | cut -f1)
        echo -e "${GREEN}Archive created: ./mongodb_backups/$ARCHIVE_NAME ($archive_size)${NC}"

        # Ask if user wants to remove the uncompressed backup
        read -p "Remove uncompressed backup directory? (y/n): " REMOVE_DIR
        if [ "$REMOVE_DIR" = "y" ] || [ "$REMOVE_DIR" = "Y" ]; then
            rm -rf "$BACKUP_DIR"
            echo "Uncompressed backup removed."
        fi
    fi
else
    echo ""
    echo -e "${RED}======================================"
    echo "Backup completed with errors!"
    echo "======================================${NC}"
    echo "Please check the error messages above."
    echo "Partial backup location: $BACKUP_DIR"
    exit 1
fi

echo ""
echo "Done!"
