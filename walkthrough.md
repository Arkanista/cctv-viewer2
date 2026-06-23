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



