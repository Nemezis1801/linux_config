# Linux Setup Manager

Modularny skrypt Bash do automatyzacji konfiguracji i instalacji oprogramowania na różnych dystrybucjach Linuksa (Debian/Ubuntu, Fedora/RHEL, Arch, openSUSE). Skrypt wykorzystuje interfejs `whiptail` (lub `dialog`) do interakcji z użytkownikiem.

![Language](https://img.shields.io/badge/language-Bash-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg) <!-- Zmień na swoją licencję -->

## 🌟 Główne Funkcje

*   **Automatyczne Wykrywanie Dystrybucji:** Identyfikuje system (Ubuntu, Fedora, Arch itp.) i dostosowuje działanie.
*   **Wsparcie dla Menedżerów Pakietów:** Obsługuje `apt`, `dnf`/`yum`, `pacman`, `zypper`.
*   **Zarządzanie Usługami:** Uruchamia, zatrzymuje, włącza i wyłącza usługi (głównie `systemd`).
*   **Modularna Budowa:** Kod podzielony na logiczne moduły (`modules/`) dla łatwiejszej rozbudowy.
*   **Wielojęzyczność:** Wykrywa język systemu i używa tłumaczeń (aktualnie Polski i Angielski - `lang/`).
*   **Konfiguracja Systemu:** Ustawianie nazwy hosta, zarządzanie użytkownikami/grupami, zadania cron.
*   **Konfiguracja Sieci:** Podstawowa konfiguracja DNS, zarządzanie zaporą sieciową (`ufw`/`firewalld`).
*   **Wzmocnienia Bezpieczeństwa:** Konfiguracja SSH, instalacja/konfiguracja `Fail2Ban`, instalacja `Certbot`.
*   **Instalacja Aplikacji:** Serwery WWW (Apache, Nginx), Bazy Danych (MariaDB, PostgreSQL), Narzędzia deweloperskie, Silniki kontenerów (Docker, Podman).
*   **Gotowe Scenariusze:** Predefiniowane przepływy pracy (Serwer WWW, Minimalny Bezpieczny, Stanowisko Deweloperskie).
*   **Zarządzanie Dyskami (Podstawowe):** Instalacja narzędzi, wyświetlanie urządzeń, dodawanie wpisów `fstab` (wymaga dużej ostrożności!).
*   **Zarządzanie Kopiami Zapasowymi (Podstawowe):** Instalacja narzędzi, przykład zadania cron dla `rsync`.
*   **Logowanie i Backupy:** Zapisuje szczegółowy log operacji i tworzy kopie zapasowe modyfikowanych plików konfiguracyjnych.

## 📋 Wymagania Wstępne

*   System Linux z powłoką **Bash w wersji 4 lub nowszej**.
*   Dostęp do konta z uprawnieniami `sudo`.
*   Zainstalowany `git` (do sklonowania repozytorium).
*   Zainstalowany `curl` lub `wget` (do pobierania).
*   Zainstalowane `whiptail` lub `dialog` (skrypt spróbuje je zainstalować, jeśli ich brakuje).
*   Połączenie z internetem (do pobierania pakietów).

## 🚀 Użycie

**⚠️ OSTRZEŻENIE BEZPIECZEŃSTWA ⚠️**

Uruchamianie skryptów pobranych bezpośrednio z internetu, zwłaszcza tych, które wymagają uprawnień `sudo` i modyfikują system, jest **bardzo ryzykowne**. Zawsze **przejrzyj kod skryptu** przed jego uruchomieniem, aby upewnić się, że rozumiesz, co robi i że jest bezpieczny dla Twojego środowiska. Używaj tego skryptu na własną odpowiedzialność!

---

### Metoda Bezpośredniego Uruchomienia (NIE ZALECANE dla tego skryptu)

Teoretycznie, skrypty Bash można uruchomić bezpośrednio za pomocą `curl`:

```bash
# Teoretyczny przykład - NIE UŻYWAJ TEGO DLA TEGO SKRYPTU!
# curl -sSL https://raw.githubusercontent.com/TWOJA_NAZWA_UZYTKOWNIKA/NAZWA_REPOZYTORIUM/main/linux_setup.sh | sudo bash
