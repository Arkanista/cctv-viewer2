# Instrukcja Obsługi programu CCTV Viewer 2

**CCTV Viewer 2** to zaawansowana aplikacja przeznaczona do jednoczesnego podglądu strumieni wideo na żywo (RTSP/ONVIF) oraz integracji z rejestratorami NVR/DVR firmy Hikvision (zarówno w trybie Live, jak i odtwarzania archiwum Playback). 

Program został zoptymalizowany pod kątem stabilności, płynności działania (60 FPS) oraz minimalnego obciążenia zasobów systemowych.

---

## Spis Treści
1. [Instalacja i Uruchamianie](#1-instalacja-i-uruchamianie)
2. [Zarządzanie Rejestratorami NVR/DVR](#2-zarządzanie-rejestratorami-nvrdvr)
3. [Podgląd na Żywo (Live View)](#3-podgląd-na-żywo-live-view)
4. [Układy Ekranu i Presety (Layouts & Presets)](#4-układy-ekranu-i-presety-layouts--presets)
5. [Panel Statystyk Systemowych (System Stats)](#5-panel-statystyk-systemowych-system-stats)
6. [Odtwarzacz Archiwum Nagrań (Playback Archive)](#6-odtwarzacz-archiwum-nagrań-playback-archive)
7. [Pobieranie Nagrań (Downloader)](#7-pobieranie-nagrań-downloader)
8. [Skróty Klawiszowe i Sterowanie Myszami](#8-skróty-klawiszowe-i-sterowanie-myszami)
9. [Wykonywanie Zrzutów Ekranu (Stopklatek) i Konfiguracja Ścieżek](#9-wykonywanie-zrzutów-ekranu-stopklatek-i-konfiguracja-ścieżek)

---

## 1. Instalacja i Uruchamianie

### Instalacja pakietu Arch Linux (Pacman)
Aby zainstalować program z przygotowanej paczki binarnej, przejdź do katalogu `packaging/arch/` i wykonaj:
```bash
sudo pacman -U cctv-viewer2-2.0.7-4-x86_64.pkg.tar.zst
```
Pakiet automatycznie zainstaluje program, plik aktywacyjny `.desktop` oraz wymagane biblioteki Hikvision SDK w systemowej ścieżce `/usr/lib/cctv-viewer2`.

### Ręczna kompilacja (ze źródeł)
Jeśli zamiast gotowej paczki chcesz skompilować program ręcznie (np. na innej dystrybucji Linuksa):

1. Zainstaluj wymagane zależności do budowania oraz działania programu. W systemie Arch Linux / CachyOS wywołaj:
   ```bash
   sudo pacman -S base-devel cmake qt5-declarative qt5-multimedia qt5-quickcontrols qt5-quickcontrols2 qt5-svg qt5-graphicaleffects qt5-tools ffmpeg git
   ```
2. Skonfiguruj projekt za pomocą CMake:
   ```bash
   cmake -B build -S . -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr
   ```
3. Skompiluj kod:
   ```bash
   cmake --build build -j$(nproc)
   ```
4. Zainstaluj aplikację w systemie:
   ```bash
   sudo cmake --install build
   ```

### Uruchamianie
Program można uruchomić z menu systemowego lub wpisując w terminalu:
```bash
cctv-viewer2
```

---

## 2. Zarządzanie Rejestratorami NVR/DVR

Aby skonfigurować połączenie z rejestratorem Hikvision:
1. Otwórz panel boczny opcji i przejdź do zakładki **Rejestratory** (ikona serwera).
2. Wprowadź dane dostępowe urządzenia:
   * **Adres IP**: Adres sieciowy rejestratora.
   * **Port**: Port sieciowy SDK (domyślnie `8000`).
   * **Użytkownik**: Nazwa użytkownika (np. `admin`).
   * **Hasło**: Hasło dostępowe do rejestratora.
3. Kliknij **Połącz** (lub **Zapisz**).
4. Po pomyślnym połączeniu aplikacja automatycznie wykryje wszystkie aktywne kamery (kanały) podłączone do NVR/DVR i doda je do listy.
5. Kliknięcie przycisku **Generuj siatkę** automatycznie utworzy gotowy układ (preset) zawierający wszystkie działające kamery z danego NVR w optymalnym układzie siatki.
6. **Lokalna zmiana nazw kamer**: Na kafelku kamery na liście kamer rejestratora NVR kliknij ikonę **Edycji** (ołówka). Otworzy to okno dialogowe, w którym możesz wpisać nową nazwę dla danej kamery. Zmiana ta jest zapisywana lokalnie w programie i natychmiast aktualizuje nazwę na kafelku, na żywo w odtwarzaczach oraz na osi czasu odtwarzacza archiwalnego, bez modyfikacji fizycznych ustawień na urządzeniu NVR. W dowolnej chwili nazwę można przywrócić do domyślnej, klikając przycisk „Resetuj”.

---

## 3. Podgląd na Żywo (Live View)

Okno główne programu odpowiada za wyświetlanie obrazu na żywo:
* **Siatka kamer**: Wyświetla jednocześnie strumienie RTSP lub bezpośrednio z SDK Hikvision.
* **Wybór jakości strumienia**: Klikając prawym przyciskiem myszy na dany kafelek kamery, możesz wybrać strumień główny (**Main Stream**) o najwyższej rozdzielczości lub pomocniczy (**Sub Stream**) w celu zmniejszenia obciążenia sieci i karty graficznej.
* **Auto-ukrywanie paska górnego**: Pasek górny (topToolBar) może automatycznie zwijać się do górnej krawędzi ekranu po zjechaniu z niego kursorem myszy (opcja konfigurowalna w zakładce Ustawienia -> *„Automatycznie zwijaj pasek górny”* lub bezpośrednio za pomocą przycisku pinezki na pasku górnym).
* **Obsługa wielu monitorów i okien pomocniczych**: Aplikacja pozwala na otwieranie niezależnych, dodatkowych okien pomocniczych (tzw. Auxiliary Windows), co ułatwia jednoczesny podgląd różnych siatek kamer na wielu monitorach lub ekranach. Aby otworzyć nowe okno pomocnicze, użyj skrótu klawiszowego `Ctrl+N` lub kliknij przycisk **„NOWE OKNO”** na pasku narzędzi u góry ekranu. Każde z okien może mieć własny rozmiar siatki oraz wybrany układ presetów.

---

## 4. Układy Ekranu i Presety (Layouts & Presets)

Układy pozwalają organizować rozmieszczenie kamer na ekranie. Z poziomu zakładki **Układy** (ikona gwiazdki) możesz:
* **Tworzyć nowe presety**: Dodaj własny układ o dowolnej konfiguracji kolumn i wierszy (np. 2x2, 3x3, 4x4).
* **Przypisywać kamery**: Kliknij na wybrany kafelek w siatce głównej, aby go zaznaczyć (zostanie wyróżniony ramką), a następnie w oknie kamer NVR najedź na wybraną kamerę i kliknij przycisk **„+” (Dodaj)**. Pozycje kamer można również zamieniać, wybierając opcję **„Zamień miejscami”** z menu podręcznego (prawy przycisk myszy) na kafelki źródłowym, a następnie klikając lewym przyciskiem myszy na kafelek docelowy.
* **Elementy Kontroli paska górnego**:
  * **Pinezka**: Służy do zablokowania paska górnego w stanie wysuniętym (wbita pineska) lub włączenia automatycznego zwijania (pochylona pineska).
  * **Pełen ekran (zielona ikona)**: Przełącza tryb pełnoekranowy (strzałki rozszerzające) i okienkowy (strzałki zwężające).
  * **Minimalizuj (błękitna ikona)**: Minimalizuje okno programu na pasek zadań. Po przywróceniu okno powróci dokładnie do poprzedniego stanu (np. pełnego ekranu lub zmaksymalizowanego).
  * **Przełącznik blokady siatki**: Pozwala zablokować możliwość zmiany rozmiaru siatki (kłódeczka/przełącznik z tooltipem).
  * **Hamburger menu (trzy kreski)**: Otwiera dodatkowe narzędzia i opcje systemowe.
  * **Potwierdzenie zamknięcia**: Przechwytuje również kliknięcie systemowego przycisku zamknięcia okna na pasku tytułowym i wyświetla zapytanie o potwierdzenie.


---

## 5. Panel Statystyk Systemowych (System Stats)

Wysuwany z lewej krawędzi ekranu Live View panel służy do monitorowania kondycji komputera oraz obciążenia generowanego przez aplikację:
* **Monitorowane parametry**:
  * **CPU / RAM**: Zużycie procesora głównego (w % wszystkich rdzeni) oraz pamięci RAM zużywanej bezpośrednio przez proces `cctv-viewer2` i powiązane z nim podprocesy pobierające.
  * **GPU / VRAM**: Zużycie rdzenia karty graficznej (w %) oraz ilość pamięci graficznej VRAM zajmowanej przez renderowanie i sprzętowe dekodowanie (obsługuje pełny wykaz procesów graficznych za pomocą parsera XML z `nvidia-smi`).
  * **SIEĆ (Network)**: Rzeczywista prędkość transferu pobieranego przez aplikację ze wszystkich aktywnych odtwarzaczy na żywo, odtwarzaczy archiwum oraz procesów pobierania nagrań.
* **Wielowątkowość (Brak zacięć)**: Zbieranie danych o procesach i karcie GPU odbywa się na osobnym wątku systemowym (`StatsWorker`). Zapobiega to jakimkolwiek mikro-przycięciom w wyświetlaniu wideo (brak gubienia klatek).
* **Funkcja Przypięcia**: Kliknięcie przycisku **„Nie chowaj”** (ikona pineski) blokuje panel w stanie rozwiniętym.
* **Estetyka**: Wykresy posiadają jasne, neonowo-zielone obwódki, wypełnienie gradientowe pod krzywą wykresu oraz tło o zrównoważonej przezroczystości 35% zapewniające czytelność tekstu.

---

## 6. Odtwarzacz Archiwum Nagrań (Playback Archive)

Dostępny po kliknięciu ikony zegara/odtwarzania przy danej kamerze lub rejestratorze. Pozwala na jednoczesne przeglądanie nagrań archiwalnych z wielu kamer Hikvision w pełnej synchronizacji czasowej.

### Oś Czasu (Timeline):
* **Szybki start (15 minut wstecz)**: Przy otwarciu archiwum z widoku live, odtwarzacz automatycznie startuje od momentu wypadającego **dokładnie 15 minut przed aktualnym czasem systemowym** (zamiast od północy). Pozwala to na natychmiastowy podgląd zdarzenia, które przed chwilą miało miejsce.
* **Nawigacja**: Oś czasu można przesuwać w lewo i w prawo poprzez przeciąganie jej lewym klawiszem myszy.
* **Zoom (Skalowanie)**: Kółkiem myszy (lub przyciskami Zoom) można płynnie zmieniać skalę osi czasu – od widoku całego dnia do precyzyjnego podglądu z dokładnością do 10 minut.
* **Paski Dostępności Nagrań**: Pod osią czasu renderowane są kolorowe paski reprezentujące znalezione segmenty wideo na dysku rejestratora. System cache zapobiega ich migotaniu podczas przesuwania osi.
* **Auto-follow (Śledzenie wskaźnika)**: Wskaźnik odtwarzania (pionowa czerwona linia) jest stale monitorowany. Jeśli wskaźnik wyjdzie poza widoczny zakres osi czasu, widok automatycznie się przesunie i wyśrodkuje. Opcja ta jest inteligentnie blokowana na czas ręcznego przeciągania wskaźnika przez użytkownika.
* **Przycisk Ręcznego Centrowania**: Przycisk **„Wycentruj”** natychmiast przesuwa oś czasu tak, aby czerwona linia odtwarzania znalazła się dokładnie na środku ekranu.

---

## 7. Pobieranie Nagrań (Downloader)

Z poziomu okna Playback Archive możesz pobierać wybrane fragmenty nagrań bezpośrednio na dysk komputera do plików MP4:
1. Kliknij ikonę pobierania (strzałka w dół) przy wybranej kamerze.
2. Wybierz zakres czasu (początek i koniec nagrania).
3. Wybierz lokalizację zapisu pliku docelowego.
4. Kliknij **Pobierz**.

### Zaawansowane Funkcje Pobierania (wprowadzone w wersji 2.0.6):
* **Sekwencyjne pobieranie części (1GB)**: Program automatycznie dzieli zapytanie na fizyczne części (o rozmiarze ok. 1GB na dysku rejestratora) i pobiera oraz konwertuje je po kolei (jeden plik po drugim, za pomocą tymczasowych plików `.pspart` konwertowanych natychmiast na format `.mp4`). Pozwala to na stabilne pobieranie bardzo długich zakresów czasu bez ryzyka przepełnienia pamięci RAM lub zawieszenia konwersji FFmpeg.
* **Wizualizacja postępu całkowitego**: Pasek postępu (w kolorze jasnoturkusowym) prezentuje całkowity postęp pobierania dla danej kamery (dla wszystkich części łącznie). Status opisowy nałożony na pasek wskazuje aktualną część, np. `Pobieranie części 1 z 3... 45% (Całkowity: 15%)`, a specjalna czcionka z obrysem zapewnia pełną czytelność tekstu.
* **Oczyszczanie nazw plików**: Nazwy pobieranych plików wideo (oraz zrzutów ekranu) są automatycznie oczyszczane z adresów IP rejestratorów, pozostawiając czytelną nazwę i datę (np. `4_Wejscie_glowne_2026-06-15.mp4` zamiast `<IP_REJESTRATORA>_4_Wejscie...`).

---

## 8. Skróty Klawiszowe i Sterowanie Myszami

### Skróty klawiszowe:
| Klawisz / Kombinacja | Działanie |
|---|---|
| **F** | Włączenie / wyłączenie trybu pełnoekranowego (Full Screen). |
| **M** | Wyciszenie / odciszenie dźwięku (działa dla aktywnej kamery posiadającej audio). |
| **Spacja** | Start / Pauza odtwarzania w oknie Playback Archive. |
| **Alt + 1** do **Alt + 9** | Szybkie przełączenie na dany preset/układ o indeksie od 1 do 9. |
| **+** / **-** | Zbliżenie / Oddalenie (kamery Hikvision obsługujące PTZ). |
| **Esc** | Wyjście z trybu pełnoekranowego. |

### Interakcja myszą:
* **Lewy przycisk myszy**:
  * **Dwukrotne kliknięcie (Double-Click)** na kafelek kamery w siatce powiększa go na pełny ekran. Kolejne dwukrotne kliknięcie przywraca widok siatki.
  * Przeciąganie osi czasu w oknie Playback w celu nawigacji.
* **Prawy przycisk myszy (Context Menu)**:
  * Otwiera podręczne menu ustawień dla wybranego kafelka (umożliwia usuwanie kamery z siatki, zmianę strumienia Main/Sub czy wejście w indywidualne parametry wyświetlania).
* **Kółko myszy (Scroll Wheel)**:
  * Regulacja skali (Zoom) osi czasu w oknie odtwarzacza archiwum.

---

## 9. Wykonywanie Zrzutów Ekranu (Stopklatek) i Konfiguracja Ścieżek

Aplikacja umożliwia szybkie wykonywanie wysokiej jakości stopklatek z dowolnego kafelka kamery w trybie podglądu na żywo oraz odtwarzania archiwum.

### Wykonywanie Stopklatek:
1. W prawym dolnym rogu każdego kafelka kamery znajduje się ikona aparatu.
2. Kliknięcie ikony aparatu powoduje wykonanie zrzutu ekranu i zapisanie go jako obraz JPEG (jakość 98 - praktycznie bezstratna).
3. Pomyślne wykonanie zrzutu jest potwierdzane podświetleniem ikony aparatu na kolor pomarańczowy (`#ff7a00`) przez dokładnie 1 sekundę.
4. **Pełna rozdzielczość**: W trybie odtwarzania archiwum stopklatki są zapisywane w pełnej, natywnej rozdzielczości strumienia z pamięci podręcznej dekodera, bez względu na aktualną wielkość kafelka na ekranie i skalowanie okna.

### Konfiguracja Ścieżek Zapisu:
1. Przejdź do zakładki **Ustawienia** (ikona koła zębatego w panelu bocznym).
2. W sekcji **Zapis** znajdziesz pola tekstowe umożliwiające konfigurację domyślnych ścieżek zapisu:
   * **Domyślna ścieżka stopklatek**: Miejsce zapisu zrzutów (domyślnie `~/Obrazy/CCTV`).
   * **Domyślna ścieżka nagrań**: Miejsce zapisu pobieranych wideo (domyślnie `~/Wideo/CCTV`).
3. Kliknięcie przycisku `...` obok pola tekstowego otwiera natywne okno wyboru folderu systemu operacyjnego (Breeze w KDE).
4. **Działanie przycisku przeglądania**: Okno wyboru katalogu otwiera się bezpośrednio w katalogu wpisanym w polu tekstowym (jeśli istnieje). W przypadku braku wpisanej ścieżki, jej nieistnienia lub braku uprawnień, okno automatycznie startuje w katalogu domowym użytkownika (`~/`).

### Ustawienia Interfejsu Użytkownika (UI):
1. Przejdź do zakładki **Ustawienia** (ikona koła zębatego w panelu bocznym) lub otwórz okno **Opcje** u góry ekranu.
2. W nowo dodanej sekcji **Ustawienia interfejsu użytkownika** możesz dostosować widoczność elementów nakładanych na kafelki kamer (viewporty):
   * **Pokazuj status kanału w lewym górnym rogu viewportu** (domyślnie włączony) — wyświetla informacje o ładowaniu, odtwarzaniu i statusie połączenia strumienia.
   * **Pokazuj informację o kamerze w dolnym lewym rogu viewportu** (domyślnie włączony) — wyświetla nazwę kamery pobraną z rejestratora Hikvision.
   * **Pokazuj ikony sterowania w dolnym prawym rogu viewportu tylko po najechaniu kursorem na viewport** (domyślnie włączony) — automatycznie ukrywa panel przycisków sterujących (stopklatka, archiwum, tryb 1:1, powiększenie regionu), gdy kursor myszy znajduje się poza danym kafelkiem kamery. Ikony pokazują się natychmiast po przesunięciu wskaźnika myszy nad dany viewport (bez konieczności klikania), co zwiększa estetykę podglądu i nie przesłania detali obrazu. Po opuszczeniu kafelka ikony natychmiast znikają.

