# Linux Config (Linux Setup Manager)

[![Language](https://img.shields.io/badge/language-Bash-blue.svg)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE) <!-- Upewnij się, że dodałeś plik LICENSE -->

Modularny skrypt Bash przeznaczony do automatyzacji konfiguracji oraz instalacji oprogramowania na różnych popularnych dystrybucjach Linuksa, w tym Debian/Ubuntu, Fedora/RHEL, Arch Linux oraz openSUSE. Skrypt wykorzystuje interfejs tekstowy oparty na `whiptail` lub `dialog` dla interakcji z użytkownikiem.

## 🌟 Główne Funkcje

*   **Wykrywanie Dystrybucji:** Automatycznie identyfikuje system operacyjny i dostosowuje polecenia (np. menedżera pakietów).
*   **Wsparcie dla Menedżerów Pakietów:** Obsługuje `apt`, `dnf`/`yum`, `pacman`, `zypper`.
*   **Modularność:** Kod jest podzielony na logiczne moduły (`modules/`) ułatwiające zarządzanie i rozbudowę.
*   **Wielojęzyczność:** Automatycznie wykrywa język systemu i ładuje tłumaczenia z katalogu `lang/` (aktualnie: Polski, Angielski).
*   **Gotowe Scenariusze:** Oferuje predefiniowane scenariusze dla typowych konfiguracji:
    *   Standardowy Serwer WWW (Web Server)
    *   Minimalny Bezpieczny Serwer (Minimal Secure)
    *   Stanowisko Deweloperskie (Developer Workstation)
*   **Konfiguracja Systemu:** Ustawianie nazwy hosta, zarządzanie użytkownikami i grupami, zarządzanie zadaniami cron.
*   **Konfiguracja Sieci:** Konfiguracja zapory sieciowej (`ufw` lub `firewalld`), podstawowa konfiguracja DNS.
*   **Wzmocnienia Bezpieczeństwa:** Zaawansowana konfiguracja i hardening SSH, instalacja i konfiguracja `Fail2Ban`, instalacja `Certbot` (Let's Encrypt), konfiguracja automatycznych aktualizacji bezpieczeństwa.
*   **Instalacja Oprogramowania:**
    *   Serwery WWW: Apache, Nginx
    *   Bazy Danych: MariaDB, PostgreSQL, SQLite
    *   Narzędzia Użytkowe i Deweloperskie: Git, curl, wget, htop, build tools, Python, Node.js (podstawowe) itp.
    *   Silniki Kontenerów: Docker CE (poprzez oficjalny skrypt), Podman.
*   **Zarządzanie Usługami:** Zarządzanie cyklem życia usług systemowych (start, stop, enable, disable) za pomocą `systemd`.
*   **Zarządzanie Dyskami (Podstawy):** Instalacja narzędzi, wyświetlanie urządzeń, **ostrożne** dodawanie wpisów do `/etc/fstab`.
*   **Zarządzanie Kopiami Zapasowymi (Podstawy):** Instalacja `rsync`, konfiguracja przykładowego zadania backupu w cron.
*   **Logowanie i Backupy:** Zapisuje szczegółowy log operacji (`*.txt`) i tworzy kopie zapasowe modyfikowanych plików konfiguracyjnych (`*_backups_*`) w katalogu skryptu.

## 📋 Wymagania Wstępne

*   System operacyjny Linux (zalecane: Debian, Ubuntu, Fedora, RHEL/CentOS/Rocky/Alma, Arch, openSUSE).
*   Powłoka **Bash w wersji 4.0 lub nowszej**. (`bash --version`)
*   Dostęp do konta z uprawnieniami `sudo`.
*   Zainstalowany `git` (do pobrania repozytorium).
*   Zainstalowany `curl` (używany w niektórych funkcjach, np. instalacji Dockera).
*   Zainstalowane `whiptail` lub `dialog` (skrypt spróbuje je zainstalować, jeśli ich brakuje).
*   Połączenie z internetem (do pobierania pakietów i potencjalnie skryptów).

## 🚀 Użycie: Klonowanie Repozytorium (Zalecana Metoda)

**⚠️ OSTRZEŻENIE BEZPIECZEŃSTWA ⚠️**

Uruchamianie jakichkolwiek skryptów modyfikujących system, zwłaszcza tych wymagających uprawnień `sudo`, powinno odbywać się z rozwagą. Zawsze **przejrzyj kod źródłowy**, aby upewnić się, że rozumiesz jego działanie i jest on bezpieczny dla Twojego środowiska. **Używasz tego skryptu na własną odpowiedzialność!**

---

Ze względu na modularną strukturę skryptu (korzystanie z plików w katalogach `modules/` i `lang/`), jedynym poprawnym sposobem jego uruchomienia jest sklonowanie repozytorium i uruchomienie go lokalnie:

1.  **Sklonuj repozytorium:**
    Otwórz terminal i wykonaj polecenie:
    ```bash
    git clone https://github.com/Nemezis1801/linux_config.git
    ```

2.  **Przejdź do katalogu skryptu:**
    ```bash
    cd linux_config
    ```

3.  **(Opcjonalnie, ale BARDZO ZALECANE) Przejrzyj kod:**
    Zapoznaj się z zawartością pliku `linux_setup.sh` oraz plików w katalogach `modules/` i `lang/`, aby zrozumieć, co skrypt będzie robił w Twoim systemie.
    ```bash
    # Przykład przeglądania
    less linux_setup.sh
    ls modules/
    less modules/core_utils.sh
    # itd.
    ```

4.  **Nadaj uprawnienia do wykonania:**
    System plików mógł nie zachować uprawnień wykonania podczas klonowania.
    ```bash
    chmod +x linux_setup.sh
    ```

5.  **Uruchom skrypt z uprawnieniami `sudo`:**
    ```bash
    sudo ./linux_setup.sh
    ```

6.  **Postępuj zgodnie z instrukcjami** wyświetlanymi w interfejsie tekstowym (`whiptail`/`dialog`). Skrypt poprowadzi Cię przez dostępne opcje i scenariusze.

## 📁 Struktura Repozytorium

```.
├── linux_setup.sh         # Główny skrypt uruchomieniowy
├── modules/               # Katalog z modułami funkcjonalnymi
│   ├── core_utils.sh      # Podstawowe funkcje, UI, logowanie, detekcja
│   ├── localization.sh    # Obsługa języków
│   ├── package_manager.sh # Zarządzanie pakietami
│   ├── service_manager.sh # Zarządzanie usługami
│   ├── system_config.sh   # Konfiguracja systemu (hostname, users, cron)
│   ├── network_config.sh  # Konfiguracja sieci (firewall, dns)
│   ├── security.sh        # Funkcje bezpieczeństwa (SSH, Fail2Ban, Certbot...)
│   ├── app_installer.sh   # Instalacja aplikacji (WWW, DB, Tools, Containers)
│   ├── disk_management.sh # Zarządzanie dyskami (podstawowe)
│   ├── backup_restore.sh  # Zarządzanie kopiami zapasowymi (podstawowe)
│   └── scenarios.sh      # Gotowe scenariusze użycia
├── lang/                  # Katalog z plikami tłumaczeń
│   ├── en.sh              # Tłumaczenia Angielskie
│   └── pl.sh              # Tłumaczenia Polskie
└── README.md              # Ten plik

```
## ⚙️ Działanie Skryptu

*   **Logowanie:** Wszelkie działania, ostrzeżenia i błędy są zapisywane do pliku tekstowego `linux_config_log_RRRRMMDD_HHMMSS.txt` tworzonego w tym samym katalogu co skrypt. Pozwala to na późniejszą analizę przeprowadzonych operacji.
*   **Kopie Zapasowe:** Przed modyfikacją istotnych plików konfiguracyjnych (np. `/etc/ssh/sshd_config`, `/etc/fstab`, `/etc/fail2ban/jail.local` itp.), skrypt automatycznie tworzy ich kopię zapasową. Kopie te są umieszczane w dedykowanym podkatalogu `linux_config_backups_RRRRMMDD_HHMMSS` w głównym katalogu skryptu, co umożliwia łatwe przywrócenie poprzedniej konfiguracji w razie potrzeby.
*   **Język:** Skrypt inteligentnie próbuje wykryć język ustawiony w systemie operacyjnym użytkownika, analizując zmienne środowiskowe `$LANG` lub `$LANGUAGE`. Jeśli w katalogu `lang/` znajduje się plik tłumaczenia odpowiadający wykrytemu kodowi języka (np. `pl.sh` dla języka polskiego), zostanie on załadowany, a komunikaty i opcje menu będą wyświetlane w tym języku. W przypadku braku odpowiedniego tłumaczenia lub problemów z jego załadowaniem, skrypt domyślnie używa języka angielskiego (`en.sh`).

## ❗ Ważne Uwagi

*   **Testowanie:** Skrypt został stworzony jako rozbudowane narzędzie, ale jego testowanie na wszystkich wspieranych dystrybucjach i w różnych konfiguracjach jest ograniczone. Zawsze testuj go najpierw w bezpiecznym środowisku (np. maszyna wirtualna).
*   **Różnice Między Dystrybucjami:** Pomimo starań o uniwersalność, mogą wystąpić problemy wynikające z różnic w nazewnictwie pakietów, ścieżkach plików lub działaniu poleceń między dystrybucjami. Zgłaszaj takie problemy jako Issue.
*   **Brak Automatycznego Rollbacku:** Skrypt **nie posiada** funkcji automatycznego przywracania systemu do stanu sprzed uruchomienia w razie błędu. Polegaj na kopiach zapasowych tworzonych przez skrypt oraz własnych backupach systemu.
*   **Ryzyko:** Modyfikacje systemu, konfiguracji bezpieczeństwa, a zwłaszcza operacje na dyskach (`fstab`) są **ryzykowne**. Upewnij się, że rozumiesz, co robisz.

## 🤝 Kontrybucje

Jeśli znajdziesz błąd, masz pomysł na ulepszenie, chcesz dodać nowe tłumaczenie lub funkcjonalność, zapraszam do współpracy!

1.  Zgłoś problem lub propozycję jako **Issue** na GitHubie.
2.  Stwórz **Fork** repozytorium.
3.  Wprowadź zmiany w swojej gałęzi (np. `feature/nowa-funkcja` lub `fix/blad-x`).
4.  Utwórz **Pull Request** do gałęzi `main` tego repozytorium, dokładnie opisując swoje zmiany.

## 📜 Licencja

Ten projekt jest udostępniany na warunkach licencji MIT. Zobacz plik [LICENSE](LICENSE) po szczegóły.
