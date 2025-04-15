#!/bin/bash
# Moduł: Scenarios - Gotowe sekwencje zadań konfiguracyjnych
# Plik: modules/scenarios.sh

# Scenariusz: Konfiguracja Standardowego Serwera WWW
run_scenario_web_server() {
    log_msg "$MSG_SCENARIO_WEB_STARTING"
    # Pokaż opis scenariusza
    if command -v $UI_TOOL >/dev/null; then
        show_message "$MSG_SCENARIO_WEB_DESC"
    else
        log_msg "$MSG_SCENARIO_WEB_DESC"
    fi

    # Krok 1: Podstawowa konfiguracja systemu (opcjonalnie, ale zalecane)
    if confirm_action "$PROMPT_SCENARIO_CONFIGURE_BASICS"; then
        # Wywołaj funkcje z modułu system_config.sh
        configure_hostname || log_warn "Hostname configuration skipped or failed."
        manage_users_submenu || log_warn "User management skipped or failed."
    fi

    # Krok 2: Instalacja serwera WWW (wymagane dla tego scenariusza)
    log_msg "Scenario Step: Installing Web Server..."
    # Wywołaj funkcję z modułu app_installer.sh
    if ! install_web_server; then
        log_error "Web server installation failed. Aborting scenario."
        show_message "ERROR: Web server installation failed. Scenario aborted."
        return 1 # Przerwij scenariusz, bo to kluczowy element
    fi

    # Krok 3: Instalacja bazy danych (wymagane)
    log_msg "Scenario Step: Installing Database Server..."
    # Wywołaj funkcję z modułu app_installer.sh
    if ! install_database; then
        log_error "Database installation failed. Aborting scenario."
        show_message "ERROR: Database installation failed. Scenario aborted."
        return 1 # Przerwij, baza danych jest zwykle potrzebna
    fi

    # Krok 4: Instalacja popularnych narzędzi (użytkowych i deweloperskich)
    if confirm_action "$PROMPT_SCENARIO_INSTALL_TOOLS"; then
        log_msg "Scenario Step: Installing Common & Dev Tools..."
        # Wywołaj funkcje z modułu app_installer.sh
        install_tools "common" || log_warn "Common tools installation skipped or failed."
        install_tools "dev" || log_warn "Dev tools installation skipped or failed."
    fi

    # Krok 5: Konfiguracja bezpieczeństwa (ważne)
    if confirm_action "$PROMPT_SCENARIO_CONFIGURE_SECURITY"; then
        log_msg "Scenario Step: Configuring Security Settings..."
        # Wywołaj funkcje z modułu security.sh
        configure_ssh || log_warn "SSH configuration skipped or failed."
        configure_fail2ban || log_warn "Fail2Ban configuration skipped or failed."
        # Certbot po instalacji serwera WWW i potencjalnej konfiguracji DNS
        configure_certbot || log_warn "Certbot configuration skipped or failed."
    fi

     # Krok 6: Konfiguracja zapory sieciowej (bardzo ważne, po zainstalowaniu usług)
     log_msg "Scenario Step: Configuring Firewall..."
     # Wywołaj funkcję z modułu network_config.sh
     configure_firewall || log_warn "Firewall configuration skipped or failed. This is highly discouraged for a web server!"

    # Krok 7: Konfiguracja automatycznych aktualizacji (zalecane)
    if confirm_action "$PROMPT_SCENARIO_CONFIGURE_AUTOUPDATES"; then
        log_msg "Scenario Step: Configuring Automatic Updates..."
        # Wywołaj funkcję z modułu security.sh
        configure_automatic_updates || log_warn "Automatic updates configuration skipped or failed."
    fi

    log_msg "$MSG_SCENARIO_WEB_COMPLETED"
    # Pokaż podsumowanie
    if command -v $UI_TOOL >/dev/null; then
        local final_msg
        final_msg=$(printf "$MSG_SCENARIO_WEB_FINISHED_MSG" "$(printf "$MSG_CHECK_LOG" "$LOG_FILE")" "$(printf "$MSG_REQUIRES_REBOOT")")
        show_message "$final_msg"
    fi
    return 0 # Scenariusz zakończony (nawet jeśli niektóre opcjonalne kroki zawiodły)
}

# Scenariusz: Konfiguracja Minimalnego Bezpiecznego Serwera
run_scenario_minimal_secure() {
    log_msg "$MSG_SCENARIO_MINIMAL_STARTING"
     if command -v $UI_TOOL >/dev/null; then
        show_message "$MSG_SCENARIO_MINIMAL_DESC"
    else
        log_msg "$MSG_SCENARIO_MINIMAL_DESC"
    fi

    # Krok 1: Konfiguracja hostname (podstawowe)
    log_msg "Scenario Step: Configuring Hostname..."
    configure_hostname || log_warn "Hostname configuration skipped or failed."

    # Krok 2: Wzmocnienie SSH (Kluczowe)
    log_msg "Scenario Step: Hardening SSH..."
    if ! configure_ssh; then
         log_error "SSH hardening failed. Aborting scenario as it's critical."
         show_message "ERROR: SSH hardening failed. Scenario aborted."
         return 1
    fi

    # Krok 3: Konfiguracja zapory sieciowej (Kluczowe)
    log_msg "Scenario Step: Configuring Firewall..."
     if ! configure_firewall; then
         log_error "Firewall configuration failed. Aborting scenario as it's critical."
         show_message "ERROR: Firewall configuration failed. Scenario aborted."
         return 1
     fi

    # Krok 4: Instalacja podstawowych narzędzi użytkowych
    log_msg "Scenario Step: Installing Common Tools..."
    install_tools "common" || log_warn "Common tools installation skipped or failed."

    # Krok 5: Konfiguracja automatycznych aktualizacji (Zalecane)
    if confirm_action "$PROMPT_SCENARIO_CONFIGURE_AUTOUPDATES"; then
        log_msg "Scenario Step: Configuring Automatic Updates..."
        configure_automatic_updates || log_warn "Automatic updates configuration skipped or failed."
    fi

    # Krok 6: Opcjonalnie Fail2ban (Bardzo zalecane)
    if confirm_action "$PROMPT_SCENARIO_MINIMAL_FAIL2BAN"; then
        log_msg "Scenario Step: Configuring Fail2Ban..."
        configure_fail2ban || log_warn "Fail2Ban configuration skipped or failed."
    fi

    log_msg "$MSG_SCENARIO_MINIMAL_COMPLETED"
    if command -v $UI_TOOL >/dev/null; then
         local final_msg
         final_msg=$(printf "$MSG_SCENARIO_MINIMAL_FINISHED_MSG" "$(printf "$MSG_CHECK_LOG" "$LOG_FILE")" "$(printf "$MSG_REQUIRES_REBOOT")")
         show_message "$final_msg"
     fi
    return 0
}

# Scenariusz: Konfiguracja Stanowiska Deweloperskiego
run_scenario_developer_workstation() {
     log_msg "$MSG_SCENARIO_DEV_STARTING"
      if command -v $UI_TOOL >/dev/null; then
         show_message "$MSG_SCENARIO_DEV_DESC"
     else
         log_msg "$MSG_SCENARIO_DEV_DESC"
     fi

     # Krok 1: Konfiguracja systemu (opcjonalnie, ale często przydatne)
     if confirm_action "$PROMPT_SCENARIO_CONFIGURE_BASICS"; then
         configure_hostname || log_warn "Hostname configuration skipped or failed."
         # Dodanie użytkownika jest ważne dla środowiska deweloperskiego
         manage_users_submenu || log_warn "User management skipped or failed."
     fi

     # Krok 2: Instalacja narzędzi deweloperskich (kluczowe)
     log_msg "Scenario Step: Installing Development Tools..."
     if ! install_tools "dev"; then
          log_error "Development tools installation failed. Aborting scenario."
          show_message "ERROR: Development tools installation failed. Scenario aborted."
          return 1
     fi
     # Zainstaluj też podstawowe narzędzia użytkowe
     log_msg "Scenario Step: Installing Common Tools..."
     install_tools "common" || log_warn "Common tools installation skipped or failed."


     # Krok 3: Instalacja silnika kontenerów (opcjonalnie)
     if confirm_action "$PROMPT_SCENARIO_DEV_INSTALL_CONTAINER"; then
         log_msg "Scenario Step: Installing Container Engine..."
         install_container_engine || log_warn "Container engine installation skipped or failed."
     fi

     # Krok 4: Konfiguracja SSH (dla dostępu zdalnego/git)
     if confirm_action "$PROMPT_SCENARIO_DEV_CONFIG_SSH"; then
          log_msg "Scenario Step: Configuring SSH..."
          configure_ssh || log_warn "SSH configuration skipped or failed."
     fi

     # Krok 5: Zapora (opcjonalnie, zależy od środowiska)
     if confirm_action "$PROMPT_SCENARIO_DEV_CONFIG_FIREWALL"; then
         log_msg "Scenario Step: Configuring Firewall..."
         configure_firewall || log_warn "Firewall configuration skipped or failed."
     fi

     # Krok 6: Automatyczne aktualizacje (dobry pomysł, ale może przeszkadzać w dev)
     if confirm_action "$PROMPT_SCENARIO_CONFIGURE_AUTOUPDATES"; then
         log_msg "Scenario Step: Configuring Automatic Updates..."
         configure_automatic_updates || log_warn "Automatic updates configuration skipped or failed."
     fi

     log_msg "$MSG_SCENARIO_DEV_COMPLETED"
     if command -v $UI_TOOL >/dev/null; then
         local final_msg
         final_msg=$(printf "$MSG_SCENARIO_DEV_FINISHED_MSG" "$(printf "$MSG_CHECK_LOG" "$LOG_FILE")" "$(printf "$MSG_REQUIRES_REBOOT")")
         show_message "$final_msg"
     fi
     return 0
}