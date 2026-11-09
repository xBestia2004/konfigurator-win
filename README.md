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

## Kreator graficzny

Na Windows możesz przejść przez kroki w oknie kreatora (Windows Forms).

Uruchomienie (najlepiej jako administrator):

- dwuklik `Kreator.cmd`, albo
- w PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -STA -File .\gui\Start-Kreator.ps1
```

Kreator pokazuje wykrytą edycję Windows, sprawdza uprawnienia administratora i obecność winget, a potem prowadzi przez pobranie informacji o obrazie, dostosowanie i instalację aplikacji. Domyślnie zaznaczony jest **Tryb próbny (bez zmian w systemie)**. W trybie próbnym nic nie jest usuwane ani instalowane, tylko logowane. Odznaczenie trybu próbnego przekazuje pracę do istniejących skryptów w trybie wykonawczym.

## Struktura

```
konfigurator-win/
  Kreator.cmd                # szybkie uruchomienie kreatora (STA)
  bootstrap.ps1              # uruchamia kolejne kroki (konsola)
  README.md
  BACKLOG.md                 # planowane funkcje
  LICENSE
  .gitignore
  gui/
    Start-Kreator.ps1        # kreator graficzny (Windows Forms)
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

## Inspiracja

Pomysł na ten projekt wziął się z narzędzia [WinUtil od Chris Titus Tech](https://github.com/ChrisTitusTech/winutil). Dziękuję autorowi za jego pracę.

konfigurator-win próbuje pójść o krok dalej. W planach jest zapis gotowego obrazu Windows z tą samą konfiguracją na bootowalny pendrive oraz możliwość uruchomienia narzędzia z Windows, Linuksa i macOS. Te funkcje nie są jeszcze gotowe. Dziś dostosowanie systemu i instalacja programów działają na Windows, a szczegóły planów są w pliku `BACKLOG.md`.

## Plany

Planowane funkcje (m.in. bootowalny pendrive) są opisane w pliku `BACKLOG.md`.

## Wymagania

- Windows 10 lub Windows 11
- PowerShell 5.1 lub PowerShell 7 (kreator GUI: 5.1+ w trybie STA)
- Uprawnienia administratora do realnych zmian (usuwanie Appx, winget, część ustawień)
- winget (App Installer z Microsoft Store), gdy chcesz instalować programy

## Bezpieczeństwo

Najpierw uruchom skrypty w maszynie wirtualnej albo na kopii zapasowej. Domyślnie działa tryb podglądu (`-WhatIf` / dry-run / tryb próbny w kreatorze): skrypt tylko wypisuje, co by zrobił. Dopiero jawne `-WhatIf:$false` (albo `-DryRun:$false`, albo odznaczenie trybu próbnego w GUI) wykonuje zmiany.

Obrazy Windows pobieraj wyłącznie ze stron Microsoft. Ten projekt nie wskazuje nieoficjalnych mirrorów.

## Przykład użycia (konsola)

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
