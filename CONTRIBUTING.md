# Współtworzenie projektu (Contributing Guide)

Dziękujemy za zainteresowanie rozwojem projektu **konfigurator-win**!
Projekt ma na celu dostarczenie przejrzystego, bezpiecznego i w pełni zautomatyzowanego narzędzia do konfiguracji systemu Windows.

## Zasady ogólne

1. **Bezpieczeństwo i transparentność**:
   - Skrypty korzystają wyłącznie z oficjalnych źródeł firmy Microsoft. Żadnych zewnętrznych mirrorów, nieoficjalnych instalatorów czy binariów nieznanego pochodzenia.
   - Domyślnym trybem pracy zawsze pozostaje tryb podglądu (`-WhatIf` / `-DryRun`).
2. **Czystość kodu**:
   - Wszystkie skrypty muszą zachowywać zgodność ze standardami `PSScriptAnalyzer`.
   - Stosujemy `Set-StrictMode -Version Latest` oraz `$ErrorActionPreference = 'Stop'`.
   - Każda funkcja i skrypt powinny zawierać pomoc w formacie Comment-Based Help (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`).

## Zgłaszanie problemów (Issues)

Przed utworzeniem nowego zgłoszenia:
- Upewnij się, że problem nie został już zgłoszony w sekcji Issues.
- Załącz informacje o wersji systemu Windows (`customize\Get-WindowsEdition.ps1`) oraz wersji PowerShell (`$PSVersionTable`).

## Proponowanie zmian (Pull Requests)

1. Sforkuj repozytorium do własnego konta GitHub.
2. Utwórz nową gałąź funkcjonalną: `git checkout -b feature/nazwa-funkcji`.
3. Wprowadź zmiany i sprawdź poprawność składni:
   ```powershell
   Invoke-ScriptAnalyzer -Path . -Recurse
   .\bootstrap.ps1 -WhatIf
   ```
4. Dodaj commit z czytelnym opisem zmian w konwencji Conventional Commits (np. `feat: dodanie opcji wyłączenia cortany`).
5. Otwórz Pull Request do gałęzi `main`.

## Licencja

Wysyłając swój wkład do repozytorium, zgadzasz się na objęcie go licencją MIT zawartą w pliku `LICENSE`.
