#!/usr/bin/env bash
# ====================================================================
#  KONFIGURATOR-WIN: Wieloplatformowy kreator nośnika USB (Linux / macOS)
#  Automatyzacja przygotowania bootowalnego nośnika instalacyjnego Windows,
#  podziału plików WIM (>4GB), bypassu TPM/Secure Boot oraz konfiguratora.
# ====================================================================

set -euo pipefail

VERSION="1.1.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=false

# Kolory terminala
if [[ -t 1 ]]; then
    C_RESET='\033[0m'
    C_BOLD='\033[1m'
    C_CYAN='\033[0;36m'
    C_GREEN='\033[0;32m'
    C_YELLOW='\033[1;33m'
    C_RED='\033[0;31m'
    C_GRAY='\033[0;90m'
else
    C_RESET=''
    C_BOLD=''
    C_CYAN=''
    C_GREEN=''
    C_YELLOW=''
    C_RED=''
    C_GRAY=''
fi

detect_os() {
    local os_type
    os_type="$(uname -s)"
    case "$os_type" in
        Linux*)  echo "linux" ;;
        Darwin*) echo "macos" ;;
        *)       echo "unknown" ;;
    esac
}

CURRENT_OS="$(detect_os)"

show_banner() {
    cat << "EOF"

====================================================================
  _  ______  _   _ ______ _____ _____ _    _ _____         _______  
 | |/ / __ \| \ | |  ____|_   _/ ____| |  | |  __ \     /\|__   __| 
 | ' / |  | |  \| | |__    | || |  __| |  | | |__) |   /  \  | |    
 |  <| |  | | . ` |  __|   | || | |_ | |  | |  _  /   / /\ \ | |    
 | . \ |__| | |\  | |     _| || |__| | |__| | | \ \  / ____ \| |    
 |_|\_\____/|_| \_|_|    |_____\_____|\____/|_|  \_\/_/    \_\_|    
               KONFIGURATOR-WIN: Kreator USB (Linux / macOS)
               Wersja 1.1.0 | Autor: Dariusz Kisiel
====================================================================
EOF
}

log_info() {
    echo -e "${C_CYAN}[INFO]${C_RESET} $1"
}

log_ok() {
    echo -e "${C_GREEN}[OK]${C_RESET} $1"
}

log_warn() {
    echo -e "${C_YELLOW}[OSTRZEŻENIE]${C_RESET} $1"
}

log_err() {
    echo -e "${C_RED}[BŁĄD]${C_RESET} $1" >&2
}

# Sprawdzenie obecności narzędzi
check_tools() {
    log_info "Sprawdzanie środowiska i wymaganych narzędzi ($CURRENT_OS)..."
    local missing=0

    # curl
    if ! command -v curl &>/dev/null; then
        log_warn "Brak narzędzia 'curl'. Zainstaluj pakiet curl."
        missing=1
    fi

    # SHA256 sum
    if [[ "$CURRENT_OS" == "linux" ]]; then
        if ! command -v sha256sum &>/dev/null; then
            log_warn "Brak 'sha256sum' (coreutils)."
            missing=1
        fi
    elif [[ "$CURRENT_OS" == "macos" ]]; then
        if ! command -v shasum &>/dev/null; then
            log_warn "Brak 'shasum'."
            missing=1
        fi
    fi

    # 7z lub mount do wypakowania ISO
    if ! command -v 7z &>/dev/null && ! command -v 7za &>/dev/null; then
        if [[ "$CURRENT_OS" == "linux" ]]; then
            log_warn "Zalecane narzędzie '7z' nie zostało odnalezione. (Ubuntu/Debian: sudo apt install p7zip-full)"
        elif [[ "$CURRENT_OS" == "macos" ]]; then
            log_warn "Zalecane narzędzie '7z' nie zostało odnalezione. (macOS: brew install p7zip)"
        fi
    fi

    # wimlib-imagex do dzielenia plików WIM > 4GB
    if ! command -v wimlib-imagex &>/dev/null; then
        log_warn "Narzędzie 'wimlib-imagex' nie jest zainstalowane."
        if [[ "$CURRENT_OS" == "linux" ]]; then
            echo -e "       ${C_GRAY}Aby zainstalować: sudo apt install wimtools (lub dnf install wimtools / pacman -S wimlib)${C_RESET}"
        elif [[ "$CURRENT_OS" == "macos" ]]; then
            echo -e "       ${C_GRAY}Aby zainstalować: brew install wimlib${C_RESET}"
        fi
        echo -e "       ${C_GRAY}(Potrzebne tylko wtedy, gdy install.wim przekracza 4 GB na partycji FAT32).${C_RESET}"
    fi

    if [[ $missing -eq 0 ]]; then
        log_ok "Podstawowe narzędzia systemowe są dostępne."
    fi
}

# Wyświetlanie oficjalnych stron pobierania
show_download_sources() {
    echo ""
    echo -e "${C_BOLD}=== Oficjalne źródła pobierania nośników Microsoft ===${C_RESET}"
    echo -e "Zgodnie z zasadami projektu, pobieramy obrazy wyłącznie z serwerów Microsoft:"
    echo ""
    echo -e "  ${C_CYAN}Windows 11:${C_RESET} https://www.microsoft.com/software-download/windows11"
    echo -e "  ${C_CYAN}Windows 10:${C_RESET} https://www.microsoft.com/software-download/windows10"
    echo ""
    echo -e "${C_GRAY}Wskazówka: Po wejściu na stronę z poziomu Linuksa lub macOS, Microsoft${C_RESET}"
    echo -e "${C_GRAY}bezpośrednio udostępnia pobieranie pełnego pliku ISO (bez wymuszania MediaCreationTool).${C_RESET}"
    echo ""
}

# Weryfikacja sumy SHA-256 pliku ISO
verify_iso_checksum() {
    local iso_file="${1:-}"
    if [[ -z "$iso_file" ]]; then
        read -r -p "Podaj ścieżkę do pliku ISO: " iso_file
    fi

    # Rozwiń ewentualną tyldę
    iso_file="${iso_file/#\~/$HOME}"

    if [[ ! -f "$iso_file" ]]; then
        log_err "Wskazany plik nie istnieje: $iso_file"
        return 1
    fi

    log_info "Obliczanie sumy SHA-256 dla pliku: $iso_file"
    echo -e "${C_GRAY}(Dla dużego pliku ISO może to potrwać kilkadziesiąt sekund...)${C_RESET}"

    local calc_hash=""
    if [[ "$CURRENT_OS" == "linux" ]]; then
        calc_hash="$(sha256sum "$iso_file" | awk '{print $1}')"
    elif [[ "$CURRENT_OS" == "macos" ]]; then
        calc_hash="$(shasum -a 256 "$iso_file" | awk '{print $1}')"
    fi

    echo ""
    echo -e "Obliczona suma SHA-256: ${C_BOLD}${calc_hash}${C_RESET}"
    echo ""

    read -r -p "Wklej oczekiwaną sumę SHA-256 (lub naciśnij Enter, aby pominąć): " exp_hash
    if [[ -n "$exp_hash" ]]; then
        exp_clean="$(echo "$exp_hash" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
        calc_clean="$(echo "$calc_hash" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"

        if [[ "$exp_clean" == "$calc_clean" ]]; then
            log_ok "Suma kontrolna SHA-256 ZGODNA! Obraz ISO jest nienaruszony."
        else
            log_err "Suma kontrolna NIE ZGADZA SIĘ z oczekiwaną!"
            echo -e "  Oczekiwano: $exp_clean"
            echo -e "  Otrzymano : $calc_clean"
            return 1
        fi
    fi
}

# Bezpieczne listowanie nośników USB
list_usb_drives() {
    echo ""
    echo -e "${C_BOLD}=== Wykryte wymienne nośniki pamięci USB ===${C_RESET}"

    if [[ "$CURRENT_OS" == "linux" ]]; then
        if command -v lsblk &>/dev/null; then
            # Wyświetl tylko dyski USB (TRAN == usb lub RM == 1)
            local usb_list
            usb_list="$(lsblk -d -p -n -o NAME,SIZE,MODEL,TRAN,RM,TYPE | awk '$4 == "usb" || $5 == "1" {print $0}')"
            if [[ -z "$usb_list" ]]; then
                log_warn "Nie wykryto żadnego podłączonego pendrive'a USB."
                echo -e "       ${C_GRAY}(Upewnij się, że nośnik USB jest włożony do portu i spróbuj ponownie).${C_RESET}"
                return 1
            else
                echo -e "${C_CYAN}Urządzenie   Rozmiar   Model / Opis${C_RESET}"
                echo "--------------------------------------------------------"
                echo "$usb_list"
                echo "--------------------------------------------------------"
            fi
        else
            log_warn "Narzędzie lsblk jest niedostępne."
            return 1
        fi
    elif [[ "$CURRENT_OS" == "macos" ]]; then
        if command -v diskutil &>/dev/null; then
            echo -e "${C_CYAN}Zewnętrzne dyski fizyczne:${C_RESET}"
            diskutil list external physical
        else
            log_warn "Narzędzie diskutil jest niedostępne."
            return 1
        fi
    fi
    return 0
}

# Przygotowanie bootowalnego pendrive'a
create_bootable_usb() {
    echo ""
    echo -e "${C_BOLD}=== Asystent przygotowania bootowalnego pendrive'a UEFI Windows ===${C_RESET}"

    if ! list_usb_drives; then
        return 1
    fi

    echo ""
    read -r -p "Wskaż ścieżkę do pliku ISO Windows: " iso_path
    iso_path="${iso_path/#\~/$HOME}"
    if [[ ! -f "$iso_path" ]]; then
        log_err "Plik ISO nie istnieje: $iso_path"
        return 1
    fi

    echo ""
    if [[ "$CURRENT_OS" == "linux" ]]; then
        read -r -p "Wskaż urządzenie USB (np. /dev/sdb - NIE partycję /dev/sdb1!): " target_dev
    elif [[ "$CURRENT_OS" == "macos" ]]; then
        read -r -p "Wskaż dysk USB (np. /dev/disk2 - NIE /dev/disk2s1!): " target_dev
    fi

    if [[ -z "$target_dev" || ! -e "$target_dev" ]]; then
        log_err "Wskazane urządzenie nie istnieje: $target_dev"
        return 1
    fi

    # Zabezpieczenie przed nadpisaniem dysku systemowego na Linuksie
    if [[ "$CURRENT_OS" == "linux" ]]; then
        local is_usb
        is_usb="$(lsblk -d -n -o TRAN "$target_dev" 2>/dev/null || true)"
        local is_rm
        is_rm="$(lsblk -d -n -o RM "$target_dev" 2>/dev/null || true)"

        if [[ "$is_usb" != "usb" && "$is_rm" != "1" ]]; then
            log_err "BEZPIECZEŃSTWO: Urządzenie $target_dev nie zostało zidentyfikowane jako USB/wymienne!"
            log_err "Operacja została wstrzymana, aby uchronić dysk systemowy przed skasowaniem."
            return 1
        fi
    fi

    echo ""
    echo -e "${C_RED}${C_BOLD}!!! OSTRZEŻENIE O UTRACIE DANYCH !!!${C_RESET}"
    echo -e "Wszystkie dane na urządzeniu ${C_BOLD}${target_dev}${C_RESET} zostaną BEZPOWROTNIE USUNIĘTE!"
    echo -e "Urządzenie zostanie sformatowane jako nośnik startowy UEFI (FAT32)."
    echo ""
    read -r -p "Wpisz dokładnie 'TAK' (wielkimi literami), aby potwierdzić i kontynuować: " confirm
    if [[ "$confirm" != "TAK" ]]; then
        log_warn "Operacja anulowana przez użytkownika."
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_ok "[DryRun] Symulacja: sformatowano by $target_dev, rozpakowano $iso_path i podzielono WIM."
        return 0
    fi

    # Tymczasowe katalogi montowania
    local work_dir
    work_dir="$(mktemp -d -t winusb_work_XXXXXX)"
    local mount_iso="$work_dir/iso"
    local mount_usb="$work_dir/usb"
    mkdir -p "$mount_iso" "$mount_usb"

    cleanup() {
        log_info "Czyszczenie punktów montowania..."
        if mountpoint -q "$mount_usb" 2>/dev/null; then sudo umount "$mount_usb" || true; fi
        if mountpoint -q "$mount_iso" 2>/dev/null; then sudo umount "$mount_iso" || true; fi
        rm -rf "$work_dir"
    }
    trap cleanup EXIT

    log_info "Partycjonowanie i formatowanie nośnika $target_dev..."
    if [[ "$CURRENT_OS" == "linux" ]]; then
        # Odmontuj ewentualne istniejące partycje
        sudo umount "${target_dev}"* 2>/dev/null || true

        # Utwórz tablicę MBR z jedną aktywną partycją FAT32 (UEFI kompatybilna)
        sudo parted -s "$target_dev" mklabel msdos
        sudo parted -s "$target_dev" mkpart primary fat32 1MiB 100%
        sudo parted -s "$target_dev" set 1 boot on

        # Ustal nazwę utworzonej partycji (np. /dev/sdb1 lub /dev/nvme0n1p1)
        local target_part
        if [[ "$target_dev" =~ [0-9]$ ]]; then
            target_part="${target_dev}p1"
        else
            target_part="${target_dev}1"
        fi

        log_info "Formatowanie partycji $target_part (FAT32, etykieta: WININSTALL)..."
        sudo mkfs.vfat -F 32 -n "WININSTALL" "$target_part"
        sudo mount "$target_part" "$mount_usb"

    elif [[ "$CURRENT_OS" == "macos" ]]; then
        log_info "Formatowanie przez diskutil (FAT32, etykieta: WININSTALL)..."
        diskutil eraseDisk FAT32 "WININSTALL" MBR "$target_dev"
        # macOS automatycznie montuje wolumen pod /Volumes/WININSTALL
        mount_usb="/Volumes/WININSTALL"
    fi

    log_info "Kopiowanie plików z obrazu ISO na nośnik USB..."
    local extracted=false

    # Metoda A: Użycie 7z (szybkie, nie wymaga montowania pętli ISO)
    if command -v 7z &>/dev/null; then
        log_info "Wypakowywanie zawartości ISO za pomocą 7z (pomijając install.wim jeśli przekracza 4GB)..."
        # Sprawdź obecność i rozmiar install.wim wewnątrz ISO
        7z x "$iso_path" -o"$mount_usb" -x'!sources/install.wim' -y >/dev/null
        extracted=true
    fi

    # Metoda B: Montowanie ISO (fallback gdy brak 7z)
    if [[ "$extracted" == "false" ]]; then
        if [[ "$CURRENT_OS" == "linux" ]]; then
            sudo mount -o loop,ro "$iso_path" "$mount_iso"
            log_info "Kopiowanie plików (z wyłączeniem install.wim)..."
            rsync -av --progress --exclude='sources/install.wim' "$mount_iso/" "$mount_usb/"
            extracted=true
        elif [[ "$CURRENT_OS" == "macos" ]]; then
            hdiutil mount "$iso_path" -mountpoint "$mount_iso"
            rsync -av --progress --exclude='sources/install.wim' "$mount_iso/" "$mount_usb/"
            extracted=true
        fi
    fi

    # Obsługa pliku install.wim / install.esd
    log_info "Przetwarzanie pliku instalacyjnego systemu Windows (sources/install.*)..."
    local temp_wim="$work_dir/install.wim"

    # Wyodrębnij install.wim
    if command -v 7z &>/dev/null; then
        7z e "$iso_path" 'sources/install.wim' -o"$work_dir" -y >/dev/null || true
        if [[ ! -f "$temp_wim" ]]; then
            # Może to być install.esd
            7z e "$iso_path" 'sources/install.esd' -o"$work_dir" -y >/dev/null || true
            if [[ -f "$work_dir/install.esd" ]]; then
                mv "$work_dir/install.esd" "$temp_wim"
            fi
        fi
    elif [[ -f "$mount_iso/sources/install.wim" ]]; then
        cp "$mount_iso/sources/install.wim" "$temp_wim"
    elif [[ -f "$mount_iso/sources/install.esd" ]]; then
        cp "$mount_iso/sources/install.esd" "$temp_wim"
    fi

    if [[ -f "$temp_wim" ]]; then
        local wim_size
        wim_size=$(stat -c%s "$temp_wim" 2>/dev/null || stat -f%z "$temp_wim" 2>/dev/null || echo 0)
        local limit_fat32=4294967295 # 4 GB - 1 B

        if (( wim_size > limit_fat32 )); then
            log_warn "Plik install.wim przekracza limit 4 GB formatu FAT32 ($(( wim_size / 1024 / 1024 )) MB)."
            if command -v wimlib-imagex &>/dev/null; then
                log_info "Dzielenie install.wim na pliki install.swm (części po 3800 MB)..."
                mkdir -p "$mount_usb/sources"
                wimlib-imagex split "$temp_wim" "$mount_usb/sources/install.swm" 3800
                log_ok "Pomyślnie podzielono plik WIM na partycji FAT32."
            else
                log_err "Plik install.wim jest za duży na FAT32, a brak 'wimlib-imagex'!"
                log_err "Zainstaluj pakiet wimtools (Linux) lub wimlib (macOS)."
                return 1
            fi
        else
            log_info "Plik install.wim mieści się w limicie FAT32. Kopiowanie..."
            mkdir -p "$mount_usb/sources"
            cp "$temp_wim" "$mount_usb/sources/install.wim"
        fi
        rm -f "$temp_wim"
    fi

    # Wstrzyknięcie autounattend.xml oraz konfigurator-win
    inject_configuration "$mount_usb"

    # Synchronizacja buforów zapisu
    log_info "Zapisywanie buforów na dysk USB (sync)..."
    sync

    log_ok "============================================================"
    log_ok " Bootowalny pendrive UEFI został pomyślnie utworzony!"
    log_ok " Możesz teraz bezpiecznie odłączyć nośnik USB."
    log_ok "============================================================"
}

# Dogranie autounattend.xml i folderu konfiguratora na nośnik
inject_configuration() {
    local target_mount="$1"
    log_info "Dogrywanie konfiguracji projektu konfigurator-win na nośnik USB..."

    # 1. Kopiowanie autounattend.xml
    local unattend_source="$SCRIPT_DIR/unattend/autounattend.example.xml"
    if [[ -f "$unattend_source" ]]; then
        cp "$unattend_source" "$target_mount/autounattend.xml"
        log_ok "Zapisano plik odpowiedzi autounattend.xml w głównym katalogu nośnika."
    fi

    # 2. Kopiowanie całego repozytorium do X:\konfigurator-win
    local target_konf="$target_mount/konfigurator-win"
    mkdir -p "$target_konf"
    rsync -av --exclude='.git' --exclude='downloads' --exclude='logs' "$SCRIPT_DIR/" "$target_konf/" >/dev/null
    log_ok "Skopiowano skrypty i konfigurację do katalogu /konfigurator-win/ na nośniku."
}

# Generator / edytor autounattend.xml
manage_unattend() {
    echo ""
    echo -e "${C_BOLD}=== Zarządzanie plikiem autounattend.xml ===${C_RESET}"
    echo "Dołączony szablon w katalogu unattend/ zapewnia:"
    echo "  1. Obejście wymagań Windows 11 (BypassTPMCheck, BypassSecureBootCheck, BypassRAMCheck, CPU)"
    echo "  2. Utworzenie konta lokalnego (omijanie wymogu konta Microsoft Online)"
    echo "  3. Pominięcie pytań telemetrycznych i akceptację EULA"
    echo ""
    echo "Plik szablonu: $SCRIPT_DIR/unattend/autounattend.example.xml"
    echo "Oficjalny generator zaawansowany: https://schneegans.de/windows/unattend-generator/"
    echo ""
}

# Menu interaktywne
interactive_menu() {
    while true; do
        show_banner
        echo -e "${C_BOLD}Dostępne opcje:${C_RESET}"
        echo "  [1] Wyświetl oficjalne źródła pobierania Windows 10 & 11"
        echo "  [2] Sprawdź sumę kontrolną SHA-256 pliku ISO"
        echo "  [3] Wyświetl podłączone pamięci USB"
        echo "  [4] Przygotuj bootowalny pendrive UEFI (Format + WIM split + autounattend)"
        echo "  [5] Informacje o autounattend.xml (bypass TPM, konto lokalne)"
        echo "  [6] Sprawdź zależności i środowisko systemowe"
        echo "  [0] Wyjście"
        echo ""
        read -r -p "Wybierz opcję [0-6]: " choice

        case "$choice" in
            1) show_download_sources ;;
            2) verify_iso_checksum "" ;;
            3) list_usb_drives || true ;;
            4) create_bootable_usb ;;
            5) manage_unattend ;;
            6) check_tools ;;
            0) echo "Do widzenia!"; exit 0 ;;
            *) log_warn "Nieprawidłowy wybór. Spróbuj ponownie." ;;
        esac

        echo ""
        read -r -p "Naciśnij Enter, aby powrócić do menu..." _
    done
}

# Przetwarzanie argumentów wiersza poleceń
case "${1:-}" in
    --help|-h)
        show_banner
        echo "Użycie:"
        echo "  $0                  Uruchamia interaktywne menu (TUI)"
        echo "  $0 --verify <iso>   Weryfikuje sumę SHA-256 pliku ISO"
        echo "  $0 --list-usb       Wyświetla podłączone pendrive'y USB"
        echo "  $0 --check-tools    Sprawdza wymagane pakiety w systemie"
        echo "  $0 --dry-run        Uruchamia skrypt w trybie symulacji"
        exit 0
        ;;
    --verify)
        verify_iso_checksum "${2:-}"
        exit $?
        ;;
    --list-usb)
        list_usb_drives
        exit $?
        ;;
    --check-tools)
        check_tools
        exit 0
        ;;
    --dry-run)
        DRY_RUN=true
        interactive_menu
        ;;
    "")
        interactive_menu
        ;;
    *)
        log_err "Nieznana opcja: $1. Użyj $0 --help"
        exit 1
        ;;
esac
