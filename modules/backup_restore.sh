#!/bin/bash
# Moduł: Backup & Restore - Podstawowe narzędzia i konfiguracja
# Plik: modules/backup_restore.sh

# Instalacja popularnych narzędzi do tworzenia kopii zapasowych
install_backup_tools() {
    # Zapytaj użytkownika, czy chce zainstalować narzędzia
    if ! confirm_action "$PROMPT_INSTALL_BACKUP_TOOLS"; then
        log_msg "$MSG_BACKUP_TOOLS_INSTALL_SKIPPED"
        return 1 # Anulowano
    fi

    log_msg "Installing common backup tools (rsync, possibly restic)..."
    local tools_to_install=("rsync") # Rsync jest podstawą

    # Opcjonalnie: Zapytaj o instalację bardziej zaawansowanych narzędzi
    # if ask_yesno "Install 'restic' (modern backup tool)?"; then
    #     tools_to_install+=("restic")
    # fi
    # if ask_yesno "Install 'borgbackup' (deduplicating backup tool)?"; then
    #      tools_to_install+=("borgbackup") # Nazwa pakietu może się różnić
    # fi

    # Usuń duplikaty i zainstaluj
    local unique_utils=($(echo "${tools_to_install[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
    log_msg "Attempting to install packages: ${unique_utils[*]}"
    if install_packages "${unique_utils[@]}"; then
        log_msg "$MSG_BACKUP_TOOLS_INSTALLED"
        return 0
    else
        log_error "$MSG_BACKUP_TOOLS_INSTALL_FAILED"
        show_message "ERROR: $MSG_BACKUP_TOOLS_INSTALL_FAILED Some tools might be missing."
        return 1 # Błąd instalacji
    fi
}

# Konfiguracja przykładowego zadania cron dla rsync
# Tworzy prosty backup lokalny jednego katalogu do drugiego.
setup_rsync_cron() {
     log_msg "Setting up a sample rsync backup cron job..."
     # Sprawdź, czy rsync jest zainstalowany
     if ! command -v rsync > /dev/null; then
         log_error "$MSG_RSYNC_NOT_FOUND"
         if confirm_action "$MSG_RSYNC_NOT_FOUND Install backup tools now?"; then
              install_backup_tools || return 1 # Przerwij, jeśli instalacja się nie uda
              # Sprawdź ponownie po instalacji
              if ! command -v rsync > /dev/null; then
                  log_error "rsync still not found after installation attempt."
                  return 1
              fi
         else
              return 1 # Anulowano instalację narzędzi
         fi
     fi

     # Zapytaj, czy kontynuować z konfiguracją przykładu
     if ! confirm_action "$PROMPT_SETUP_BACKUP_CRON"; then
         log_msg "$MSG_BACKUP_CRON_SETUP_SKIPPED"
         return 1 # Anulowano
     fi

     # Zbierz informacje od użytkownika
     local backup_user
     backup_user=$(ask_input "$PROMPT_CRON_USER (for backup task)" "${SUDO_USER:-root}")
     if [ $? -ne 0 ]; then log_msg "$MSG_ACTION_CANCELLED"; return 1; fi
     if [ -z "$backup_user" ]; then backup_user="root"; fi # Domyślnie root
      # Sprawdź, czy użytkownik istnieje
      if ! id "$backup_user" &>/dev/null; then
         log_error "$(printf "$MSG_USER_DOES_NOT_EXIST" "$backup_user")"
         show_message "ERROR: $(printf "$MSG_USER_DOES_NOT_EXIST" "$backup_user")"
         return 1
     fi

     local source_dir=""
     while [ -z "$source_dir" ]; do
        source_dir=$(ask_input "$PROMPT_BACKUP_SOURCE (absolute path)" "/home/$backup_user/data")
        if [ $? -ne 0 ]; then log_msg "$MSG_ACTION_CANCELLED"; return 1; fi
        if [ -z "$source_dir" ]; then show_message "Source directory cannot be empty."; fi
     done
      # Sprawdź, czy katalog źródłowy istnieje (tylko ostrzeżenie)
      if [ ! -d "$source_dir" ]; then
          log_warn "$(printf "$MSG_BACKUP_SOURCE_WARN" "$source_dir")"
          show_message "Warning: $(printf "$MSG_BACKUP_SOURCE_WARN" "$source_dir")"
      fi

     local dest_dir=""
     while [ -z "$dest_dir" ]; do
        dest_dir=$(ask_input "$PROMPT_BACKUP_DEST (absolute path, ensure it exists & has permissions)" "/mnt/backups/$backup_user")
        if [ $? -ne 0 ]; then log_msg "$MSG_ACTION_CANCELLED"; return 1; fi
        if [ -z "$dest_dir" ]; then show_message "Destination directory cannot be empty."; fi
     done
      # Nie sprawdzamy istnienia katalogu docelowego, może być zdalny lub zamontowany później

     local cron_schedule
     cron_schedule=$(ask_input "$PROMPT_CRON_SCHEDULE_BACKUP" "0 3 * * *") # Domyślnie 3 AM codziennie
     if [ $? -ne 0 ]; then log_msg "$MSG_ACTION_CANCELLED"; return 1; fi
     if [ -z "$cron_schedule" ]; then cron_schedule="0 3 * * *"; fi # Użyj domyślnego, jeśli puste

     # Przygotuj polecenie rsync (prosty przykład)
     # -a: tryb archiwum (rekursywnie, zachowuje uprawnienia, czasy itp.)
     # -v: verbose (więcej informacji w logach crona)
     # --delete: usuwa pliki w miejscu docelowym, których nie ma już w źródle
     # Można dodać --exclude, --log-file itp.
     # Użycie cudzysłowów jest ważne dla ścieżek ze spacjami
     local rsync_cmd="rsync -av --delete \"$source_dir/\" \"$dest_dir/\""
     local cron_line="$cron_schedule $rsync_cmd"

     # Pokaż i potwierdź dodanie
     log_msg "Proposed cron job line for user '$backup_user':\n$cron_line"
     if ! confirm_action "$(printf "$PROMPT_BACKUP_CRON_CONFIRM" "$backup_user" "$cron_line")"; then
        log_msg "$MSG_BACKUP_CRON_ADD_CANCELLED"
        return 1 # Anulowano
     fi

    # Dodaj zadanie do crontab użytkownika używając pliku tymczasowego
    local temp_cronfile
    temp_cronfile=$(mktemp)
    sudo crontab -u "$backup_user" -l > "$temp_cronfile" 2>/dev/null || true # Ignoruj błąd, jeśli crontab nie istnieje
    # Dodaj komentarz wyjaśniający
    echo -e "\n# Added by Linux Setup Manager ($(date +%Y-%m-%d)) - Sample Rsync Backup" >> "$temp_cronfile"
    echo "$cron_line" >> "$temp_cronfile"

    if sudo crontab -u "$backup_user" "$temp_cronfile"; then
        log_msg "$(printf "$MSG_BACKUP_CRON_EXAMPLE" "$backup_user")"
        rm "$temp_cronfile" # Usuń plik tymczasowy
        CONFIG_CHANGES_MADE=true
        # Pokaż wiadomość w UI
        if command -v $UI_TOOL >/dev/null; then
             local ui_message=$(printf "$MSG_BACKUP_CRON_EXAMPLE" "$backup_user" "$backup_user")
             show_message "$ui_message"
        fi
        return 0
    else
        log_error "$(printf "$MSG_BACKUP_CRON_ADD_FAILED" "$backup_user")"
        rm "$temp_cronfile" # Usuń plik tymczasowy
        show_message "ERROR: $(printf "$MSG_BACKUP_CRON_ADD_FAILED" "$backup_user") Check logs."
        return 1 # Błąd dodawania do crontab
    fi
}


# --- Główna funkcja modułu Backup ---
run_backup_menu() {
     while true; do
        local choice
        choice=$(show_menu "$SUBMENU_BACKUP_TITLE" "$SUBMENU_BACKUP_DESC" \
            "INSTALL_TOOLS" "$OPT_INSTALL_BACKUP_TOOLS" \
            "SETUP_CRON" "$OPT_SETUP_RSYNC_CRON" \
            "BACK" "$OPT_BACKUP_BACK")
        local exit_status=$?
        [ $exit_status -ne 0 ] && choice="BACK"

        case "$choice" in
            INSTALL_TOOLS) install_backup_tools ;;
            SETUP_CRON) setup_rsync_cron ;;
            BACK) break ;;
            *) log_warn "Invalid choice in backup menu: $choice" ;;
        esac
        # if [ "$choice" != "BACK" ] && [ $? -eq 0 ]; then wait_for_enter; fi
    done
    return 0
}