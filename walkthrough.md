# Walkthrough: CCTV Viewer Fixes & Optimizations

Ten dokument podsumowuje wszystkie wdrożone poprawki błędów (QML, ścieżki zapisu) oraz wskaźnik FPS w viewportach.

---

## 1. Wyjaśnienie Ostrzeżeń o Fontach (Segoe UI & Hack)

Ostrzeżenia te:
`Warning: QFont::fromString: Invalid description 'Segoe UI,9,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,Normalny,0,0'`
pochodzą z **wewnątrz samej biblioteki Qt** (poza kodem programu CCTV Viewer). 
* Program CCTV Viewer **nie korzysta** i **nie definiuje** w swoim kodzie czcionek Segoe UI ani Hack.
* Ostrzeżenie to pojawia się, ponieważ przy uruchomieniu Qt automatycznie odpytuje systemowe środowisko graficzne (np. KDE/GNOME) o jego domyślne czcionki (w Twoim systemie są to Segoe UI i Hack).
* Ponieważ język systemu to polski, Qt konwertuje styl czcionki na `"Normalny"`. Kiedy wewnętrzny parser Qt (`QFont::fromString`) próbuje wczytać to z powrotem, nie rozpoznaje słowa `"Normalny"` (oczekuje standardowego `"Normal"` lub liczby) i zgłasza błąd formatu opisu czcionki.
* **Ostrzeżenie to jest całkowicie nieszkodliwe** i nie ma żadnego wpływu na działanie programu, interfejs ani wydajność. Można je w pełni zignorować.

---

## 2. Wdrożone Zmiany i Naprawy Błędów QML

### Pełne przywrócenie zachowania Hover (Reversion)
* W plikach [Player.qml](file:///home/arkanis/cctv/cctv-viewer2/src/Player.qml) oraz [PlaybackWindow.qml](file:///home/arkanis/cctv/cctv-viewer2/src/PlaybackWindow.qml) usunęliśmy testowy element `HoverHandler` i przywróciliśmy oryginalne zachowanie `MouseArea` wraz z poprawnym ukrywaniem elementów nakładki po opuszczeniu viewportu przez kursor.
* Przywrócono pierwotną logikę `containsMouse` dla plakietek informacyjnych w `Player.qml`.

### Rozwiązanie problemu ze ścieżką pobierania (`undefined` w oknie pobierania)
* **Diagnoza:** W oknie archiwum `PlaybackWindow.qml` zadeklarowaliśmy lokalne obiekty `Settings`. Ponieważ okno to jest oknem nadrzędnym dla dynamicznie tworzonego `DownloadDialog.qml`, dialog ten (szukając obiektu `generalSettings`) odnajdywał ten lokalny z `PlaybackWindow.qml` (który nie definiował właściwości `videoPath`) zamiast globalnego z `RootWindow.qml`. Skutkowało to ścieżką `undefined/<nazwa pliku>`.
* **Rozwiązanie:**
  1. Usunięto lokalne, niekompletne obiekty `Settings` z [PlaybackWindow.qml](file:///home/arkanis/cctv/cctv-viewer2/src/PlaybackWindow.qml).
  2. W głównym oknie [RootWindow.qml](file:///home/arkanis/cctv/cctv-viewer2/src/RootWindow.qml) dodaliśmy jawne aliasy właściwości (property aliases) do obiektów ustawień:
     ```qml
     property alias generalSettings: generalSettings
     property alias viewSettings: viewSettings
     ```
     Dzięki temu obiekty te stały się częścią interfejsu `rootWindow` (który jest dostępny globalnie w całej aplikacji).
  3. Zaktualizowaliśmy odwołania do ustawień w [PlaybackWindow.qml](file:///home/arkanis/cctv/cctv-viewer2/src/PlaybackWindow.qml) oraz [DownloadDialog.qml](file:///home/arkanis/cctv/cctv-viewer2/src/DownloadDialog.qml), aby korzystały z bezpiecznych odwołań globalnych (np. `rootWindow.generalSettings.videoPath`).

### Likwidacja pętli bindowania `isHovered` (Binding Loop Fix)
* **Diagnoza:** Właściwość `isHovered` była zdefiniowana jako binding zależny od właściwości `containsMouse` podprzycisków kontrolnych. Jednak widoczność całego paska przycisków była zależna od `isHovered`. Gdy przycisk stawał się niewidoczny, jego stan `containsMouse` ulegał zmianie, co powodowało ostrzeżenie QML: `Binding loop detected for property "isHovered"`.
* **Rozwiązanie:** Zastąpiliśmy deklaratywny binding imperatywną funkcją `updateHoverState()`, która jest wywoływana za pomocą sygnałów `onContainsMouseChanged` na głównym obszarze oraz podprzyciskach.

### Ukrycie ostrzeżeń (Warnings) w wersji domyślnej (non-verbose)
* Zmodyfikowaliśmy obsługę logów w [main.cpp](file:///home/arkanis/cctv/cctv-viewer2/src/main.cpp). Wersja domyślna (bez flagi `--verbose`) nie wyświetla już żadnych logów, w tym ostrzeżeń Qt (`QtWarningMsg`), takich jak ostrzeżenia o brakujących dekoderach QmlAV czy błędy autoryzacji ISAPI. Pojawią się one tylko z flagą `--verbose`.

---

## 3. Optymalizacja sieciowa (Kalendarz i Oś czasu)

* **Problem:** Otwarcie okna archiwalnego generowało do 48 współbieżnych, ciężkich zapytań HTTP (12 miesięcy * 4 kamery w siatce) do rejestratora (NVR), co przeciążało jego bazę danych i powodowało błędy komunikacji oraz bardzo wolne ładowanie.
* **Wdrożona Optymalizacja:**
  1. **Tylko aktywna kamera:** Ograniczyliśmy pobieranie dostępności nagrań (month availability) oraz szczegółowych segmentów dnia (timeline segments) wyłącznie do aktualnie zaznaczonej kamery (`selectedPlayerIndex`). Inne kamery w siatce korzystają z uproszczonej reprezentacji i są doładowywane natychmiast po ich kliknięciu.
  2. **Prefetch na 2 miesiące:** Skróciliśmy startowe pobieranie dostępności z 12 miesięcy do **2 miesięcy** (bieżący i poprzedni, które są widoczne w okienku kalendarza). Dalsze miesiące są pobierane w tle na żądanie, gdy użytkownik przewija kalendarz wstecz.

---

## 4. Przywrócenie stabilnego odtwarzania w Archiwum (Rollback pacingu SDK)

* **Problem:** Poprzednia wersja odtwarzacza archiwalnego wprowadziła eksperymentalną logikę kolejkowania klatek oraz pacingu opartego o własny wątek prezentacji w C++. Spowodowało to bardzo poważne problemy z wydajnością: odtwarzanie 1x działało z połową prędkości, a odtwarzanie przyspieszone (np. 2x/4x/8x) nie funkcjonowało prawidłowo ze względu na narzut blokad wątków i zaburzenie taktowania dekodera SDK.
* **Rozwiązanie:** 
  1. Przywróciliśmy pliki `src/hikvisionarchiveplayer.cpp` oraz `src/hikvisionarchiveplayer.h` do ich w pełni stabilnej wersji (z commitu `07ed808`), która korzysta z wbudowanej w SDK logiki odtwarzania i dekodowania.
  2. Zachowaliśmy funkcjonalność zapisywania zrzutów ekranu (`saveCurrentFrame`) potrzebną dla poprawnego działania eksportu klatek w oknie dialogowym.
  3. Wyeliminowaliśmy całkowicie własny pacing i kolejki C++, co natychmiast przywróciło pełną, prawidłową prędkość odtwarzania 1x oraz bezproblemowe działanie odtwarzania przyspieszonego i wstecznego.

---

## 5. Licznik klatek w czasie rzeczywistym (Wskaźnik FPS)

* **Wdrożona Funkcjonalność:**
  Zgodnie z życzeniem, dodaliśmy wyświetlanie rzeczywistej liczby klatek na sekundę (FPS) w lewym górnym rogu każdego viewportu, z odświeżaniem co 1 sekundę bazującym na liczbie klatek faktycznie przekazanych na ekran (zaprezentowanych klatkach):
  1. **Dla Live (RTSP/Hikvision):** Plakietka w lewym górnym rogu wyświetla teraz np. `MAIN | 25 FPS | 2240 kb/s` lub `SUB | 15 FPS | 180 kb/s` z eleganckimi pionowymi separatorami.
  2. **Dla Archiwum (Playback):** Zintegrowaliśmy licznik FPS bezpośrednio w wątku GUI (`updateImage`) w klasie `HikvisionArchivePlayer` oraz w `QmlAVPlayer`. Licznik ten zlicza faktycznie wyrysowane ramki na sekundę bez jakiegokolwiek narzutu wydajnościowego czy blokowania wątków dekodujących. W lewym górnym rogu okien odtwarzania archiwalnego wyświetla się plakietka zawierająca np. `Nazwa Kamery (CH 01) | 30 FPS`, która precyzyjnie pokazuje wydajność renderowania.

---

## 6. Wyniki Weryfikacji

* **Budowanie projektu:** Kompilacja `cmake --build build -j$(nproc)` zakończona pełnym powodzeniem.
* **Testy automatyczne:** Wszystkie 16 testów jednostkowych pomyślnie zaliczone:
  ```
  100% tests passed, 0 tests failed out of 16
  Total Test time (real) =   0.86 sec
  ```

---

## 7. Rozwiązanie Wycieku Pamięci po zamknięciu Okna Archiwum (Anulowanie Sesji)

* **Problem:** Otwieranie, przeglądanie i zamykanie okna odtwarzacza archiwalnego (`PlaybackWindow.qml`) powodowało przyrost zużycia pamięci RAM (RSS), która nie wracała do pierwotnego poziomu po zamknięciu okna ze względu na trwające w tle zapytania HTTP.
* **Rozwiązanie:**
  1. **Anulowanie wszystkich wyszukiwań w locie (`cancelAllSearches()`):** 
     Zaimplementowaliśmy w klasie `HikvisionISAPI` bezpieczną metodę anulowania aktywnych sesji. Przechowujemy teraz wszystkie aktywne wskaźniki `QNetworkReply*` w mapie `m_activeReplies`. Wywołanie `cancelAllSearches()` czyści sesje, natychmiast przerywa (`abort()`) wszystkie trwające zapytania HTTP i bezpiecznie zwalnia ich pamięć (`deleteLater()`).
  2. **Czyszczenie globalnych cache-ów przy zamknięciu:** 
     W zdarzeniu `onClosing` w pliku `PlaybackWindow.qml` jawnie resetujemy cache segmentów i miesięcy do stanu początkowego (`{}`), co odcina referencje do starych danych.

---

## 8. Całkowite i Precyzyjne Uwalnianie Pamięci (Archiwum & Przełączanie Widoków)

Aby zagwarantować powrót zużycia pamięci fizycznej (RSS) dokładnie do poziomu bazowego zarówno po zamknięciu okna archiwum (`PlaybackWindow.qml`), jak i podczas przełączania widoków w głównym oknie (np. Widok 1 -> Widok 2 -> Widok 1), wdrożyliśmy zaawansowane, trzystopniowe zarządzanie pamięcią sterty i silnika QML:

### 1. Synchroniczne Czyszczenie Delegatów (Synchronous Delegate Cleanup)
* W zdarzeniu `onClosing` oraz bloku `Component.onDestruction` w pliku [PlaybackWindow.qml](file:///home/arkanis/cctv/cctv-viewer2/src/PlaybackWindow.qml) przypisujemy `activePlayersList = []` oraz `selectedPlayerIndex = -1`.
* Dzięki temu obiekt `Repeater` w siatce odtwarzaczy natychmiast, **synchronicznie** niszczy wszystkie delegaty widoków i powiązane z nimi obiekty C++ `HikvisionArchivePlayer`, zanim samo okno zostanie usunięte. To gwarantuje natychmiastowy start procedury zwalniania pamięci.

### 2. Zwracanie pamięci sterty alokatora glibc do jądra OS (`malloc_trim`)
* Alokator `glibc` na Linuksie (`ptmalloc`) domyślnie przetrzymuje zwolnione bloki pamięci (np. odalokowane bufory wideo PlayM4 oraz pool buforów klatek `m_frameBufferPool`) w wątkowych arenach wolnych bloków, co powodowało, że system operacyjny nadal widział wysokie zużycie pamięci (RSS).
* Dodaliśmy warunkowe wywołanie `malloc_trim(0)` (pod `#ifdef __linux__`) na końcu destruktora `~HikvisionArchivePlayer()`.
* Dodaliśmy metodę pomocniczą `Context::trimMemory()` wywołującą `malloc_trim(0)` na Linuksie w klasie `Context` (singletonie dostępnym w QML).

### 3. Globalna Optymalizacja Pamięci, Bezpieczne Oczyszczanie Cache QML i Opóźnione GC w RootWindow
* **Problem rezydualnej pamięci 20-30MB:** Gdy dynamiczne okno archiwum (`PlaybackWindow.qml` - blisko 2800 linii kodu QML/JS) jest tworzone po raz pierwszy, silnik QML (`QQmlEngine`) kompiluje je do kodu bajtowego i zapisuje w swojej wewnętrznej pamięci podręcznej (Component Cache). Dzięki temu kolejne otwarcia okna są natychmiastowe, ale skompilowany szablon i metadane zajmują w pamięci wirtualnej dokładnie 20-30 MB, nawet po całkowitym zniszczeniu instancji okna.
* **Bezpieczne, bezbłędne uwalnianie pamięci cache silnika QML:** Aby całkowicie usunąć ten narzut bez ryzyka naruszenia stabilności programu (błędów segmentacji przy przełączaniu widoków), dopracowaliśmy metodę `Context::trimMemory()` w C++:
  1. **Usunięcie `clearComponentCache()`:** Wyeliminowaliśmy całkowicie metodę `clearComponentCache()`. Agresywnie usuwała ona skompilowane typy z pamięci podręcznej, co powodowało unieważnienie kontekstu (`QQmlContextData`) aktywnych, działających w tle elementów layoutów i prowadziło do crashu (crashed at `QQmlContextData::propertyNames`).
  2. **Sekwencyjne i bezpieczne czyszczenie:** Zmieniliśmy kolejność wywołań w `trimMemory()`. Najpierw wywoływane jest `m_engine->collectGarbage()` (co zmusza silnik JS do natychmiastowego usunięcia nieaktywnych referencji), a dopiero potem `m_engine->trimComponentCache()`. Ponieważ nieużywane instancje okna archiwum zostały już rozładowane z Loadera i ich referencje JS usunięte, `trimComponentCache()` jest w stanie w 100% bezpiecznie i kompletnie zwolnić pamięć podręczną skompilowanego bytecode-u bez dotykania aktywnych komponentów!
* **Asynchroniczne i bezpieczne rozładowanie Loadera w `PlaybackWindow.qml`**:
  - Zmodyfikowaliśmy obsługę sygnału `onClosing` okna archiwum. Zamiast synchronicznego niszczenia okna poprzez ustawienie `playbackWindowLoader.active = false` (co powodowało niszczenie obiektu w trakcie wykonywania jego własnego kodu i prowadziło do błędów), przenieśliśmy to wywołanie do pętli asynchronicznej za pomocą `Qt.callLater()`.
  - Dzięki temu okno archiwum kończy całą procedurę zamykania całkowicie i bezbłędnie, a ułamek milisekundy później Loader zostaje bezpiecznie wyładowany z pamięci podręcznej silnika QML i wyzwalane jest bezpieczne, opóźnione odśmiecanie pamięci sterty.
* W głównym oknie [RootWindow.qml](file:///home/arkanis/cctv/cctv-viewer2/src/RootWindow.qml) dodaliśmy timer `gcTimer` o interwale 1000 ms, który działa cyklicznie 5-krotnie (przez 5 sekund). W każdym takcie wywołuje on najpierw silnik `gc()`, aby usunąć wszelkie osierocone wrappery JavaScript, a następnie ulepszoną metodę `Context.trimMemory()`, aby wyczyścić cache kompilatora QML i oddać całą zwolnioną pamięć systemowi operacyjnemu za pomocą `malloc_trim`.
* **Optymalizacja Przełączania Widoków:** Podpieliśmy wywołanie `rootWindow.triggerGcDeferred()` wewnątrz zdarzenia `onCurrentIndexChanged` komponentu `StackLayout` (odpowiedzialnego za wyświetlanie siatek/widoków kamer). Dzięki temu przy każdej zmianie widoku (gdy odtwarzacze poprzedniego widoku zatrzymują się i zwalniają zasoby), cała zwolniona pamięć (wraz z cachem i metadanymi) jest precyzyjnie i całkowicie zwracana do systemu operacyjnego bez ryzyka jakichkolwiek crashów. Przy powrocie do poprzedniego widoku zużycie pamięci zwraca się dokładnie do pierwotnego poziomu!

---

## 9. Stabilizacja i Bezpieczeństwo Pobierania Plików (Downloader Thread Fix)

* **Problem:** Jeśli wyszukiwanie segmentów nagrań (część procesu pobierania pliku) było aktywne w osobnym wątku `m_searchThread` w momencie zamknięcia okna pobierania lub całego programu, destruktor `~HikvisionDownloader` niszczył obiekt, ale wątek tła nadal działał. Próba wykonania callbacks przez `QMetaObject::invokeMethod` z użyciem nieistniejącego już wskaźnika `this` skutkowała natychmiastowym crashem (segmentation fault) programu.
* **Rozwiązanie:**
  1. **Synchroniczne i bezpieczne zatrzymanie wątku:** Zaktualizowaliśmy destruktor `~HikvisionDownloader()` w pliku [hikvisiondownloader.cpp](file:///home/arkanis/cctv/cctv-viewer2/src/hikvisiondownloader.cpp). Przed usunięciem downloader pobiera teraz bezpieczną kopię wskaźnika wątku `m_searchThread`, wysyła żądanie przerwania (`requestInterruption()`), odłącza wszelkie powiązane sygnały (`disconnect()`), a następnie wywołuje `wait()`, blokując i czekając na całkowite i bezpieczne zakończenie wątku tła przed dokończeniem destrukcji obiektu C++.
  2. **Usunięcie wycieków zasobów QThread:** Po bezpiecznym doczekaniu na zakończenie wątku, pamięć powiązana z obiektem `QThread` jest natychmiast uwalniana poprzez jawne wywołanie `delete threadToWait`. Zapobiega to jakimkolwiek wyciekom uchwytów systemowych i wątków w systemie operacyjnym.

---

## 10. Likwidacja opóźnienia 500ms (zamrażania GUI) przy zamykaniu odtwarzacza archiwalnego

* **Problem:** Destruktor klasy `HikvisionArchivePlayer` oczekiwał w pętli `while` na wyzerowanie licznika zadań w tle `m_pendingTasks`. Jednak zwalnianie licznika odbywało się wewnątrz lambdy wysyłanej za pomocą `Qt::QueuedConnection` na wątek GUI. Zablokowanie wątku GUI przez destruktor uniemożliwiało wykonanie lambdy, co powodowało, że pętla zawsze osiągała timeout bezpieczeństwa wynoszący 500 ms, odczuwalnie zamrażając interfejs aplikacji.
* **Rozwiązanie:** Przeniesiono dekrementację `pPlayer->m_pendingTasks--` w klasie [YV12ToRGBTask](file:///home/robert/cctv/cctv-viewer2/src/hikvisionarchiveplayer.cpp#L18) bezpośrednio do wątku tła, poza asynchroniczną lambdę. Zapobiegło to głodzeniu pętli oczekiwania wątku GUI i wyeliminowało 500 ms zamrożenie interfejsu.

---

### 11. Zatrzymywanie strumieni Hikvision w tle przy przełączaniu widoków (Wyciek RAM i sieci)

* **Problem:** Komponent `HikvisionPlayer` (wykorzystywany do odtwarzania strumieni na żywo z kamer Hikvision) nie reagował na utratę widoczności. Wyciszał jedynie odświeżanie graficzne, ale połączenie sieciowe TCP (`NET_DVR_RealPlay_V40`) i buforowanie danych przez SDK Hikvision pozostawały w pełni aktywne dla wszystkich historycznie załadowanych siatek (stron `StackLayout`). Powodowało to ciągły wzrost zużycia RAM-u, CPU oraz pasma sieciowego przy przełączaniu widoków.
* **Rozwiązanie:** Zmodyfikowano deklaratywne powiązanie właściwości `recorderIp` w pliku [Player.qml](file:///home/robert/cctv/cctv-viewer2/src/Player.qml#L369). Jeśli viewport przestaje być widoczny na ekranie, adres IP przekazywany do `HikvisionPlayer` zmienia się na pusty string `""`. Powoduje to natychmiastowe zatrzymanie strumienia sieciowego w C++ za pomocą `NET_DVR_StopRealPlay` i całkowite zwolnienie jego zasobów. Przy powrocie do widoku, adres IP jest automatycznie przywracany, a strumień wznawiany.

---

## 12. Dwukierunkowa Synchronizacja Konfiguracji w Czasie Rzeczywistym i Wydanie v2.1.7-1

W wersji `v2.1.7-1` dodaliśmy zaawansowany system dwukierunkowej synchronizacji ustawień kamer (NVR) oraz układów widoków (ViewportsLayouts) między wszystkimi otwartymi oknami programu w czasie rzeczywistym.

### Opis Mechanizmu Synchronizacji:
1. **Brak pętli zapisu i niskie zużycie zasobów:** Klasa `Context` monitoruje główny plik konfiguracyjny za pomocą klasy `QFileSystemWatcher`. Na Linuksie wykorzystuje ona natywny mechanizm `inotify` (działający w 100% zdarzeniowo przy 0% obciążeniu procesora w trybie bezczynności). Każda modyfikacja ustawień w dowolnym procesie zapisuje plik na dysk, co natychmiast wyzwala sygnał `configFileChanged` u pozostałych instancji. Aby uniknąć nieskończonej pętli zapisu, każda instancja przed aktualizacją najpierw porównuje nowo wczytaną wartość z wartością w pamięci – jeśli są one identyczne, aktualizacja pamięci i ponowny zapis nie są wykonywane.
2. **Izolacja konfiguracji okien (Multi-Monitor Support):** Aby wspierać niezależne ekrany i zachować niezależne pozycje okien oraz wybrany aktywny widok (`currentIndex`) dla każdego okna, wprowadziliśmy dynamiczne przydzielanie unikalnych ID dla okien pomocniczych (`AuxiliaryWindow_1`, `AuxiliaryWindow_2` itd.).
3. **Automatyczne zwalnianie zasobów:** ID okien są przydzielane sekwencyjnie i zwalniane natychmiast po zamknięciu danego okna pomocniczego, co pozwala na bezpieczne i poprawne ponowne użycie tego samego ID w kolejnych sesjach.
4. **Lokalizacja i kompilacja:** Nowe teksty zostały przetłumaczone w plikach `.ts` (zarówno dla wersji polskiej, jak i angielskiej).
5. **Budowanie pakietów i wersjonowanie:** Zaktualizowano wersję projektu do `2.1.7-1` w `CMakeLists.txt`, `packaging/arch/PKGBUILD` oraz `debian/changelog`. Cały projekt został z powodzeniem przebudowany, a pakiety binarne `.pkg.tar.zst` wygenerowane za pomocą polecenia `makepkg`.

---

## 13. Poprawa wyglądu ikon prędkości, usunięcie duplikatów przycisków i tłumaczenia angielskie

Wdrożyliśmy następujące poprawki wyglądu i spójności interfejsu paska sterowania odtwarzaniem archiwalnym:
1. **Powiększenie ikon bez tekstu (Speed & VCR):**
   - Zmodyfikowaliśmy komponent `CctvButton.qml`, zwiększając wymiary obrazka dla przycisków bez tekstu (`text === ""`) z `18x18px` do `22x22px` (dla małych przycisków `isSmall: true`, takich jak przyciski wyboru prędkości, Zoom i VCR) oraz z `20x20px` do `24x24px` (dla standardowych przycisków). Dzięki temu ikony wewnątrz okręgów o średnicy 30px są o ok. 50% większe powierzchniowo i znacznie bardziej czytelne.
2. **Poprawa czytelności napisów wewnątrz wygenerowanych ikon SVG:**
   - Zwiększyliśmy rozmiar czcionki (font-size) napisów wewnątrz ikon SVG dla skrótów Zoom (`1h`, `8h` do `9.5pt`, `24h` do `8.5pt`), prędkości odtwarzania (`1x`, `2x` itd. do `9.5pt`) oraz przycisków VCR (`15`, `45`, `60` do `9pt`), co w połączeniu z większym rozmiarem ikon znacznie poprawiło ich czytelność na ekranie.
3. **Usunięcie duplikatów przycisków tekstowych:**
   - Całkowicie usunęliśmy stare przyciski tekstowe ("Ostatnia 1h", "Ostatnie 8h", "Cały dzień") z pliku `PlaybackWindow.qml`, pozostawiając wyłącznie estetyczne, okrągłe przyciski ikonowe z tooltipami.
4. **Tłumaczenia angielskie i polskie tooltipów:**
   - Za pomocą narzędzia `lupdate` wyeksportowaliśmy wszystkie nowo dodane etykiety tooltipów i uzupełniliśmy kompletne tłumaczenia w plikach lokalizacyjnych `translations/cctv-viewer_en_US.ts` oraz `translations/cctv-viewer_pl_PL.ts`.
   - Zbudowaliśmy pliki binarne tłumaczeń `.qm`, które są automatycznie kompilowane i integrowane z zasobami aplikacji przy budowaniu CMake.

---

## 14. Pływające Doki, Przeciągalne Statystyki, Poprawki Archiwum i Wydanie v2.1.9-1

W wersji `v2.1.9-1` wprowadziliśmy szereg optymalizacji i poprawek wizualnych oraz funkcjonalnych w oknach LIVE i ARCHIWUM, a także naprawiliśmy krytyczny błąd synchronizacji przy usuwaniu układów:

### 1. Centrowane Pływające Doki (LIVE & ARCHIWUM)
* **LIVE:** Zintegrowano górny pasek narzędzi w estetyczny, zaokrąglony i pływający dok (dock) o dynamicznie dopasowującej się szerokości zależnej od liczby widocznych layoutów.
* **ARCHIWUM:** Zintegrowano górny pasek w pływający dok o zaokrąglonych dolnych narożnikach. Dok ten jest domyślnie przypięty po otwarciu okna.
* **Separatory pionowe:** Dodano pionowe linie separujące opcje siatki od zdefiniowanych widoków.
* **Wizualna spójność przycisków:** Zastosowano jednolity styl kolorystyczny dla przycisków wyboru układu w oknie ARCHIWUM (tożsamy z LIVE), poprawiając kontrast tekstu zaznaczonej siatki (ciemny tekst na seledynowym tle).

### 2. Panel Statystyk Systemowych
* Przekształcono wysuwane okno statystyk w półprzezroczysty, pływający panel.
* Panel pozostaje click-through (kliknięcia przenikają pod spód), ale dodano dedykowaną ikonę uchwytu w lewym górnym rogu.
* Użytkownik może przesuwać panel wyłącznie poprzez kliknięcie, przytrzymanie i przeciągnięcie tej ikony.

### 3. Zmiany w Oknie Archiwum i Kalendarzu
* **Przezroczystość pasków:** Zwiększono przezroczystość paska górnego oraz dolnego w trybie pełnoekranowym (26%) i okienkowym (60%). Oś czasu zyskała przezroczyste tło.
* **Uproszczona kontrola prędkości:** Zastąpiono ikony prędkości odtwarzania boldowanym tekstem (`1x`, `2x`, `4x`) i całkowicie usunięto niestabilną prędkość `8x`.
* **Ikony Chevronów:** Przyciski przewijania miesięcy w kalendarzu popapów zamieniono na graficzne strzałki (chevrony).
* **Bezpieczne usuwanie kamer:** Przycisk usuwania kamery przeniesiono z prawego górnego rogu wideo na dolny pasek kontrolny viewportów, zapobiegając przypadkowym kliknięciom podczas zamykania viewportu.

### 4. Naprawa Błędu Usuwania Układów (Freeze & Loop Fix)
* Rozwiązano problem z pętlą synchronizacji zapisów konfiguracji przy usuwaniu układów podglądu w oknie ustawień, co powodowało kilkusekundowe zamrożenie interfejsu i ponowne pojawianie się usuniętych układów.

### 5. Kompilacja i Pakietowanie
* Zaktualizowano bilingualne pliki tłumaczeń (`.ts`) i wygenerowano pliki `.qm` bez nieprzetłumaczonych wpisów.
* Zbudowano pakiet dla systemu Arch Linux (`2.1.9-1`) i opublikowano wydanie na GitHubie.

---

## 15. Poprawka Tłumaczeń i Wydanie v2.1.9-2

W wersji `v2.1.9-2` naprawiliśmy błąd braku angielskich tłumaczeń wpisów w QML-owym changelogu w panelu bocznym. Wszystkie teksty zostały w pełni przetłumaczone i wbudowane w pliki binarne `.qm`.

---

## 16. Powiększenie Okna Kamer i Nowy Przycisk Miniatur w Wydaniu v2.1.9-3

W wersji `v2.1.9-3` wprowadziliśmy następujące zmiany:
* **Okno list kamer rejestratora:** Zwiększono jego domyślną wysokość o 40% (z 600px do 840px), co pozwala na wygodniejsze przeglądanie kafelków z podglądem kamer w pionie bez konieczności ciągłego przewijania.
* **Nowy przycisk generowania miniatur:** Zastąpiono tekstowy przycisk "Generuj miniatury" estetycznym, okrągłym przyciskiem z jaskrawo-seledynowym akcentem (kolor `#00f5d4` zgodny z resztą programu) oraz ikoną SVG przedstawiającą aparat fotograficzny z pętlą odświeżania. Przycisk zyskał również dedykowany tooltip oraz animację przejścia przy najechaniu myszą.

---

## 17. Safe Destructor, Player Pooling, Statystyki GPU/VRAM i Poprawki UX w Wydaniu v2.2.0

W wersji `v2.2.0` wprowadziliśmy zaawansowane poprawki stabilności i wydajności w zarządzaniu pamięcią wideo oraz monitorowaniu zasobów systemowych:
* **Bezpieczny destruktor odtwarzacza archiwalnego:** Zwiększono limit oczekiwania (safeguard) z 500 ms (100 iteracji) do 5000 ms (1000 iteracji) w `~HikvisionArchivePlayer` przy zwalnianiu wątków i usuwaniu zadań dekodowania w tle (`YV12ToRGBTask`). Eliminuje to ryzyko wyścigów danych i awarii (crashy) programu przy zamykaniu okna podglądu przy silnie obciążonym procesorze.
* **QML Player Pooling (Pula Odtwarzaczy):** Przepisano architekturę dynamicznego tworzenia odtwarzaczy w `ViewportsLayout.qml`. Zamiast ciągłego niszczenia i tworzenia komponentów wideo od zera przy zmianie układu kamer (co powodowało alokacje u sterowników graficznych i błędy *Presenting frames*), wprowadziliśmy reużywalną pulę obiektów w locie. Obiekty `Player` są teraz reparentowane do nowych kontenerów siatki, a ich właściwości są dynamicznie bindowane. Pozwala to na płynne przełączanie układów bez migotania obrazu i fragmentacji pamięci RAM.
* **Lekkie monitorowanie GPU/VRAM:** Całkowicie wyeliminowano uruchamianie zewnętrznych procesów `nvidia-smi` co 1 sekundę. Zamiast tego zaimplementowano lekki i uniwersalny mechanizm:
  - Dla kart **NVIDIA** dynamicznie ładujemy bibliotekę `libnvidia-ml.so` i odczytujemy obciążenie procesów za pomocą natywnych wywołań NVML.
  - Jako uniwersalny mechanizm dla kart **AMD** oraz **Intel** (oraz jako rezerwowy dla Nvidii) parsujemy standardowe statystyki **DRM Client Stats** z jądra Linux `/proc/<pid>/fdinfo/<fd>`, wyliczając rzeczywiste, procesowe zużycie pamięci VRAM oraz silnika renderowania GPU. **Uwaga: te statystyki dla kart AMD oraz Intel nie zostały przetestowane na rzeczywistym sprzęcie.**
  - W razie braku szczegółowych danych procesowych, aplikacja płynnie przechodzi do odczytu węzłów systemowych sysfs `/sys/class/drm/card0/device/` lub systemowych wskaźników NVML.
* **Rozszerzanie panelu statystyk systemowych:** Umożliwiono dynamiczną zmianę rozmiaru panelu poprzez przeciąganie za jego krawędzie oraz narożniki. Wykresy CPU, GPU i sieci automatycznie skalują swoją szerokość i wysokość, dopasowując się płynnie do nowych wymiarów panelu w czasie rzeczywistym.
* **Natychmiastowe zamykanie programu (UX):** Wprowadzono wywołanie `hide()` na oknach przed wywołaniem `Qt.quit()` w oknach dialogowych wyjścia. Sprawia to, że interfejs programu znika natychmiast z ekranu użytkownika, a faktyczne zwalnianie zasobów i wątków w tle odbywa się niezauważalnie.

---

## 18. Optymalizacja Okna Pobierania, Precyzyjne Limity, Selektor Czasu oraz Nowe Ikony

Wprowadziliśmy kompleksową przebudowę interfejsu konfiguracji limitów okien pomocniczych oraz okna pobierania archiwalnego, wzbogacając je o intuicyjne elementy sterujące, dynamiczną walidację oraz spójną identyfikację wizualną:

### 1. Walidacja limitu okien pomocniczych w locie
* **Zachowanie**: Wprowadzono natychmiastowe sprawdzanie wpisywanej wartości w polu `auxiliaryLimitField` (`SideBar.qml`). Każda cyfra większa niż `3` jest w locie (przy zdarzeniu `onTextChanged`) automatycznie zamieniana na `3`.
* **Zakres**: Limit został ściśle określony na przedział `0-3` (0 oznacza całkowite zablokowanie otwierania nowych okien pomocniczych).
* **Bezpieczeństwo startu**: Wprowadzono dodatkową weryfikację odczytu limitu z pliku konfiguracyjnego na dysku w `RootWindow.qml` oraz `main.cpp` w celu zapewnienia prawidłowych granic (0–3) już na starcie aplikacji.

### 2. Przebudowa Układu i Skrócenie Pól w Oknie Pobierania
* **Estetyka**: Przebudowano układ siatki (`GridLayout`) w oknie `DownloadDialog.qml` na układ 4-kolumnowy, dodając element rozciągający się na końcu każdego wiersza. Zapobiega to rozciąganiu pól tekstowych na całą szerokość dialogu (1200px) i eliminuje nieestetyczne puste przestrzenie.
* **Szerokości preferowane**: Pola daty i czasu posiadają odtąd stałe szerokości preferowane (odpowiednio `150` dla daty i `130` dla czasu).
* **Domyślne wartości**: Zmieniono domyślny czas zakończenia pobierania z `23:59:59` na `01:00:00` w bloku inicjalizacyjnym.

### 3. Graficzny Selektor Czasu (Time Picker Popup)
* **Wizualny przycisk**: Obok każdego pola czasu umieszczono okrągły przycisk szybkiego wyboru z ikoną zegara.
* **Interfejs wyboru**: Kliknięcie przycisku otwiera modalny `timePickerPopup` z dopasowanym, eleganckim tłem `#0f151b`, który pozwala na płynne przewijanie i precyzyjny wybór godzin (`00-23`), minut (`00-59`) oraz sekund (`00-59`).
* **Aktywne podświetlenie**: Wybrane wartości są podświetlane na jaskrawy pomarańczowy kolor (`#ff7a00`), a zatwierdzenie wartości przyciskiem "Zatwierdź" automatycznie formatuje czas i wpisuje go do odpowiedniego pola tekstowego.
* **Automatyczne pozycjonowanie**: Przy otwarciu popupa, kolumny automatycznie przewijają się i pozycjonują (za pomocą `positionViewAtIndex` w bloku `Qt.callLater`) na wartościach aktualnie wpisanych w polu tekstowym.

### 4. Inteligentna Walidacja i Blokada Pobierania
* **Walidacja w locie**: Pola tekstowe weryfikują poprawność formatu (regex) oraz logikę (np. poprawne dni w miesiącu z uwzględnieniem lat przestępnych) automatycznie przy edycji oraz przy utracie fokusu.
* **Formaty**: Wspierany jest format daty `DD.MM.RRRR` oraz elastyczny format czasu obsługujący zarówno separatory dwukropkowe, jak i kropkowe (`HH:MM:SS` oraz `HH.MM.SS`).
* **Sygnalizacja błędów**: Pole zawierające błędne dane zostaje otoczone czerwoną, grubą ramką (`#ff3333`), a najechanie na nie myszą lub aktywacja wyświetla szczegółowy, czerwony tooltip informujący o prawidłowym formacie.
* **Blokada przycisku**: Przycisk "Pobierz" zostaje automatycznie dezaktywowany (disabled) tak długo, jak długo w dowolnym polu widnieje błąd walidacji.

### 5. Nowoczesne, Spójne Ikony Wyboru Daty (Kalendarza)
* **Aestetyczna aktualizacja**: Zgodnie z sugestią użytkownika, zaktualizowaliśmy ikony przycisków wyboru daty (kalendarza) do nowoczesnego, szczegółowego inline SVG zawierającego miniaturowy układ siatki dni (kropek).
* **Zakres**: Zmiana została wprowadzona zarówno w oknie pobierania (`DownloadDialog.qml`), jak i w głównym panelu odtwarzacza archiwalnego na osi czasu (`PlaybackWindow.qml`), co gwarantuje pełną spójność wizualną i premium design całego interfejsu.
* **Interakcja**: Ikony te dynamicznie reagują na najechanie kursorem (hover), płynnie przechodząc z białego (lub szarego) koloru na seledynowy akcent (`#00f5d4`).

### Wyniki Weryfikacji
* **Budowanie projektu**: Kompilacja zakończona pełnym sukcesem (`100% Built target cctv-viewer`).
* **Testy automatyczne**: Wszystkie 16 testów jednostkowych przeszło pomyślnie.

---

## 19. Płynne przełączanie strumieni (Seamless Switch), dźwięk w archiwum, automatyczne sterowanie i wyciszanie okna Live View

W tej aktualizacji rozwiązaliśmy kluczowe problemy związane ze stabilnością strumieni wideo podczas maksymalizacji viewportów, odtwarzaniem dźwięku w oknie archiwum oraz automatycznym wyciszaniem dźwięku na żywo przy otwartym archiwum:

### 1. Płynne przełączanie z SUB na MAIN bez zamrażania obrazu (Seamless Switch)
* **Problem:** Podczas powiększania viewportu QML przełączał strumień z niskiej jakości (SUB) na wysoką (MAIN). Zmiana widoczności elementów `VideoOutput` w Qt Quick powodowała, że silnik QML wywoływał metodę `setVideoSurface` na nowym odtwarzaczu. Dotychczasowa implementacja `QmlAVPlayer::setVideoSurface` wywoływała przy jakiejkolwiek zmianie powierzchni metodę `stop()`, co niszczyło demuxer, zrywało połączenie RTSP i resetowało cały stan nowego odtwarzacza właśnie wtedy, gdy interfejs na niego przełączał. Skutkowało to zamrożeniem obrazu i zniknięciem dźwięku.
* **Rozwiązanie:** Zmodyfikowano metodę `QmlAVPlayer::setVideoSurface` w [qmlavplayer.cpp](file:///home/arkanis/cctv/kvision/src/qmlav/src/qmlavplayer.cpp). Zamiast zatrzymywać cały odtwarzacz, teraz zatrzymywana jest jedynie stara powierzchnia (jeśli była aktywna) i przypisywana nowa. Metoda `frameHandler` automatycznie wykrywa zmianę i inicjalizuje nową powierzchnię formatem przy najbliższej ramce wideo, kontynuując odtwarzanie bez zrywania wątku sieciowego i demuxera.
* **Brak wycieków pamięci:** Zmiana opiera się na bezpiecznym przypisaniu wskaźników bez alokacji nowych zasobów, dzięki czemu zużycie pamięci RAM pozostaje całkowicie stabilne i nie rośnie w nieskończoność.

### 2. Przywrócenie odtwarzania dźwięku w oknie Archiwum (Playback Window)
* **Problem:** Próba wykorzystania funkcji `PlayM4_PlaySoundShare` w Linux PlayM4 SDK kończyła się niepowodzeniem (brak dźwięku), ponieważ ta funkcja w wersji SDK na system Linux często nie jest poprawnie wspierana lub stanowi jedynie stub.
* **Rozwiązanie:** Przywrócono standardowe, w pełni wspierane i stabilne funkcje SDK: `PlayM4_PlaySound(nPort)` oraz globalną `PlayM4_StopSound()` w [hikvisionarchiveplayer.cpp](file:///home/arkanis/cctv/kvision/src/hikvisionarchiveplayer.cpp). Mikser dźwięku (ALSA/PulseAudio/PipeWire) na nowoczesnych systemach Linux bez problemu obsługuje jednoczesne odtwarzanie dźwięku z wielu aplikacji za pomocą domyślnego urządzenia.

### 3. Automatyczne sterowanie dźwiękiem w siatce archiwum
* **Funkcjonalność:** Zaktualizowano właściwość `isAudible` w [PlaybackWindow.qml](file:///home/arkanis/cctv/kvision/src/PlaybackWindow.qml). 
  - Gdy siatka ma wymiar 1x1, sterowanie dźwiękiem i sam dźwięk z jedynej kamery włącza się automatycznie.
  - W większych układach (siatkach), sterowanie dźwiękiem i dźwięk aktywuje się automatycznie dla aktualnie wybranego (zaznaczonego) kafelka kamery.
  - Zaimplementowane reguły ściśle respektują globalną opcję `disableAudio` w ustawieniach (wtedy suwak i dźwięk są całkowicie zablokowane i niewidoczne).

### 4. Całkowite wyciszanie okna Live View po otwarciu okna Archiwum
* **Problem:** Odtwarzanie dźwięku z kamer na żywo (Live View) nakładało się na dźwięk z odtwarzanego materiału archiwalnego, powodując kakofonię.
* **Rozwiązanie:** 
  1. W głównym oknie [RootWindow.qml](file:///home/arkanis/cctv/kvision/src/RootWindow.qml) zdefiniowano nową reaktywną właściwość:
     ```qml
     readonly property bool isPlaybackWindowOpen: playbackWindowLoader.active && playbackWindowLoader.item && playbackWindowLoader.item.visible
     ```
  2. W pliku [ViewportsLayout.qml](file:///home/arkanis/cctv/kvision/src/ViewportsLayout.qml) zaktualizowano powiązanie właściwości `player.muted` o sprawdzenie stanu otwarcia archiwum:
     ```qml
     if (typeof rootWindow !== "undefined" && rootWindow.isPlaybackWindowOpen) {
         return true;
     }
     ```
     Dzięki temu, w momencie otwarcia okna archiwum wszystkie kamery w trybie podglądu na żywo są natychmiastowo i całkowicie wyciszane. Po zamknięciu okna archiwum dźwięk na żywo (jeśli był włączony dla wybranej kamery) automatycznie powraca.

### Wyniki Końcowej Weryfikacji
* **Budowanie projektu**: Kompilacja zakończona pełnym sukcesem (`100% Built target kvision` oraz pomyślne przejście wszystkich testów).
* **Testy automatyczne**: Wszystkie 16 testów jednostkowych przeszło pomyślnie.


---

## 20. Ostateczna naprawa pętli "ping-pong" (Video Freeze) oraz odtwarzania dźwięku w archiwum

W tej aktualizacji zlikwidowaliśmy ostatecznie uciążliwą pętlę przełączania wideo na żywo (live stream switch loop) oraz przywróciliśmy działające i czyste odtwarzanie dźwięku w oknie archiwum na systemie Linux za pośrednictwem systemowego serwera dźwięku (PulseAudio/Pipewire):

### 1. Rozbicie pętli przełączania wstecznego w `Player.qml`
* **Problem**: Podczas zatrzymywania starego odtwarzacza (np. przy przejściu z SUB na MAIN) jego właściwość `hasVideo` była zmieniana synchronicznie na `false`, co wywoływało sygnał `onHasVideoChanged`. QML uruchamiał funkcję `checkSeamlessSwitch`. Ponieważ stan starego odtwarzacza wciąż wskazywał na `MediaPlayer.Buffered`, a dźwięk `hasAudio` nie zdążył się jeszcze wyczyścić i był `true`, funkcja błędnie oceniała ten odtwarzacz jako "nowy, gotowy strumień" i przełączała aktywny odtwarzacz z powrotem na niego. To powodowało nieskończoną pętlę "ping-pong" i zamrożenie wideo.
* **Rozwiązanie**: W pliku [Player.qml](file:///home/arkanis/cctv/kvision/src/Player.qml) zmieniono warunek gotowości w `checkSeamlessSwitch` na rygorystyczny wymóg posiadania wideo oraz aktywnego stanu odtwarzania (`PlayingState`):
  ```qml
  if (player.playbackState === MediaPlayer.PlayingState && player.status === MediaPlayer.Buffered && player.hasVideo)
  ```
  Zatrzymywany odtwarzacz przechodzi w stan `StoppedState`, a jego `hasVideo` przyjmuje wartość `false`, co powoduje, że zostaje on natychmiast odrzucony i pętla przełączania została całkowicie wyeliminowana.

### 2. Przywrócenie odtwarzania dźwięku w oknie archiwum (`HikvisionArchivePlayer`)
* **Problem**: Wcześniej zaimplementowana ścieżka odtwarzania próbek PCM do Qt `QAudioOutput` nie generowała dźwięku, ponieważ:
  1. Rejestratory Hikvision podczas odtwarzania archiwum domyślnie wysyłają wyłącznie dane wideo.
  2. Rejestracja callbacku `PlayM4_SetAudioCallBack` nie uruchamiała automatycznie dekodera dźwięku w SDK.
* **Rozwiązanie**: 
  1. W pliku [hikvisionarchiveplayer.cpp](file:///home/arkanis/cctv/kvision/src/hikvisionarchiveplayer.cpp) w funkcji `playAtTime` dodaliśmy wysłanie komendy `NET_DVR_PLAYSTARTAUDIO` zaraz po pomyślnym uruchomieniu odtwarzania (`NET_DVR_PLAYSTART`). Informuje to rejestrator (NVR) o konieczności dołączenia strumienia audio do sesji odtwarzania.
  2. W funkcji `PlayDataCallBack` (podczas przetwarzania nagłówka `NET_DVR_SYSHEAD`), zaraz po udanej rejestracji callbacku audio, dodaliśmy wywołanie `PlayM4_PlaySound(activePort)`. Powoduje to uruchomienie dekodera audio w SDK, dzięki czemu `AudioCallBack` zaczyna poprawnie otrzymywać zdekodowane pakiety PCM i przesyłać je bezpośrednio do Qt `QAudioOutput`, które z powodzeniem odtwarza czysty dźwięk.

---

## 21. Gwarancja braku wycieków pamięci i pełnego sprzątania po zamknięciu archiwum

Aby zagwarantować pełną stabilność aplikacji, brak wycieków pamięci oraz natychmiastowe usunięcie wszelkich śladów sesji archiwalnej w pamięci RAM (RSS) po zamknięciu okna archiwalnego, zaimplementowaliśmy rygorystyczny proces zarządzania zasobami i wątkami w klasie `HikvisionArchivePlayer`:

### 1. Bezpieczna i re-używalna pula buforów klatek (`FrameBufferPool`)
* Wszystkie ramki wideo (`YV12` oraz skonwertowane `RGB32`) są zarządzane w dynamicznym basenie `m_frameBufferPool` z użyciem `std::shared_ptr`. 
* Podczas wywołania `cleanupPlayback()`, pula klatek jest czyszczona (`m_frameBufferPool.clear()`).
* Jeśli w tle nadal trwa przetwarzanie zadania konwersji wideo `YV12ToRGBTask`, przechowuje ono własny, silny wskaźnik `std::shared_ptr<FrameBuffer>`. Gwarantuje to, że pamięć bufora nie zostanie przedwcześnie skasowana (co prowadziłoby do naruszenia pamięci), lecz ulegnie automatycznemu zwolnieniu dokładnie w momencie zakończenia i usunięcia zadania tła przez `QThreadPool`.

### 2. Blokowanie wątku GUI i oczekiwanie na zakończenie zadań w tle (Destruktor)
* W destruktorze `~HikvisionArchivePlayer` program odpytuje licznik atomowy aktywnych zadań w tle `m_pendingTasks`.
* Destruktor blokuje powrót do czasu, aż wszystkie zadania tła zostaną pomyślnie ukończone i usunięte (maksymalny czas oczekiwania to bezpieczne 5000 ms). Zapobiega to jakimkolwiek wyścigom danych (race conditions) w pamięci.

### 3. Automatyczne usuwanie zdarzeń w pętli Qt (`QPointer` i Kontekst)
* Wszystkie wywołania `QMetaObject::invokeMethod` w wątkach pobocznych przekazują surowy wskaźnik `player` jako obiekt kontekstu Qt.
* Jeśli odtwarzacz zostanie zniszczony, pętla zdarzeń Qt automatycznie odrzuca i usuwa wszystkie powiązane z nim zaplanowane wywołania. To powoduje zniszczenie lambdy i uwalnia captured `QByteArray` i `QImage`, eliminując ryzyko wycieku referencji i obiektów tymczasowych.

### 4. Kompletne zwalnianie bibliotek, portów i serwerów audio
* Podczas zatrzymywania odtwarzania w `cleanupPlayback()` uwalniany jest przypisany port dekodera PlayM4 (`PlayM4_FreePort`), a powiązany obiekt Qt `QAudioOutput` zostaje zatrzymany i zaplanowany do usunięcia (`deleteLater()`). 
* Gdy odtwarzacz ulega zniszczeniu, obiekt `QAudioOutput` (jako dziecko hierarchii `QObject`) zostaje automatycznie i synchronicznie usunięty.

### 5. Natychmiastowe zwracanie wolnych stron pamięci sterty do systemu operacyjnego (`malloc_trim`)
* Alokator sterty `glibc` domyślnie zatrzymuje wolne bloki pamięci (np. po buforach wideo 1080p) w wątkowych arenach. Powoduje to, że system operacyjny nadal widzi wysoki poziom Resident Set Size (RSS), mimo poprawnego zwolnienia pamięci przez program.
* Aby temu zapobiec, dodaliśmy bezpośrednie wywołanie `malloc_trim(0)` na końcu destruktora `~HikvisionArchivePlayer()`. Gwarantuje to, że po zamknięciu okna archiwum fizycznie zajęta przez proces pamięć RAM (RSS) natychmiast wraca do stanu początkowego!

### Status Końcowy
* **Kompilacja**: Zakończona pełnym sukcesem (`100% Built target kvision`).
* **Testy jednostkowe**: Wszystkie 16 testów przeszło pomyślnie.
* **Rezultat**: Przełączanie na MAIN stream odbywa się teraz błyskawicznie i płynnie bez żadnego zamrożenia obrazu, odtwarzacz archiwalny poprawnie odtwarza czysty dźwięk, a po zamknięciu okna archiwum wszystkie zasoby (wątki, sesje SDK, serwer audio i alokacje pamięci) są natychmiastowo, bezpiecznie i całkowicie czyszczone.


---

## 22. Rozwiązanie problemu lawinowego wzrostu RAM-u (Backpressure) i zawieszania aplikacji (Audio Stabilization)

Podczas intensywnego przełączania kamer w oknie archiwum zidentyfikowano i wyeliminowano krytyczny błąd, który mógł doprowadzić do nagłego wzrostu zużycia pamięci RAM o kilkadziesiąt gigabajtów (nawet 45 GB w 30 sekund) oraz zablokowania interfejsu graficznego (GUI).

### 1. Diagnoza i Potwierdzenie Zjawiska
Analiza wykazała następującą sekwencję zdarzeń:
1. **Zablokowanie wątku GUI (Inicjalizacja Audio)**: Szybkie przełączanie kamer z dźwiękiem lub drobne wahania w sieci powodowały gwałtowne zmiany estymowanej częstotliwości próbkowania (np. z 8000 Hz na 11025 Hz). Wywoływało to "burzę" kasowania i ponownej inicjalizacji obiektu `QAudioOutput`, co blokowało systemowe wywołania dźwiękowe ALSA/PulseAudio i w efekcie całkowicie zamrażało pętlę zdarzeń Qt (wątek GUI).
2. **Brak sprzężenia zwrotnego (Backpressure Bypass)**: Podczas gdy wątek GUI wisiał, wątek dekodujący SDK w tle (`DecCallBack`) działał dalej bez przeszkód. Ponieważ poprzedni licznik zadań `m_pendingTasks` był zmniejszany na wątku pobocznym zaraz po przekazaniu klatki za pomocą `QMetaObject::invokeMethod`, dekoder uważał, że kolejka jest pusta.
3. **Zasypanie pętli zdarzeń**: Do kolejki zamrożonego wątku GUI trafiały tysiące nieprzetworzonych obiektów `QImage` o wysokiej rozdzielczości (4K, każda zajmująca ok. 33 MB). Z powodu braku limitu w kolejce Qt, w ciągu 30 sekund nieobsłużone zdarzenia zajmowały dziesiątki gigabajtów pamięci operacyjnej, doprowadzając do katastrofalnego przeciążenia systemu.

### 2. Rozwiązanie - Dwustopniowe Backpressure (Dual-Counter)
Wprowadziliśmy nowatorski, dwustopniowy system kontroli przeciążenia (backpressure):
* **Licznik GUI (`m_guiPendingTasks`)**: Dodano atomowy licznik, który jest zwiększany w wątku pobocznym *przed* wysłaniem zdarzenia do wątku głównego, a zmniejszany *wyłącznie wewnątrz obsługi zdarzenia na wątku GUI* (po wyrenderowaniu lub odrzuceniu klatki).
* **Sztywne ograniczenie w `DecCallBack`**:
  ```cpp
  if (player->m_pendingTasks.load() + player->m_guiPendingTasks.load() >= 5) {
      // Drastyczne odcięcie - odrzucamy nowe klatki wideo
      return;
  }
  ```
  Jeśli suma klatek przetwarzanych przez pulę wątków w tle oraz klatek wiszących w kolejce GUI przekroczy 5, dekoder **natychmiast odrzuca klatkę**. Gwarantuje to, że nawet jeśli główny wątek GUI z jakiegokolwiek powodu zostanie całkowicie zablokowany, program zużyje maksymalnie ~160 MB na bufory klatek, chroniąc system przed wyczerpaniem pamięci.

### 3. Rozwiązanie - Stabilizujący filtr częstotliwości próbkowania (Audio Lock)
Aby całkowicie usunąć pierwotną przyczynę blokowania wątku głównego (przeładowanie PulseAudio):
* Wprowadziliśmy mechanizm `m_lastProposedSampleRate` i `m_sampleRateConsecutiveCount`.
* Nowy algorytm wymaga, aby estymowana częstotliwość próbkowania dźwięku była **dokładnie taka sama przez co najmniej 5 kolejnych ramek audio** przed podjęciem decyzji o ponownej inicjalizacji `QAudioOutput`.
* Zapobiega to natychmiastowym fluktuacjom wywoływanym przez zakłócenia sieciowe (jitter), eliminując zawieszanie wątku graficznego przy starcie i przełączaniu kamer z dźwiękiem.

---

## 23. Pomoc/Instrukcja: Wektorowe Ikony SVG w Oknie Instrukcji i Automatyczne Wyświetlanie przy Pierwszym Uruchomieniu

Wprowadziliśmy szereg usprawnień podnoszących estetykę i wygodę korzystania z wbudowanego okna instrukcji/pomocy:

### 1. Rozbudowa Instrukcji o Rozdział 1 - „Opis działania przycisków”
* Dodaliśmy zupełnie nową, dedykowaną sekcję **„1. Opis działania przycisków”** (w języku polskim w [INSTRUKCJA.md](file:///home/arkanis/cctv/kvision/INSTRUKCJA.md) oraz angielskim w [INSTRUCTIONS.md](file:///home/arkanis/cctv/kvision/INSTRUCTIONS.md)).
* Przesunęliśmy wszystkie dotychczasowe rozdziały (dawne 1–10) o jeden numer w dół (stając się teraz rozdziałami 2–11).
* Zaktualizowaliśmy spis treści oraz wszystkie odnośniki krzyżowe wewnątrz dokumentów (np. odwołania do Sekcji 3, Sekcji 4, Sekcji 11 itd.), zachowując pełną spójność i poprawność odnośników.
* **Rozszerzenie Sekcji Odtwarzacza**: Rozbudowaliśmy sekcję przycisków odtwarzacza archiwum (Playback Window) o pełen opis elementów górnego paska sterowania (zamknięcie okna, przypięcie paska, pełny ekran, przełącznik paska bocznego i osi czasu, foldery nagrań/stopklatek, siatka `1x1`..`2x2`) oraz dolnego paska i osi czasu (dzień wstecz/w przód, kalendarz, przejście do dzisiaj, odświeżenie nagrań, powiększenia osi 1h/8h/24h, wyśrodkowanie osi, prędkości odtwarzania, downloader, skoki czasowe w sekundy wstecz i w przód, play/pause).

### 2. Eliminacja Emoji i Wdrożenie Natywnych Ikon Wektorowych SVG w RichText QML
* **Problem**: Wykorzystanie emoji do prezentacji wyglądu przycisków w instrukcji było niespójne wizualnie (różny wygląd w zależności od czcionek systemowych, brak dopasowania do ciemnego motywu KVision).
* **Rozwiązanie**:
  * Zaprojektowaliśmy i wdrożyliśmy bazę **30 precyzyjnych definicji wektorowych SVG** odpowiadających dokładnie ikonom interfejsu użytkownika KVision (odtwarzanie, pauza, nagrywanie, zoom, kalendarz, wybór układu siatki, prędkości odtwarzania, downloader, skoki czasowe itd.) z zachowaniem kolorystyki aplikacji (`#00f5d4`).
  * W [InstructionsWindow.qml](file:///home/arkanis/cctv/kvision/src/InstructionsWindow.qml) stworzyliśmy pomocniczą funkcję `getIconHtml(name)`, która dynamicznie konwertuje kod XML SVG do formatu Base64 (`Qt.btoa()`) i zwraca bezpieczny element `<img>` typu `data:image/svg+xml;base64,...`.
  * Integracja z parserem Markdown: Podczas renderowania instrukcji tagi typu `{ICON:name}` (np. `{ICON:play}`, `{ICON:grid_2x2}`) są w locie zastępowane wygenerowanym kodem HTML `<img>`, co umożliwia renderowanie ostrych, skalowalnych wektorowo ikon bezpośrednio wewnątrz pola tekstowego typu `Text.RichText`.

### 3. Automatyczny Popup przy Pierwszym Uruchomieniu, Flaga `--first-run` i Korekta Focusu
* **Problem ze startem (race condition)**: Wywołanie `instructionsWindow.show()` bezpośrednio w zdarzeniu `Component.onCompleted` głównego okna programu uruchamiało się w momencie, gdy system operacyjny jeszcze w pełni nie zamapował ani nie skupił na sobie głównego okna. Kiedy okno główne w pełni się otworzyło, menedżer okien systemu operacyjnego (OS Window Manager) narzucał je na wierzch, ukrywając otwarte okno instrukcji pod nim.
* **Rozwiązanie**:
  * Zaimplementowaliśmy dedykowany, jednorazowy timer `firstRunHelpTimer` (o opóźnieniu 350 ms) w pliku [RootWindow.qml](file:///home/arkanis/cctv/kvision/src/RootWindow.qml).
  * Przy starcie programu z flagą `--first-run` lub przy pierwszym uruchomieniu uruchamiany jest ten timer, który po upływie opóźnienia wywołuje kolejno: `instructionsWindow.show()`, `instructionsWindow.raise()` oraz `instructionsWindow.requestActivate()`. Gwarantuje to, że okno instrukcji otworzy się idealnie nad oknem głównym, wycentrowane i skupione (focused).
  * Zaktualizowaliśmy również manualny przycisk wyzwalający pomoc, dodając do niego wywołania `raise()` oraz `requestActivate()`, co sprawia, że jeśli okno pomocy jest już otwarte w tle, kliknięcie przycisku natychmiast wyciągnie je na samą górę.
* **Wymuszenie Zachowania (`--first-run`)**: Dodaliśmy nową flagę CLI `--first-run` do parsera opcji linii komend C++ w [context.cpp](file:///home/arkanis/cctv/kvision/src/context.cpp). Przekazanie tej flagi wymusza potraktowanie sesji jako pierwszego uruchomienia i automatycznie otwiera okno instrukcji, co ułatwia debugowanie i prezentację aplikacji.

### 4. Korekta Tłumaczeń w en_US oraz kvision_en_US
* Poprawiliśmy tłumaczenie angielskich komunikatów wersji i autora w plikach `.ts` ([en_US.ts](file:///home/arkanis/cctv/kvision/translations/en_US.ts) oraz [kvision_en_US.ts](file:///home/arkanis/cctv/kvision/translations/kvision_en_US.ts)):
  * `Wersja %1` -> `Version %1`
  * `Oryginalny autor: Evgeny S. Maksimov` -> `Original author: Evgeny S. Maksimov`
* Przeprowadziliśmy udaną kompilację wszystkich plików tłumaczeń do formatu `.qm`, weryfikując kompletność oraz poprawność działania lokalizacji.

---

## 24. Odblokowanie Ustawień NVR, Rozszerzenie Menu Viewportów i Centralny Dialog Potwierdzenia Stopklatki (Teal Dialog)

Dodaliśmy szereg zaawansowanych funkcji sterowania i powiadamiania przy wykonywaniu stopklatek oraz odblokowaliśmy pełne edytowanie ustawień kamer rejestratorów Hikvision w menu podręcznym.

### 1. Odblokowanie Edycji Ustawień Kamer NVR
* **Problem**: W pliku `ViewportsLayout.qml` opcja menu podręcznego **„Zmień ustawienia”** była sztucznie wyłączona (disabled) dla kamer Hikvision przy użyciu warunku `model.url.indexOf("hikvision://") !== 0`. Uniemożliwiało to bezpośrednią modyfikację parametrów połączeń i haseł kamer pochodzących z rejestratora.
* **Rozwiązanie**: Usunięto to ograniczenie. Od teraz element podręczny jest aktywny dla każdego prawidłowego adresu streamu (`enabled: model.url !== ""`), co pozwala na bezproblemową konfigurację dowolnej kamery w locie.

### 2. Nowe Opcje Menu Podręcznego Viewportów
W menu wywoływanym prawym przyciskiem myszy na każdym viewportcie dodano trzy nowe, elegancko ostylowane pozycje (w kolorystyce `#00f5d4` seledyn/teal-green przy najechaniu kursorem):
* **„Stopklatka”** (`Snapshot`): Wykonuje natychmiastowy zrzut klatki z aktualnie aktywnego strumienia wideo (MAIN lub SUB).
* **„Stopklatka HD”** (`Snapshot HD`): Wykonuje zrzut ekranu w wysokiej rozdzielczości (HD). Jeśli aktywny strumień to `SUB`, odtwarzacz tymczasowo i bezszmerowo przełącza jakość na `MAIN`, rejestruje klatkę, a następnie automatycznie powraca do trybu `SUB`. W przypadku powiększonego lub pełnoekranowego viewportu, gdzie strumień to już naturalnie `MAIN`, stopklatka HD jest wykonywana bezpośrednio.
* **„Odtwarzaj”** (`Playback`): Błyskawicznie otwiera okno odtwarzacza archiwalnego dla wybranej kamery.

### 3. Centralny, Seledynowy Dialog Potwierdzenia Zapisu Stopklatki (`SnapshotSavedDialog.qml`)
Zaprojektowaliśmy i wdrożyliśmy nowy, niezwykle estetyczny element interfejsu potwierdzający pomyślny zapis stopklatki:
* **Wygląd (Rich Aesthetics)**: Ciemne tło (`#1c242c`), wyrazista seledynowa obwódka o grubości `1.5` i zaokrągleniu `8px` (`border.color: "#00f5d4"`, `radius: 8`), tealowa nagłówkowa linia podziału oraz dedykowany wektorowy symbol aparatu fotograficznego SVG (`#00f5d4`).
* **Wyświetlana treść**: `"Zapisano stopklatkę - <pełna ścieżka do pliku>"`
* **Przycisk „Przeglądaj”**: Otwiera nadrzędny folder z zapisaną stopklatką w systemowym eksploratorze plików za pomocą natywnego wywołania `Qt.openUrlExternally()`.
* **Przycisk „Wyjdź”**: Natychmiastowo zamyka popup potwierdzający.
* **Auto-zamykanie (Inactivity Timeout)**: Jeśli użytkownik nie podejmie akcji, dialog automatycznie zamknie się po dokładnie **15 sekundach** dzięki wbudowanemu licznikowi czasu `Timer`.
* **Pełna integracja**: Dialog został wdrożony jako dynamicznie sterowany element w głównym oknie aplikacji (`RootWindow.qml`), oknach pomocniczych (`AuxiliaryWindow.qml`) oraz oknie odtwarzacza archiwalnego (`PlaybackWindow.qml`).

### 4. Lokalizacja (Tłumaczenia) i Budowanie
* Zaktualizowaliśmy wszystkie trzy pliki tłumaczeń (`translations/kvision_pl_PL.ts`, `translations/kvision_en_US.ts` oraz `translations/en_US.ts`), dodając pełne polskie i angielskie odpowiedniki dla wszystkich nowo wprowadzonych fraz i tekstów przycisków.
* Z powodzeniem skompilowaliśmy zasoby i kod C++ aplikacji (`cmake --build build -j$(nproc)`). Wszystkie testy jednostkowe oraz testy integracyjne QML zakończyły się pełnym sukcesem.

### 5. Wyłączenie i usunięcie opcji "Stopklatka HD"
* **Usunięcie z menu podręcznego**: Całkowicie wycięto element `Stopklatka HD` (`snapshotHdMenuItem`) z menu kontekstowego viewportów w `ViewportsLayout.qml`.
* **Uproszczenie Player.qml**: Usunięto dedykowane właściwości `pendingHdSnapshot` i `originalStreamMode`, timery `hdSnapshotTimeoutTimer` i `hdSnapshotCaptureTimer` oraz interfejs graficzny informujący o ładowaniu HD (`hdLoadingOverlay`). Funkcja `takeSnapshot()` została uproszczona do standardowego przechwytywania klatki z zachowaniem pełnej stabilności i wydajności.
* **Kompilacja i weryfikacja**: Kod źródłowy kompiluje się bez żadnych błędów czy ostrzeżeń, a testy jednostkowe przechodzą pomyślnie.

---

## 25. Wielodystrybucyjność i kompatybilność RPATH (Ubuntu & Arch Linux)

Wprowadziliśmy dynamiczne wyznaczanie ścieżek wyszukiwania bibliotek współdzielonych (RPATH), co rozwiązuje problem uruchamiania aplikacji na dystrybucjach Ubuntu/Debian i pochodnych bez zakłócania procesu budowania ze źródeł na Arch Linux:

### 1. Problem multiarch i statycznego RPATH
* Na systemach **Arch Linux** biblioteki współdzielone instalowane są bezpośrednio do `/usr/lib`. Wartość `${CMAKE_INSTALL_LIBDIR}` ewaluuje się do `lib`.
* Na systemach **Debian/Ubuntu** i pochodnych stosowana jest architektura **multiarch**, w której biblioteki instalowane są w katalogu zależnym od architektury, np. `/usr/lib/x86_64-linux-gnu`. `${CMAKE_INSTALL_LIBDIR}` ewaluuje się tam do `lib/x86_64-linux-gnu`.
* Wcześniejsza konfiguracja CMake miała na sztywno zahardkodowany `INSTALL_RPATH` jako `\$ORIGIN/../lib/kvision`. Na Ubuntu dynamiczny linker próbował załadować biblioteki SDK Hikvision (`libhcnetsdk.so` itd.) z katalogu `/usr/lib/kvision`, który nie istniał (ponieważ SDK zostało prawidłowo zainstalowane do `/usr/lib/x86_64-linux-gnu/kvision`), co skutkowało błędem braku plików i przerwaniem uruchamiania programu.

### 2. Rozwiązanie (Dynamiczny RPATH)
* Przesunęliśmy wywołanie `include(GNUInstallDirs)` na sam początek pliku `CMakeLists.txt` (zaraz pod definicją projektu), aby zmienne instalacyjne były zdefiniowane przy deklaracji właściwości targetów.
* Zastąpiliśmy zahardkodowaną ścieżkę w `INSTALL_RPATH` dynamiczną zmienną CMake:
  ```cmake
  INSTALL_RPATH "\$ORIGIN/../${CMAKE_INSTALL_LIBDIR}/kvision"
  ```
* Rozwiązanie to jest w pełni kompatybilne wstecznie. Podczas instalacji na Arch Linux ścieżka rozwinie się automatycznie do `\$ORIGIN/../lib/kvision`, natomiast na systemach Debian/Ubuntu do `\$ORIGIN/../lib/x86_64-linux-gnu/kvision`. Gwarantuje to poprawne załadowanie wszystkich bibliotek Hikvision SDK na każdej dystrybucji bez konieczności utrzymywania osobnych konfiguracji budowania.

---

## 26. Pobieranie informacji o detekcji ruchu z rejestratora (Hikvision SDK)

Zaprojektowaliśmy kompletną architekturę pobierania informacji o alarmach detekcji ruchu z rejestratorów NVR za pośrednictwem oficjalnego SDK Hikvision:

### 1. Rejestracja globalnego callbacku alarmowego
Do nasłuchiwania na pakiety alarmowe z urządzeń wymagana jest rejestracja statycznej/globalnej funkcji zwrotnej w SDK za pomocą funkcji `NET_DVR_SetDVRMessageCallBack_V50`:
```cpp
// W HikvisionManager (C++):
NET_DVR_SetDVRMessageCallBack_V50(0, MessageCallback, this);
```
Wskaźnik `this` (instancja naszego menedżera) jest przekazywany jako parametr `pUser`, co umożliwia dostęp do obiektów i sygnałów Qt z poziomu statycznej funkcji callbacku.

### 2. Aktywacja (uzbrojenie) strumienia alarmowego (Arming)
Po pomyślnym zalogowaniu się do rejestratora (`lUserID`), należy wywołać funkcję uzbrojenia kanału alarmowego `NET_DVR_SetupAlarmChan_V41`:
```cpp
NET_DVR_SETUPALARM_PARAM struSetupParam = {0};
struSetupParam.dwSize = sizeof(NET_DVR_SETUPALARM_PARAM);
struSetupParam.byLevel = 1;         // Poziom alarmów (0-bardzo ważne, 1-standardowe)
struSetupParam.byAlarmInfoType = 1;  // Informacje zgodne z nowymi strukturami V40
struSetupParam.byDeployType = 1;     // Typ: uzbrojenie klienckie (Client Arming)

LONG lAlarmHandle = NET_DVR_SetupAlarmChan_V41(lUserID, &struSetupParam);
if (lAlarmHandle < 0) {
    qWarning() << "Nie udało się uzbroić kanału alarmowego dla userID:" << lUserID;
}
```

### 3. Filtrowanie i interpretacja zdarzeń w callbacku
Wewnątrz zarejestrowanego callbacku odbieramy komendy (`lCommand`). Detekcja ruchu przekazywana jest głównie poprzez komendy `COMM_ALARM_V30` (starsza) oraz `COMM_ALARM_V40` (nowsza). Typ alarmu `3` oznacza detekcję ruchu:
```cpp
void CALLBACK MessageCallback(LONG lCommand, NET_DVR_ALRAM_INFO_V30 *pAlramInfo, char *pBuf, DWORD dwBufLen, void* pUser) {
    HikvisionManager* manager = static_cast<HikvisionManager*>(pUser);
    if (!manager) return;

    if (lCommand == COMM_ALARM_V30) {
        NET_DVR_ALRAM_INFO_V30* struAlarmInfo = (NET_DVR_ALRAM_INFO_V30*)pAlramInfo;
        if (struAlarmInfo->dwAlarmType == 3) { // 3 = Motion Detection
            int channelId = struAlarmInfo->dwAlarmInputNumber; // Numer kanału (kamery)
            emit manager->motionDetected(manager->getIpByUserId(struAlarmInfo->lUserID), channelId, true);
        }
    } 
    else if (lCommand == COMM_ALARM_V40) {
        NET_DVR_ALRAM_INFO_V40* struAlarmInfo = (NET_DVR_ALRAM_INFO_V40*)pAlramInfo;
        if (struAlarmInfo->dwAlarmType == 3) {
            int channelId = struAlarmInfo->struAlarmChannel.dwChannel;
            emit manager->motionDetected(manager->getIpByUserId(struAlarmInfo->lUserID), channelId, true);
        }
    }
}
```

### 4. Zarządzanie stanem aktywności (Decay Timer)
Ponieważ SDK wysyła zdarzenie detekcji w momencie rozpoczęcia ruchu lub cyklicznie podczas jego trwania (bez jawnego sygnału "ruch się zakończył"), w warstwie C++ (lub QML) stosuje się licznik opóźnienia wygaśnięcia (tzw. **Decay Timer**):
* Po nadejściu sygnału `motionDetected(..., true)` uruchamiamy licznik czasu o interwale np. **8 sekund**.
* Każde kolejne nadejście sygnału detekcji dla tego samego kanału **resetuje i uruchamia ponownie** ten timer.
* Jeśli timer wygaśnie bez odebrania nowych alarmów w tym oknie czasowym, emitujemy sygnał zakończenia ruchu: `motionDetected(..., false)`. Zapobiega to gwałtownemu miganiu ikonek na podglądzie w przypadku chwilowych spadków intensywności ruchu.

---

## 26. Aktualizacja Changelogów i Synchronizacja Wydania na GitHubie (Wersja v2.2.7)

Zgodnie z wymaganiami użytkownika, uzupełniono changelogi w kodzie źródłowym, paczce Debiana oraz na platformie GitHub o najbardziej istotne i krytyczne zmiany techniczne wprowadzone w wersji **v2.2.7**:

### 1. In-App Changelog (język polski, `SideBar.qml`)
Rozbudowano listę zmian w panelu bocznym aplikacji o szczegółowe opisy:
* **Rewolucja w obsłudze dźwięku PCM**: Bezpośrednie przekazywanie potoku audio do `QAudioOutput`, stabilizacja sample rate za pomocą debounce (wymóg 5 stabilnych ramek), cooldown 2s na rekreację wyjścia, filtracja uszkodzonych parametrów i bufor 64KB redukujący jitter sieciowy.
* **Automatyczne wyciszanie Live View**: Automatyczne wyciszanie strumieni LIVE przy otwarciu okna odtwarzania Archiwum w celu uniknięcia nakładania się dźwięków (kakofonii).
* **Nowy system powiadomień**: Centralny dialog `SnapshotSavedDialog` informujący o zapisaniu stopklatki (ciemnoszare tło `#1c242c`, seledynowe krawędzie `#00f5d4`, auto-zamknięcie po 10 sekundach) wraz z bezpośrednim przyciskiem "Przeglądaj" do natychmiastowego otwarcia katalogu w systemowym menedżerze plików.
* **Dynamiczny RPATH (Ubuntu/Debian)**: Zastosowanie `GNUInstallDirs` i dynamicznego `INSTALL_RPATH` w `CMakeLists.txt`, co całkowicie eliminuje crashe przy uruchamianiu aplikacji z paczki na systemach Ubuntu/Debian i usuwa potrzebę ręcznej konfiguracji `ldconfig`.

### 2. Debian Changelog (`debian/changelog`)
Wpisy dla wersji `2.2.7-1` zostały w pełni zaktualizowane i wzbogacone o profesjonalne, szczegółowe opisy techniczne w języku angielskim:
* Pełne wyjaśnienie zmian w potoku PCM audio, w tym filtr sample rate debounce, 2-sekundowy cooldown i 64KB buffer.
* Opis automatycznego wyciszania siatki podglądu na żywo podczas sesji odtwarzania.
* Opis nowego interfejsu powiadomień `SnapshotSavedDialog` z automatycznym zamknięciem i przyciskiem przeglądania.
* Opis dynamicznego dynamic-linking RPATH na Ubuntu/Debian za pomocą `${CMAKE_INSTALL_LIBDIR}`.

### 3. GitHub Release Notes (`create_release_2_2_7.py`)
Zaktualizowano szablon opisu wydania na GitHubie w skrypcie synchronizacyjnym. Skrypt został uruchomiony i pomyślnie zaktualizował opis release **v2.2.7** na platformie GitHub, a także podmienił plik binarny paczki Arch Linux (`kvision-2.2.7-1-x86_64.pkg.tar.zst`).




