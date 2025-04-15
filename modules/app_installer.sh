#!/bin/bash
# Moduł: Application Installer - Serwery WWW, Bazy Danych, Narzędzia, Kontenery
# Plik: modules/app_installer.sh

# --- Instalacja Serwera WWW ---
install_web_server() {
    log_msg "Web Server Installation..."
    local web_server_choice
    # Użyj zmiennych z tłumaczeń
    web_server_choice=$(show_menu "$PROMPT_WEBSERVER_CHOICE" "$PROMPT_WEBSERVER_CHOICE" \
        "APACHE" "$OPT_APACHE" \
        "NGINX" "$OPT_NGINX" \
        "NONE" "$OPT_NONE_SKIP")
     local exit_status=$?
     # Jeśli wybrano Anuluj (exit_status != 0) lub "NONE"
     if [ $exit_status -ne 0 ] || [ "$web_server_choice" == "NONE" ]; then
         log_msg "$MSG_WEBSERVER_INSTALL_SKIPPED"
         return 1 # Anulowano lub pominięto
     fi

     local web_server_pkg=""
     local web_server_name=""
     case "$web_server_choice" in
         APACHE)
             # Określ nazwę pakietu Apache w zależności od dystrybucji
             if [[ "$PKG_MANAGER" == "apt" ]]; then web_server_pkg="apache2";
             elif [[ "$PKG_MANAGER" == "dnf" || "$PKG_MANAGER" == "yum" || "$PKG_MANAGER" == "zypper" || "$PKG_MANAGER" == "pacman" ]]; then web_server_pkg="httpd";
             else log_error "Apache package name unknown for $PKG_MANAGER"; return 1; fi
             web_server_name="Apache ($web_server_pkg)"
             ;;
         NGINX)
             web_server_pkg="nginx" # Zazwyczaj taka sama nazwa
             web_server_name="Nginx"
             ;;
         *)
             log_error "Invalid web server choice: $web_server_choice"
             return 1
             ;;
     esac

    log_msg "Selected web server: $web_server_name"
    log_msg "Attempting to install package: $web_server_pkg"

    # Wywołaj instalację pakietu
    if install_packages "$web_server_pkg"; then
        log_msg "Package '$web_server_pkg' installed successfully."
        # Włącz i uruchom usługę
        log_msg "Enabling and starting $web_server_name service..."
        if manage_service "$web_server_pkg" enable && manage_service "$web_server_pkg" start; then
            log_msg "$(printf "$MSG_WEBSERVER_INSTALLED_STARTED" "$web_server_name")"
            # Przypomnienie o firewallu
            show_message "$(printf "$MSG_WEBSERVER_FIREWALL_REMINDER" "$web_server_name")"
            # Można dodać podstawową konfigurację Apache/Nginx tutaj (np. wywołanie osobnej funkcji)
            # configure_apache # (osobna funkcja)
            # configure_nginx # (osobna funkcja)
            return 0
        else
            log_error "Failed to enable or start $web_server_name service, although package installed."
            show_message "ERROR: Failed to enable/start $web_server_name service. Check logs."
            return 1 # Błąd zarządzania usługą
        fi
    else
         log_error "$(printf "$MSG_WEBSERVER_INSTALL_FAILED" "$web_server_name")"
         show_message "ERROR: $(printf "$MSG_WEBSERVER_INSTALL_FAILED" "$web_server_name")"
         return 1 # Błąd instalacji pakietu
    fi
}

# --- Instalacja Bazy Danych ---
install_database() {
     log_msg "Database Installation..."
     local db_choice
     db_choice=$(show_menu "$PROMPT_DB_CHOICE" "$PROMPT_DB_CHOICE" \
         "MARIADB" "$OPT_MARIADB" \
         "POSTGRESQL" "$OPT_POSTGRESQL" \
         "SQLITE" "$OPT_SQLITE" \
         "NONE" "$OPT_NONE_SKIP")
     local exit_status=$?
      if [ $exit_status -ne 0 ] || [ "$db_choice" == "NONE" ]; then
          log_msg "$MSG_DB_INSTALL_SKIPPED"
          return 1 # Anulowano lub pominięto
      fi

      local install_status=1 # Domyślnie błąd

      case "$db_choice" in
          MARIADB)
              install_status=$(install_mariadb)
              # Zapytaj o zabezpieczenie po udanej instalacji
              if [ $install_status -eq 0 ] && confirm_action "$PROMPT_SECURE_MARIADB"; then
                  secure_mariadb || log_warn "Securing MariaDB failed or was skipped."
              fi
              ;;
          POSTGRESQL)
              install_status=$(install_postgresql)
              ;;
          SQLITE)
              install_status=$(install_sqlite)
              ;;
          *)
              log_error "Invalid database choice: $db_choice"
              return 1
              ;;
      esac

      return $install_status # Zwróć status ostatniej operacji
 }

# Funkcja pomocnicza do instalacji MariaDB
install_mariadb() {
    log_msg "Attempting to install MariaDB..."
    local server_pkg="mariadb-server"
    local client_pkg="mariadb-client"
    # Dostosuj nazwy pakietów dla różnych dystrybucji
    if [ "$PKG_MANAGER" == "pacman" ]; then server_pkg="mariadb"; client_pkg="mariadb-clients";
    elif [ "$PKG_MANAGER" == "zypper" ]; then client_pkg="mariadb-client"; fi # Serwer ma tę samą nazwę

    log_msg "Installing MariaDB packages: $server_pkg, $client_pkg"
    if ! install_packages "$server_pkg" "$client_pkg"; then
        log_error "$MSG_MARIADB_INSTALL_FAILED"
        show_message "ERROR: $MSG_MARIADB_INSTALL_FAILED"
        return 1
    fi

    # Po instalacji na niektórych systemach (np. Arch, czasem RHEL-based)
    # może być potrzebna inicjalizacja bazy danych
    # Sprawdźmy, czy katalog danych istnieje i jest pusty lub zawiera pliki inicjalizacyjne
    local datadir="/var/lib/mysql" # Domyślna lokalizacja
    if [ ! -d "$datadir" ] || [ -z "$(ls -A "$datadir" 2>/dev/null)" ]; then
        log_msg "MariaDB data directory '$datadir' seems empty or non-existent. Attempting initialization..."
        # Wyłącz 'set -e' na czas inicjalizacji
        set +e
        if command -v mysql_install_db >/dev/null; then
            # Starsza metoda
             sudo mysql_install_db --user=mysql --basedir=/usr --datadir="$datadir"
        elif command -v mariadb-install-db >/dev/null; then
             # Nowsza metoda
             sudo mariadb-install-db --user=mysql --basedir=/usr --datadir="$datadir"
        elif command -v mariadbd-safe >/dev/null; then
             # Czasem wystarczy uruchomić, aby zainicjalizować
             log_warn "Initialization command not found, trying to start service to initialize..."
        else
             log_warn "Could not find MariaDB initialization command (mysql_install_db or mariadb-install-db)."
        fi
        # Ignorujemy błędy inicjalizacji na razie, start usługi pokaże problem
        set -e
    fi

    log_msg "Enabling and starting MariaDB service..."
    if manage_service "$server_pkg" enable && manage_service "$server_pkg" start; then
        log_msg "$MSG_MARIADB_INSTALLED"
        return 0
    else
        log_error "Failed to enable or start MariaDB service."
        show_message "ERROR: Failed to enable/start MariaDB service. Check logs."
        return 1
    fi
}

# Funkcja pomocnicza do zabezpieczania MariaDB
secure_mariadb() {
    log_msg "Securing MariaDB using mysql_secure_installation..."
    log_warn "$MSG_MARIADB_SECURE_WARN"

    # Sprawdź czy polecenie istnieje
    if ! command -v mysql_secure_installation > /dev/null 2>&1; then
         log_error "$MSG_MARIADB_SECURE_CMD_NOT_FOUND"
         show_message "ERROR: $MSG_MARIADB_SECURE_CMD_NOT_FOUND"
         return 1
    fi

    # Uruchom interaktywnie - automatyzacja jest zbyt ryzykowna i nieprzenośna
    log_msg "Running 'sudo mysql_secure_installation' interactively..."
    # Wyłącz 'set -e' na czas interaktywnego polecenia
    set +e
    sudo mysql_secure_installation
    local secure_status=$?
    set -e

    if [ $secure_status -eq 0 ]; then
        log_msg "$MSG_MARIADB_SECURE_FINISHED"
        return 0
    else
         log_error "mysql_secure_installation finished with errors (Code: $secure_status). Check output above."
         show_message "Warning: mysql_secure_installation finished with errors. Check logs."
         return 1
    fi
}

# Funkcja pomocnicza do instalacji PostgreSQL
install_postgresql() {
    log_msg "Attempting to install PostgreSQL..."
    local server_pkg="postgresql" # Domyślne dla Debiana/Ubuntu
    local client_pkg="postgresql-client" # Domyślne dla Debiana/Ubuntu
    # Dostosuj dla innych dystrybucji
    if [[ "$PKG_MANAGER" == "dnf" || "$PKG_MANAGER" == "yum" ]]; then
        # RHEL/Fedora często wymagają wersji, np. postgresql15-server
        # Spróbujmy zainstalować generyczny 'postgresql-server' i 'postgresql' (klient)
        server_pkg="postgresql-server"
        client_pkg="postgresql"
    elif [[ "$PKG_MANAGER" == "pacman" ]]; then
         server_pkg="postgresql" # Zawiera serwer i klienta
         client_pkg="" # Niepotrzebny osobno
    elif [[ "$PKG_MANAGER" == "zypper" ]]; then
          server_pkg="postgresql-server" # Sprawdź dokładną nazwę
          client_pkg="postgresql"       # Sprawdź dokładną nazwę
    fi

    local packages_to_install=("$server_pkg")
    if [ -n "$client_pkg" ]; then packages_to_install+=("$client_pkg"); fi

    log_msg "Installing PostgreSQL packages: ${packages_to_install[*]}"
    if ! install_packages "${packages_to_install[@]}"; then
        log_error "$MSG_POSTGRESQL_INSTALL_FAILED"
        show_message "ERROR: $MSG_POSTGRESQL_INSTALL_FAILED"
        return 1
    fi

    # Inicjalizacja bazy danych (wymagana na RHEL/Fedora/CentOS, Arch)
    local datadir_pattern="/var/lib/postgres*/[0-9]*/data" # Ogólny wzorzec dla nowszych wersji
    local datadir=""
    # Wyłącz 'set -e' na czas find/ls
    set +e
    datadir=$(find /var/lib/ -maxdepth 1 -type d -name 'pgsql' -o -name 'postgres*' | head -n 1) # Znajdź główny katalog
    set -e
    # Jeśli główny katalog istnieje, sprawdź wersję i katalog danych
    local needs_initdb=false
    if [ -d "$datadir" ]; then
        # Sprawdź, czy katalog danych istnieje i czy jest pusty lub zawiera PG_VERSION
        local pg_version_file=$(find "$datadir" -name PG_VERSION | head -n 1)
        if [ -z "$pg_version_file" ]; then
            needs_initdb=true
        fi
    # Jeśli /var/lib/pgsql nie istnieje, ale instalacja RPM się powiodła, initdb jest prawdopodobnie wymagane
    elif [[ "$PKG_MANAGER" == "dnf" || "$PKG_MANAGER" == "yum" || "$PKG_MANAGER" == "pacman" ]]; then
         needs_initdb=true
    fi


    if [ "$needs_initdb" = true ]; then
        log_msg "$MSG_POSTGRESQL_INITDB"
         # Wyłącz 'set -e' na czas initdb
         set +e
         local initdb_cmd=""
         # RHEL/Fedora
         if [[ "$PKG_MANAGER" == "dnf" || "$PKG_MANAGER" == "yum" ]]; then
              initdb_cmd=$(find /usr/pgsql-*/bin -name 'postgresql-*-setup' | head -n 1)
              if [ -n "$initdb_cmd" ]; then
                  sudo "$initdb_cmd" --initdb || sudo "$initdb_cmd" initdb
              fi
         # Arch
         elif [[ "$PKG_MANAGER" == "pacman" ]]; then
             # Na Archu initdb jest zazwyczaj wykonywane jako użytkownik postgres
             if [ -d "$datadir/data" ]; then # Sprawdź domyślną lokalizację danych na Archu
                sudo -u postgres initdb --locale "$LANG" -E UTF8 -D "$datadir/data"
             else
                  log_warn "Could not determine PostgreSQL data directory on Arch for initdb."
             fi
         fi

         if [ -z "$initdb_cmd" ] && [[ "$PKG_MANAGER" != "pacman" ]]; then
             # Spróbuj ogólnego initdb jeśli dostępne
             if command -v initdb > /dev/null; then
                 # Wymaga znalezienia katalogu danych, co jest trudne
                 log_warn "Found 'initdb' but cannot determine data directory reliably. Manual initialization might be needed."
             else
                  log_warn "$MSG_POSTGRESQL_INITDB_WARN"
             fi
         fi
         local initdb_status=$?
         set -e # Włącz 'set -e'

         if [ $initdb_status -ne 0 ] && [ -n "$initdb_cmd" ]; then
              log_error "PostgreSQL initdb failed (Code: $initdb_status). Service might not start."
              # Nie przerywaj, pozwól spróbować uruchomić usługę
         elif [ $initdb_status -eq 0 ]; then
               log_msg "PostgreSQL database cluster initialized successfully."
         fi
    fi

    log_msg "Enabling and starting PostgreSQL service..."
    if manage_service "$server_pkg" enable && manage_service "$server_pkg" start; then
        log_msg "$MSG_POSTGRESQL_INSTALLED"
        log_warn "$MSG_POSTGRESQL_MANUAL_CONFIG"
        show_message "$MSG_POSTGRESQL_INSTALLED\n$MSG_POSTGRESQL_MANUAL_CONFIG"
        return 0
    else
        log_error "Failed to enable or start PostgreSQL service. Check logs (initdb might have failed)."
        show_message "ERROR: Failed to enable/start PostgreSQL service. Check logs (initdb?).\n$MSG_POSTGRESQL_MANUAL_CONFIG"
        return 1
    fi
}

# Funkcja pomocnicza do instalacji SQLite
install_sqlite() {
    log_msg "Attempting to install SQLite 3..."
    local sqlite_pkg="sqlite3"
    local sqlite_lib_pkg="libsqlite3-0" # Biblioteka w Debian/Ubuntu
    # Dostosuj dla innych dystrybucji
    if [[ "$PKG_MANAGER" == "dnf" || "$PKG_MANAGER" == "yum" ]]; then
        sqlite_pkg="sqlite" # Narzędzie CLI i biblioteka
        sqlite_lib_pkg="" # Zazwyczaj w głównym pakiecie
    elif [[ "$PKG_MANAGER" == "pacman" || "$PKG_MANAGER" == "zypper" ]]; then
         sqlite_pkg="sqlite"
         sqlite_lib_pkg=""
    fi

    local packages_to_install=("$sqlite_pkg")
    if [ -n "$sqlite_lib_pkg" ]; then packages_to_install+=("$sqlite_lib_pkg"); fi

    log_msg "Installing SQLite packages: ${packages_to_install[*]}"
    if install_packages "${packages_to_install[@]}"; then
        log_msg "$MSG_SQLITE_INSTALLED"
        return 0
    else
        log_error "$MSG_SQLITE_INSTALL_FAILED"
        show_message "ERROR: $MSG_SQLITE_INSTALL_FAILED"
        return 1
    fi
}


# --- Instalacja Narzędzi (Common & Dev) ---
# $1: Typ narzędzi ("common" lub "dev")
install_tools() {
    local tool_type=$1
    if [ "$tool_type" != "common" ] && [ "$tool_type" != "dev" ]; then
        log_error "Invalid tool type specified for install_tools: '$tool_type'. Must be 'common' or 'dev'."
        return 1
    fi

    local checklist_title=""
    local checklist_prompt=""
    local tools_list=() # Format: "TAG" "Opis" "ON/OFF" "pakiet(y)"

    log_msg "Preparing list for '$tool_type' tools..."

    if [ "$tool_type" == "common" ]; then
        checklist_title="$PROMPT_COMMONTOOLS_CHOICE"
        checklist_prompt="$PROMPT_COMMONTOOLS_DESC"
        # Podstawowe narzędzia użytkowe
        tools_list=(
            "git" "Git (Version Control)" "ON" "git"
            "curl" "Curl (Data transfer)" "ON" "curl"
            "wget" "Wget (File downloader)" "ON" "wget"
            "htop" "Htop (Process viewer)" "ON" "htop"
            "tmux" "Tmux (Terminal multiplexer)" "OFF" "tmux"
            "vim" "Vim (Text editor)" "OFF" "vim"
            "nano" "Nano (Text editor)" "ON" "nano"
            "unzip" "Unzip (Archive extractor)" "ON" "unzip"
            "zip" "Zip (Archive creator)" "ON" "zip"
            "rsync" "Rsync (File copier)" "ON" "rsync"
            "jq" "jq (JSON processor)" "OFF" "jq"
            "net-tools" "Net-tools (netstat, ifconfig - legacy)" "OFF" "net-tools"
            "dnsutils" "DNS Utilities (dig, nslookup)" "OFF" "dnsutils bind-utils" # Nazwy różne: dnsutils (apt), bind-utils (dnf/yum)
            "bashcomp" "Bash Completion" "ON" "bash-completion"
        )
        # Dostosuj 'dnsutils'
        if [[ "$PKG_MANAGER" == "dnf" || "$PKG_MANAGER" == "yum" || "$PKG_MANAGER" == "pacman" || "$PKG_MANAGER" == "zypper" ]]; then
             tools_list[43]="bind-utils" # Zastąp pakiet dla dnsutils
        fi

    elif [ "$tool_type" == "dev" ]; then
         checklist_title="$PROMPT_DEVTOOLS_CHOICE"
         checklist_prompt="$PROMPT_DEVTOOLS_DESC"
         # Narzędzia deweloperskie - nazwy pakietów różnią się BARDZO
         local build_essentials="build-essential" # Debian/Ubuntu
         local python_dev="python3-dev"
         local python_pip="python3-pip"
         local cmake_pkg="cmake"
         local nodejs_pkg="nodejs npm" # Podstawowe, mogą być stare wersje

         if [[ "$PKG_MANAGER" == "dnf" || "$PKG_MANAGER" == "yum" ]]; then
             # Fedora/RHEL - często używa się grup pakietów
             build_essentials="@development-tools" # Grupa
             python_dev="python3-devel"
             python_pip="python3-pip"
             # Node.js często wymaga dodatkowego repo lub modułu stream
             # np. sudo dnf module enable nodejs:18
         elif [[ "$PKG_MANAGER" == "pacman" ]]; then
             build_essentials="base-devel" # Grupa
             python_dev="python" # Zazwyczaj zawiera nagłówki
             python_pip="python-pip"
         elif [[ "$PKG_MANAGER" == "zypper" ]]; then
             # SUSE używa wzorców
             build_essentials="patterns-devel-base-devel_basis patterns-devel-C-C++-devel_C_C++" # Wzorce
             python_dev="python3-devel" # Sprawdź nazwę (może być z wersją)
             python_pip="python3-pip"
         fi

         tools_list=(
             "build" "Build Tools (gcc, make...)" "ON" "$build_essentials"
             "python" "Python 3 Interpreter" "ON" "python3" # Zakładając, że python3 jest dostępne
             "python-dev" "Python 3 Headers & Dev libs" "ON" "$python_dev"
             "python-pip" "Python Package Installer (pip)" "ON" "$python_pip"
             "git" "Git (Version Control)" "ON" "git" # Ponownie, bo kluczowe
             "cmake" "CMake (Build system generator)" "OFF" "$cmake_pkg"
             "nodejs" "Node.js + npm (Basic)" "OFF" "$nodejs_pkg" # Może wymagać dodatkowych kroków
             # "java" "Java Development Kit (JDK)" "OFF" "default-jdk openjdk-17-jdk" # Bardzo różne nazwy
         )
         # Dostosuj pakiet python3, jeśli system używa 'python' zamiast 'python3'
          if ! command -v python3 &>/dev/null && command -v python &>/dev/null; then
               tools_list[5]="python" # Zmień tag
               tools_list[7]="python" # Zmień pakiet
          fi
    fi

    # Przygotuj opcje dla checklist
    local checklist_options=()
    local packages_map=() # Mapa TAG -> pakiet(y)
    for (( i=0; i<${#tools_list[@]}; i+=4 )); do
        local tag="${tools_list[i]}"
        local desc="${tools_list[i+1]}"
        local state="${tools_list[i+2]}"
        local pkgs="${tools_list[i+3]}"
        checklist_options+=("$tag" "$desc" "$state")
        # Użyj asocjacyjnej tablicy Bash 4+ lub prostego mapowania dla kompatybilności
        # Zamiast mapy, po prostu wyszukamy w pętli później
    done

    # Pokaż checklist użytkownikowi
    local selected_tags_quoted # Wynik z whiptail zawiera cudzysłowy
    selected_tags_quoted=$(show_checklist "$checklist_title" "$checklist_prompt" "${checklist_options[@]}")
    local exit_status=$?
     if [ $exit_status -ne 0 ]; then
         log_msg "$(printf "$MSG_TOOLS_INSTALL_SKIPPED" "$tool_type")"
         return 1 # Anulowano
     fi

     # Usuń cudzysłowy i przetwórz wybrane tagi
     local selected_tags=${selected_tags_quoted//\"/}
     local final_packages_to_install=()
     log_msg "Selected tags for '$tool_type' tools: $selected_tags"

     # Przejdź przez listę narzędzi i znajdź pakiety dla wybranych tagów
     for (( i=0; i<${#tools_list[@]}; i+=4 )); do
         local current_tag="${tools_list[i]}"
         local current_pkgs="${tools_list[i+3]}"
         # Sprawdź, czy bieżący tag jest na liście wybranych tagów
         if [[ " $selected_tags " == *" $current_tag "* ]]; then
              log_msg "Processing tag '$current_tag' with packages '$current_pkgs'"
              # Rozdziel pakiety oddzielone spacją (lub grupy pakietów dla RPM)
              read -ra pkgs_for_tag <<< "$current_pkgs"
              for pkg in "${pkgs_for_tag[@]}"; do
                   # Dodaj do listy, jeśli nie jest pusty
                   if [ -n "$pkg" ]; then
                     final_packages_to_install+=("$pkg")
                   fi
              done
         fi
     done

     if [ ${#final_packages_to_install[@]} -gt 0 ]; then
         # Usuń duplikaty (ważne, jeśli tagi wskazują na ten sam pakiet)
         local unique_packages=($(echo "${final_packages_to_install[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
         log_msg "$(printf "$MSG_TOOLS_SELECTED_PACKAGES" "$tool_type" "${unique_packages[*]}")"
         # Wywołaj instalację
         install_packages "${unique_packages[@]}"
         # Zwróć status instalacji
         return $?
     else
         log_msg "$(printf "$MSG_TOOLS_NO_NEW_SELECTED" "$tool_type")"
         return 0 # Nic nie wybrano, ale to nie błąd
     fi
}


# --- Instalacja Silnika Kontenerów ---
install_container_engine() {
     log_msg "Container Engine Installation..."
     local engine_choice
     engine_choice=$(show_menu "$PROMPT_CONTAINER_CHOICE" "$PROMPT_CONTAINER_CHOICE" \
         "DOCKER" "$OPT_DOCKER" \
         "PODMAN" "$OPT_PODMAN" \
         "NONE" "$OPT_NONE_SKIP")
     local exit_status=$?
      if [ $exit_status -ne 0 ] || [ "$engine_choice" == "NONE" ]; then
          log_msg "$MSG_CONTAINER_INSTALL_SKIPPED"
          return 1 # Anulowano lub pominięto
      fi

      local install_status=1 # Domyślnie błąd

      case "$engine_choice" in
          DOCKER)
              install_status=$(install_docker_ce)
              ;;
          PODMAN)
              install_status=$(install_podman)
              ;;
          *)
              log_error "Invalid container engine choice: $engine_choice"
              return 1
              ;;
      esac

       return $install_status
}

# Funkcja pomocnicza do instalacji Docker CE
install_docker_ce() {
    log_msg "$MSG_INSTALLING_DOCKER..."
    # Instalacja Dockera CE jest złożona i zaleca się użycie oficjalnych metod.
    # Najprostsza, ale ryzykowna metoda to użycie skryptu get.docker.com.

    if confirm_action "$PROMPT_DOCKER_USE_SCRIPT"; then
        log_msg "$MSG_DOCKER_DOWNLOADING_SCRIPT..."
        local get_docker_sh="get-docker.sh"
        # Wyłącz 'set -e' na czas pobierania i wykonania skryptu zewnętrznego
        set +e
        if ! curl -fsSL https://get.docker.com -o "$get_docker_sh"; then
            log_error "$MSG_DOCKER_DOWNLOAD_FAILED"
            rm -f "$get_docker_sh"
            set -e
            return 1
        fi

        log_msg "$MSG_DOCKER_INSTALLING_SCRIPT (sudo sh $get_docker_sh)..."
        # Uruchom skrypt instalacyjny
        sudo sh "$get_docker_sh"
        local install_script_status=$?
        rm -f "$get_docker_sh" # Usuń skrypt po użyciu

        if [ $install_script_status -eq 0 ]; then
            log_msg "$MSG_DOCKER_INSTALL_SCRIPT_SUCCESS"
            # Upewnij się, że usługa jest włączona i działa
            log_msg "Enabling and starting Docker service..."
            if manage_service docker enable && manage_service docker start; then
                # Zapytaj o dodanie użytkownika do grupy docker
                local current_user=${SUDO_USER:-$(whoami)}
                if [ -n "$current_user" ] && id "$current_user" &>/dev/null; then
                    if ask_yesno "$(printf "$PROMPT_ADD_USER_DOCKER" "$current_user")"; then
                         log_msg "Adding user '$current_user' to docker group..."
                         sudo usermod -aG docker "$current_user"
                         log_msg "$(printf "$MSG_DOCKER_USER_ADDED" "$current_user")"
                         show_message "$(printf "$MSG_DOCKER_USER_ADDED_REMINDER" "$current_user")"
                    fi
                fi
                 set -e # Włącz set -e
                 return 0 # Sukces
            else
                 log_error "Docker package installed, but failed to enable/start service."
                 set -e
                 return 1 # Błąd usługi
            fi
        else
            log_error "$MSG_DOCKER_INSTALL_SCRIPT_FAILED (Code: $install_script_status)"
            show_message "ERROR: $MSG_DOCKER_INSTALL_SCRIPT_FAILED"
            set -e
            return 1 # Błąd skryptu instalacyjnego
        fi
    else
        log_msg "$MSG_DOCKER_INSTALL_MANUAL"
        show_message "$MSG_DOCKER_INSTALL_MANUAL"
        return 1 # Poinformowano o ręcznej instalacji
    fi
}

# Funkcja pomocnicza do instalacji Podman
install_podman() {
    log_msg "$MSG_INSTALLING_PODMAN..."
    local podman_pkg="podman"
    # Dodaj pakiety rekomendowane/zależne
    local extra_pkgs=()
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        # podman-docker zapewnia alias docker -> podman
        extra_pkgs+=("podman-docker")
    fi
    # Można dodać slirp4netns, fuse-overlayfs jeśli nie są automatycznie zależnościami

    local packages_to_install=("$podman_pkg")
    packages_to_install+=("${extra_pkgs[@]}")

    # Usuń duplikaty
    local unique_packages=($(echo "${packages_to_install[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

    log_msg "Installing Podman packages: ${unique_packages[*]}"
    if install_packages "${unique_packages[@]}"; then
         log_msg "$(printf "$MSG_CONTAINER_INSTALLED" "Podman")"
         # Podman zazwyczaj działa rootless, ale socket API może być potrzebne
         log_msg "Enabling Podman socket API (podman.socket) if available..."
         # Wyłącz 'set -e' na czas próby włączenia gniazda
         set +e
         manage_service podman.socket enable # Włącz tylko, nie startuj od razu
         local enable_status=$?
         set -e
         if [ $enable_status -ne 0 ]; then
             log_warn "Could not enable podman.socket. Podman API might not be available."
         fi
         log_msg "$MSG_PODMAN_INSTALLED_INFO"
         return 0
    else
         log_error "$MSG_PODMAN_INSTALL_FAILED"
         show_message "ERROR: $MSG_PODMAN_INSTALL_FAILED"
         return 1
    fi
}


# --- Główna funkcja modułu Instalatora Aplikacji ---
run_app_installer_menu() {
     while true; do
        local choice
        # Użyj zmiennych z tłumaczeń
        choice=$(show_menu "$SUBMENU_APP_INSTALLER_TITLE" "$SUBMENU_APP_INSTALLER_DESC" \
            "WEBSERVER" "$OPT_INSTALL_WEBSERVER" \
            "DATABASE" "$OPT_INSTALL_DB" \
            "CONTAINER" "$OPT_INSTALL_CONTAINER" \
            "TOOLS_COMMON" "$OPT_INSTALL_TOOLS_COMMON" \
            "TOOLS_DEV" "$OPT_INSTALL_TOOLS_DEV" \
            "BACK" "$OPT_APPS_BACK")
        local exit_status=$?
        [ $exit_status -ne 0 ] && choice="BACK"

        case "$choice" in
            WEBSERVER) install_web_server ;;
            DATABASE) install_database ;;
            CONTAINER) install_container_engine ;;
            TOOLS_COMMON) install_tools "common" ;;
            TOOLS_DEV) install_tools "dev" ;;
            BACK) break ;;
            *) log_warn "Invalid choice in app installer menu: $choice" ;;
        esac
         # if [ "$choice" != "BACK" ]; then wait_for_enter; fi
    done
    return 0
}