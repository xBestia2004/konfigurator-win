# Dziennik zmian (Changelog)

Wszystkie istotne zmiany w projekcie **konfigurator-win** są dokumentowane w tym pliku.
Format bazuje na wytycznych [Keep a Changelog](https://keepachangelog.com/pl/1.0.0/), a wersjonowanie odpowiada [Semantic Versioning](https://semver.org/lang/pl/).

## [1.0.0] - 2026-11-09

### Dodano
- **Orkiestrator `bootstrap.ps1`**:
  - Interaktywny nagłówek ASCII z numerem wersji i autorem.
  - Automatyczna detekcja uprawnień administracyjnych oraz wersji PowerShell.
  - Bezpieczny tryb podglądu `-WhatIf` (domyślnie aktywny).
  - Przełączniki modułowe: `-SkipDownload`, `-SkipCustomize`, `-SkipInstall`, `-UpgradeApps`, `-RestartExplorer`, `-Log`.
  - Rejestrowanie wykonania do pliku `.log` (`Start-Transcript`).
  - Podsumowanie tabelaryczne wszystkich wykonanych kroków wraz z czasem trwania.
- **Moduł detekcji `customize/Get-WindowsEdition.ps1`**:
  - Precyzyjne odczytywanie nazwy systemu, wersji funkcjonalnej (np. 23H2, 24H2), numeru kompilacji, rewizji UBR i architektury.
  - Bezpieczne działanie w środowiskach testowych / CI.
  - Wsparcie dla wyjścia obiektowego i JSON (`-AsJson`).
- **Moduł personalizacji i debloatu `customize/Invoke-Customize.ps1`**:
  - Dwuetapowe usuwanie pakietów Appx: z profilu bieżącego użytkownika oraz z obrazu aprowizowanego systemu (`ProvisionedPackage`).
  - Zastosowanie motywu ciemnego/jasnego (`AppsUseLightTheme`, `SystemUsesLightTheme`).
  - Konfiguracja paska zadań (wyrównanie do lewej w Windows 11, ukrywanie widżetów).
  - Włączanie widoczności rozszerzeń plików oraz plików ukrytych w Eksploratorze Windows.
  - Wyłączanie sugestii wyszukiwania Bing w menu Start oraz telemetrii diagnostycznej.
  - Zmiana tapety pulpitu z natychmiastowym odświeżeniem przez Win32 API (`SystemParametersInfo`).
- **Moduł pobierania nośników `download/Get-WindowsImage.ps1`**:
  - Oficjalne adresy pobierania Microsoft dla Windows 10 oraz Windows 11.
  - Automatyczne pobieranie narzędzia `MediaCreationTool` (`-DownloadMediaCreationTool`).
  - Weryfikacja sumy kontrolnej SHA-256 dla pobranych plików ISO (`-VerifyIsoPath`).
- **Moduł instalacji aplikacji `install/Install-Apps.ps1`**:
  - Pełna integracja z menedżerem pakietów Windows Package Manager (`winget`).
  - Sprawdzanie obecności pakietu przed instalacją (`winget list`).
  - Wsparcie dla cichej instalacji (unattended) oraz aktualizacji (`-UpgradeExisting`).
  - Przejrzyste podsumowanie statystyk (Zainstalowano, Pominięto, Zaktualizowano, Błędy).
- **Infrastruktura projektu**:
  - Workflow GitHub Actions dla ciągłej integracji i analizy kodu (`.github/workflows/ci.yml`).
  - Dokumentacja dla współtwórców (`CONTRIBUTING.md`).
  - Profesjonalne szablony konfiguracyjne (`settings.example.json`, `apps.example.json`, `bloatware.txt`).
