#!/bin/bash
#
# Linux Multi-Distribution Setup & Configuration Manager
# Modular Version with Language Support
# Główny plik: linux_setup.sh
#

# --- Podstawowe Ustawienia Skryptu ---
# Nazwa skryptu dla logów itp.
readonly SCRIPT_NAME=$(basename "$0")
# Katalog, w którym znajduje się skrypt (ważne dla ładowania modułów)
# readlink -f zapewnia pełną ścieżkę, nawet jeśli skrypt jest linkiem symbolicznym
# shellcheck disable=SC2155 # Dynamiczne przypisanie jest tu celowe
readonly SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# Lokalizacje plików logów i backupów (w katalogu skryptu)
readonly TIMESTAMP=$(date +%Y%m%d_%H%M%S)
readonly LOG_FILE="$SCRIPT_DIR/${SCRIPT_NAME%.sh}_log_${TIMESTAMP}.txt"
readonly BACKUP_DIR="$SCRIPT_DIR/${SCRIPT_NAME%.sh}_backups_${TIMESTAMP}"

# Ustawienia interfejsu użytkownika (można dostosować)
readonly MIN_WHIPTAIL_WIDTH=78
readonly MIN_WHIPTAIL_HEIGHT=22

# Eksportuj niezmienne zmienne, aby były dostępne w modułach
export SCRIPT_DIR LOG_FILE BACKUP_DIR MIN_WHIPTAIL_WIDTH MIN_WHIPTAIL_HEIGHT

# --- Sprawdzenie Podstawowych Zależności (Bash >= 4) ---
if (( BASH_VERSINFO[0] < 4 )); then
    echo "ERROR: This script requires Bash version 4 or higher." >&2
    exit 1
fi

# --- Ładowanie Modułów ---
# Kolejność ładowania modułów jest ważna!
# Najpierw podstawowe funkcje, potem reszta.
# Używamy source (lub '.'), aby funkcje i zmienne były dostępne w głównym skrypcie.

MODULES_DIR="$SCRIPT_DIR/modules"
MODULES=(
    "core_utils.sh"         # Podstawowe funkcje, UI, logowanie, detekcja
    "localization.sh"       # Obsługa języków (musi być wcześnie dla komunikatów)
    "package_manager.sh"    # Zarządzanie pakietami (apt, dnf, pacman, zypper)
    "service_manager.sh"    # Zarządzanie usługami (systemd)
    "system_config.sh"      # Konfiguracja systemu (hostname, users, cron)
    "network_config.sh"     # Konfiguracja sieci (firewall, dns)
    "security.sh"           # Funkcje bezpieczeństwa (SSH, Fail2Ban, Certbot, etc.)
    "app_installer.sh"      # Instalacja aplikacji (WWW, DB, Dev Tools, Containers)
    "disk_management.sh"    # Podstawowe zarządzanie dyskami (ostrożnie!)
    "backup_restore.sh"     # Podstawy backupu (rsync, cron)
    "scenarios.sh"          # Gotowe scenariusze użycia
)

# Sprawdź i załaduj każdy moduł
for module in "${MODULES[@]}"; do
    module_path="$MODULES_DIR/$module"
    if [ -f "$module_path" ]; then
        # Użyj '.' zamiast source dla lepszej kompatybilności
        # Wyłącz 'set -e' na czas ładowania modułu, na wypadek błędów w samym module
        set +e
        # shellcheck source=modules/core_utils.sh
        # ... (pozostałe moduły - shellcheck nie może ich dynamicznie sprawdzić)
        . "$module_path"
        module_load_status=$?
        set -e # Włącz 'set -e' z powrotem

        if [ $module_load_status -ne 0 ]; then
             # Nie można użyć log_error, bo core_utils może się nie załadować
            echo "FATAL: Error loading module '$module' from '$module_path'. Exit code: $module_load_status" >&2
            exit 1
        fi
        # Można dodać logowanie po załadowaniu core_utils
        # [[ -type log_msg ]] && log_msg "Module '$module' loaded successfully."
    else
        echo "FATAL: Required module '$module' not found at '$module_path'." >&2
        exit 1
    fi
done

# --- Główna Funkcja Skryptu ---
main() {
    # 1. Inicjalizacja (obsługa błędów, przekierowanie wyjścia)
    # Uwaga: przekierowanie wyjścia musi być po ustawieniu LOG_FILE
    # i przed jakimkolwiek wyjściem, które ma trafić do logu.
    redirect_output
    # Obsługa błędów musi być ustawiona po załadowaniu core_utils (dla handle_error)
    # i localization (dla komunikatów błędów). Zrobimy to po detekcji języka.

    log_msg "--- Starting Linux Setup Manager (PID: $$) ---"
    log_msg "Script Directory: $SCRIPT_DIR"
    log_msg "Log File: $LOG_FILE"

    # 2. Sprawdzenie uprawnień roota (po załadowaniu core_utils)
    check_root

    # 3. Detekcja dystrybucji (po załadowaniu core_utils)
    detect_distro

    # 4. Sprawdzenie zależności UI (whiptail/dialog) (po detekcji distro)
    check_ui_dependencies

    # 5. Wykryj i załaduj język (po core_utils, przed resztą)
    detect_and_load_language # To załaduje zmienne MSG_*

    # 6. Teraz można bezpiecznie ustawić obsługę błędów używającą MSG_*
    setup_error_handling_and_exit

    # 7. Utwórz katalog backupu
    log_msg "Creating backup directory: $BACKUP_DIR"
    if ! mkdir -p "$BACKUP_DIR"; then
        # Użyj log_error po ustawieniu obsługi błędów
        log_error "Failed to create backup directory '$BACKUP_DIR'. Check permissions."
        # Wyjście zostanie obsłużone przez trap EXIT
        exit 1
    fi
    log_msg "$(printf "$MSG_BACKUP_LOCATION" "$BACKUP_DIR")"

    # 8. Wyświetl powitanie w UI (jeśli dostępne)
    if command -v $UI_TOOL >/dev/null; then
        show_message "$MSG_WELCOME (Language: $CURRENT_LANG)"
    else
         log_msg "$MSG_WELCOME (Language: $CURRENT_LANG) - UI tool not available, using logs only."
    fi

    # 9. Główne Menu Pętli
    while true; do
        # Użyj zmiennych językowych w menu
        local main_choice
        # Przypisz wynik wywołania show_menu do main_choice
        main_choice=$(show_menu "$MENU_MAIN_TITLE" "$MENU_MAIN_DESC" \
            "SCENARIO_WEB" "$MENU_SCENARIO_WEB" \
            "SCENARIO_MINIMAL" "$MENU_SCENARIO_MINIMAL" \
            "SCENARIO_DEV" "$MENU_SCENARIO_DEV" \
            "$MENU_SEP" "$MENU_SEP_LINE" \
            "APPS" "$MENU_INSTALL_APPS" \
            "SYSTEM" "$MENU_CONFIG_SYSTEM" \
            "NETWORK" "$MENU_CONFIG_NETWORK" \
            "SECURITY" "$MENU_CONFIG_SECURITY" \
            "DISK" "$MENU_MANAGE_DISKS" \
            "BACKUP" "$MENU_MANAGE_BACKUPS" \
            "$MENU_SEP" "$MENU_SEP_LINE" \
            "UPDATE_PKGS" "$MENU_UPDATE_PKGS" \
            "HELP" "$MENU_HELP" \
            "EXIT" "$MENU_EXIT")
        # Pobierz kod wyjścia z show_menu (ważne dla Anuluj/Esc)
        local menu_exit_status=$?

        # Jeśli naciśnięto Anuluj lub Esc (kod != 0)
        if [ $menu_exit_status -ne 0 ]; then
            log_msg "Main menu cancelled by user (Esc/Cancel pressed)."
            main_choice="EXIT" # Traktuj Anuluj jak Wyjście
        fi

        log_msg "Main menu choice selected: '$main_choice'"

        # Obsługa wyboru z menu
        case "$main_choice" in
            SCENARIO_WEB) run_scenario_web_server ;;
            SCENARIO_MINIMAL) run_scenario_minimal_secure ;;
            SCENARIO_DEV) run_scenario_developer_workstation ;;
            APPS) run_app_installer_menu ;;
            SYSTEM) run_system_config_menu ;;
            NETWORK) run_network_config_menu ;;
            SECURITY) run_security_menu ;;
            DISK) run_disk_management_menu ;;
            BACKUP) run_backup_menu ;;
            UPDATE_PKGS)
                log_msg "$MSG_UPDATING_ALL_PACKAGES..."
                if update_package_lists; then
                    # Aktualizacja wszystkich zainstalowanych pakietów jest ryzykowna i może zależeć od menedżera
                    # Prostsze podejście: po prostu uruchom polecenie upgrade
                    log_msg "Running system upgrade command..."
                    local upgrade_cmd=""
                    case "$PKG_MANAGER" in
                        apt) upgrade_cmd="sudo apt-get upgrade -y" ;;
                        dnf|yum) upgrade_cmd="sudo $PKG_MANAGER upgrade -y" ;;
                        pacman) upgrade_cmd="sudo pacman -Syu --noconfirm" ;; # -Syu aktualizuje system
                        zypper) upgrade_cmd="sudo zypper update -y --no-confirm" ;; # 'dup' to dist-upgrade
                    esac
                    if [ -n "$upgrade_cmd" ]; then
                        if $upgrade_cmd; then
                             log_msg "$MSG_UPDATE_ALL_PACKAGES_COMPLETE"
                             show_message "$MSG_UPDATE_ALL_PACKAGES_COMPLETE Check logs."
                             NEEDS_REBOOT=true # Aktualizacja często wymaga restartu
                        else
                             log_error "$MSG_UPDATE_ALL_PACKAGES_FAILED Check logs for details."
                             show_message "ERROR: $MSG_UPDATE_ALL_PACKAGES_FAILED Check logs."
                        fi
                    else
                         log_error "Upgrade command unknown for $PKG_MANAGER."
                    fi
                else
                     log_error "Failed to update package lists before upgrade."
                     show_message "ERROR: Failed to update package lists before upgrade."
                fi
                ;;
            HELP)
                # Przygotuj tekst pomocy używając zmiennych językowych
                local help_text
                help_text=$(printf "$MSG_HELP_BODY")
                help_text+=$(printf "$MSG_HELP_USAGE" "$LOG_FILE" "$BACKUP_DIR" "$CURRENT_LANG")
                # Pokaż pomoc w UI
                show_message "$MSG_HELP_TITLE\n\n$help_text"
                ;;
            EXIT)
                log_msg "$MSG_EXITING_USER..."
                # Pętla zostanie przerwana, a trap EXIT zajmie się resztą
                break
                ;;
            *)
                # Ten przypadek nie powinien wystąpić, jeśli show_menu działa poprawnie
                log_error "$(printf "$MSG_INVALID_CHOICE" "$main_choice")"
                show_message "$(printf "$MSG_INVALID_CHOICE" "$main_choice")"
                ;;
        esac

        # Mała pauza po akcji przed powrotem do menu, jeśli UI jest dostępne
        # i użytkownik nie wybrał EXIT
        if [ "$main_choice" != "EXIT" ] && command -v $UI_TOOL >/dev/null; then
             # Zapytaj, czy wrócić do menu, jeśli nie, traktuj jak EXIT
             if ! ask_yesno "Return to the main menu?"; then
                 log_msg "User chose not to return to main menu. Exiting."
                 break # Wyjdź z pętli while
             fi
        elif [ "$main_choice" != "EXIT" ]; then
            # Jeśli nie ma UI, po prostu kontynuuj pętlę
             : # No-op
        fi

    done # Koniec pętli while true

    log_msg "--- Linux Setup Manager Finished ---"
}

# --- Uruchomienie Głównej Funkcji Skryptu ---
# Umieszczamy wywołanie main w konstrukcji if, aby uniknąć wykonania,
# jeśli skrypt jest tylko 'source'owany (chociaż w tym przypadku nie powinien być).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
    # Kod wyjścia zostanie obsłużony przez trap EXIT
fi