# Nienadzorowana instalacja Windows (autounattend.xml)

Katalog zawiera szablon odpowiedzi dla instalatora systemu Windows (`autounattend.example.xml`), który umożliwia automatyzację instalacji systemu i ominięcie ograniczeń na starszym sprzęcie.

## Co robi dołączony szablon?

1. **Obejście wymagań sprzętowych Windows 11 (LabConfig):**
   - Pomija weryfikację modułu TPM 2.0 (`BypassTPMCheck`)
   - Pomija weryfikację Secure Boot (`BypassSecureBootCheck`)
   - Pomija weryfikację pamięci RAM (`BypassRAMCheck`)
   - Pomija weryfikację generacji procesora (`BypassCPUCheck`)
   - Pomija weryfikację minimalnej przestrzeni dyskowej (`BypassStorageCheck`)
   Idealne rozwiązanie dla starszych laptopów poleasingowych (np. ThinkPad T480/T470, Dell Latitude, HP EliteBook).

2. **Pominięcie wymuszonego konta Microsoft (MSA):**
   - Tworzy lokalne konto administratora o nazwie `Uzytkownik` z pustym hasłem (możesz zmienić je w pliku).
   - Pomija ekrany logowania online i wymaganie połączenia z Internetem podczas OOBE.

3. **Komfort pierwszego uruchomienia:**
   - Automatycznie akceptuje licencję EULA.
   - Wyłącza natrętne ekrany telemetrii i analityki OOBE.

## Jak użyć pliku na pendrive USB?

Plik odpowiedzi musi znajdować się w **głównym katalogu (root)** pendrive'a instalacyjnego pod nazwą `autounattend.xml`:
```text
X:\
├── autounattend.xml
├── setup.exe
├── boot/
├── efi/
├── sources/
└── konfigurator-win/
```

Wieloplatformowy skrypt `konfigurator.sh` automatycznie proponuje wgranie tego pliku podczas przygotowywania bootowalnego nośnika USB.

## Zaawansowana personalizacja

Jeśli potrzebujesz wygenerować bardziej złożony plik (partycjonowanie automatyczne, klucze licencyjne, niestandardowe nazwy komputerów), polecamy skorzystać z oficjalnego generatora:
- [Schneegans Unattend Generator](https://schneegans.de/windows/unattend-generator/)
- Po wygenerowaniu pliku na tej stronie zapisz go jako `autounattend.xml` w głównym katalogu pendrive'a.
