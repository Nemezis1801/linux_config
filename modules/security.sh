#!/bin/bash
# Moduł: Security - Wzmocnienie SSH, Fail2Ban, Certbot, SELinux/AppArmor, AutoUpdates
# Plik: modules/security.sh

# --- Konfiguracja SSH ---
# Wzmacnia konfigurację serwera SSH (/etc/ssh/sshd_config)
configure_ssh() {
    log_msg "Configuring SSH server (sshd)..."
    local sshd_config_file="/etc/ssh/sshd_config"
    local ssh_server_pkg="openssh-server" # Domyślna nazwa pakietu

    # Sprawdź, czy plik konfiguracyjny istnieje
    if [ ! -f "$sshd_config_file" ]; then
        log_warn "$(printf "$MSG_SSH_CONFIG_NOT_FOUND" "$sshd_config_file")"
        # Spróbuj zainstalować serwer SSH, jeśli go nie ma
        if ask_yesno "$PROMPT_INSTALL_SSH_SERVER"; then
             # Nazwa pakietu może się różnić
             if [[ "$PKG_MANAGER" == "apt" ]]; then ssh_server_pkg="openssh-server"; fi
             # Na systemach RPM często jest to 'openssh-server'
             log_msg "Attempting to install SSH server package '$ssh_server_pkg'..."
             if ! install_packages "$ssh_server_pkg"; then
                 log_error "$MSG_SSH_INSTALL_FAILED"
                 show_message "$MSG_SSH_INSTALL_FAILED"
                 return 1
             fi
             # Sprawdź ponownie, czy plik konfiguracyjny istnieje po instalacji
             if [ ! -f "$sshd_config_file" ]; then
                  log_error "$(printf "$MSG_SSH_CONFIG_STILL_NOT_FOUND" "$sshd_config_file")"
                  show_message "$(printf "$MSG_SSH_CONFIG_STILL_NOT_FOUND" "$sshd_config_file")"
                  return 1
             fi
             log_msg "SSH server installed successfully."
             # Upewnij się, że usługa jest włączona i działa po instalacji
             manage_service "$ssh_server_pkg" enable || log_warn "Failed to enable sshd/ssh service."
             manage_service "$ssh_server_pkg" start || log_warn "Failed to start sshd/ssh service."
        else
            log_msg "$MSG_SSH_INSTALL_SKIPPED"
            return 1 # Nie można kontynuować bez konfiguracji SSH
        fi
    fi

    # Zapytaj, czy zastosować wzmocnienia
    if ! confirm_action "$PROMPT_CONFIG_SSH"; then
        log_msg "$MSG_SSH_CONFIG_SKIPPED"
        return 1 # Anulowano
    fi

    # Utwórz kopię zapasową przed modyfikacją
    create_backup "$sshd_config_file" || return 1

    log_msg "$MSG_SSH_APPLYING_RULES..."

    # Zmiana portu (opcjonalna)
    local current_port=22 # Domyślny
    set +e # Wyłącz set -e na czas grep
    local port_line=$(grep -iE "^\s*Port\s+" "$sshd_config_file" | head -n 1)
    set -e
    if [ -n "$port_line" ]; then
        local detected_port=$(echo "$port_line" | awk '{print $2}')
        if [[ "$detected_port" =~ ^[0-9]+$ ]]; then current_port=$detected_port; fi
    fi
    log_msg "Current SSH port detected/assumed: $current_port"

    if ask_yesno "$(printf "$PROMPT_SSH_CHANGE_PORT" "$current_port")"; then
        local new_port
        new_port=$(ask_input "$PROMPT_SSH_NEW_PORT" "$current_port")
        local input_status=$?
        if [ $input_status -eq 0 ] && [[ "$new_port" =~ ^[0-9]+$ ]] && [ "$new_port" -gt 0 ] && [ "$new_port" -lt 65536 ] && [ "$new_port" != "$current_port" ]; then
             # Zmień lub dodaj dyrektywę Port
             # Najpierw usuń istniejącą (zakomentowaną lub nie)
             sudo sed -i '/^[[:space:]]*#*Port\s\+/d' "$sshd_config_file"
             # Dodaj nową na początku pliku (lub w innym preferowanym miejscu)
             echo "Port $new_port" | sudo tee -a "$sshd_config_file" > /dev/null
             log_msg "$(printf "$MSG_SSH_PORT_CHANGED" "$new_port")"
             show_message "$(printf "$MSG_SSH_PORT_REMINDER" "$new_port")"
             current_port=$new_port # Zaktualizuj bieżący port na potrzeby logów/komunikatów
        elif [ $input_status -ne 0 ]; then
             log_msg "Port change cancelled."
        else
             log_warn "$(printf "$MSG_SSH_INVALID_PORT" "$current_port")"
        fi
    fi

    # Wyłącz logowanie roota (PermitRootLogin)
    if ask_yesno "$PROMPT_SSH_DISABLE_ROOT"; then
         sudo sed -i 's/^[[:space:]]*#*PermitRootLogin.*/PermitRootLogin no/' "$sshd_config_file"
         log_msg "$MSG_SSH_ROOT_LOGIN_DISABLED"
    fi

    # Ustaw MaxAuthTries
    sudo sed -i 's/^[[:space:]]*#*MaxAuthTries.*/MaxAuthTries 3/' "$sshd_config_file"
    # Jeśli linia nie istnieje, dodaj ją (mniej typowe, ale bezpieczne)
    if ! grep -q "^\s*MaxAuthTries" "$sshd_config_file"; then
        echo "MaxAuthTries 3" | sudo tee -a "$sshd_config_file" > /dev/null
    fi
    log_msg "$MSG_SSH_MAX_AUTH_TRIES"

    # Ustaw LoginGraceTime
    sudo sed -i 's/^[[:space:]]*#*LoginGraceTime.*/LoginGraceTime 60/' "$sshd_config_file"
     if ! grep -q "^\s*LoginGraceTime" "$sshd_config_file"; then
        echo "LoginGraceTime 60" | sudo tee -a "$sshd_config_file" > /dev/null
    fi
    log_msg "$MSG_SSH_LOGIN_GRACE_TIME"

    # Wyłącz puste hasła (PermitEmptyPasswords)
    sudo sed -i 's/^[[:space:]]*#*PermitEmptyPasswords.*/PermitEmptyPasswords no/' "$sshd_config_file"
     if ! grep -q "^\s*PermitEmptyPasswords" "$sshd_config_file"; then
        echo "PermitEmptyPasswords no" | sudo tee -a "$sshd_config_file" > /dev/null
    fi
    log_msg "$MSG_SSH_EMPTY_PASSWORDS"

    # Włącz/Wyłącz uwierzytelnianie hasłem (PasswordAuthentication)
    if ask_yesno "$PROMPT_SSH_DISABLE_PASSWD"; then
         sudo sed -i 's/^[[:space:]]*#*PasswordAuthentication.*/PasswordAuthentication no/' "$sshd_config_file"
          if ! grep -q "^\s*PasswordAuthentication" "$sshd_config_file"; then
             echo "PasswordAuthentication no" | sudo tee -a "$sshd_config_file" > /dev/null
          fi
         log_msg "$MSG_SSH_PASSWD_AUTH_DISABLED"
    else
         sudo sed -i 's/^[[:space:]]*#*PasswordAuthentication.*/PasswordAuthentication yes/' "$sshd_config_file"
          if ! grep -q "^\s*PasswordAuthentication" "$sshd_config_file"; then
             echo "PasswordAuthentication yes" | sudo tee -a "$sshd_config_file" > /dev/null
          fi
         log_msg "$MSG_SSH_PASSWD_AUTH_ENABLED"
    fi

    # Ograniczenie dostępu do użytkowników (AllowUsers)
    if ask_yesno "$PROMPT_SSH_ALLOW_USERS"; then
        local allowed_users
        allowed_users=$(ask_input "$PROMPT_SSH_ALLOWED_USERS_INPUT" "")
        local input_status=$?
        if [ $input_status -eq 0 ] && [ -n "$allowed_users" ]; then
            # Usuń istniejącą linię AllowUsers, jeśli istnieje
            sudo sed -i '/^[[:space:]]*#*AllowUsers\s\+/d' "$sshd_config_file"
            # Dodaj nową linię
            echo "AllowUsers $allowed_users" | sudo tee -a "$sshd_config_file" > /dev/null
            log_msg "$(printf "$MSG_SSH_ACCESS_RESTRICTED" "$allowed_users")"
        elif [ $input_status -ne 0 ]; then
             log_msg "AllowUsers configuration cancelled."
        else
             log_warn "No users specified for AllowUsers. Removing restriction if exists."
              sudo sed -i '/^[[:space:]]*#*AllowUsers\s\+/d' "$sshd_config_file"
              log_msg "$MSG_SSH_ALLOWUSERS_REMOVED"
        fi
    else
         # Upewnij się, że nie ma ograniczenia, jeśli użytkownik wybrał "Nie"
         sudo sed -i '/^[[:space:]]*#*AllowUsers\s\+/d' "$sshd_config_file"
         log_msg "$MSG_SSH_ALLOWUSERS_REMOVED"
    fi

    # Test konfiguracji SSHD
    log_msg "$MSG_SSH_TESTING_CONFIG..."
    # Wyłącz set -e na czas testu
    set +e
    local sshd_test_output
    sshd_test_output=$(sudo sshd -t 2>&1)
    local test_status=$?
    set -e # Włącz set -e

    if [ $test_status -eq 0 ]; then
        log_msg "$MSG_SSH_CONFIG_TEST_OK"
        # Restart usługi SSH
        log_msg "$MSG_SSH_RESTARTING_SERVICE..."
        # Spróbuj obu nazw usługi: sshd i ssh
        if manage_service sshd restart || manage_service ssh restart; then
             log_msg "$MSG_SSH_CONFIG_APPLIED"
             CONFIG_CHANGES_MADE=true
             NEEDS_REBOOT=true # Dobry pomysł po zmianach SSH
             return 0
        else
             log_error "$MSG_SSH_RESTART_FAILED"
             show_message "$MSG_SSH_RESTART_FAILED"
             return 1 # Błąd restartu usługi
        fi
    else
        log_error "$(printf "$MSG_SSH_CONFIG_TEST_FAIL" "$sshd_config_file" "$BACKUP_DIR")"
        log_error "sshd -t output:\n$sshd_test_output"
        show_message "ERROR: $(printf "$MSG_SSH_CONFIG_TEST_FAIL" "$sshd_config_file" "$BACKUP_DIR")\nCheck logs for details. Configuration NOT applied."
        # Rozważ automatyczne przywrócenie backupu?
        # log_msg "Attempting to restore SSH config from backup..."
        # sudo cp "$BACKUP_DIR/$sshd_config_file" "$sshd_config_file" || log_error "Failed to restore SSH config backup!"
        return 1 # Błąd konfiguracji
    fi
}

# --- Konfiguracja Fail2Ban ---
# Instaluje i konfiguruje podstawowe zasady Fail2Ban
configure_fail2ban() {
    if ! confirm_action "$PROMPT_INSTALL_FAIL2BAN"; then
        log_msg "$MSG_FAIL2BAN_INSTALL_SKIPPED"
        return 1 # Anulowano
    fi

    local fail2ban_pkg="fail2ban"
    log_msg "Installing Fail2Ban package '$fail2ban_pkg'..."
    if ! install_packages "$fail2ban_pkg"; then
        log_error "Failed to install Fail2Ban."
        show_message "ERROR: Failed to install Fail2Ban."
        return 1
    fi

    log_msg "$MSG_FAIL2BAN_CONFIGURING"
    local jail_conf="/etc/fail2ban/jail.conf"
    local jail_local="/etc/fail2ban/jail.local"

    # Utwórz jail.local z domyślnych ustawień, jeśli nie istnieje
    if [ ! -f "$jail_local" ]; then
        if [ -f "$jail_conf" ]; then
            log_msg "Creating $jail_local from $jail_conf..."
            if ! sudo cp "$jail_conf" "$jail_local"; then
                 log_error "Failed to create $jail_local. Check permissions."
                 return 1
            fi
            # Zrób backup nowo utworzonego pliku
            create_backup "$jail_local" || return 1
        else
            log_error "$(printf "$MSG_FAIL2BAN_NO_JAIL_CONF") Cannot create $jail_local."
            return 1
        fi
    else
        log_msg "$jail_local already exists. Creating backup before potential modification."
        create_backup "$jail_local" || return 1
    fi

    # Zastosuj podstawowe zmiany w jail.local - włącz ochronę SSH
    # Zamiast edytować [DEFAULT], lepiej dodać/zmodyfikować sekcję [sshd]
    log_msg "Ensuring SSHd jail is enabled in $jail_local..."

    # Sprawdź, czy sekcja [sshd] istnieje
    if ! grep -q '^[[:space:]]*\[sshd\]' "$jail_local"; then
         # Jeśli nie, dodaj podstawową sekcję na końcu pliku
         log_msg "Section [sshd] not found in $jail_local. Adding basic enabled section."
         if ! echo -e "\n[sshd]\nenabled = true\n# Optional: Set specific bantime/maxretry for sshd\n# bantime = 1h\n# maxretry = 3" | sudo tee -a "$jail_local" > /dev/null; then
             log_error "Failed to append [sshd] section to $jail_local."
             return 1
         fi
         log_msg "$MSG_FAIL2BAN_ADDED_SSHD_JAIL"
    else
         # Jeśli sekcja istnieje, upewnij się, że 'enabled = true' jest ustawione i odkomentowane
         # To jest bardziej złożone z sed, prostsze może być użycie `crudini` lub `augtool` jeśli dostępne
         # Proste podejście z sed:
         # 1. Znajdź linię [sshd]
         # 2. W zakresie do następnej sekcji [...] lub końca pliku:
         # 3. Zamień '#*enabled[[:space:]]*=.*' na 'enabled = true'
         # Uwaga: sed może być skomplikowany dla różnych przypadków
         # Użyjmy prostszego, mniej odpornego sed:
         # Odkomentuj i ustaw enabled = true w sekcji [sshd]
         sudo sed -i '/^[[:space:]]*\[sshd\]/,/^[[:space:]]*\[/ s/^[[:space:]]*#*[[:space:]]*enabled[[:space:]]*=.*/enabled = true/' "$jail_local"
         log_msg "$MSG_FAIL2BAN_ENSURED_SSHD_ENABLED"
         # Można też ustawić bantime i maxretry w podobny sposób, jeśli użytkownik sobie życzy
         # np. sudo sed -i '/^[[:space:]]*\[sshd\]/,/^[[:space:]]*\[/ s/^[[:space:]]*#*[[:space:]]*bantime[[:space:]]*=.*/bantime = 1h/' "$jail_local"
         # np. sudo sed -i '/^[[:space:]]*\[sshd\]/,/^[[:space:]]*\[/ s/^[[:space:]]*#*[[:space:]]*maxretry[[:space:]]*=.*/maxretry = 3/' "$jail_local"
    fi

    # Włącz i zrestartuj usługę Fail2Ban
    log_msg "Enabling and restarting Fail2Ban service..."
    if ! manage_service fail2ban enable || ! manage_service fail2ban restart; then
        log_error "$MSG_FAIL2BAN_ENABLE_RESTART_FAILED"
        show_message "ERROR: $MSG_FAIL2BAN_ENABLE_RESTART_FAILED Check logs."
        return 1
    fi

    log_msg "$MSG_FAIL2BAN_CONFIGURED"
    CONFIG_CHANGES_MADE=true
    return 0
}

# --- Konfiguracja Certbot (Let's Encrypt) ---
# Instaluje Certbot i opcjonalnie wtyczki dla serwerów WWW
configure_certbot() {
     if ! confirm_action "$PROMPT_INSTALL_CERTBOT"; then
         log_msg "$MSG_CERTBOT_INSTALL_SKIPPED"
         return 1 # Anulowano
     fi

     local certbot_pkg="certbot"
     local certbot_apache_plugin=""
     local certbot_nginx_plugin=""
     local packages_to_install=("$certbot_pkg")

     # Określ nazwy pakietów wtyczek w zależności od dystrybucji
     case "$PKG_MANAGER" in
         apt)
             certbot_apache_plugin="python3-certbot-apache"
             certbot_nginx_plugin="python3-certbot-nginx"
             ;;
         dnf|yum)
             certbot_apache_plugin="python3-certbot-apache" # Może być python-certbot-apache w starszych
             certbot_nginx_plugin="python3-certbot-nginx"   # Może być python-certbot-nginx w starszych
             ;;
         pacman)
             certbot_apache_plugin="certbot-apache"
             certbot_nginx_plugin="certbot-nginx"
             ;;
         zypper)
             certbot_apache_plugin="python3-certbot-apache" # Sprawdź dokładną nazwę
             certbot_nginx_plugin="python3-certbot-nginx"   # Sprawdź dokładną nazwę
             ;;
     esac

     # Sprawdź, czy serwery WWW są zainstalowane i dodaj odpowiednie wtyczki
     local webserver_found=false
     if is_package_installed apache2 || is_package_installed httpd; then
         if [ -n "$certbot_apache_plugin" ]; then
             packages_to_install+=("$certbot_apache_plugin")
             log_msg "Apache detected, adding Certbot plugin: $certbot_apache_plugin"
             webserver_found=true
         else
              log_warn "Apache detected, but Apache plugin package name is unknown for '$PKG_MANAGER'."
         fi
     fi
      if is_package_installed nginx; then
         if [ -n "$certbot_nginx_plugin" ]; then
             packages_to_install+=("$certbot_nginx_plugin")
             log_msg "Nginx detected, adding Certbot plugin: $certbot_nginx_plugin"
             webserver_found=true
         else
             log_warn "Nginx detected, but Nginx plugin package name is unknown for '$PKG_MANAGER'."
         fi
     fi

     if [ "$webserver_found" = false ]; then
         log_warn "$MSG_CERTBOT_CORE_ONLY_WARN"
     fi

     # Usuń duplikaty przed instalacją
     local unique_packages=($(echo "${packages_to_install[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

     log_msg "Installing Certbot packages: ${unique_packages[*]}"
     if ! install_packages "${unique_packages[@]}"; then
         log_error "Failed to install Certbot packages."
         show_message "ERROR: Failed to install Certbot packages."
         return 1
     fi

     log_msg "$MSG_CERTBOT_INSTALLED"
     show_message "$MSG_CERTBOT_USAGE_INFO"

     # Skonfiguruj automatyczne odnawianie (zazwyczaj robi to pakiet certbota przez timer lub cron)
     log_msg "Checking for Certbot automatic renewal timer..."
     # Wyłącz set -e na czas sprawdzania timera
     set +e
     if systemctl list-timers | grep -q 'certbot.timer'; then
         log_msg "$MSG_CERTBOT_RENEWAL_TIMER_OK"
         # Upewnij się, że jest włączony i aktywny
         if manage_service certbot.timer enable; then
              log_msg "$MSG_CERTBOT_RENEWAL_TIMER_ENABLED"
         fi
     # Niektóre systemy mogą używać crona w /etc/cron.d/
     elif [ -f /etc/cron.d/certbot ]; then
          log_msg "Certbot cron job found in /etc/cron.d/certbot. Automatic renewal should be configured."
     else
         log_warn "$MSG_CERTBOT_RENEWAL_TIMER_WARN"
         # Można dodać logikę tworzenia zadania cron jako fallback
         # np. echo "0 */12 * * * root certbot renew --quiet" | sudo tee /etc/cron.d/certbot-renew-custom > /dev/null
     fi
     set -e # Włącz set -e

     CONFIG_CHANGES_MADE=true # Instalacja pakietu to zmiana
     return 0
}

# --- Sprawdzenie SELinux/AppArmor ---
# Sprawdza status modułów bezpieczeństwa SELinux lub AppArmor
check_security_modules() {
    if ! confirm_action "$PROMPT_CHECK_SELINUX_APPARMOR"; then
        log_msg "$MSG_SE_AA_CHECK_SKIPPED"
        return 1 # Anulowano
    fi

    local status_msg=""
    local selinux_found=false
    local apparmor_found=false

    # Sprawdź SELinux (głównie systemy RPM)
    if command -v getenforce > /dev/null 2>&1; then
        selinux_found=true
        local selinux_status
        selinux_status=$(getenforce)
        log_msg "$(printf "$MSG_SELINUX_STATUS" "$selinux_status")"
        status_msg+="$(printf "$MSG_SELINUX_STATUS" "$selinux_status")\n"
    else
         log_msg "$MSG_SELINUX_CMD_NOT_FOUND"
    fi

    # Sprawdź AppArmor (głównie Debian/Ubuntu/SUSE)
    if command -v aa-status > /dev/null 2>&1; then
        apparmor_found=true
        log_msg "$MSG_APPARMOR_STATUS"
        status_msg+="\n$MSG_APPARMOR_STATUS\n"
        # Wyłącz set -e na czas wywołania aa-status, które może zwrócić błąd, jeśli niezaładowany
        set +e
        local apparmor_output
        apparmor_output=$(sudo aa-status 2>&1)
        local aa_status_code=$?
        set -e
        log_msg "AppArmor Status Output (Code: $aa_status_code):\n$apparmor_output" # Zaloguj pełny status
        # Dodaj tylko pierwsze kilka linii do wiadomości UI
        status_msg+=$(echo "$apparmor_output" | head -n 5)
        if [ $(echo "$apparmor_output" | wc -l) -gt 5 ]; then status_msg+="\n(...)"; fi
    else
         log_msg "$MSG_APPARMOR_CMD_NOT_FOUND"
    fi

    # Pokaż podsumowanie w UI
    if [ "$selinux_found" = false ] && [ "$apparmor_found" = false ]; then
        log_msg "$MSG_SE_AA_NONE_FOUND"
        show_message "$MSG_SE_AA_NONE_FOUND"
    else
        show_message "$status_msg"
    fi
    return 0
}

# --- Konfiguracja Automatycznych Aktualizacji ---
# Konfiguruje automatyczne aktualizacje bezpieczeństwa (jeśli obsługiwane)
configure_automatic_updates() {
     if ! confirm_action "$PROMPT_CONFIG_AUTO_UPDATES"; then
         log_msg "$MSG_AUTO_UPDATES_CONFIG_SKIPPED"
         return 1 # Anulowano
     fi

     CONFIG_CHANGES_MADE=true # Nawet próba konfiguracji to zmiana
     local pkg_name=""
     local config_success=false

     log_msg "Attempting to configure automatic security updates for '$DISTRO_ID'..."

     case "$PKG_MANAGER" in
         apt)
             pkg_name="unattended-upgrades"
             log_msg "Installing/configuring $pkg_name for Debian/Ubuntu family..."
             # Upewnij się, że pakiet jest zainstalowany
             if ! install_packages "$pkg_name" apt-listchanges; then
                 log_error "$(printf "$MSG_AUTO_UPDATES_FAILED_INSTALL" "$pkg_name")"
                 return 1
             fi
             # Podstawowa konfiguracja: włącz tylko aktualizacje bezpieczeństwa
             local uupg_conf="/etc/apt/apt.conf.d/50unattended-upgrades"
             local auto_upg_conf="/etc/apt/apt.conf.d/20auto-upgrades"
             create_backup "$uupg_conf" || return 1
             create_backup "$auto_upg_conf" || return 1

             # Włącz tylko linie origin=...Security...
             # Zakomentuj inne linie origins (updates, proposed, backports)
             sudo sed -i -E \
                 -e 's|^//(.*"-security".*);|\1;|' \
                 -e 's|^([[:space:]]*".*-(updates|proposed|backports).*);|\//\1;|' \
                 "$uupg_conf"

             # Włącz codzienne sprawdzanie i instalację
             log_msg "Configuring $auto_upg_conf..."
             if ! echo -e 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";' | sudo tee "$auto_upg_conf" > /dev/null; then
                  log_error "Failed to write to $auto_upg_conf."
                  return 1
             fi
             # Uruchom ponownie, aby zastosować (lub system sam to zrobi)
             # manage_service unattended-upgrades restart # Usługa może nie istnieć/działać inaczej
             log_msg "$MSG_AUTO_UPDATES_CONFIGURED_APT"
             config_success=true
             ;;
         dnf|yum)
             if [ "$PKG_MANAGER" == "dnf" ]; then
                 pkg_name="dnf-automatic"
             else # yum
                 pkg_name="yum-cron"
             fi
             log_msg "Installing/configuring $pkg_name for RHEL/Fedora family..."
             if ! install_packages "$pkg_name"; then
                  log_error "$(printf "$MSG_AUTO_UPDATES_FAILED_INSTALL" "$pkg_name")"
                  return 1
             fi

             if [ "$pkg_name" == "dnf-automatic" ]; then
                 local dnf_conf="/etc/dnf/automatic.conf"
                 create_backup "$dnf_conf" || return 1
                 log_msg "Configuring $dnf_conf..."
                 # Ustaw apply_updates = yes
                 sudo sed -i 's/^[#[:space:]]*apply_updates\s*=.*/apply_updates = yes/' "$dnf_conf"
                 # Opcjonalnie: ustaw upgrade_type = security
                 sudo sed -i 's/^[#[:space:]]*upgrade_type\s*=.*/upgrade_type = security/' "$dnf_conf"
                 # Włącz i uruchom timer
                 if manage_service dnf-automatic.timer enable; then
                     log_msg "$MSG_AUTO_UPDATES_CONFIGURED_DNF"
                     config_success=true
                 else
                     log_error "Failed to enable/start dnf-automatic.timer."
                 fi
             elif [ "$pkg_name" == "yum-cron" ]; then
                 local yum_conf="/etc/yum/yum-cron.conf"
                 create_backup "$yum_conf" || return 1
                 log_msg "Configuring $yum_conf..."
                  # Ustaw apply_updates = yes
                 sudo sed -i 's/^[#[:space:]]*apply_updates\s*=.*/apply_updates = yes/' "$yum_conf"
                  # Ustaw update_cmd = security (lub default, minimal)
                 sudo sed -i 's/^[#[:space:]]*update_cmd\s*=.*/update_cmd = security/' "$yum_conf"
                 # Włącz i uruchom usługę
                 if manage_service yum-cron enable && manage_service yum-cron start; then
                     log_msg "$MSG_AUTO_UPDATES_CONFIGURED_YUM"
                     config_success=true
                 else
                     log_error "Failed to enable/start yum-cron service."
                 fi
             fi
             ;;
         pacman)
             log_warn "$MSG_AUTO_UPDATES_WARN_PACMAN"
             show_message "$MSG_AUTO_UPDATES_WARN_PACMAN"
             # Zwróć sukces, bo brak konfiguracji jest oczekiwany
             config_success=true
             ;;
         zypper)
             log_warn "$MSG_AUTO_UPDATES_WARN_ZYPPER"
             show_message "$MSG_AUTO_UPDATES_WARN_ZYPPER"
             config_success=true
             ;;
         *)
             log_error "$(printf "$MSG_AUTO_UPDATES_NOT_IMPLEMENTED" "$PKG_MANAGER")"
             ;;
     esac

     if [ "$config_success" = true ]; then
         log_msg "$MSG_AUTO_UPDATES_CONFIGURED"
         if command -v $UI_TOOL >/dev/null; then
             show_message "$MSG_AUTO_UPDATES_CONFIGURED"
         fi
         return 0
     else
          log_error "$MSG_AUTO_UPDATES_FAILED"
          if command -v $UI_TOOL >/dev/null; then
             show_message "$MSG_AUTO_UPDATES_FAILED"
          fi
         return 1
     fi
}

# --- Główna funkcja modułu Bezpieczeństwa ---
# Wyświetla podmenu
run_security_menu() {
     while true; do
        local choice
        choice=$(show_menu "$SUBMENU_SECURITY_TITLE" "$SUBMENU_SECURITY_DESC" \
            "SSH" "$OPT_CONFIG_SSH" \
            "FAIL2BAN" "$OPT_CONFIG_FAIL2BAN" \
            "CERTBOT" "$OPT_CONFIG_CERTBOT" \
            "SE_AA" "$OPT_CHECK_SE_AA" \
            "AUTOUPDATE" "$OPT_CONFIG_AUTOUPDATE" \
            "BACK" "$OPT_SECURITY_BACK")
        local exit_status=$?
        [ $exit_status -ne 0 ] && choice="BACK"

        case "$choice" in
            SSH) configure_ssh ;;
            FAIL2BAN) configure_fail2ban ;;
            CERTBOT) configure_certbot ;;
            SE_AA) check_security_modules ;;
            AUTOUPDATE) configure_automatic_updates ;;
            BACK) break ;;
            *) log_warn "Invalid choice in security menu: $choice" ;;
        esac
        # if [ "$choice" != "BACK" ]; then wait_for_enter; fi
    done
    return 0
}