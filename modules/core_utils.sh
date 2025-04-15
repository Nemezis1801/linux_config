#!/bin/bash
# Moduł: Core Utilities - Podstawowe funkcje, UI, logowanie, detekcja
# Plik: modules/core_utils.sh

# --- Konfiguracja Podstawowa ---
# Te zmienne są ustawiane przez główny skrypt linux_setup.sh
# i eksportowane, aby były dostępne tutaj.
# LOG_FILE=""
# BACKUP_DIR=""
# SCRIPT_DIR=""
# MIN_WHIPTAIL_WIDTH=75 # Można nadpisać w głównym skrypcie
# MIN_WHIPTAIL_HEIGHT=20 # Można nadpisać w głównym skrypcie

# --- Zmienne Globalne (inicjowane tutaj lub w głównym skrypcie) ---
DISTRO_ID=""
DISTRO_NAME=""
DISTRO_VERSION_ID=""
PKG_MANAGER=""
UPDATE_CMD=""
INSTALL_CMD=""
REMOVE_CMD=""
CHECK_PKG_CMD=""
SERVICE_MANAGER="systemd" # Załóż systemd, może zostać dostosowane
ARCHITECTURE=""
UI_TOOL="whiptail" # Domyślne, zostanie zweryfikowane
CONFIG_CHANGES_MADE=false # Śledź, czy wprowadzono zmiany konfiguracyjne
NEEDS_REBOOT=false # Śledź, czy zalecany jest restart
CURRENT_LANG="en" # Domyślny język, zostanie ustawiony przez localization.sh

# --- Podstawowe Ustawienia i Obsługa Błędów ---

# Funkcja do ustawiania obsługi błędów i wyjścia
# Musi być wywołana *po* załadowaniu tłumaczeń, aby używać MSG_*
setup_error_handling_and_exit() {
    # Wyjście przy pierwszym błędzie (set -e)
    set -e
    # Przechwytywanie błędów (trap ERR)
    # Używamy $? dla kodu wyjścia, $LINENO dla numeru linii, $BASH_COMMAND dla polecenia
    trap 'handle_error $? $LINENO "$BASH_COMMAND"' ERR
    # Przechwytywanie normalnego wyjścia i sygnałów (trap EXIT)
    # SIGINT (Ctrl+C), SIGTERM (kill)
    trap 'cleanup $?' EXIT SIGINT SIGTERM
}

# Przekierowanie wyjścia do pliku logu i na ekran
# Musi być wywołane *po* ustawieniu LOG_FILE w głównym skrypcie
redirect_output() {
    # Sprawdź czy LOG_FILE jest ustawiony i zapisywalny
    if [ -z "$LOG_FILE" ]; then
        echo "FATAL: LOG_FILE variable is not set." >&2
        exit 1
    fi
    # Próba zapisu do katalogu logu, aby upewnić się, że mamy uprawnienia
    if ! touch "$LOG_FILE" 2>/dev/null; then
        echo "FATAL: Cannot write to log file: $LOG_FILE. Check permissions." >&2
        exit 1
    fi
    # Przekieruj stdout i stderr
    exec > >(tee -i "$LOG_FILE")
    exec 2>&1
    # Uwaga: To przekierowanie jest globalne dla reszty skryptu i załadowanych modułów
}

# --- Funkcje Pomocnicze ---

# Logowanie z timestampem
_log() {
    local level=$1
    shift
    local message=$*
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ${level} : ${message}"
}
log_msg() { _log "INFO " "$@"; }
log_warn() { _log "WARN " "$@"; }
log_error() { _log "ERROR" "$@"; } # Zostawiamy na stderr dla widoczności

# Obsługa błędów (wywoływana przez trap ERR)
handle_error() {
    local exit_code=$1
    local line_no=$2
    local command=$3
    local msg
    # Użyj printf, aby bezpiecznie obsłużyć potencjalne % w $command
    msg=$(printf "$MSG_ERROR_OCCURRED" "$line_no" "$command" "$exit_code")

    echo "--------------------------------------------------" >&2
    # Użyj log_error, które może (jeśli jest poprawnie skonfigurowane) iść do stderr
    log_error "$msg" >&2
    log_error "$(printf "$MSG_CHECK_LOG" "$LOG_FILE")" >&2
    echo "--------------------------------------------------" >&2

    # Nie wywołuj 'exit' tutaj, pozwól trap EXIT obsłużyć sprzątanie
    # Zwróć kod błędu, aby trap EXIT wiedział, że był błąd
    return $exit_code
}

# Sprzątanie przy wyjściu (wywoływane przez trap EXIT, SIGINT, SIGTERM)
cleanup() {
    local exit_code=$1
    # Jeśli nie podano kodu wyjścia (np. normalne zakończenie bez błędu), ustaw na 0
    exit_code=${exit_code:-0}

    # Przywróć terminal do normalnego stanu, jeśli whiptail/dialog go zmienił
    if command -v stty >/dev/null 2>&1; then
        stty sane
    fi

    echo "--------------------------------------------------"
    # Użyj zmiennych językowych, jeśli są dostępne
    local finish_msg="$MSG_SCRIPT_FINISHED_SUCCESS"
    local log_loc_msg="$(printf "$MSG_LOG_LOCATION" "$LOG_FILE")"
    local backup_loc_msg="$(printf "$MSG_BACKUP_LOCATION" "$BACKUP_DIR")"
    local reboot_msg="$MSG_REQUIRES_REBOOT"
    local reboot_prompt="$PROMPT_REBOOT_NOW"

    if [ "$exit_code" -ne 0 ]; then
        finish_msg="$MSG_SCRIPT_FINISHED_ERRORS"
    fi

    log_msg "$finish_msg (Exit Code: $exit_code)"
    log_msg "$log_loc_msg"
    log_msg "$backup_loc_msg"

    # Pytaj o restart tylko jeśli skrypt zakończył się pomyślnie (exit_code 0)
    # i flagi wskazują na potrzebę restartu
    if [ "$exit_code" -eq 0 ] && [ "$NEEDS_REBOOT" = true ]; then
        log_msg "$reboot_msg"
        # Sprawdź, czy UI_TOOL jest dostępny, zanim zapytasz
        if command -v $UI_TOOL >/dev/null 2>&1; then
            # Używamy 'if ask_yesno', bo 'ask_yesno' zwraca kod wyjścia
            if ask_yesno "$reboot_prompt"; then
                 log_msg "Rebooting system NOW..."
                 # Daj chwilę na zapis logów przed restartem
                 sleep 3
                 # Bezpieczniejszy sposób wywołania reboot
                 if command -v systemctl >/dev/null 2>&1; then
                    sudo systemctl reboot
                 elif command -v shutdown >/dev/null 2>&1; then
                     sudo shutdown -r now
                 else
                     log_error "Cannot find reboot command (systemctl reboot or shutdown -r now)."
                 fi
                 # Poczekaj chwilę, aby system zdążył zainicjować restart
                 sleep 10
            else
                log_msg "Reboot cancelled by user."
            fi
        else
             log_warn "UI tool not available to ask for reboot. Please reboot manually if needed."
        fi
    elif [ "$exit_code" -ne 0 ] && [ "$NEEDS_REBOOT" = true ]; then
         log_warn "Script finished with errors, but a reboot might be needed due to earlier changes."
         log_warn "Please check the logs and reboot manually if necessary."
    fi

    echo "--------------------------------------------------"
    # Zakończ skrypt z otrzymanym kodem wyjścia
    # exit $exit_code # To jest niepotrzebne, bo trap EXIT sam w sobie kończy skrypt
}

# Sprawdzenie roota
check_root() {
    log_msg "Checking for root privileges..."
    # Użyj ${EUID:-$(id -u)} dla kompatybilności
    if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
        # Użyj log_error, które idzie do stderr
        log_error "$MSG_RUN_AS_ROOT"
        # Spróbuj użyć whiptail jeśli jest dostępne (już po check_ui_dependencies), inaczej echo
        if command -v $UI_TOOL >/dev/null 2>&1; then
            show_message "$MSG_RUN_AS_ROOT" # Pokaż w UI
        fi
        # Zakończ natychmiast, bo bez roota nic nie zrobimy
        exit 1
    fi
    log_msg "$MSG_ROOT_OK"
}

# Sprawdzenie whiptail/dialog
check_ui_dependencies() {
    log_msg "Checking for UI dependencies (whiptail/dialog)..."
    if command -v whiptail > /dev/null 2>&1; then
        UI_TOOL="whiptail"
        log_msg "$(printf "$MSG_USING_UI_TOOL" "$UI_TOOL")"
        return 0
    elif command -v dialog > /dev/null 2>&1; then
        UI_TOOL="dialog"
        log_msg "$(printf "$MSG_USING_UI_TOOL" "$UI_TOOL")"
        return 0
    fi

    # Jeśli żadne nie jest dostępne, spróbuj zainstalować whiptail
    log_warn "$MSG_INSTALLING_WHIPTAIL"
    # Potrzebujemy PKG_MANAGER i INSTALL_CMD ustawionych przez detect_distro
    if [ -n "$PKG_MANAGER" ] && [ -n "$INSTALL_CMD" ]; then
         log_msg "Attempting to install whiptail using $PKG_MANAGER..."
         # Wyłącz chwilowo 'set -e', aby móc obsłużyć błąd instalacji
         set +e
         sudo $INSTALL_CMD whiptail
         local install_status=$?
         set -e # Włącz 'set -e' z powrotem

         if [ $install_status -eq 0 ] && command -v whiptail > /dev/null 2>&1; then
             UI_TOOL="whiptail"
             log_msg "$(printf "$MSG_USING_UI_TOOL" "$UI_TOOL") installed successfully."
             return 0
         else
             log_error "$MSG_INSTALL_WHIPTAIL_FAILED (Exit code: $install_status)"
             # Nie używaj show_message tutaj, bo UI_TOOL może nie działać
             echo "ERROR: $MSG_INSTALL_WHIPTAIL_FAILED" >&2
             exit 1
          fi
    else
         log_error "Cannot determine package manager to install whiptail. Please install whiptail or dialog manually."
         echo "ERROR: Cannot determine package manager to install whiptail. Please install whiptail or dialog manually." >&2
         exit 1
    fi
}

# --- Funkcje UI Helper (korzystające z $UI_TOOL) ---
# Standardowo przekierowują 3>&1 1>&2 2>&3, aby oddzielić dialog od wyniku
# Zwracają kod wyjścia whiptail/dialog (0=OK/Yes, 1=Cancel/No, inne=Error/Esc)

# Wyświetla pytanie Tak/Nie
# $1: Tekst pytania
# $2: Opcjonalnie --defaultno lub --defaultyes (domyślnie --defaultno)
# Zwraca: 0 dla Tak, 1 dla Nie, 255 dla Esc
ask_yesno() {
    local question=$1
    local default_choice=${2:-"--defaultno"}
    $UI_TOOL --title "Confirmation" "$default_choice" --yesno "$question" "$MIN_WHIPTAIL_HEIGHT" "$MIN_WHIPTAIL_WIDTH" 3>&1 1>&2 2>&3
    return $?
}

# Wyświetla pole do wprowadzania tekstu
# $1: Tekst pytania
# $2: Wartość domyślna
# Zwraca: Wpisany tekst na stdout, kod wyjścia 0 dla OK, 1 dla Anuluj
ask_input() {
    local question=$1
    local default_value=$2
    # Wynik idzie na stderr, przekierowujemy go na stdout skryptu
    $UI_TOOL --title "Input Required" --inputbox "$question" "$MIN_WHIPTAIL_HEIGHT" "$MIN_WHIPTAIL_WIDTH" "$default_value" 3>&1 1>&2 2>&3
    return $?
}

# Wyświetla pole do wprowadzania hasła
# $1: Tekst pytania
# Zwraca: Wpisane hasło na stdout, kod wyjścia 0 dla OK, 1 dla Anuluj
ask_password() {
    local question=$1
    $UI_TOOL --title "Password Input" --passwordbox "$question" "$MIN_WHIPTAIL_HEIGHT" "$MIN_WHIPTAIL_WIDTH" 3>&1 1>&2 2>&3
    return $?
}

# Wyświetla prostą wiadomość
# $1: Tekst wiadomości
show_message() {
    local message=$1
    $UI_TOOL --title "Information" --msgbox "$message" "$MIN_WHIPTAIL_HEIGHT" "$MIN_WHIPTAIL_WIDTH" 3>&1 1>&2 2>&3
}

# Wyświetla menu wyboru
# $1: Tytuł
# $2: Opis
# $@: Lista opcji w formacie "TAG1" "Opis1" "TAG2" "Opis2" ...
# Zwraca: Wybrany TAG na stdout, kod wyjścia 0 dla OK, 1 dla Anuluj
show_menu() {
    local title=$1
    local description=$2
    shift 2
    local options=("$@")
    # Oblicz wysokość listy menu (liczba opcji)
    local list_height=$((${#options[@]}/2))
    # Upewnij się, że list_height nie jest większe niż dostępne miejsce
    local max_list_height=$((MIN_WHIPTAIL_HEIGHT - 8)) # Zostaw miejsce na tytuł, opis, przyciski
    [ "$list_height" -gt "$max_list_height" ] && list_height=$max_list_height
    [ "$list_height" -lt 1 ] && list_height=1 # Minimum 1

    $UI_TOOL --title "$title" --menu "$description" "$MIN_WHIPTAIL_HEIGHT" "$MIN_WHIPTAIL_WIDTH" "$list_height" "${options[@]}" 3>&1 1>&2 2>&3
    return $?
}

# Wyświetla listę wyboru (checklist)
# $1: Tytuł
# $2: Opis
# $@: Lista opcji w formacie "TAG1" "Opis1" "ON/OFF" "TAG2" "Opis2" "ON/OFF" ...
# Zwraca: Wybrane TAGi (oddzielone spacją, w cudzysłowach) na stdout, kod 0 dla OK, 1 dla Anuluj
show_checklist() {
    local title=$1
    local description=$2
    shift 2
    local options=("$@")
    local list_height=$((${#options[@]}/3))
    local max_list_height=$((MIN_WHIPTAIL_HEIGHT - 8))
    [ "$list_height" -gt "$max_list_height" ] && list_height=$max_list_height
    [ "$list_height" -lt 1 ] && list_height=1

    # Wynik (wybrane tagi) idzie na stderr, przekierowujemy na stdout
    $UI_TOOL --title "$title" --checklist "$description" "$MIN_WHIPTAIL_HEIGHT" "$MIN_WHIPTAIL_WIDTH" "$list_height" "${options[@]}" 3>&1 1>&2 2>&3
    return $?
}

# --- Detekcja Systemu ---
detect_distro() {
    log_msg "$MSG_DETECTING_DISTRO"
    ARCHITECTURE=$(uname -m)
    log_msg "$(printf "$MSG_ARCH" "$ARCHITECTURE")"

    DISTRO_ID="unknown"
    DISTRO_NAME="Unknown"
    DISTRO_VERSION_ID="unknown"

    if [ -f /etc/os-release ]; then
        # Użyj . zamiast source, aby uniknąć problemów w niektórych powłokach/trybach
        # i zignoruj błędy, jeśli plik jest uszkodzony
        set +e
        . /etc/os-release
        set -e
        DISTRO_ID=${ID:-$DISTRO_ID}
        DISTRO_NAME=${PRETTY_NAME:-$ID}
        DISTRO_VERSION_ID=${VERSION_ID:-$DISTRO_VERSION_ID}
    elif command -v lsb_release > /dev/null 2>&1; then
        DISTRO_ID=$(lsb_release -si | tr '[:upper:]' '[:lower:]' | sed 's/ //g') # np. linuxmint
        DISTRO_NAME=$(lsb_release -sd)
        DISTRO_VERSION_ID=$(lsb_release -sr)
    else
        log_warn "Cannot detect Linux distribution reliably. /etc/os-release not found and lsb_release command not available."
        # Można spróbować sprawdzić istnienie plików charakterystycznych dla dystrybucji
        if [ -f /etc/debian_version ]; then
            DISTRO_ID="debian" # Może to być też Ubuntu, Mint itp.
            DISTRO_NAME="Debian-based (detection limited)"
        elif [ -f /etc/redhat-release ]; then
             DISTRO_ID="rhel" # Może to być Fedora, CentOS itp.
             DISTRO_NAME="RedHat-based (detection limited)"
        fi
    fi

    log_msg "$(printf "$MSG_DETECTED_DISTRO" "$DISTRO_NAME" "$DISTRO_ID" "$DISTRO_VERSION_ID")"

    # Zmapuj ID dystrybucji do menedżera pakietów
    case "$DISTRO_ID" in
        ubuntu|debian|raspbian|linuxmint|mint|pop|elementary|zorin)
            PKG_MANAGER="apt"
            UPDATE_CMD="sudo apt-get update"
            # Zmieniono -qq na mniej ciche, aby widzieć postęp, dodano --allow-releaseinfo-change
            INSTALL_CMD="sudo apt-get install -y --allow-releaseinfo-change"
            REMOVE_CMD="sudo apt-get remove -y"
            CHECK_PKG_CMD="dpkg-query -W -f='\${Status}'" # Zwraca np. "install ok installed"
            ;;
        fedora|centos|rhel|rocky|almalinux)
            # Sprawdź czy dnf jest dostępne, jeśli nie, użyj yum
            if command -v dnf > /dev/null 2>&1; then
                 PKG_MANAGER="dnf"
            elif command -v yum > /dev/null 2>&1; then
                 PKG_MANAGER="yum"
            else
                 log_error "Cannot find dnf or yum package manager on $DISTRO_NAME."
                 exit 1
            fi
            UPDATE_CMD="sudo $PKG_MANAGER check-update" # DNF/YUM zazwyczaj nie wymaga 'update' przed install
            INSTALL_CMD="sudo $PKG_MANAGER install -y"
            REMOVE_CMD="sudo $PKG_MANAGER remove -y"
            CHECK_PKG_CMD="rpm -q" # Zwraca 0 jeśli zainstalowany, błąd jeśli nie
            ;;
        arch|manjaro|endeavouros|garuda)
            PKG_MANAGER="pacman"
            UPDATE_CMD="sudo pacman -Sy" # Synchronizuj tylko bazę danych
            INSTALL_CMD="sudo pacman -S --noconfirm"
            REMOVE_CMD="sudo pacman -Rns --noconfirm"
            CHECK_PKG_CMD="pacman -Q" # Zwraca 0 jeśli zainstalowany, błąd jeśli nie
            ;;
        opensuse*|sles)
             PKG_MANAGER="zypper"
             UPDATE_CMD="sudo zypper refresh"
             INSTALL_CMD="sudo zypper install -y --no-confirm" # -y i --no-confirm mogą być redundantne, ale pewniejsze
             REMOVE_CMD="sudo zypper remove -y --no-confirm"
             CHECK_PKG_CMD="rpm -q" # Zypper używa RPM, więc rpm -q jest niezawodne
             ;;
        *)
            log_error "Unsupported distribution ID: '$DISTRO_ID'. This script currently supports Debian/Ubuntu family, Fedora/RHEL family, Arch family, and openSUSE family."
            # Spróbuj użyć UI jeśli dostępne
            if command -v $UI_TOOL >/dev/null 2>&1; then
                show_message "ERROR: Unsupported distribution ID: '$DISTRO_ID'."
            fi
            exit 1
            ;;
    esac
    log_msg "$(printf "$MSG_PKG_MANAGER" "$PKG_MANAGER")"
}

# --- Backup ---
# Tworzy kopię zapasową pliku lub katalogu
# $1: Ścieżka do pliku/katalogu
create_backup() {
    local item_to_backup=$1
    if [ -z "$item_to_backup" ]; then
        log_warn "create_backup called with empty argument."
        return 1
    fi

    # Usuń wiodący '/' jeśli istnieje, aby poprawnie połączyć ścieżki
    local relative_item_path="${item_to_backup#/}"
    local backup_path="$BACKUP_DIR/$relative_item_path"
    local backup_dir
    backup_dir=$(dirname "$backup_path")

    if [ -e "$item_to_backup" ]; then # Sprawdź czy istnieje (plik lub katalog)
        log_msg "Backing up '$item_to_backup' to '$backup_path'"
        # Utwórz strukturę katalogów w miejscu docelowym
        if ! mkdir -p "$backup_dir"; then
            log_error "Failed to create backup directory '$backup_dir'. Check permissions."
            return 1
        fi
        # Kopiuj z zachowaniem atrybutów (-a)
        if ! sudo cp -a "$item_to_backup" "$backup_path"; then
            log_error "Failed to copy '$item_to_backup' to '$backup_path'. Check permissions and disk space."
            return 1
        fi
        log_msg "Backup of '$item_to_backup' created successfully."
        return 0
    else
        log_warn "Item '$item_to_backup' does not exist, skipping backup."
        return 0 # Nie traktuj tego jako błędu krytycznego
    fi
}

# --- Potwierdzenie przed akcją ---
# Prosi użytkownika o potwierdzenie przed wykonaniem potencjalnie destrukcyjnej akcji
# $1: Wiadomość z pytaniem
confirm_action() {
    local message=${1:-"$MSG_CONFIRM_ACTION"} # Użyj generycznej wiadomości, jeśli nic nie podano
    if ask_yesno "$message"; then
        return 0 # Potwierdzono (kod wyjścia 0)
    else
        log_msg "$MSG_ACTION_CANCELLED"
        return 1 # Anulowano (kod wyjścia 1)
    fi
}

# --- Oczekiwanie na Enter ---
# Wyświetla komunikat i czeka na naciśnięcie Enter przez użytkownika
# $1: Opcjonalna wiadomość do wyświetlenia przed monitem
wait_for_enter() {
    local message=$1
    if [ -n "$message" ]; then
        echo "$message" # Wyświetl na standardowym wyjściu (widoczne w logu i na terminalu)
    fi
    # Użyj read z opcją -p, aby wyświetlić monit
    # Przekieruj stdin/stdout, aby działało poprawnie z whiptail/dialog
    read -p "$MSG_PRESS_ENTER" </dev/tty
}