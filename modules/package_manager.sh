#!/bin/bash
# Moduł: Package Manager - Zarządzanie pakietami
# Plik: modules/package_manager.sh

# Sprawdza, czy pakiet jest zainstalowany.
# Używa różnych metod w zależności od menedżera pakietów.
# $1: Nazwa pakietu do sprawdzenia
# Zwraca: 0 jeśli zainstalowany, 1 jeśli nie, 2 w przypadku błędu.
is_package_installed() {
    local pkg_name=$1
    if [ -z "$pkg_name" ]; then
        log_warn "is_package_installed: No package name provided."
        return 2 # Błąd - brak argumentu
    fi

    log_msg "$(printf "$MSG_PKG_CHECKING" "$pkg_name")"
    local installed=false
    local query_output
    local query_status

    # Wyłącz 'set -e' na czas sprawdzania, bo niektóre polecenia zwracają błąd, gdy pakietu nie ma
    set +e
    case "$PKG_MANAGER" in
        apt)
            # dpkg-query zwraca błąd, jeśli pakietu nie ma LUB nie jest zainstalowany
            query_output=$($CHECK_PKG_CMD "$pkg_name" 2>/dev/null)
            query_status=$?
            # Sprawdzamy status zwrócony przez dpkg-query
            if [ $query_status -eq 0 ] && [[ "$query_output" == *"install ok installed"* ]]; then
                installed=true
            fi
            ;;
        dnf|yum)
             # rpm -q zwraca 0 jeśli pakiet jest zainstalowany, 1 jeśli nie
             $CHECK_PKG_CMD "$pkg_name" >/dev/null 2>&1
             query_status=$?
             if [ $query_status -eq 0 ]; then
                 installed=true
             fi
            ;;
        pacman)
            # pacman -Q zwraca 0 jeśli pakiet jest zainstalowany, 1 jeśli nie
            $CHECK_PKG_CMD "$pkg_name" >/dev/null 2>&1
             query_status=$?
             if [ $query_status -eq 0 ]; then
                 installed=true
             fi
            ;;
        zypper)
            # rpm -q jest bardziej niezawodne niż 'zypper se --installed-only' dla pojedynczego pakietu
             $CHECK_PKG_CMD "$pkg_name" >/dev/null 2>&1
             query_status=$?
             if [ $query_status -eq 0 ]; then
                 installed=true
             fi
            ;;
        *)
            log_error "is_package_installed: Unsupported package manager '$PKG_MANAGER'"
            set -e # Włącz 'set -e' z powrotem
            return 2 # Błąd - nieobsługiwany menedżer
            ;;
    esac
    set -e # Włącz 'set -e' z powrotem

    if [ "$installed" = true ]; then
        log_msg "$(printf "$MSG_PKG_INSTALLED" "$pkg_name")"
        return 0 # Sukces (zainstalowany)
    else
        log_msg "$(printf "$MSG_PKG_NOT_INSTALLED" "$pkg_name")"
        return 1 # Porażka (niezainstalowany)
    fi
}

# Aktualizuje listy pakietów
update_package_lists() {
    log_msg "$MSG_PKG_UPDATE_LISTS"
    # Użyj sudo i obsłuż potencjalne błędy
    if ! sudo $UPDATE_CMD; then
        log_error "Failed to update package lists. Check network connection and repository configuration."
        # Pokaż błąd w UI, jeśli dostępne
        if command -v $UI_TOOL >/dev/null 2>&1; then
            show_message "ERROR: Failed to update package lists. Check network and repository configuration."
        fi
        return 1 # Zwróć błąd
    fi
    log_msg "Package lists updated successfully."
    return 0
}

# Instaluje jeden lub więcej pakietów
# Argumenty: lista nazw pakietów do zainstalowania/zaktualizowania
# Zwraca: 0 jeśli wszystkie pakiety zostały pomyślnie zainstalowane/zaktualizowane lub pominięte,
#         1 jeśli wystąpił błąd podczas instalacji.
install_packages() {
    local packages_to_process=("$@")
    local packages_to_install=() # Lista do faktycznej instalacji/aktualizacji
    local pkg
    local status

    if [ ${#packages_to_process[@]} -eq 0 ]; then
        log_msg "install_packages: No packages specified."
        return 0 # Nic do zrobienia
    fi

    # Najpierw zaktualizuj listy pakietów - kluczowe przed instalacją
    update_package_lists || return 1 # Przerwij, jeśli aktualizacja list zawiedzie

    # Sprawdź każdy pakiet i zapytaj o aktualizację, jeśli już zainstalowany
    for pkg in "${packages_to_process[@]}"; do
        is_package_installed "$pkg"
        status=$?
        if [ $status -eq 0 ]; then # Pakiet jest zainstalowany
             # Zapytaj użytkownika czy zaktualizować
            if ask_yesno "$(printf "$PROMPT_PKG_UPGRADE" "$pkg")"; then
                log_msg "Package '$pkg' marked for update."
                packages_to_install+=("$pkg")
            else
                log_msg "$(printf "$MSG_PACKAGES_SKIPPED" "$pkg")"
            fi
        elif [ $status -eq 1 ]; then # Pakiet nie jest zainstalowany
            log_msg "Package '$pkg' marked for installation."
            packages_to_install+=("$pkg")
        else # Błąd podczas sprawdzania (status=2)
            log_error "Could not determine installation status for '$pkg'. Skipping."
            # Można rozważyć zwrócenie błędu tutaj, ale kontynuacja może być lepsza
        fi
    done

    if [ ${#packages_to_install[@]} -eq 0 ]; then
        log_msg "$MSG_NO_PACKAGES_SELECTED"
        return 0
    fi

    log_msg "$(printf "$MSG_PKG_INSTALLING" "${packages_to_install[*]}")"

    # Wykonaj instalację
    if sudo $INSTALL_CMD "${packages_to_install[@]}"; then
        log_msg "$(printf "$MSG_PKG_INSTALL_SUCCESS" "${packages_to_install[*]}")"
        # Oznacz, że wprowadzono zmiany w systemie
        CONFIG_CHANGES_MADE=true
        return 0
    else
        log_error "$(printf "$MSG_PKG_INSTALL_FAIL" "${packages_to_install[*]}")"
        # Pokaż błąd w UI
        if command -v $UI_TOOL >/dev/null 2>&1; then
            show_message "ERROR: $(printf "$MSG_PKG_INSTALL_FAIL" "${packages_to_install[*]}")\n$(printf "$MSG_CHECK_LOG" "$LOG_FILE")"
        fi
        return 1 # Zwróć błąd
    fi
}

# Usuwa jeden lub więcej pakietów
# Argumenty: lista nazw pakietów do usunięcia
# Zwraca: 0 jeśli pakiety zostały pomyślnie usunięte lub pominięte, 1 w przypadku błędu.
remove_packages() {
     local packages_to_process=("$@")
     local packages_to_remove=()
     local pkg
     local status

     if [ ${#packages_to_process[@]} -eq 0 ]; then
         log_msg "remove_packages: No packages specified."
         return 0
     fi

     # Sprawdź, które pakiety faktycznie istnieją do usunięcia
     for pkg in "${packages_to_process[@]}"; do
         is_package_installed "$pkg"
         status=$?
          if [ $status -eq 0 ]; then # Pakiet jest zainstalowany
             packages_to_remove+=("$pkg")
         elif [ $status -eq 1 ]; then # Pakiet nie jest zainstalowany
             log_msg "Package '$pkg' is not installed. Skipping removal."
         else # Błąd podczas sprawdzania
             log_error "Could not determine installation status for '$pkg'. Skipping removal check."
         fi
     done

     if [ ${#packages_to_remove[@]} -eq 0 ]; then
         log_msg "No installed packages from the list found to remove."
         return 0
     fi

     log_msg "Packages marked for removal: ${packages_to_remove[*]}"

     # Poproś o potwierdzenie przed usunięciem
     if ! confirm_action "$(printf "Are you sure you want to REMOVE these packages: %s ?" "${packages_to_remove[*]}")"; then
         log_msg "Package removal cancelled by user."
         return 1 # Anulowane przez użytkownika
     fi

     log_msg "$(printf "$MSG_PKG_REMOVING" "${packages_to_remove[*]}")"

     if sudo $REMOVE_CMD "${packages_to_remove[@]}"; then
        log_msg "$(printf "$MSG_PKG_REMOVE_SUCCESS" "${packages_to_remove[*]}")"
        CONFIG_CHANGES_MADE=true
        return 0
     else
        log_error "$(printf "$MSG_PKG_REMOVE_FAIL" "${packages_to_remove[*]}")"
        if command -v $UI_TOOL >/dev/null 2>&1; then
            show_message "ERROR: $(printf "$MSG_PKG_REMOVE_FAIL" "${packages_to_remove[*]}")\n$(printf "$MSG_CHECK_LOG" "$LOG_FILE")"
        fi
        return 1 # Błąd podczas usuwania
     fi
}

# Funkcja do wyszukiwania pakietów (może być przydatna)
# $1: Wzorzec wyszukiwania
search_packages() {
    local search_term=$1
    if [ -z "$search_term" ]; then
        log_warn "search_packages: No search term provided."
        return 1
    fi
    log_msg "Searching for packages matching '$search_term'..."
    local search_cmd=""
    case "$PKG_MANAGER" in
        apt) search_cmd="apt-cache search" ;;
        dnf|yum) search_cmd="$PKG_MANAGER search" ;;
        pacman) search_cmd="pacman -Ss" ;;
        zypper) search_cmd="zypper search" ;;
        *)
            log_error "Package search not supported for '$PKG_MANAGER'."
            return 1
            ;;
    esac

    # Wykonaj wyszukiwanie i pokaż wyniki (może być dużo)
    # Można użyć 'less' lub zapisać do pliku
    local search_output
    set +e
    search_output=$(sudo $search_cmd "$search_term")
    local search_status=$?
    set -e

    if [ $search_status -eq 0 ]; then
        log_msg "Search results for '$search_term':\n$search_output"
        # Pokaż w UI jeśli dostępne
        if command -v $UI_TOOL >/dev/null 2>&1; then
            # Ogranicz długość, aby zmieściło się w msgbox
            show_message "Search results for '$search_term':\n\n$(echo "$search_output" | head -n 20)\n\n(Check log for full results)"
        else
             echo "Search results for '$search_term':"
             echo "$search_output" | head -n 20
             echo "(Check log file for full results)"
        fi
    else
        log_warn "Package search for '$search_term' failed or returned no results (status: $search_status)."
    fi
    return $search_status
}