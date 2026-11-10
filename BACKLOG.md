# Backlog konfigurator-win

Lista funkcji zrealizowanych oraz planowanych na przyszłość.

## Zrealizowane w wersji 1.1.0

- [x] **Wieloplatformowy kreator bootowalnego pendrive'a USB (`konfigurator.sh`)**:
  - Działa natywnie na systemach Linux i macOS (czysty Bash, bez wymogu PowerShell Core).
  - Bezpieczne wykrywanie podłączonych pendrive'ów USB (ochrona dysków wewnętrznych NVMe/SATA).
  - Formatowanie nośnika w standardzie UEFI FAT32 z etykietą `WININSTALL`.
  - Obsługa obrazów z plikiem `install.wim` > 4 GB poprzez automatyczny podział na pliki `.swm` (3800 MB) za pomocą `wimlib-imagex`.
  - Automatyczne wstrzykiwanie pliku `autounattend.xml` oraz katalogu `konfigurator-win` na przygotowany nośnik.
- [x] **Szablon nienadzorowanej instalacji Windows (`unattend/autounattend.example.xml`)**:
  - Obejście wymagań sprzętowych Windows 11 (TPM 2.0, Secure Boot, RAM, CPU) pod laptopy poleasingowe.
  - Pominięcie wymogu konta Microsoft Online i automatyczne utworzenie konta lokalnego.
  - Automatyczna akceptacja EULA i wyłączenie natrętnych pytań telemetrycznych OOBE.
- [x] **Infrastruktura CI**:
  - Workflow GitHub Actions (`.github/workflows/ci.yml`) weryfikujący poprawność składni PowerShell oraz skryptów powłoki na runnerach Ubuntu i Windows.

## Planowane na kolejne wydania

### 1. Kreator USB dla środowiska Windows
- Status: planowane.
- Dodanie modułu w PowerShell (`download/New-WindowsUsb.ps1` lub wbudowanie w `Kreator.cmd` / GUI), który pozwoli przygotować bootowalny pendrive USB bezpośrednio z poziomu Windows bez zewnętrznych narzędzi (np. Rufus).
- Wykorzystanie natywnych poleceń `Get-Disk`, `Clear-Disk`, `New-Partition`, `Format-Volume` oraz `dism /Split-Image`.

### 2. Testy na maszynie wirtualnej (VM)
- Status: w trakcie przygotowania.
- Przetestowanie pliku `autounattend.xml` w środowisku wirtualnym (np. VirtualBox, VMware, QEMU lub Hyper-V).
- Weryfikacja bezbłędnego przejścia fazy instalacji bez interwencji użytkownika aż do pulpitu z kontem lokalnym.

### 3. Lekki interfejs okienkowy dla Linuksa (opcjonalnie)
- Status: pomysł / do analizy.
- Możliwość uruchomienia graficznego okna wyboru pendrive'a za pomocą `zenity` lub `dialog`/`whiptail`, jeśli są obecne w systemie.
