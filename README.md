# konfigurator-win

Szkielet (wczesna wersja) narzędzi PowerShell do przygotowania świeżej instalacji Windows.

Projekt ma w przyszłości:

1. Pobrać obraz Windows 10 lub 11 (edycje Pro i Home) z oficjalnego źródła Microsoft.
2. Rozpoznać edycję systemu, która właśnie działa na komputerze.
3. Dostosować system: usunąć zbędne aplikacje z listy, zastosować ustawienia z pliku konfiguracyjnego (tapeta, motyw, domyślna przeglądarka i inne).
4. Zainstalować ulubione programy przez winget.

Na razie to tylko szkielet. Skrypty mają tryb podglądu (domyślnie nic nie zmieniają na dysku) i miejsca oznaczone TODO.

## Autor

Dariusz Kisiel, technik informatyk, Lublin

## Struktura

```
konfigurator-win/
  bootstrap.ps1              # uruchamia kolejne kroki
  README.md
  LICENSE
  .gitignore
  download/
    Get-WindowsImage.ps1     # pobieranie obrazu (szkielet)
  customize/
    Get-WindowsEdition.ps1   # rozpoznanie edycji systemu
    Invoke-Customize.ps1     # usuwanie bloatware i ustawienia
    bloatware.txt            # lista nazw pakietów Appx
    settings.example.json    # przykład ustawień
  install/
    Install-Apps.ps1         # instalacja przez winget
    apps.example.json        # przykład listy aplikacji
```

## Wymagania

- Windows 10 lub Windows 11
- PowerShell 5.1 lub PowerShell 7
- Uprawnienia administratora do realnych zmian (usuwanie Appx, winget, część ustawień)
- winget (App Installer z Microsoft Store), gdy chcesz instalować programy

## Bezpieczeństwo

Najpierw uruchom skrypty w maszynie wirtualnej albo na kopii zapasowej. Domyślnie działa tryb podglądu (`-WhatIf` / dry-run): skrypt tylko wypisuje, co by zrobił. Dopiero jawne `-WhatIf:$false` (albo `-DryRun:$false` tam, gdzie jest ten przełącznik) wykonuje zmiany.

Obrazy Windows pobieraj wyłącznie ze stron Microsoft. Ten projekt nie wskazuje nieoficjalnych mirrorów.

## Przykład użycia

W PowerShell uruchomionym jako administrator, w katalogu projektu:

```powershell
# tylko podgląd (domyślnie)
.\bootstrap.ps1

# podgląd z wybraną wersją obrazu
.\bootstrap.ps1 -WindowsVersion 11 -Edition Pro

# realne zmiany dopiero po świadomej decyzji
.\bootstrap.ps1 -WhatIf:$false
```

Pojedyncze kroki:

```powershell
.\download\Get-WindowsImage.ps1 -Version 11 -Edition Home
.\customize\Get-WindowsEdition.ps1
.\customize\Invoke-Customize.ps1
.\install\Install-Apps.ps1
```

Przed realnym dostosowaniem skopiuj przykłady:

```powershell
Copy-Item .\customize\settings.example.json .\customize\settings.json
Copy-Item .\install\apps.example.json .\install\apps.json
```

Pliki `settings.json` i `apps.json` są lokalne i nie powinny trafiać do repozytorium (patrz `.gitignore`).

## Licencja

MIT. Szczegóły w pliku `LICENSE`.
