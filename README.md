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

## 🚀 Użycie

**⚠️ OSTRZEŻENIE BEZPIECZEŃSTWA ⚠️**

Skrypty modyfikujące system, zwłaszcza te uruchamiane z `sudo`, powinny być uruchamiane z dużą ostrożnością. Zawsze **przejrzyj kod źródłowy**, aby upewnić się, że rozumiesz jego działanie i jest on bezpieczny dla Twojego środowiska. **Używasz tego skryptu na własną odpowiedzialność!**

---

### Metoda Bezpośredniego Uruchomienia (NIE DZIAŁA dla tego skryptu)

Próba uruchomienia tego skryptu bezpośrednio za pomocą `curl | sudo bash` **nie powiedzie się**. Skrypt ma strukturę **modularną** i wymaga dostępu do plików w katalogach `modules/` oraz `lang/`, które nie zostaną pobrane tą metodą.

```bash
# PONIŻSZE POLECENIE NIE ZADZIAŁA POPRAWNIE Z TYM SKRYPTEM!
# curl -sSL https://raw.githubusercontent.com/Nemezis1801/linux_config/main/linux_setup.sh | sudo bash
# Spowoduje to błędy ładowania modułów.
