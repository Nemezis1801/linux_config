#!/bin/bash
# Moduł: Service Manager - Zarządzanie usługami systemowymi (głównie systemd)
# Plik: modules/service_manager.sh

# Mapuje nazwę pakietu na oczekiwaną nazwę usługi systemd.
# Niektóre pakiety mają inne nazwy usług niż nazwy pakietów.
# $1: Nazwa pakietu
# Zwraca: Nazwę usługi na stdout, kod wyjścia 0 w sukcesie, 1 jeśli nie można zmapować.
map_package_to_service_name() {
    local pkg_name=$1
    local service_name=$pkg_name # Domyślnie taka sama nazwa

    case "$pkg_name" in
        # Serwery WWW
        apache2) service_name="apache2" ;; # Debian/Ubuntu
        httpd) service_name="httpd" ;;     # RHEL/Fedora/Arch

        # Bazy Danych
        mariadb-server|mariadb)
             # Usługa to zazwyczaj mariadb lub mysql(d)
             # Sprawdźmy, która jednostka istnieje
             if systemctl list-unit-files | grep -q -E '^mariadb\.service'; then
                 service_name="mariadb"
             elif systemctl list-unit-files | grep -q -E '^mysql\.service'; then
                 service_name="mysql" # Niektóre systemy mogą używać mysql dla mariadb
             elif systemctl list-unit-files | grep -q -E '^mysqld\.service'; then
                 service_name="mysqld" # Starsze systemy RPM
             else
                 # Nie znaleziono znanej usługi, ale pakiet może istnieć.
                 # Może usługa nie jest jeszcze utworzona (np. przed initdb)?
                 # Zwróćmy domyślną nazwę i zobaczymy, czy zadziała.
                 log_warn "$(printf "$MSG_SERVICE_UNKNOWN_DB" "MariaDB/MySQL") Assuming service name '$service_name'."
                 # return 1 # Zwrócenie błędu mogłoby przerwać proces instalacji
             fi
            ;;
        postgresql-server|postgresql)
            # Usługa zazwyczaj nazywa się 'postgresql', ale może zawierać wersję
            if systemctl list-unit-files | grep -q -E '^postgresql@[0-9]+-[^.]+\.service'; then # Wzorzec dla instancji np. postgresql@15-main.service
                # Trudno wybrać właściwą instancję automatycznie, użyj generycznej nazwy
                service_name="postgresql"
            elif systemctl list-unit-files | grep -q -E '^postgresql\.service'; then
                 service_name="postgresql"
            else
                 log_warn "$(printf "$MSG_SERVICE_UNKNOWN_DB" "PostgreSQL") Assuming service name '$service_name'."
            fi
             ;;

        # Inne usługi
        nginx) service_name="nginx" ;;
        fail2ban) service_name="fail2ban" ;;
        ufw) service_name="ufw" ;;
        firewalld) service_name="firewalld" ;;
        sshd|openssh-server)
             # Usługa może nazywać się sshd lub ssh
             if systemctl list-unit-files | grep -q '^sshd\.service'; then
                 service_name="sshd"
             elif systemctl list-unit-files | grep -q '^ssh\.service'; then
                 service_name="ssh"
             else
                 log_warn "Cannot determine SSH service name (sshd or ssh). Assuming '$service_name'."
             fi
             ;;
        # Kontenery
        docker-ce|docker.io|docker) service_name="docker" ;;
        podman)
            # Podman często używa socket activation
            if systemctl list-unit-files | grep -q '^podman\.socket'; then
                 service_name="podman.socket"
            else
                 # Niektóre konfiguracje mogą mieć podman.service
                 service_name="podman" # Spróbuj jako fallback
                 log_msg "Podman socket not found, assuming service name 'podman'."
            fi
             ;;
        # Automatyczne aktualizacje
        unattended-upgrades) service_name="unattended-upgrades" ;;
        dnf-automatic) service_name="dnf-automatic.timer" ;; # To jest timer systemd
        yum-cron) service_name="yum-cron" ;;

        # Pakiety bez usług (przykłady)
        sqlite|sqlite3|git|curl|wget|htop|vim|nano|build-essential|base-devel|python3|rsync|parted|gdisk)
            service_name="" # Pusta nazwa oznacza brak usługi do zarządzania
            ;;

        # Dodaj więcej mapowań w razie potrzeby
        #*)
            #log_msg "No specific service mapping for package '$pkg_name', assuming service name '$service_name'."
            #;;
    esac

    # Zwróć znalezioną (lub domyślną) nazwę usługi
    echo "$service_name"
    return 0 # Zawsze zwracaj sukces, chyba że wystąpił krytyczny błąd mapowania
}


# Zarządza usługą (start, stop, enable, disable, restart, status) używając systemd
# $1: Nazwa pakietu (do mapowania na nazwę usługi)
# $2: Akcja (start, stop, enable, disable, restart, status)
# Zwraca: 0 w sukcesie, 1 w przypadku błędu wykonania polecenia systemctl
manage_service() {
    local pkg_name=$1
    local action=$2
    local service_name
    local is_timer=false

    # Zmapuj nazwę pakietu na nazwę usługi
    service_name=$(map_package_to_service_name "$pkg_name")
    local map_exit_code=$?

    # Jeśli mapowanie nie powiodło się (kod 1) lub zwróciło pustą nazwę
    if [ $map_exit_code -ne 0 ]; then
        log_warn "$MSG_SERVICE_SKIPPED_MAP_FAIL"
        return 0 # Nie traktuj tego jako błędu krytycznego skryptu
    fi
    if [ -z "$service_name" ]; then
        log_msg "$MSG_SERVICE_NO_ASSOC"
        return 0 # Pakiet nie ma powiązanej usługi, to normalne
    fi

    log_msg "$(printf "$MSG_SERVICE_MANAGING" "$service_name" "$action")"

    # Sprawdź, czy to timer
    if [[ "$service_name" == *.timer ]]; then
        is_timer=true
    fi

    # Sprawdź, czy jednostka (usługa lub timer) istnieje w systemd
    # Wyłącz 'set -e', aby `systemctl list-unit-files` nie przerwało skryptu, jeśli jednostki nie ma
    set +e
    sudo systemctl list-unit-files --type=service,timer | grep -q -E "^${service_name}\.(service|timer)"
    local unit_exists_status=$?
    set -e # Włącz 'set -e' z powrotem

    if [ $unit_exists_status -ne 0 ]; then
         log_warn "$(printf "$MSG_SERVICE_NOT_FOUND" "$service_name")"
         # Niektóre usługi mogą pojawić się później (np. po initdb).
         # Nie zwracaj błędu, ale zaloguj ostrzeżenie.
         return 0
    fi

    # Wykonaj akcję za pomocą systemctl
    local systemctl_output
    local systemctl_status

    # Wyłącz 'set -e' na czas wywołania systemctl, aby przechwycić błędy
    set +e
    case "$action" in
        start|stop|restart)
            systemctl_output=$(sudo systemctl "$action" "$service_name" 2>&1)
            systemctl_status=$?
            ;;
        status)
            # 'status' zwraca niezerowy kod, jeśli usługa nie jest aktywna, obsłużmy to
            systemctl_output=$(sudo systemctl "$action" "$service_name" 2>&1)
            systemctl_status=$? # Zapisz status dla logów, ale nie traktuj jako błąd skryptu
            log_msg "Status check for '$service_name' (exit code $systemctl_status):\n$systemctl_output"
             # Dla akcji status, zawsze zwracaj sukces skryptu, chyba że samo polecenie systemctl zawiodło
            if [[ "$systemctl_output" == *"Unknown operation"* || "$systemctl_output" == *"Failed to get properties"* ]]; then
                 systemctl_status=1 # Traktuj jako błąd systemctl
            else
                 systemctl_status=0 # Sukces (nawet jeśli nieaktywna)
            fi
            ;;
        enable|disable)
            # Dla timerów użyj --now, aby od razu je włączyć/wyłączyć
            if [ "$is_timer" = true ]; then
                systemctl_output=$(sudo systemctl "$action" --now "$service_name" 2>&1)
                systemctl_status=$?
            else
                systemctl_output=$(sudo systemctl "$action" "$service_name" 2>&1)
                systemctl_status=$?
            fi
            ;;
        *)
            log_error "Unsupported service action: '$action' for service '$service_name'"
            set -e # Włącz 'set -e'
            return 1 # Błąd - nieobsługiwana akcja
            ;;
    esac
    set -e # Włącz 'set -e' z powrotem

    # Sprawdź wynik polecenia systemctl (poza 'status')
    if [ $systemctl_status -ne 0 ] && [ "$action" != "status" ]; then
        local error_msg_var="MSG_SERVICE_FAILED_ACTION"
        if [ "$is_timer" = true ]; then error_msg_var="MSG_SERVICE_FAILED_TIMER"; fi
        log_error "$(printf "${!error_msg_var}" "$action" "$service_name")"
        log_error "systemctl output: $systemctl_output"
        # Pokaż błąd w UI
         if command -v $UI_TOOL >/dev/null 2>&1; then
             show_message "ERROR: Failed to $action service/timer $service_name. Check logs."
         fi
        return 1 # Błąd wykonania polecenia systemctl
    elif [ "$action" != "status" ]; then
        log_msg "$(printf "$MSG_SERVICE_ACTION_SUCCESS" "$service_name" "$action")"
        # Oznacz, że wprowadzono zmiany konfiguracyjne, jeśli włączono/wyłączono usługę
        if [ "$action" == "enable" ] || [ "$action" == "disable" ]; then
            CONFIG_CHANGES_MADE=true
            NEEDS_REBOOT=true # Włączenie/wyłączenie usług może wymagać restartu
        fi
    fi

    return $systemctl_status # Zwróć kod wyjścia z systemctl (ważne dla 'status')
}

# Funkcja sprawdzająca, czy usługa jest aktywna (running)
# $1: Nazwa pakietu (do mapowania)
# Zwraca: 0 jeśli aktywna, 1 jeśli nieaktywna lub nie istnieje, 2 w przypadku błędu
is_service_active() {
    local pkg_name=$1
    local service_name

    service_name=$(map_package_to_service_name "$pkg_name")
    local map_exit_code=$?

    if [ $map_exit_code -ne 0 ] || [ -z "$service_name" ]; then
        # Jeśli nie ma usługi lub błąd mapowania, zakładamy, że nie jest aktywna
        return 1
    fi

    # Użyj systemctl is-active. Zwraca 0 jeśli aktywna, niezerowy jeśli nie.
    # Wyłącz 'set -e' na czas sprawdzania
    set +e
    sudo systemctl is-active --quiet "$service_name"
    local is_active_status=$?
    set -e # Włącz 'set -e'

    if [ $is_active_status -eq 0 ]; then
        log_msg "Service '$service_name' is active."
        return 0 # Aktywna
    else
        log_msg "Service '$service_name' is not active (or does not exist)."
        return 1 # Nieaktywna lub nie istnieje
    fi
}