#!/bin/bash
# Moduł: System Configuration - Hostname, Użytkownicy, Grupy, Cron
# Plik: modules/system_config.sh

# --- Konfiguracja Hostname ---
configure_hostname() {
    log_msg "Configuring hostname..."
    local current_hostname
    current_hostname=$(hostname --fqdn 2>/dev/null || hostname) # Spróbuj FQDN, fallback do krótkiej nazwy
    local new_hostname

    # Zapytaj użytkownika o nową nazwę hosta
    new_hostname=$(ask_input "$PROMPT_HOSTNAME" "$current_hostname")
    local exit_status=$?

    if [ $exit_status -ne 0 ]; then
        log_msg "$MSG_HOSTNAME_CONFIG_CANCELLED"
        return 1 # Anulowano
    fi

    # Sprawdź czy nazwa jest pusta lub taka sama jak obecna
    if [ -z "$new_hostname" ] || [ "$new_hostname" == "$current_hostname" ]; then
        log_msg "$MSG_HOSTNAME_UNCHANGED"
        return 0 # Bez zmian
    fi

    log_msg "Attempting to set hostname to '$new_hostname'..."

    # Backup istniejących plików
    create_backup "/etc/hostname" || return 1 # Przerwij jeśli backup się nie uda
    create_backup "/etc/hosts" || return 1

    # Ustaw nazwę hosta
    # 1. W /etc/hostname
    if ! echo "$new_hostname" | sudo tee /etc/hostname > /dev/null; then
        log_error "Failed to write to /etc/hostname."
        return 1
    fi
    # 2. Użyj hostnamectl jeśli dostępne (preferowane)
    if command -v hostnamectl > /dev/null; then
        if ! sudo hostnamectl set-hostname "$new_hostname"; then
            log_error "hostnamectl set-hostname failed."
            # Spróbuj przywrócić /etc/hostname?
            return 1
        fi
    # 3. Użyj polecenia hostname (dla starszych systemów)
    elif command -v hostname > /dev/null; then
         if ! sudo hostname "$new_hostname"; then
             log_error "hostname command failed."
             return 1
         fi
    else
        log_warn "Neither hostnamectl nor hostname command found. Hostname set only in /etc/hostname."
    fi

    # Aktualizacja /etc/hosts
    log_msg "Updating /etc/hosts..."
    # Usuń stare wpisy z poprzednią nazwą hosta dla 127.0.1.1 i adresu IP maszyny
    # (uważaj, aby nie usunąć wpisu dla 127.0.0.1 localhost)
    # To jest złożone i ryzykowne, lepiej jest dodać nowy wpis i poinstruować użytkownika
    # sudo sed -i "/\s$current_hostname/d" /etc/hosts # Zbyt agresywne

    # Prostsze podejście: Upewnij się, że 127.0.0.1 mapuje na localhost
    if ! grep -qP "^\s*127\.0\.0\.1\s+localhost\b" /etc/hosts; then
        echo "127.0.0.1    localhost" | sudo tee -a /etc/hosts > /dev/null
    fi
    # Dodaj wpis 127.0.1.1 dla nowej nazwy (typowe dla Debiana/Ubuntu)
    # Najpierw usuń stary wpis 127.0.1.1, jeśli istnieje
    sudo sed -i '/^127\.0\.1\.1\s/d' /etc/hosts
    echo "127.0.1.1    $new_hostname" | sudo tee -a /etc/hosts > /dev/null

    log_msg "$(printf "$MSG_HOSTNAME_SET" "$new_hostname")"
    CONFIG_CHANGES_MADE=true
    NEEDS_REBOOT=true # Zmiana hostname często wymaga restartu
    log_warn "A reboot is recommended for the hostname change to take full effect across all services."
    return 0
}

# --- Zarządzanie Użytkownikami i Grupami ---
# Wyświetla podmenu do zarządzania użytkownikami
manage_users_submenu() {
     while true; do
        local choice
        choice=$(show_menu "$SUBMENU_USER_MGMT_TITLE" "$SUBMENU_USER_MGMT_DESC" \
            "ADD" "$OPT_USER_ADD" \
            "MOD" "$OPT_USER_MOD" \
            "LIST" "$OPT_USER_LIST" \
            "BACK" "$OPT_USER_BACK")
        local exit_status=$?
        [ $exit_status -ne 0 ] && choice="BACK" # Anuluj/Esc wraca

        case "$choice" in
            ADD) add_new_user ;;
            MOD) modify_user_group ;; # Zmieniono nazwę funkcji
            LIST) list_users ;;
            # DEL) delete_user ;; # Implementacja delete_user wymaga dużej ostrożności
            BACK) return 0 ;; # Powrót do poprzedniego menu
            *) log_warn "Invalid choice in user management submenu: $choice" ;;
        esac
    done
}

# Dodaje nowego użytkownika systemowego
add_new_user() {
    log_msg "Adding a new system user..."
    local username
    username=$(ask_input "$PROMPT_ADD_USER" "")
    local exit_status=$?
    if [ $exit_status -ne 0 ] || [ -z "$username" ]; then
        log_msg "$MSG_USERNAME_EMPTY or cancelled."
        return 1
    fi

    # Sprawdź, czy użytkownik już istnieje
    if id "$username" &>/dev/null; then
        log_error "$(printf "$MSG_USER_EXISTS" "$username")"
        show_message "$(printf "$MSG_USER_EXISTS" "$username")"
        return 1
    fi

    # Zapytaj o hasło i potwierdzenie
    local user_password
    local user_password_confirm
    user_password=$(ask_password "$(printf "$PROMPT_USER_PW" "$username")")
    exit_status=$?
     if [ $exit_status -ne 0 ]; then log_msg "$MSG_PW_CANCELLED"; return 1; fi
    user_password_confirm=$(ask_password "$(printf "$PROMPT_USER_PW_CONFIRM" "$username")")
     exit_status=$?
     if [ $exit_status -ne 0 ]; then log_msg "$MSG_PW_CANCELLED"; return 1; fi

    if [ "$user_password" != "$user_password_confirm" ]; then
        log_error "$MSG_PW_MISMATCH"
        show_message "$MSG_PW_MISMATCH"
        return 1
    fi
    if [ -z "$user_password" ]; then
        log_warn "Password is empty. User might not be able to log in."
        if ! confirm_action "Password is empty. Continue creating user $username?"; then
            log_msg "User creation cancelled due to empty password."
            return 1
        fi
    fi


    # Dodaj użytkownika (z katalogiem domowym, domyślną powłoką)
    log_msg "Creating user account '$username'..."
    if ! sudo useradd -m -s /bin/bash "$username"; then
        log_error "$(printf "$MSG_USER_CREATE_FAILED" "$username") (useradd failed)"
        show_message "$(printf "$MSG_USER_CREATE_FAILED" "$username")"
        return 1
    fi
    log_msg "$(printf "$MSG_USER_CREATED_ACC" "$username")"

    # Ustaw hasło
    log_msg "Setting password for user '$username'..."
    # Użyj printf, aby uniknąć problemów ze znakami specjalnymi w haśle
    if ! printf "%s:%s" "$username" "$user_password" | sudo chpasswd; then
        log_error "$(printf "$MSG_USER_CREATE_FAILED" "$username") (chpasswd failed)"
        # Rozważ usunięcie użytkownika, jeśli ustawienie hasła się nie powiodło?
        # sudo userdel -r "$username"
        show_message "$(printf "$MSG_USER_CREATE_FAILED" "$username") (password setting failed)"
        return 1
    fi
    log_msg "$(printf "$MSG_USER_PW_SET" "$username")"

    # Opcjonalne dodanie do grupy sudo/wheel
    local sudo_group="sudo" # Domyślne dla Debian/Ubuntu
    if [[ "$PKG_MANAGER" == "dnf" || "$PKG_MANAGER" == "yum" || "$PKG_MANAGER" == "pacman" || "$PKG_MANAGER" == "zypper" ]]; then
         sudo_group="wheel" # Domyślne dla Fedora/CentOS/Arch/SUSE
    fi

    # Sprawdź, czy grupa sudo/wheel istnieje
    if getent group "$sudo_group" > /dev/null; then
        if ask_yesno "$(printf "$PROMPT_ADD_USER_SUDO" "$username")"; then
            log_msg "Adding user '$username' to group '$sudo_group'..."
            if ! sudo usermod -aG "$sudo_group" "$username"; then
                log_error "Failed to add user '$username' to group '$sudo_group'."
                # Nie jest to błąd krytyczny, kontynuuj
            else
                log_msg "$(printf "$MSG_USER_ADDED_TO_GROUP" "$username" "$sudo_group")"
            fi
        fi
    else
        log_warn "$(printf "$MSG_GROUP_NOT_FOUND" "$sudo_group"). Cannot add user '$username' to it."
    fi

    log_msg "$(printf "$MSG_USER_CREATED" "$username")"
    CONFIG_CHANGES_MADE=true
    return 0
}

# Modyfikuje użytkownika (np. dodaje do grupy) lub tworzy grupę
modify_user_group() {
    log_msg "Modifying user/group..."
    local group_name
    group_name=$(ask_input "$PROMPT_ADD_GROUP (Leave blank to skip group creation/modification)" "")
    local exit_status=$?
     if [ $exit_status -ne 0 ]; then log_msg "$MSG_ACTION_CANCELLED"; return 1; fi

     # Jeśli podano nazwę grupy
     if [ -n "$group_name" ]; then
        # Sprawdź, czy grupa istnieje
        if ! getent group "$group_name" > /dev/null; then
            log_msg "Group '$group_name' does not exist."
            if ask_yesno "$(printf "$PROMPT_CREATE_GROUP" "$group_name")"; then
                log_msg "Creating group '$group_name'..."
                if ! sudo groupadd "$group_name"; then
                    log_error "$(printf "$MSG_GROUP_CREATE_FAILED" "$group_name")"
                    return 1
                fi
                log_msg "$(printf "$MSG_GROUP_CREATED" "$group_name")"
                CONFIG_CHANGES_MADE=true
            else
                log_msg "$MSG_GROUP_CREATE_CANCELLED"
                # Nie możemy dodać użytkownika do nieistniejącej grupy
                group_name="" # Wyczyść nazwę grupy, aby nie pytać o użytkownika
            fi
        fi
     fi

     # Jeśli mamy grupę (istniejącą lub nowo utworzoną), zapytaj o użytkownika do dodania
     if [ -n "$group_name" ]; then
        local username_to_add
        username_to_add=$(ask_input "$(printf "$PROMPT_ADD_USER_TO_GROUP" "$group_name") (Leave blank to skip)" "")
         exit_status=$?
         if [ $exit_status -ne 0 ]; then log_msg "$MSG_ACTION_CANCELLED"; return 1; fi

         if [ -n "$username_to_add" ]; then
            # Sprawdź, czy użytkownik istnieje
            if ! id "$username_to_add" &>/dev/null; then
                log_error "$(printf "$MSG_USER_DOES_NOT_EXIST" "$username_to_add")"
                show_message "$(printf "$MSG_USER_DOES_NOT_EXIST" "$username_to_add")"
                return 1
            fi

            log_msg "Adding user '$username_to_add' to group '$group_name'..."
            if ! sudo usermod -aG "$group_name" "$username_to_add"; then
                log_error "$(printf "$MSG_USER_ADD_TO_GROUP_FAILED" "$username_to_add" "$group_name")"
                return 1
            fi
            log_msg "$(printf "$MSG_USER_ADDED_TO_GROUP" "$username_to_add" "$group_name")"
            CONFIG_CHANGES_MADE=true
         else
            log_msg "No user specified to add to group '$group_name'."
         fi
     else
         log_msg "No group specified or created, skipping user addition."
     fi

     return 0
}

# Wyświetla listę użytkowników lokalnych
list_users() {
    log_msg "$MSG_LISTING_USERS"
    local user_list
    # Użyj getent dla większej przenośności (działa też z LDAP itp.)
    # Filtruj UID >= 1000 (typowi użytkownicy) i != 65534 (nobody)
    user_list=$(getent passwd | awk -F: '($3 >= 1000 && $3 != 65534) { print $1 }' | sort)
    if [ -z "$user_list" ]; then
        user_list="(No local users found with UID >= 1000)"
    fi
    log_msg "Local users found:\n$user_list"
    # Pokaż w UI
    if command -v $UI_TOOL >/dev/null 2>&1; then
        show_message "$MSG_USER_LIST_HEADER\n\n$user_list"
    else
        echo -e "$MSG_USER_LIST_HEADER\n\n$user_list"
    fi
    return 0
}

# --- Zarządzanie Cron ---
manage_cron() {
    log_msg "Managing cron jobs..."
    local cron_user
    cron_user=$(ask_input "$PROMPT_CRON_USER" "${SUDO_USER:-root}") # Domyślnie użytkownik sudo lub root
    local exit_status=$?
     if [ $exit_status -ne 0 ]; then log_msg "$MSG_ACTION_CANCELLED"; return 1; fi
    if [ -z "$cron_user" ]; then cron_user="root"; fi # Fallback na root

    # Sprawdź czy użytkownik istnieje
    if ! id "$cron_user" &>/dev/null; then
        log_error "$(printf "$MSG_USER_DOES_NOT_EXIST" "$cron_user")"
        show_message "$(printf "$MSG_USER_DOES_NOT_EXIST" "$cron_user")"
        return 1
    fi

    # Pokaż istniejące zadania i zapytaj co robić
    local current_crontab
    current_crontab=$(sudo crontab -u "$cron_user" -l 2>/dev/null || echo "# No crontab for $cron_user")
    log_msg "Current crontab for user '$cron_user':\n$current_crontab"

    local cron_action
    cron_action=$(show_menu "Cron Management for user '$cron_user'" "Choose an action:" \
        "ADD" "Add a new cron job" \
        "EDIT" "Edit crontab manually (using \$EDITOR)" \
        "VIEW" "View current crontab" \
        "BACK" "Cancel")
     exit_status=$?
     if [ $exit_status -ne 0 ]; then cron_action="BACK"; fi

     case "$cron_action" in
        ADD) add_cron_job "$cron_user" ;;
        EDIT)
            log_msg "Opening crontab for user '$cron_user' in editor..."
            if sudo crontab -u "$cron_user" -e; then
                log_msg "Crontab editing finished."
                CONFIG_CHANGES_MADE=true # Zakładamy, że mogły być zmiany
            else
                 log_error "Failed to open crontab editor for '$cron_user'."
            fi
            ;;
        VIEW)
             show_message "Crontab for user '$cron_user':\n\n$current_crontab"
             ;;
        BACK) log_msg "Cron management cancelled." ;;
        *) log_warn "Invalid cron action: $cron_action" ;;
     esac
     return 0
}

# Pomocnicza funkcja do dodawania zadania cron
add_cron_job() {
    local cron_user=$1
    log_msg "Adding new cron job for user '$cron_user'..."

    local cron_cmd
    cron_cmd=$(ask_input "$PROMPT_CRON_CMD" "")
     exit_status=$?
     if [ $exit_status -ne 0 ] || [ -z "$cron_cmd" ]; then log_msg "$MSG_CRON_CMD_EMPTY or cancelled."; return 1; fi

    local cron_schedule
    cron_schedule=$(ask_input "$PROMPT_CRON_SCHEDULE" "0 2 * * *") # Domyślnie 2 AM codziennie
     exit_status=$?
     if [ $exit_status -ne 0 ] || [ -z "$cron_schedule" ]; then log_msg "$MSG_CRON_SCHEDULE_EMPTY or cancelled."; return 1; fi

    # Zbuduj linię crona
    local cron_line="$cron_schedule $cron_cmd"

    # Potwierdź dodanie
    if ! confirm_action "Add the following line to crontab for user '$cron_user'?\n\n$cron_line"; then
        log_msg "Cron job addition cancelled."
        return 1
    fi

    # Dodaj zadanie do crontab użytkownika
    # Pobierz istniejący crontab, dodaj nową linię, zapisz z powrotem
    # Użyj tymczasowego pliku dla bezpieczeństwa
    local temp_cronfile
    temp_cronfile=$(mktemp)
    sudo crontab -u "$cron_user" -l > "$temp_cronfile" 2>/dev/null || true # Ignoruj błąd, jeśli crontab nie istnieje
    echo "$cron_line" >> "$temp_cronfile"

    if sudo crontab -u "$cron_user" "$temp_cronfile"; then
        log_msg "$(printf "$MSG_CRON_ADDED" "$cron_user")"
        rm "$temp_cronfile" # Usuń plik tymczasowy
        CONFIG_CHANGES_MADE=true
        # Zapytaj o edycję po dodaniu
        if ask_yesno "$(printf "$PROMPT_EDIT_CRON" "$cron_user")"; then
            sudo crontab -u "$cron_user" -e
        fi
        return 0
    else
        log_error "$(printf "$MSG_CRON_ADD_FAILED" "$cron_user")"
        rm "$temp_cronfile" # Usuń plik tymczasowy
        show_message "ERROR: $(printf "$MSG_CRON_ADD_FAILED" "$cron_user")"
        return 1
    fi
}


# --- Główna funkcja modułu Konfiguracji Systemu ---
# Wyświetla podmenu dla konfiguracji systemowych
run_system_config_menu() {
     while true; do
        local choice
        choice=$(show_menu "$SUBMENU_SYSTEM_CONFIG_TITLE" "$SUBMENU_SYSTEM_CONFIG_DESC" \
            "HOSTNAME" "$OPT_CONFIG_HOSTNAME" \
            "USERS" "$OPT_MANAGE_USERS" \
            "CRON" "$OPT_MANAGE_CRON" \
            "BACK" "$OPT_SYSTEM_BACK")
        local exit_status=$?
        # Jeśli Anuluj/Esc (kod != 0), traktuj jak Powrót
        [ $exit_status -ne 0 ] && choice="BACK"

        case "$choice" in
            HOSTNAME) configure_hostname ;;
            USERS) manage_users_submenu ;;
            CRON) manage_cron ;;
            BACK) break ;; # Wyjdź z pętli tego podmenu
            *) log_warn "Invalid choice in system config menu: $choice" ;;
        esac
        # Pauza przed powrotem do menu, chyba że wybrano BACK
        # if [ "$choice" != "BACK" ]; then wait_for_enter; fi
    done
    return 0 # Zawsze wracaj z sukcesem z podmenu
}