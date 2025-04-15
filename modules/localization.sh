#!/bin/bash
# Moduł: Localization - Obsługa języków
# Plik: modules/localization.sh

# Wykrywa język systemu i ładuje odpowiedni plik językowy.
# Jeśli plik dla wykrytego języka nie istnieje, używa angielskiego jako domyślnego.
detect_and_load_language() {
    local detected_lang_code="en" # Domyślnie angielski

    # Spróbuj wykryć język systemu na podstawie zmiennych środowiskowych
    # Preferuj LANGUAGE, potem LANG
    if [ -n "$LANGUAGE" ]; then
        # LANGUAGE może zawierać listę, np. pl:en_US:en, bierzemy pierwszy
        detected_lang_code=${LANGUAGE%%[:_]*}
    elif [ -n "$LANG" ]; then
        # LANG zazwyczaj ma format pl_PL.UTF-8, bierzemy pierwsze dwa znaki
        detected_lang_code=${LANG:0:2}
    fi

    # Sprawdź, czy mamy plik dla wykrytego dwuliterowego kodu języka
    # Użyj $SCRIPT_DIR ustawionego w głównym skrypcie
    local lang_file="$SCRIPT_DIR/lang/${detected_lang_code}.sh"

    if [ -f "$lang_file" ]; then
        log_msg "Detected system language code: '$detected_lang_code'. Loading language file: $lang_file"
        # Załaduj plik językowy
        # Użycie '.' (source) wykonuje polecenia z pliku w bieżącej powłoce
        # Wyłącz chwilowo 'set -e' na wypadek problemów w pliku językowym
        set +e
        # shellcheck source=../lang/en.sh
        # shellcheck source=../lang/pl.sh
        . "$lang_file"
        local source_exit_code=$?
        set -e # Włącz 'set -e' z powrotem

        if [ $source_exit_code -ne 0 ]; then
            log_error "Error sourcing language file '$lang_file'. Falling back to English."
            # Załaduj angielski jako fallback
             set +e
            # shellcheck source=../lang/en.sh
            . "$SCRIPT_DIR/lang/en.sh"
            source_exit_code=$?
            set -e
            if [ $source_exit_code -ne 0 ]; then
                 log_error "FATAL: Error sourcing English fallback language file '$SCRIPT_DIR/lang/en.sh'."
                 # Nie używaj UI, bo może nie działać
                 echo "FATAL: Error loading language files. Cannot continue." >&2
                 exit 1
             fi
            CURRENT_LANG="en"
        else
             # Sprawdź, czy LANG_CODE został ustawiony w pliku językowym
             if [ -z "$LANG_CODE" ]; then
                  log_warn "LANG_CODE variable not set in '$lang_file'. Assuming '$detected_lang_code'."
                  CURRENT_LANG="$detected_lang_code"
             else
                  CURRENT_LANG="$LANG_CODE" # Użyj kodu z załadowanego pliku
             fi
        fi
    else
        log_warn "Language file for detected code '$detected_lang_code' ('$lang_file') not found. Using default language: English."
        # Załaduj domyślny angielski
        set +e
        # shellcheck source=../lang/en.sh
        . "$SCRIPT_DIR/lang/en.sh"
        local source_exit_code=$?
        set -e
         if [ $source_exit_code -ne 0 ]; then
             log_error "FATAL: Error sourcing English fallback language file '$SCRIPT_DIR/lang/en.sh'."
             echo "FATAL: Error loading language files. Cannot continue." >&2
             exit 1
         fi
        CURRENT_LANG="en"
    fi

    # Eksportuj CURRENT_LANG, aby był dostępny w innych podpowłokach, jeśli zajdzie potrzeba
    export CURRENT_LANG
    log_msg "Current language set to: '$CURRENT_LANG'"

    # Sprawdzenie, czy kluczowe komunikaty zostały załadowane (prosty test)
    if [ -z "$MSG_WELCOME" ]; then
        log_error "FATAL: Key language strings (e.g., MSG_WELCOME) were not loaded correctly. Check language files."
        echo "FATAL: Key language strings were not loaded correctly. Check language files." >&2
        exit 1
    fi
}

# Można dodać funkcję do pobierania tłumaczenia, ale na razie używamy bezpośrednio zmiennych
# get_string() {
#   local key=$1
#   eval echo "\$$key"
# }