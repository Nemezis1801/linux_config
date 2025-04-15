#!/bin/bash
# Moduł: Disk Management - Podstawowe operacje na dyskach (ostrożnie!)
# Plik: modules/disk_management.sh

# Instalacja podstawowych narzędzi do zarządzania dyskami
install_disk_utils() {
    # Pokaż ostrzeżenie przed instalacją
    if command -v $UI_TOOL >/dev/null; then
         show_message "$MSG_DISK_WARNING"
    else
         log_warn "$MSG_DISK_WARNING"
    fi

    # Zapytaj, czy kontynuować
    if ! confirm_action "$PROMPT_INSTALL_DISK_UTILS"; then
        log_msg "$MSG_DISK_UTILS_INSTALL_SKIPPED"
        return 1 # Anulowano
    fi

    log_msg "Installing common disk management utilities..."
    local utils_to_install=()
    # Podstawowe narzędzia, które powinny być dostępne w większości repo
    utils_to_install+=("parted" "fdisk" "e2fsprogs" "xfsprogs" "btrfs-progs" "util-linux")
    # util-linux zazwyczaj zawiera lsblk, mkswap itp.
    # gdisk (dla GPT) jest w pakiecie 'gdisk' lub 'gptfdisk'
    if [[ "$PKG_MANAGER" == "apt" ]]; then utils_to_install+=("gdisk");
    elif [[ "$PKG_MANAGER" == "dnf" || "$PKG_MANAGER" == "yum" || "$PKG_MANAGER" == "zypper" ]]; then utils_to_install+=("gdisk");
    elif [[ "$PKG_MANAGER" == "pacman" ]]; then utils_to_install+=("gptfdisk"); fi
    # Dodaj obsługę NTFS
    if [[ "$PKG_MANAGER" == "apt" ]]; then utils_to_install+=("ntfs-3g");
    elif [[ "$PKG_MANAGER" == "dnf" || "$PKG_MANAGER" == "yum" ]]; then utils_to_install+=("ntfs-3g"); # Lub z repo EPEL/Fusion
    elif [[ "$PKG_MANAGER" == "pacman" || "$PKG_MANAGER" == "zypper" ]]; then utils_to_install+=("ntfs-3g"); fi

    # Usuń duplikaty i zainstaluj
    local unique_utils=($(echo "${utils_to_install[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
    log_msg "Attempting to install packages: ${unique_utils[*]}"
    if install_packages "${unique_utils[@]}"; then
        log_msg "$MSG_DISK_UTILS_INSTALLED"
        return 0
    else
        log_error "$MSG_DISK_UTILS_INSTALL_FAILED"
        show_message "ERROR: $MSG_DISK_UTILS_INSTALL_FAILED Some tools might be missing."
        return 1 # Błąd instalacji
    fi
}

# Wyświetlenie listy urządzeń blokowych (dysków i partycji)
list_block_devices() {
    log_msg "$MSG_LISTING_BLOCK_DEVICES..."
    # Sprawdź, czy lsblk istnieje
    if ! command -v lsblk > /dev/null; then
        log_error "$MSG_LSBLK_NOT_FOUND"
        if confirm_action "$MSG_LSBLK_NOT_FOUND Install disk utilities now?"; then
             install_disk_utils || return 1 # Przerwij, jeśli instalacja się nie uda
             # Spróbuj ponownie po instalacji
             if ! command -v lsblk > /dev/null; then
                 log_error "lsblk still not found after installation attempt."
                 return 1
             fi
        else
             return 1 # Anulowano instalację narzędzi
        fi
    fi

    # Wykonaj lsblk z przydatnymi kolumnami
    # Wyłącz 'set -e' na czas lsblk
    set +e
    local output
    output=$(lsblk -o NAME,MAJ:MIN,RM,SIZE,RO,TYPE,FSTYPE,MOUNTPOINT,UUID,LABEL 2>&1)
    local lsblk_status=$?
    set -e

    if [ $lsblk_status -ne 0 ]; then
         log_error "lsblk command failed (Code: $lsblk_status). Output:\n$output"
         show_message "ERROR: Failed to run lsblk command. Check logs."
         return 1
    fi

    log_msg "$MSG_BLOCK_DEVICES_HEADER\n$output"
    # Pokaż w UI
    if command -v $UI_TOOL >/dev/null; then
        # Ogranicz wysokość dla msgbox
        show_message "$MSG_BLOCK_DEVICES_HEADER\n\n$(echo "$output" | head -n 20)"
    else
        echo -e "$MSG_BLOCK_DEVICES_HEADER\n\n$output"
    fi
    return 0
}

# Dodaje wpis do /etc/fstab
# UWAGA: Bardzo ryzykowne! Błędny wpis może uniemożliwić start systemu.
add_fstab_entry() {
    log_msg "Adding entry to /etc/fstab..."
    # Pokaż poważne ostrzeżenie
    if command -v $UI_TOOL >/dev/null; then
         show_message "$MSG_DISK_WARNING\n\n$MSG_FSTAB_ADD_WARNING" # Dodaj nowe ostrzeżenie
    else
         log_error "$MSG_DISK_WARNING"
         log_error "$MSG_FSTAB_ADD_WARNING"
    fi

    # Zapytaj, czy kontynuować
    if ! confirm_action "$PROMPT_ADD_FSTAB"; then
        log_msg "$MSG_FSTAB_MODIFY_CANCELLED"
        return 1 # Anulowano
    fi

    # Zbierz informacje od użytkownika
    local device_path=""
    while [ -z "$device_path" ]; do
        device_path=$(ask_input "$PROMPT_FSTAB_PATH (e.g., UUID=xxx or /dev/sdXN)" "")
        if [ $? -ne 0 ]; then log_msg "$MSG_ACTION_CANCELLED"; return 1; fi
        if [ -z "$device_path" ]; then show_message "$MSG_FSTAB_PATH_EMPTY"; fi
    done

    local mount_point=""
    while [ -z "$mount_point" ]; do
        mount_point=$(ask_input "$PROMPT_FSTAB_MOUNTPOINT (must be an existing directory)" "")
        if [ $? -ne 0 ]; then log_msg "$MSG_ACTION_CANCELLED"; return 1; fi
        if [ -z "$mount_point" ]; then show_message "$MSG_FSTAB_MOUNTPOINT_EMPTY"; fi
    done

    # Sprawdź, czy punkt montowania istnieje
    if [ ! -d "$mount_point" ]; then
        log_warn "$(printf "$MSG_FSTAB_MOUNTPOINT_NOT_EXIST_WARN" "$mount_point")"
        if ask_yesno "$(printf "$PROMPT_FSTAB_MOUNTPOINT_CREATE" "$mount_point")"; then
            log_msg "Creating mount point '$mount_point'..."
            if ! sudo mkdir -p "$mount_point"; then
                log_error "$(printf "$MSG_FSTAB_MOUNTPOINT_CREATE_FAILED" "$mount_point")"
                show_message "ERROR: $(printf "$MSG_FSTAB_MOUNTPOINT_CREATE_FAILED" "$mount_point")"
                return 1
            fi
            log_msg "$(printf "$MSG_FSTAB_MOUNTPOINT_CREATED" "$mount_point")"
        else
            log_msg "Mount point creation cancelled. fstab entry might fail."
            # Pozwól kontynuować, ale z ostrzeżeniem
        fi
    fi

    local fs_type=""
    while [ -z "$fs_type" ]; do
        fs_type=$(ask_input "$PROMPT_FSTAB_FSTYPE (e.g., ext4, xfs, ntfs, btrfs, auto)" "auto")
        if [ $? -ne 0 ]; then log_msg "$MSG_ACTION_CANCELLED"; return 1; fi
        if [ -z "$fs_type" ]; then show_message "$MSG_FSTAB_FSTYPE_EMPTY"; fi
    done

    local mount_options=""
    mount_options=$(ask_input "$PROMPT_FSTAB_OPTIONS (e.g., defaults,nofail,ro)" "defaults")
    if [ $? -ne 0 ]; then log_msg "$MSG_ACTION_CANCELLED"; return 1; fi
    if [ -z "$mount_options" ]; then
        log_msg "$MSG_FSTAB_OPTIONS_USING_DEFAULTS"
        mount_options="defaults"
    fi

    # Ostatnie dwa pola fstab (dump, pass) - zazwyczaj 0 0 dla dysków nie-root
    local dump_field="0"
    local pass_field="0"
    if [ "$fs_type" == "ext4" ] || [ "$fs_type" == "ext3" ] || [ "$fs_type" == "ext2" ] || [ "$fs_type" == "xfs" ]; then
         # Można zapytać użytkownika o pass (0, 1, 2)
         # pass_field=$(ask_input "Enter 'pass' field for fsck order (0, 1, 2)" "2")
         pass_field="2" # Domyślnie sprawdzaj po roocie
    fi

    local fstab_line="$device_path\t$mount_point\t$fs_type\t$mount_options\t$dump_field\t$pass_field"

    # Pokaż linię i poproś o ostateczne potwierdzenie
    log_msg "Proposed fstab line: $fstab_line"
    if ! confirm_action "$(printf "$PROMPT_FSTAB_CONFIRM_LINE" "$fstab_line")"; then
        log_msg "$MSG_FSTAB_ADD_CANCELLED"
        return 1 # Anulowano
    fi

    # Zrób backup /etc/fstab PRZED dodaniem linii
    create_backup "/etc/fstab" || return 1

    # Dodaj linię do /etc/fstab
    log_msg "Adding line to /etc/fstab..."
    # Użyj tee -a z sudo
    if echo -e "$fstab_line" | sudo tee -a /etc/fstab > /dev/null; then
        log_msg "$MSG_FSTAB_ADDED"
        show_message "$MSG_FSTAB_ADDED"
        CONFIG_CHANGES_MADE=true
        NEEDS_REBOOT=true # Zmiany w fstab zdecydowanie sugerują restart
        return 0
    else
        log_error "$MSG_FSTAB_ADD_FAILED"
        show_message "ERROR: $MSG_FSTAB_ADD_FAILED Check permissions and logs."
        # Rozważyć przywrócenie backupu?
        return 1 # Błąd zapisu
    fi
}

# --- Główna funkcja modułu Zarządzania Dyskami ---
run_disk_management_menu() {
     # Pokaż ostrzeżenie przy wejściu do menu
     if command -v $UI_TOOL >/dev/null; then
         show_message "$MSG_DISK_WARNING"
     else
         log_error "$MSG_DISK_WARNING"
     fi

     while true; do
        local choice
        choice=$(show_menu "$SUBMENU_DISK_MGMT_TITLE" "$SUBMENU_DISK_MGMT_DESC" \
            "INSTALL_UTILS" "$OPT_INSTALL_DISK_UTILS" \
            "LIST_DISKS" "$OPT_LIST_DISKS" \
            "ADD_FSTAB" "$OPT_ADD_FSTAB" \
            "BACK" "$OPT_DISK_BACK")
        local exit_status=$?
        [ $exit_status -ne 0 ] && choice="BACK"

        case "$choice" in
            INSTALL_UTILS) install_disk_utils ;;
            LIST_DISKS) list_block_devices ;;
            ADD_FSTAB) add_fstab_entry ;;
            BACK) break ;;
            *) log_warn "Invalid choice in disk management menu: $choice" ;;
        esac
        # Pauza po akcji, chyba że wybrano BACK
        # if [ "$choice" != "BACK" ] && [ $? -eq 0 ]; then # Czekaj tylko po sukcesie
        #     wait_for_enter
        # fi
    done
    return 0
}

# Dodatkowe ostrzeżenie specyficzne dla fstab
MSG_FSTAB_ADD_WARNING="Adding entries to /etc/fstab requires correct device paths/UUIDs, mount points, filesystem types, and options. Incorrect entries can prevent the system from booting!"