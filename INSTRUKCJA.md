# Instrukcja Obsługi programu CCTV Viewer 2

**CCTV Viewer 2** to zaawansowana aplikacja przeznaczona do jednoczesnego podglądu strumieni wideo na żywo (RTSP/ONVIF) oraz integracji z rejestratorami NVR/DVR firmy Hikvision (zarówno w trybie Live, jak i odtwarzania archiwum Playback). 

Program został zoptymalizowany pod kątem stabilności, płynności działania (60 FPS) oraz minimalnego obciążenia zasobów systemowych.

---

## Spis Treści
1. [Instalacja i Uruchamianie](#1-instalacja-i-uruchamianie)
2. [Zarządzanie Rejestratorami NVR/DVR](#2-zarządzanie-rejestratorami-nvrdvr)
3. [Podgląd na Żywo (Live View) i Nakładki Viewportów](#3-podgląd-na-żywo-live-view-i-nakładki-viewportów)
4. [Układy Ekranu, Presety oraz Pasek Narzędziowy](#4-układy-ekranu-presety-oraz-pasek-narzędziowy)
5. [Panel Statystyk Systemowych (System Stats)](#5-panel-statystyk-systemowych-system-stats)
6. [Odtwarzacz Archiwum Nagrań (Playback Archive)](#6-odtwarzacz-archiwum-nagrań-playback-archive)
7. [Pobieranie Nagrań (Downloader)](#7-pobieranie-nagrań-downloader)
8. [Zaawansowane Ustawienia i Personalizacja w Panelu Opcji](#8-zaawansowane-ustawienia-i-personalizacja-w-panelu-opcji)
9. [Skróty Klawiszowe i Sterowanie Myszami](#9-skróty-klawiszowe-i-sterowanie-myszami)
10. [Wykonywanie Zrzutów Ekranu (Stopklatek) i Konfiguracja Ścieżek](#10-wykonywanie-zrzutów-ekranu-stopklatek-i-konfiguracja-ścieżek)

---

## 1. Instalacja i Uruchamianie

### Instalacja pakietu Arch Linux (Pacman)
Aby zainstalować program z przygotowanej paczki binarnej, przejdź do katalogu `packaging/arch/` i wykonaj:
```bash
sudo pacman -U cctv-viewer2-2.1.2-1-x86_64.pkg.tar.zst
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
6. **Wyświetlanie list kamer (NvrCamerasWindow)**: Kliknięcie przycisku z ikoną monitora komputerowego na kafelku danego rejestratora otwiera dedykowane okno z kafelkową listą wykrytych kamer.
7. **Generowanie miniatur (Generate thumbnails)**: W oknie kamer rejestratora dostępny jest przycisk *„Generate thumbnails”* (Generuj miniatury). Po jego kliknięciu program pobiera w tle pojedyncze klatki ze strumieni pomocniczych (Sub Stream) z rejestratora i ustawia je jako miniatury tła kafelków kamer, co pozwala na szybką orientację wizualną bez uruchamiania pełnego odtwarzania.
8. **Funkcja Kliknij i Przypisz (Click-and-Add)**: Program nie obsługuje przeciągania kafelków (drag and drop) z okna listy kamer na siatkę. Przypisywanie kamer odbywa się w prosty i niezawodny sposób: najpierw kliknij lewym przyciskiem myszy na wybrany viewport (kafelek) w siatce okna głównego, aby go zaznaczyć (podświetli się jasną ramką), a następnie w oknie listy kamer rejestratora kliknij zielony przycisk **„+” (Przypisz do aktywnego podglądu)** na kafelku żądanej kamery. Strumień zostanie natychmiast załadowany w wybranym slocie.
9. **Statusy zalogowania SDK (Wskaźnik kropki)**: Obok nazwy każdego rejestratora na liście znajduje się kolorowa kropka statusu:
   * **Zielona (LOGGED IN)**: Oznacza aktywne połączenie sesyjne SDK Hikvision (wymagane do operacji PTZ, obsługi archiwum i pobierania).
   * **Czerwona (NOT LOGGED IN)**: Brak aktywnego połączenia sesyjnego SDK (np. przed pierwszym żądaniem lub po wylogowaniu). Warto pamiętać, że strumienie na żywo (RTSP) działają niezależnie od statusu sesji SDK.
10. **Lokalna zmiana nazw kamer**: Na kafelku kamery na liście kamer rejestratora NVR kliknij ikonę **Edycji** (ołówka). Otworzy to okno dialogowe, w którym możesz wpisać nową nazwę dla danej kamery. Zmiana ta jest zapisywana lokalnie w programie i natychmiast aktualizuje nazwę na kafelku, na żywo w odtwarzaczach oraz na osi czasu odtwarzacza archiwalnego, bez modyfikacji fizycznych ustawień na urządzeniu NVR. W dowolnej chwili nazwę można przywrócić do domyślnej, klikając przycisk „Resetuj”.
11. **Usuwanie rejestratora z listy**: Na liście skonfigurowanych rejestratorów obok każdego urządzenia znajduje się czerwona ikona kosza. Kliknięcie jej uruchamia dwuetapową procedurę bezpieczeństwa mającą zapobiec przypadkowemu usunięciu:
    * **Krok 1 (Potwierdzenie usunięcia)**: Wyświetla się okno dialogowe *„Confirm NVR Deletion”* z zapytaniem, czy na pewno chcesz usunąć rejestrator.
    * **Krok 2 (Ostrzeżenie)**: Wyświetla się drugie okno ostrzegawcze *„Warning!”* z pytaniem, czy jesteś w pełni świadomy konsekwencji usunięcia.
    * **Skutek usunięcia**: Po zatwierdzeniu drugiego dialogu program wylogowuje się z danego rejestratora w tle, usuwa jego dane z konfiguracji aplikacji, a także **automatycznie czyści kolekcję presetów**, usuwając z niej wszystkie siatki wideo wygenerowane dynamicznie dla tego urządzenia.

---

## 3. Podgląd na Żywo (Live View) i Nakładki Viewportów

Okno główne programu odpowiada za wyświetlanie obrazu na żywo:
* **Siatka kamer**: Wyświetla jednocześnie strumienie RTSP lub bezpośrednio z SDK Hikvision.
* **Wybór jakości strumienia**: Klikając prawym przyciskiem myszy na dany kafelek kamery, możesz wybrać strumień główny (**Main Stream**) o najwyższej rozdzielczości lub pomocniczy (**Sub Stream**) w celu zmniejszenia obciążenia sieci i karty graficznej.
* **Szybkie przełączanie pełnego ekranu (Double-Click)**: Dwukrotne kliknięcie lewym przyciskiem myszy na dowolny kafelek kamery w siatce natychmiast maksymalizuje go na cały obszar wyświetlania (pełny ekran pojedynczego kafelka). Ponowne dwukrotne kliknięcie przywraca poprzednią siatkę wielu kamer.
* **Auto-ukrywanie paska górnego**: Pasek górny (topToolBar) może automatycznie zwijać się do górnej krawędzi ekranu po zjechaniu z niego kursorem myszy (opcja konfigurowalna w zakładce Ustawienia -> *„Automatycznie zwijaj pasek górny”* lub bezpośrednio za pomocą przycisku pinezki na pasku górnym).
* **Obsługa wielu monitorów i okien pomocniczych**: Aplikacja pozwala na otwieranie niezależnych, dodatkowych okien pomocniczych (tzw. Auxiliary Windows), co ułatwia jednoczesny podgląd różnych siatek kamer na wielu monitorach lub ekranach. Aby otworzyć nowe okno pomocnicze, użyj skrótu klawiszowego `Ctrl+N` lub kliknij przycisk **„NOWE OKNO”** na pasku narzędzi u góry ekranu. Każde z okien może mieć własny rozmiar siatki oraz wybrany układ presetów.

### Przyciski Sterujące na Kafelkach (Viewportach)
W prawym dolnym rogu każdego kafelka kamery po najechaniu na niego kursorem myszy (zależnie od ustawień interfejsu) wyświetla się nakładkowy panel zawierający cztery funkcjonalne ikony sterowania:
1. **Ikona Aparatu (Stopklatka)**: Umożliwia wykonanie zrzutu ekranu z kamery. Zrzut jest zapisywany w pełnej, natywnej rozdzielczości strumienia bezpośrednio z dekodera, bez strat wynikających z aktualnego rozmiaru okna lub skalowania na ekranie. Pomyślne zapisanie stopklatki potwierdzane jest rozbłyskiem ikony aparatu na kolor pomarańczowy (`#ff7a00`) przez dokładnie 1 sekundę.
2. **Ikona Play (Archiwum)**: Służy do szybkiego przejścia do odtwarzacza archiwalnego. Po kliknięciu automatycznie uruchamia okno osi czasu `PlaybackWindow` dla tej konkretnej kamery, rozpoczynając odtwarzanie **dokładnie 15 minut przed aktualnym czasem systemowym** (wygodny offset wsteczny).
3. **Ikona 1:1 (Skalowanie natywne)**: Przełącza tryb wyświetlania wideo piksel-w-piksel. Po włączeniu obraz nie jest rozciągany do granic kafelka, lecz wyświetlany w swojej oryginalnej, niezniekształconej rozdzielczości na środku obszaru viewportu. Gdy tryb jest aktywny, tło przycisku i napis podświetlają się na jaskrawy kolor jasnoturkusowy.
4. **Ikona Lupy (Interaktywne Powiększenie)**: Pozwala na przybliżenie wybranego regionu wideo:
   * **Aktywacja**: Kliknięcie ikony przełącza przycisk w stan aktywny (podświetlenie na turkusowo). Kursor zmienia kształt, a tooltip instruuje: *„Kliknij i przeciągnij po obrazie kamery, aby przybliżyć”*.
   * **Działanie**: Użytkownik zaznacza lewym przyciskiem myszy prostokątny obszar na obrazie. Viewport automatycznie kadruje i powiększa wybrany fragment tak, by wypełnił cały kafelek.
   * **Reset**: Gdy obraz jest przybliżony, ikona lupy zmienia swój wygląd (czerwona obwódka i minus w środku). Kliknięcie jej natychmiast resetuje przybliżenie i przywraca pełen kadr kamery.

---

## 4. Układy Ekranu, Presety oraz Pasek Narzędziowy

Układy pozwalają organizować rozmieszczenie kamer na ekranie. Z poziomu zakładki **Układy** (ikona gwiazdki) możesz:
* **Tworzyć nowe presety**: Dodaj własny układ o dowolnej konfiguracji kolumn i wierszy (np. 2x2, 3x3, 4x4).
* **Przypisywać kamery**: Kliknij na wybrany kafelek w siatce głównej, aby go zaznaczyć (zostanie wyróżniony ramką), a następnie w oknie kamer NVR najedź na wybraną kamerę i kliknij przycisk **„+” (Dodaj)**. Pozycje kamer można również zamieniać, wybierając opcję **„Zamień miejscami”** z menu podręcznego (prawy przycisk myszy) na kafelki źródłowym, a następnie klikając lewym przyciskiem myszy na kafelek docelowy.

### Przyciski Paska Górnego (Top Tool Bar)
Pasek górny zawiera kompletny zestaw kontrolek nawigacyjnych i funkcyjnych aplikacji:
1. **Zamknięcie Okna (Czerwony przycisk ✕)**: Zamyka aktywne okno. W celu zapobieżenia przypadkowym kliknięciom przechwytuje zdarzenie zamknięcia i wyświetla okno dialogowe z prośbą o potwierdzenie wyjścia z programu.
2. **Pinezka (Pin Bar)**: Kontroluje mechanizm automatycznego zwijania paska górnego. Gdy pinezka jest ustawiona pionowo (stan przypięty), pasek górny jest stale zablokowany w pozycji wysuniętej. Gdy pinezka jest obrócona o -45 stopni (stan odpięty), pasek automatycznie wsuwa się pod górną krawędź ekranu po opuszczeniu go przez kursor myszy.
3. **Pełen Ekran (Zielona ikona strzałek)**: Służy do błyskawicznego przełączania aktywnego okna w tryb pełnoekranowy i z powrotem. W trybie pełnoekranowym strzałki są skierowane do wewnątrz (zwężenie), a w okienkowym na zewnątrz (rozszerzenie).
4. **Minimalizuj (Błękitna ikona minimalizacji)**: Minimalizuje okno programu na pasek zadań systemu operacyjnego. Po przywróceniu okno powraca dokładnie do swojego poprzedniego stanu (np. zmaksymalizowanego lub pełnoekranowego).
5. **⚙️ OPCJE**: Otwiera wysuwane z lewej krawędzi okno ustawień, rejestratorów, presetów i dziennika zmian. Jeżeli panel boczny jest już otwarty, przycisk zamyka go.
6. **📺 NOWE OKNO**: Otwiera nowe, niezależne i w pełni konfigurowalne okno pomocnicze (`Auxiliary Window`), idealne do rozciągnięcia podglądu kamer na konfiguracjach wielomonitorowych.
7. **ARCHIVE**: Otwiera pusty odtwarzacz archiwum nagrań (`PlaybackWindow`) z aktywną osią czasu i kalendarzem, umożliwiając ręczny wybór kanałów i kamer z dowolnego rejestratora z poziomu listy bocznej.
8. **INSTRUKCJA**: Uruchamia to okno pomocy technicznej zawierające pełną dokumentację użytkownika w języku polskim lub angielskim (zależnie od wybranej lokalizacji).
9. **Przełącznik 📊 STATYSTYKI**: Suwak włączający/wyłączający wysuwany z lewej krawędzi ekranu panel monitoringu zużycia zasobów komputera.
10. **Przełącznik Blokady Siatki (Kłódeczka)**: Przełącznik, który po włączeniu (podświetlenie suwaka na jaskrawy pomarańczowy kolor) blokuje możliwość klikania i zmieniania rozmiaru siatki podglądu za pomocą sąsiednich przycisków siatki, zabezpieczając aktywny układ przed przypadkowym zniekształceniem.
11. **Przycisk Rozmiarów Siatki (od 1x1 do 9x9)**: Zestaw dziewięciu przycisków umożliwiających błyskawiczne zdefiniowanie liczby kolumn i wierszy siatki (od pojedynczej kamery 1x1, aż do jednoczesnego wyświetlania 81 kamer w układzie 9x9). Aktywny rozmiar podświetla się na pomarańczowo.
12. **Więcej Opcji (Hamburger Menu z trzema kreskami)**: Przycisk otwierający wyskakujące okienko `Layout & Grid Tools` (Narzędzia Układu i Siatki), umożliwiające zaawansowaną parametryzację siatki (szczegółowy opis poniżej).
13. **Przyciski Presetów/Widoków**: Dynamicznie renderowane przyciski na prawym skraju paska górnego, odzwierciedlające zdefiniowane i włączone w opcjach presety układów kamer (np. *📹 Rejestrator*, *Widok 1*, itp.). Kliknięcie przycisku natychmiast przełącza siatkę na przypisany preset. Aktywny widok podświetla się na jaskrawy turkusowy kolor.

### Zaawansowana parametryzacja siatki i proporcji (Layout & Grid Tools)
Po otwarciu panelu hamburgera (Więcej opcji) pojawia się dedykowany przybornik narzędziowy. Aby aktywować jego funkcje:
1. **Odblokowanie panelu (Unlock tools pane)**: Należy zaznaczyć przełącznik na samej górze panelu. Zabezpiecza to przed przypadkową zmianą zaawansowanych parametrów układu ekranu.
2. **Niestandardowy podział siatki (Window Division - F2 / Przytrzymanie)**: Panel wyświetla przyciski siatki od 1x1 do 9x9. Cechą unikalną tego okna jest możliwość **edytowania domyślnych rozmiarów podziału**. Jeśli klikniesz i przytrzymasz dany przycisk lewym klawiszem myszy (oraz zaznaczysz go i naciśniesz klawisz **F2**), otworzy się pole tekstowe. Możesz w nim wpisać własny, asymetryczny lub niestandardowy podział (np. `2x3`, `1x4` itp.) i zatwierdzić klawiszem Enter. Przycisk zostanie natychmiast przeprogramowany, a kliknięcie go zmieni siatkę na zdefiniowaną przez Ciebie.
3. **Proporcje geometrii siatki (Geometry Ratio)**: Umożliwia wymuszenie proporcji wyświetlania całej siatki:
   * **16:9 Aspect Ratio**: Blokuje i dopasowuje okno siatki do szerokiego formatu kinowego 16:9 (standard dla większości kamer IP).
   * **4:3 Aspect Ratio**: Dopasowuje siatkę do klasycznego formatu kwadratowego 4:3 (częsty dla starszych kamer analogowych/IP).
4. **Operacje na siatce (Merge Highlighted Cells)**: Umożliwia asymetryczne scalanie komórek (szczegółowo opisane w Sekcji 8.2).

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

### Oś Czasu (Timeline) i sterowanie:
* **Szybki start (15 minut wstecz)**: Przy otwarciu archiwum z widoku live, odtwarzacz automatycznie startuje od momentu wypadającego **dokładnie 15 minut przed aktualnym czasem systemowym** (zamiast od północy). Pozwala to na natychmiastowy podgląd zdarzenia, które przed chwilą miało miejsce.
* **Nawigacja**: Oś czasu można przesuwać w lewo i w prawo poprzez przeciąganie jej lewym klawiszem myszy.
* **Zoom (Skalowanie)**: Kółkiem myszy (lub przyciskami Zoom) można płynnie zmieniać skalę osi czasu – od widoku całego dnia do precyzyjnego podglądu z dokładnością do 10 minut.
* **Skróty szybkiego zoomu**: Na dolnym pasku kontrolnym znajdują się przyciski pozwalające na błyskawiczne przeskalowanie osi czasu do wybranego wycinka:
  * **„Ostatnia 1h”**: Skaluje widok osi czasu do szczegółowego podglądu z rozdzielczością 1 godziny.
  * **„Ostatnie 8h”**: Skaluje oś czasu do wycinka 8-godzinnego.
  * **„Cały dzień”**: Resetuje zbliżenie i pokazuje pełne 24 godziny na jednym ekranie.
* **Nawigacja datami (Kalendarz i Dni)**: Obok wyświetlanej daty znajdują się przyciski sterujące:
  * **Przycisk „<” (Poprzedni dzień)** oraz **„>” (Następny dzień)**: Pozwalają na szybkie przeskoczenie o 24 godziny wstecz lub w przód bez otwierania kalendarza.
  * **Przycisk „Dzisiaj”**: Natychmiast przestawia aktywną datę i kalendarz na bieżący dzień dzisiejszy.
* **Przycisk „Odśwież” (Czyszczenie cache)**: Służy do wymuszenia ponownego wyszukiwania nagrań. Jeśli klikniesz ten przycisk, program wyczyści lokalną pamięć podręczną (cache) segmentów nagrań dla wszystkich aktualnie otwartych kanałów i wyśle nowe zapytania do rejestratora, co jest przydatne do zaktualizowania najświeższych plików nagranych przed chwilą.
* **Paski Dostępności Nagrań**: Pod osią czasu renderowane są kolorowe paski reprezentujące znalezione segmenty wideo na dysku rejestratora. System cache zapobiega ich migotaniu podczas przesuwania osi.
* **Auto-follow (Śledzenie wskaźnika)**: Wskaźnik odtwarzania (pionowa czerwona linia) jest stale monitorowany. Jeśli wskaźnik wyjdzie poza widoczny zakres osi czasu, widok automatycznie się przesunie i wyśrodkuje. Opcja ta jest inteligentnie blokowana na czas ręcznego przeciągania wskaźnika przez użytkownika.
* **Przycisk Ręcznego Centrowania**: Przycisk **„Wycentruj”** natychmiast przesuwa oś czasu tak, aby czerwona linia odtwarzania znalazła się dokładnie na środku ekranu.

### Panel boczny kamer w oknie archiwum
W prawej części okna odtwarzacza archiwum znajduje się pionowa lista zawierająca wszystkie dodane do programu rejestratory NVR wraz z ich kamerami:
* **Włączanie i wyłączanie kanałów**: Kliknięcie na dany kanał (kamerę) na liście dodaje go jako aktywny element na osi czasu archiwum (otwierając dla niego nowy odtwarzacz wideo). Ponowne kliknięcie usuwa kanał z osi.
* **Menu podręczne kanałów**: Kliknięcie prawym przyciskiem myszy na aktywnym slocie wideo w oknie archiwum pozwala na:
  * Przełączanie jakości odtwarzanego wideo (Main Stream / Sub Stream).
  * Całkowite zamknięcie (usunięcie) danego odtwarzacza z siatki archiwalnej.

---

## 7. Pobieranie Nagrań (Downloader)

Z poziomu okna Playback Archive możesz pobierać wybrane fragmenty nagrań bezpośrednio na dysk komputera do plików MP4:
1. Kliknij ikonę pobierania (strzałka w dół) przy wybranej kamerze.
2. Wybierz zakres czasu (początek i koniec nagrania).
3. Wybierz lokalizację zapisu pliku docelowego.
4. Kliknij **Pobierz**.

### Zaawansowane Funkcje Pobierania:
* **Sekwencyjne pobieranie części (1GB)**: Program automatycznie dzieli zapytanie na fizyczne części (o rozmiarze ok. 1GB na dysku rejestratora) i pobiera oraz konwertuje je po kolei (jeden plik po drugim, za pomocą tymczasowych plików `.pspart` konwertowanych natychmiast na format `.mp4`). Pozwala to na stabilne pobieranie bardzo długich zakresów czasu bez ryzyka przepełnienia pamięci RAM lub zawieszenia konwersji FFmpeg.
* **Wizualizacja postępu całkowitego**: Pasek postępu (w kolorze jasnoturkusowym) prezentuje całkowity postęp pobierania dla danej kamery (dla wszystkich części łącznie). Status opisowy nałożony na pasek wskazuje aktualną część, np. `Pobieranie części 1 z 3... 45% (Całkowity: 15%)`, a specjalna czcionka z obrysem zapewnia pełną czytelność tekstu.
* **Oczyszczanie nazw plików**: Nazwy pobieranych plików wideo (oraz zrzutów ekranu) są automatycznie oczyszczane z adresów IP rejestratorów, pozostawiając czytelną nazwę i datę (np. `4_Wejscie_glowne_2026-06-15.mp4` zamiast `<IP_REJESTRATORA>_4_Wejscie...`).

---

## 8. Zaawansowane Ustawienia i Personalizacja w Panelu Opcji

Wysuwany z lewej krawędzi panel opcji (`SideBar`) dzieli się na sześć dedykowanych sekcji konfiguracji:

### 1. Szczegóły Viewportu (Viewport Details - ikona monitora)
Wyświetla zaawansowane parametry wybranego kafelka siatki. Umożliwia:
* Wpisanie własnego adresu **głównego strumienia RTSP** (Primary Stream URL) oraz **strumienia zapasowego** (Secondary Backup URL).
* Włączenie/wyłączenie wyciszenia audio dla wybranej kamery.
* Wprowadzenie zaawansowanych parametrów dekodowania za pomocą pola **Nadpisanie parametrów FFmpeg** (FFmpeg Options Override).

### 2. Układy i Siatka (Layout & Grid Tools - ikona suwaków)
Zaawansowane opcje manipulacji siatką ekranu:
* Szybkie przełączanie pełnego ekranu.
* **Asymetryczne Scalanie Komórek (Merge Highlighted Cells)**: Jedna z najbardziej zaawansowanych funkcji aplikacji. Umożliwia użytkownikowi zaznaczenie kilku sąsiadujących kafelków w siatce (poprzez kliknięcie z przytrzymanym klawiszem **Ctrl** lub **Shift**, bądź za pomocą klawiatury trzymając **Shift** i nawigując strzałkami), a następnie scalenie ich w jedną, dużą komórkę. Pozwala to na projektowanie dowolnych asymetrycznych układów, gdzie np. jedna ważna kamera jest ogromna, a poboczne są mniejsze.

### 3. Rejestrator (Recorders - ikona serwera)
Pełny menedżer konfiguracji połączeń z urządzeniami NVR/DVR Hikvision (szczegółowo opisany w Sekcji 2).

### 4. Presety (Presets - ikona gwiazdki)
Zarządzanie zapisanymi siatkami i konfiguracjami kamer. Umożliwia tworzenie pustych presetów o zadanym rozmiarze siatki, zmianę ich kolejności, ukrywanie ich na pasku górnym (przełącznik „Visible”) oraz ich aktywowanie w bieżącym oknie.

### 5. Ustawienia Systemowe (Settings - ikona koła zębatego)
Pozwala dostosować parametry globalne programu:
* **Uruchamianie wielu instancji**: Opcja *„Zezwalaj na uruchamianie wielu instancji aplikacji”* pozwala na jednoczesne otwarcie wielu kopii programu (domyślnie program działa w trybie pojedynczej instancji).
* **Automatyczne zwijanie**: Opcje regulacji zachowania autozwijania paska górnego oraz panelu statystyk.
* **Zamiana kafelków miejscami**: Opcja *„Zezwalaj na zamianę kafelków miejscami”* pozwala na intuicyjne przestawianie układu kamer w siatce (klikasz prawym na kafelek źródłowy -> Wybierasz "Zamień miejscami" -> Klikasz lewym na kafelek docelowy).
* **Zezwolenia menu podręcznego**: Zestaw przełączników pozwalający zablokować lub odblokować funkcje dostępne pod prawym przyciskiem myszy na kafelku (Włącz menu podręczne, Zezwalaj na zamianę kafelków miejscami, Włącz usuwanie kamer z siatki, Zezwalaj na edycję parametrów strumieni, Włącz szybką jakość Main/Sub).
* **Automatyczne odciszanie**: Funkcja automatycznie odciszająca audio kamery po wejściu w tryb pełnoekranowy.
* **Ukrywanie kursora w trybie pełnoekranowym**: Opcja *„Ukryj kursor w trybie pełnoekranowym”* automatycznie ukrywa kursor myszy po okresie bezczynności, gdy obraz jest wyświetlany w trybie pełnoekranowym, aby nie przesłaniać monitorowanego kadru.
* **Wybór Języka (Language)**: Pozwala na natychmiastową zmianę języka aplikacji (Domyślny systemowy, Polski, Angielski).
* **Ustawienia Interfejsu (UI)**: Opisane w Sekcji 10 opcje dostosowania widoczności nakładek informacyjnych na viewportach (np. ukrywanie kontrolek w prawym dolnym rogu viewportu tylko po najechaniu kursorem).

### 6. Changelog (Dziennik zmian - ikona dokumentu z zegarem)
Prezentuje interaktywny i uporządkowany rejestr historycznych oraz bieżących aktualizacji, poprawek błędów i nowych funkcji aplikacji, dzięki czemu użytkownik ma zawsze pod ręką pełną wiedzę o zmianach w programie.

---

## 9. Skróty Klawiszowe i Sterowanie Myszami

### Skróty klawiszowe:
| Klawisz / Kombinacja | Działanie |
|---|---|
| **F** / **F11** | Włączenie / wyłączenie trybu pełnoekranowego (Full Screen). |
| **M** | Wyciszenie / odciszenie dźwięku (działa dla aktywnej kamery posiadającej audio). |
| **Spacja** | Start / Pauza odtwarzania w oknie Playback Archive. |
| **Alt + 1** do **Alt + 9** | Szybkie przełączenie na dany preset/układ o indeksie od 1 do 9. |
| **Alt + Strzałka w lewo** | Szybkie przełączenie na poprzedni preset/układ w kolekcji. |
| **Alt + Strzałka w prawo** | Szybkie przełączenie na kolejny preset/układ w kolekcji. |
| **Strzałki (Góra/Dół/Lewo/Prawo)** | Nawigacja i przenoszenie aktywnego zaznaczenia (focusa) pomiędzy kafelkami kamer (viewportami). |
| **Shift + Strzałki** | Zaznaczanie wielu sąsiadujących kafelków kamer jednocześnie (używane m.in. do scalania komórek). |
| **Ctrl + N** | Otwarcie nowego, niezależnego okna pomocniczego (Auxiliary Window). |
| **+** / **-** | Zbliżenie / Oddalenie (kamery Hikvision obsługujące PTZ). |
| **Esc** | Wyjście z trybu pełnoekranowego / anulowanie aktywnego zaznaczenia kafelka. |

### Interakcja myszą:
* **Lewy przycisk myszy**:
  * **Dwukrotne kliknięcie (Double-Click)** na kafelek kamery w siatce powiększa go na pełny ekran. Kolejne dwukrotne kliknięcie przywraca widok siatki.
  * Przeciąganie osi czasu w oknie Playback w celu nauki i nawigacji.
* **Prawy przycisk myszy (Context Menu)**:
  * Otwiera podręczne menu ustawień dla wybranego kafelka (umożliwia usuwanie kamery z siatki, zmianę strumienia Main/Sub czy wejście w indywidualne parametry wyświetlania).
* **Kółko myszy (Scroll Wheel)**:
  * Regulacja skali (Zoom) osi czasu w oknie odtwarzacza archiwum.

---

## 10. Wykonywanie Zrzutów Ekranu (Stopklatek) i Konfiguracja Ścieżek

Aplikacja umożliwia szybkie wykonywanie wysokiej jakości stopklatek z dowolnego kafelka kamery w trybie podglądu na żywo oraz odtwarzania archiwum.

### Wykonywanie Stopklatek:
1. W prawym dolnym rogu każdego kafelka kamery znajduje się ikona aparatu (szczegółowo opisana w Sekcji 3).
2. Kliknięcie ikony aparatu powoduje wykonanie zrzutu ekranu i zapisanie go jako obraz JPEG (jakość 98 - praktycznie bezstratna).
3. Pomyślne wykonanie zrzutu jest potwierdzane podświetleniem ikony aparatu na kolor pomarańczowy (`#ff7a00`) przez dokładnie 1 sekundę.
4. **Pełna rozdzielczość**: W trybie odtwarzania archiwum stopklatki są zapisywane w pełnej, natywnej rozdzielczości strumienia z pamięci podręcznej dekodera, bez względu na aktualną wielkość kafelka na ekranie i skalowanie okna.

### Konfiguracja Ścieżek Zapisu:
1. Przejdź do zakładki **Ustawienia** (ikona koła zębatego w panelu bocznym).
2. W seki **Zapis** znajdziesz pola tekstowe umożliwiające konfigurację domyślnych ścieżek zapisu:
   * **Domyślna ścieżka stopklatek**: Miejsce zapisu zrzutów (domyślnie `~/Obrazy/CCTV`).
   * **Domyślna ścieżka nagrań**: Miejsce zapisu pobieranych wideo (domyślnie `~/Wideo/CCTV`).
3. Kliknięcie przycisku `...` obok pola tekstowego otwiera natywne okno wyboru folderu systemu operacyjnego (Breeze w KDE).
4. **Działanie przycisku przeglądania**: Okno wyboru katalogu otwiera się bezpośrednio w katalogu wpisanym w polu tekstowym (jeśli istnieje). W przypadku braku wpisanej ścieżki, jej nieistnienia lub braku uprawnień, okno automatycznie startuje w katalogu domowym użytkownika (`~/`).

### Ustawienia Interfejsu Użytkownika (UI):
1. Przejdź do zakładki **Ustawienia** (ikona koła zębatego w panelu bocznym) lub otwórz okno **Opcje** u góry ekranu.
2. In nowo dodanej sekcji **Ustawienia interfejsu użytkownika** możesz dostosować widoczność elementów nakładanych na kafelki kamer (viewporty):
   * **Pokazuj status kanału w lewym górnym rogu viewportu** (domyślnie włączony) — wyświetla informacje o ładowaniu, odtwarzaniu i statusie połączenia strumienia.
   * **Pokazuj informację o kamerze w dolnym lewym rogu viewportu** (domyślnie włączony) — wyświetla nazwę kamery pobraną z rejestratora Hikvision.
   * **Pokazuj ikony sterowania w dolnym prawym rogu viewportu tylko po najechaniu kursorem na viewport** (domyślnie włączony) — automatycznie ukrywa panel przycisków sterujących (stopklatka, archiwum, tryb 1:1, powiększenie regionu), gdy kursor myszy znajduje się poza danym kafelkiem kamery. Ikony pokazują się natychmiast po przesunięciu wskaźnika myszy nad dany viewport (bez konieczności klikania), co zwiększa estetykę podglądu i nie przesłania detali obrazu. Po opuszczeniu kafelka ikony natychmiast znikają.
   * **Pokazuj pola informacyjne tylko po najechaniu kursorem na viewport** (domyślnie wyłączony) — analogiczna funkcja ukrywająca status w lewym górnym rogu oraz nazwę w lewym dolnym rogu viewportu, pozostawiając czysty kadr kamery, dopóki kursor myszy nie znajdzie się nad danym kafelkiem.
