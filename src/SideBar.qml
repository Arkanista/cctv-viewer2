import QtQml 2.12
import QtQuick 2.12
import QtQuick.Layouts 1.12
import QtQuick.Controls 2.12
import Qt.labs.settings 1.0
import QtGraphicalEffects 1.12
import CCTV_Viewer.Core 1.0
import CCTV_Viewer.Themes 1.0
import CCTV_Viewer.Utils 1.0
import CCTV_Viewer.Hikvision 1.0
import Qt.labs.platform 1.1 as Platform
import QtQuick.Dialogs 1.3 as QuickDialogs

FocusScope {
    id: rootSideBar

    enum State {
        Compact,
        Popup,
        Expanded
    }

    anchors.fill: parent
    implicitWidth: 800
    implicitHeight: 600

    property int state: SideBar.Expanded
    property int currentViewportIndex: Utils.currentLayout() ? Utils.currentLayout().focusIndex : -1

    onVisibleChanged: {
        resetPathChangesCheckbox();
    }

    function resetPathChangesCheckbox() {
        if (typeof activatePathChangesCheckbox !== "undefined" && activatePathChangesCheckbox) {
            activatePathChangesCheckbox.checked = false;
        }
        if (typeof activateMediaChangesCheckbox !== "undefined" && activateMediaChangesCheckbox) {
            activateMediaChangesCheckbox.checked = false;
        }
    }

    property var regularIndices: []
    property var nvrIndices: []
    property var nvrPresetIndices: []

    property bool hasNewVersion: false
    property string newVersionString: ""

    function compareVersions(v1, v2) {
        var parts1 = v1.split(".").map(Number);
        var parts2 = v2.split(".").map(Number);
        for (var i = 0; i < Math.max(parts1.length, parts2.length); ++i) {
            var p1 = parts1[i] || 0;
            var p2 = parts2[i] || 0;
            if (p1 !== p2) {
                return p1 - p2;
            }
        }
        return 0;
    }

    function checkForUpdates() {
        if (Context.mockNewVersion) {
            hasNewVersion = true;
            newVersionString = "v9.9.9 (MOCK)";
            return;
        }
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "https://api.github.com/repos/Arkanista/KVision/releases/latest", true);
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        var response = JSON.parse(xhr.responseText);
                        var latestVersion = response.tag_name;
                        var currentVersion = Qt.application.version;
                        
                        var latestClean = latestVersion.replace(/^v/, "");
                        var currentClean = currentVersion.replace(/^v/, "");
                        
                        if (compareVersions(latestClean, currentClean) > 0) {
                            hasNewVersion = true;
                            newVersionString = latestVersion;
                        } else {
                            hasNewVersion = false;
                        }
                    } catch (e) {
                        console.error("Failed to parse update check response:", e);
                    }
                }
            }
        }
        xhr.send();
    }

    function updateIndices() {
        var regs = [];
        var nvrs = [];
        var nvrPres = [];
        for (var i = 0; i < layoutsCollectionModel.count; ++i) {
            var layout = layoutsCollectionModel.get(i);
            if (layout) {
                if (layout.isNvr) {
                    nvrs.push(i);
                } else if (layout.isNvrPreset) {
                    nvrPres.push(i);
                } else {
                    regs.push(i);
                }
            }
        }
        regularIndices = regs;
        nvrIndices = nvrs;
        nvrPresetIndices = nvrPres;
    }

    Component.onCompleted: {
        layoutsCollectionModel.changed.connect(updateIndices);
        updateIndices();
        resetPathChangesCheckbox();
        checkForUpdates();
    }

    property var changelogData: [
        {
            version: "v2.4.1",
            date: "01.07.2026",
            changes: [
                qsTr("Dodano niskopoziomowe opcje FFmpeg (nobuffer, low_delay) usuwające opóźnienia w strumieniach na żywo (drift) przy wielogodzinnym działaniu."),
                qsTr("Wprowadzono przycisk masowej aktualizacji parametrów FFmpeg dla wszystkich istniejących kamer we wszystkich układach."),
                qsTr("Dodano opcję wykluczenia wybranej kamery z aktualizacji globalnych parametrów FFmpeg (nowy checkbox w ustawieniach viewportu)."),
                qsTr("Zabezpieczono proces migracji ustawień domyślnych, umożliwiając użytkownikowi trwałe usunięcie lub zmodyfikowanie nowych flag bez ich ponownego wymuszania przy każdym starcie.")
            ]
        },
        {
            version: "v2.4.0",
            date: "30.06.2026",
            changes: [
                qsTr("Dodano funkcjonalność szybkiego podglądu wstecz (do 30 minut) bezpośrednio w kafelku kamery (viewport).")
            ]
        },
        {
            version: "v2.3.0",
            date: "30.06.2026",
            changes: [
                qsTr("Zaimplementowano pełną, dwukierunkową synchronizację w czasie rzeczywistym między wszystkimi oknami i pomocniczymi procesami programu dla ustawień: wyciszenia dźwięku, wyłączenia animacji zoomu oraz wszystkich parametrów monitorowania statusu rejestratorów Hikvision NVR."),
                qsTr("Dodano dynamiczne wyświetlanie opisów minut (np. :15, :30, :45) przy podziałkach minutowych na osi czasu odtwarzacza archiwalnego z inteligentnym dostosowywaniem gęstości napisów (zoomHours)."),
                qsTr("Dodano nową opcję w ustawieniach interfejsu użytkownika: \"Wyłącz animację powiększania viewportu\" z natychmiastowym zastosowaniem w widoku siatki kamer."),
                qsTr("Przebudowano proces inicjalizacji odtwarzacza archiwalnego: wstrzymano logowanie i ładowanie wideo do czasu precyzyjnego ustalenia krańców nagrania (asynchroniczne, ultra-szybkie przeszukiwanie zakresu 24h), eliminując przedwczesne odtwarzanie i skakanie obrazu."),
                qsTr("Usprawniono komunikaty ładowania archiwum Hikvision – informacja o ładowaniu jest widoczna tylko podczas aktywnego pobierania strumienia, a w przypadku ustawienia suwaka poza zakresem nagrania wyświetlany jest dedykowany komunikat ostrzegawczy."),
                qsTr("Wprowadzono nowe pola konfiguracji w panelu ustawień: domyślne przesunięcie startu odtwarzania archiwalnego (start offset w sekundach, domyślnie 60s) oraz domyślne przybliżenie osi czasu (zoom hours, domyślnie 2h)."),
                qsTr("Dodano ikonę bezpośredniego logowania do panelu web rejestratora w oknie statusu NVR.")
            ]
        },
        {
            version: "v2.2.8-2",
            date: "29.06.2026",
            changes: [
                qsTr("Dodano funkcjonalność wyciszania (Suppression) raportowania błędów dla poszczególnych rejestratorów (pole wyboru \"Wycisz\"). Wyciszenie maskuje błędy rejestratora w globalnych wskaźnikach alarmów, ale zachowuje podgląd błędów i czerwone wyróżnienie bezpośrednio na kafelkach w popupie statusu."),
                qsTr("Poprawiono błędną polską translację \"Symulowany Rejestrator\" w oknie statusu oraz wdrożono właściwe rozróżnienie słowne (\"Suppress\" dla błędów vs \"Mute\" dla dźwięku).")
            ]
        },
        {
            version: "v2.2.8-1",
            date: "29.06.2026",
            changes: [
                qsTr("Zaimplementowano okresowe (co 5 minut) oraz ręczne sprawdzanie stanu błędów rejestratorów Hikvision (SDK / ISAPI)."),
                qsTr("Dodano dedykowaną sekcję w ustawieniach ogólnych do włączania monitorowania oraz wyboru monitorowanych błędów (błędy logowania, przeciążenie CPU >85%, błędy sprzętowe, uszkodzenia dysków, brak formatu, brak nadpisywania)."),
                qsTr("Zaprojektowano animowaną ikonę ostrzegawczą na górnym pasku w kolorze ciepłym-zielonym (status OK) lub pulsującym czerwonym z podwójną poświatą (wykryto krytyczne błędy)."),
                qsTr("Wprowadzono wystające czerwone kółko ostrzegawcze przy górnej krawędzi ekranu, widoczne i pulsujące nawet wtedy, gdy pasek narzędziowy jest ukryty."),
                qsTr("Stworzono eleganckie, przewijane, ograniczone do 85% wysokości ekranu okno popup \"Status rejestratorów\" ze szczegółowym podglądem błędów urządzeń, błędów dysków oraz dokładnym czasem ostatniego sprawdzenia."),
                qsTr("Dodano flagę uruchomieniową \"--simulate-error\" do natychmiastowej symulacji uszkodzeń dysków oraz błędów połączenia we wszystkich rejestratorach w celach demonstracyjnych."),
                qsTr("Wdrożono plakietki ostrzegawcze i wyrównanie wskaźników stanu w listach skonfigurowanych rejestratorów."),
                qsTr("Zapewniono pełne dwujęzyczne (polski/angielski) tłumaczenie wszystkich nowych komunikatów diagnostycznych, ustawień i opcji programu.")
            ]
        },
        {
            version: "v2.2.7-5",
            date: "29.06.2026",
            changes: [
                qsTr("Dodano możliwość ponownego przeładowania aktywnego układu poprzez kliknięcie jego przycisku na górnym pasku.")
            ]
        },
        {
            version: "v2.2.7-4",
            date: "29.06.2026",
            changes: [
                qsTr("Uśredniono próbki pobierane z biblioteki NVML w celu wygładzenia wykresu zużycia GPU i wyeliminowania skokowych wahań odczytu.")
            ]
        },
        {
            version: "v2.2.7-3",
            date: "29.06.2026",
            changes: [
                qsTr("Wyeliminowano chwilowe mrugnięcia (czarne klatki) oraz opóźnienia obrazu i dźwięku podczas przełączania jakości wideo ze strumienia pomocniczego (SUB) na główny (MAIN) przy powiększaniu viewportu, synchronizując moment przełączenia z fizycznym wyrenderowaniem pierwszej klatki nowego strumienia."),
                qsTr("Dodano interaktywne, wyraźne i 2x szersze suwaki (paski przewijania) do kolumn wyboru godzin, minut i sekund w oknie wyboru czasu pobierania z archiwum."),
                qsTr("Dodano nowe, intuicyjne opcje do menu podręcznego viewportów (pod prawym przyciskiem myszy): 'Stopklatka' (zapis bieżącej klatki) oraz 'Odtwarzaj' (natychmiastowe przejście do archiwalnego odtwarzania danej kamery)."),
                qsTr("Zrewolucjonizowano i naprawiono obsługę dźwięku PCM: bezpośrednie przekazywanie potoku do QAudioOutput, eliminacja zawieszeń interfejsu (ALSA/PulseAudio/Pipewire) przez stabilizację sample rate (debounce po 5 stabilnych ramkach), cooldown 2s na rekreację wyjścia, filtrowanie uszkodzonych parametrów i bufor 64KB redukujący jitter sieciowy."),
                qsTr("Zaimplementowano interaktywny suwak regulacji głośności HUD bezpośrednio na kafelkach viewportów wraz z opcją szybkiego wyciszenia oraz maksymalizacji głośności jednym kliknięciem."),
                qsTr("Zaimplementowano automatyczne i natychmiastowe wyciszanie strumieni LIVE w siatce głównej przy otwarciu okna odtwarzania Archiwum, co zapobiega nakładaniu się dźwięków (kakofonii)."),
                qsTr("Wprowadzono centralny system powiadomień SnapshotSavedDialog o zapisaniu stopklatki (ciemnoszara obudowa, seledynowe krawędzie, auto-zamknięcie po 10 sekundach) z szybkim łączem 'Przeglądaj' do bezpośredniego otwierania folderu w systemowym menedżerze plików."),
                qsTr("Wzbogacono wbudowane okno pomocy o szczegółowy rozdział 'Opis działania przycisków' z natywnymi, ostrymi ikonami wektorowymi SVG. Okno pomocy otwiera się teraz w pełni automatycznie i wyśrodkowane nad oknem głównym przy pierwszym uruchomieniu programu."),
                qsTr("Wprowadzono domyślne wyświetlanie paska górnego przy uruchomieniu programu/okna oraz dodano w ustawieniach opcję 'Domyślnie pokazuj pasek górny po otwarciu okna', umożliwiającą dostosowanie tego zachowania do własnych preferencji."),
                qsTr("Zaimplementowano dynamiczną ścieżkę bibliotek RPATH w CMakeLists.txt z użyciem GNUInstallDirs, co umożliwia natychmiastowe uruchomienie skompilowanej aplikacji na Ubuntu i Debianie bez konieczności ręcznej konfiguracji /etc/ld.so.conf.d/ i ldconfig.")
            ]
        },
        {
            version: "v2.2.6-3",
            date: "27.06.2026",
            changes: [
                qsTr("Zmieniono nazwę programu na KVision wraz z automatyczną migracją dotychczasowych ustawień użytkownika, nowymi ikonami o wielu rozmiarach (128px, 256px, 512px) oraz wyświetlaniem pełnej wersji w pasku tytułowym."),
                qsTr("Naprawiono okno ostrzegawcze przekroczenia limitu okien pomocniczych (brakujący zasób QML i odczyt z QSettings)."),
                qsTr("Naprawiono brakującą ikonę programu pod Waylandem (instalacja w motywie hicolor oraz setDesktopFileName)."),
                qsTr("Wycofano opcję automatycznego zwijania paska górnego z ustawień – odtąd pasek górny w oknach LIVE (głównym i pomocniczym) zwija się domyślnie przy starcie, a pinezka przypina go lokalnie i tymczasowo (w pamięci) bez zapisywania stanu."),
                qsTr("Wprowadzono limit liczby okien pomocniczych (konfigurowalny w zakresie 0-3) z eleganckim oknem ostrzegawczym o zablokowaniu przy próbie jego przekroczenia."),
                qsTr("Dodano subtelne, ciemnoszare ramki o szerokości 1px wokół nieużywanych viewportów w siatce podglądu LIVE dla lepszego rozgraniczenia pól."),
                qsTr("Zabezpieczono edycję ścieżek zapisu i konfiguracji multimediów w ustawieniach przejściowym polem wyboru 'Uaktywnij zmiany w tej sekcji', zapobiegając przypadkowym modyfikacjom (stan edycji resetuje się po zamknięciu)."),
                qsTr("Wprowadzono bezpośrednie skróty 'otwórz folder zapisu' (wyróżniony seledynowym kolorem przy ukończonym pobieraniu w oknie Archiwum) oraz zawsze aktywne przyciski szybkiego otwierania folderów zrzutów i wideo w ustawieniach (z automatycznym tworzeniem katalogu na dysku)."),
                qsTr("Wprowadzono interaktywną walidację przy kliknięciu przycisku 'Pobierz' w oknie pobierania: automatyczna kontrola formatów pól oraz chronologii dat z dymkiem ostrzegawczym i przekierowaniem fokusu na pierwsze błędne pole."),
                qsTr("Zaimplementowano pełną nawigację klawiaturą (strzałkami góra/dół do zmiany wartości, lewo/prawo do zmiany kolumn) w graficznym selektorze czasu (Clock Picker)."),
                qsTr("Zapewniono całkowicie czysty start okien pomocniczych (bez automatycznego otwierania panelu opcji) oraz wykluczono zapisywanie ustawień geometrii z okien pomocniczych, eliminując zanieczyszczanie konfiguracji."),
                qsTr("Dodano pełne wsparcie dla języka angielskiego dla wszystkich nowych komunikatów o błędach walidacji i formatowania w oknie pobierania.")
            ]
        },
        {
            version: "v2.2.5",
            date: "25.06.2026",
            changes: [
                qsTr("Wyeliminowano wycieki pamięci RAM przy przełączaniu układów kamer poprzez automatyczne i poprawne zatrzymywanie powierzchni wideo przed zmianą formatu oraz dopasowanie rozmiaru renderera."),
                qsTr("Zaimplementowano bezwarunkowe zwalnianie i niszczenie obiektów wyjściowych audio przy zatrzymaniu odtwarzacza oraz wprowadzono ich automatyczny recykling, usuwając wycieki pamięci i wątków w systemie Linux."),
                qsTr("Rozwiązano problem zablokowania wideo (jednokolorowa plansza po powiększeniu viewportu) poprzez wymuszenie prawidłowego wysyłania sygnału dostępności wideo przy prezentacji pierwszej klatki nowego strumienia."),
                qsTr("Dodano globalną opcję w ustawieniach 'Wyłącz obsługę audio całkowicie', pozwalającą całkowicie pominąć przetwarzanie dźwięku w celu eliminacji ewentualnego narzutu i wycieków pamięci."),
                qsTr("Zoptymalizowano moduł statystyk systemowych, wygaszając ciągłe zużycie pamięci poprzez buforowanie identyfikatorów procesów i eliminację alokacji dynamicznych wyrażeń regularnych."),
                qsTr("Wprowadzono agresywne czyszczenie pamięci (Garbage Collection) przy każdej zmianie układu kamer oraz zerowanie kontekstu skalowania obrazu (SwsContext) w buforach wideo."),
                qsTr("Zapewniono poprawne czyszczenie pamięci statycznego detektora zmian plików konfiguracyjnych przy wyjściu z aplikacji."),
                qsTr("Naprawiono błędy synchronizacji i zawieszania się procesu okna pomocniczego na wolniejszych maszynach przy seryjnym usuwaniu kamer oraz łączeniu i przenoszeniu viewportów."),
                qsTr("Naprawiono agregację statystyk obciążenia GPU, pamięci VRAM oraz pasma sieciowego ze wszystkich procesów aplikacji przy wykorzystaniu pamięci współdzielonej (/dev/shm) w tle.")
            ]
        },
        {
            version: "v2.2.0",
            date: "24.06.2026",
            changes: [
                qsTr("Zabezpieczono destruktor odtwarzacza archiwalnego przed wyścigami danych przy usuwaniu zadań RGB."),
                qsTr("Wprowadzono pooling odtwarzaczy wideo w celu eliminacji skoków zużycia pamięci i migotania obrazu przy przełączaniu układów kamer."),
                qsTr("Zoptymalizowano monitorowanie obciążenia GPU i pamięci VRAM do trybu procesowego (bez wywołań nvidia-smi) z natywnym wsparciem dla układów NVIDIA, AMD i Intel (statystyki dla AMD/Intel są nieprzetestowane)."),
                qsTr("Umożliwiono zmianę rozmiaru panelu statystyk systemowych poprzez przeciąganie za jego krawędzie i narożniki z automatycznym skalowaniem wykresów."),
                qsTr("Wprowadzono natychmiastowe ukrywanie okna głównego i pomocniczego przy potwierdzeniu wyjścia, co sprawia, że program zamyka się natychmiastowo dla użytkownika, a zwalnianie wątków i pamięci odbywa się bezpiecznie w tle.")
            ]
        },
        {
            version: "v2.1.9",
            date: "23.06.2026",
            changes: [
                qsTr("Przekształcono górny pasek narzędzi w oknach LIVE i ARCHIWUM w wyśrodkowane pływające doki (dok LIVE ma dynamiczną szerokość)."),
                qsTr("Dodano pionowy separator oddzielający opcje siatki od widoków w dokach na pasku górnym."),
                qsTr("Zwiększono przezroczystość pasków górnego i dolnego w archiwum (60% w oknie, 26% na pełnym ekranie) oraz ustawiono przezroczyste tło osi czasu."),
                qsTr("Uproszczono ikony prędkości odtwarzania w archiwum do czytelnego tekstu (1x, 2x, 4x) i usunięto niestabilną prędkość 8x."),
                qsTr("Zastąpiono tekstowe przyciski nawigacji miesięcy w kalendarzu archiwum i pobierania graficznymi strzałkami (chevronami)."),
                qsTr("Przeniesiono przycisk usuwania kamery z prawego górnego rogu wideo na dolny pasek kontrolny viewportów, zapobiegając przypadkowym kliknięciom."),
                qsTr("Zoptymalizowano kontrast tekstu przycisków wyboru siatki w archiwum (ciemny tekst na seledynowym tle)."),
                qsTr("Przekształcono panel statystyk w okno pływające i przeciągane za pomocą nowego dedykowanego uchwytu (z zachowaniem click-through)."),
                qsTr("Naprawiono krytyczny błąd synchronizacji i pętli zwrotnej zapisu konfiguracyjnego przy usuwaniu układów podglądu.")
            ]
        },
        {
            version: "v2.1.8",
            date: "23.06.2026",
            changes: [
                qsTr("Powiększono ikony sterowania prędkością, zoomem i VCR w archiwum w celu poprawy ich czytelności, a także zwiększono napisy wewnątrz ikon SVG."),
                qsTr("Usunięto zduplikowane przyciski tekstowe dla skrótów zoomu w archiwum, zastępując je w pełni ikonami okrągłymi."),
                qsTr("Dodano kompletne angielskie i polskie tłumaczenia dla wszystkich tooltipów w oknie archiwum.")
            ]
        },
        {
            version: "v2.1.7",
            date: "23.06.2026",
            changes: [
                qsTr("Wprowadzono dwukierunkową synchronizację konfiguracji w czasie rzeczywistym między oknem głównym a pomocniczymi z obsługą unikalnych, automatycznych ID okien pomocniczych.")
            ]
        },
        {
            version: "v2.1.6",
            date: "23.06.2026",
            changes: [
                qsTr("Dodano automatyczne wznawianie sesji (auto-reconnect) w odtwarzaczu archiwum Hikvision po zakończeniu pobierania nagrań lub zerwaniu połączenia przez rejestrator.")
            ]
        },
        {
            version: "v2.1.5",
            date: "23.06.2026",
            changes: [
                qsTr("Wyeliminowano problem potencjalnego wycieku wątków i zawieszenia dekoderów wideo FFmpeg podczas zmiany widoków poprzez przejście na bezpieczne odwołania std::weak_ptr dla kontekstu dekodera."),
                qsTr("Naprawiono wyciek pamięci modeli układów widoków (ViewportsLayouts) poprzez bezpieczne niszczenie obiektów za pomocą deleteLater()."),
                qsTr("Złagodzono błąd uruchamiania powierzchni rysowania wideo OpenGL (start wideo surface) przy bardzo szybkiej zmianie zakładki NVR – logi zostały wyciszone do poziomu Debug, a system w tle ponawia automatycznie próbę renderowania po zwolnieniu buforów karty graficznej.")
            ]
        },
        {
            version: "v2.1.4",
            date: "23.06.2026",
            changes: [
                qsTr("Rozwiązano problem rezydualnego zużycia pamięci RAM (20-30 MB) po zamknięciu okna Archiwum poprzez wieloetapowe oczyszczanie sterty oraz optymalizację pamięci podręcznej silnika QML."),
                qsTr("Zoptymalizowano zużycie pamięci RAM przy skalowaniu i powiększaniu widoku kamer w viewportach, zapobiegając nadmiernemu wzrostowi alokacji pamięci podczas ciągłej zmiany rozmiaru okien strumieni wideo."),
                qsTr("Dodano precyzyjny, rzeczywisty wskaźnik klatek na sekundę (FPS) w lewym górnym rogu każdego viewportu dla strumieni na żywo i odtwarzacza archiwalnego."),
                qsTr("Wdrożono bezpieczne zamykanie i zwalnianie wątków pobierania plików w downloaderze Hikvision, zapewniając stabilne i natychmiastowe zamykanie programu bez blokowania zasobów systemowych.")
            ]
        },
        {
            version: "v2.1.3",
            date: "22.06.2026",
            changes: [
                qsTr("Dodano dynamiczną wyszukiwarkę kamer w oknie archiwum z przyciskiem resetowania i automatycznym rozwijaniem pasujących rejestratorów."),
                qsTr("Włączono zawijanie zbyt długich nazw kamer na kafelkach listy w archiwum."),
                qsTr("Powiększono i odwrócono kolory przycisku plus (+) na kafelkach kamer (seledynowe tło) dla lepszej widoczności, dodając wyraźne stany hover/pressed.")
            ]
        },
        {
            version: "v2.1.2",
            date: "19.06.2026",
            changes: [
                qsTr("Poprawiono przesunięcie paska dostępności nagrań o 2-3 godziny w oknie odtwarzacza archiwum, synchronizując oś czasu ze strefą czasową klienta (z poprawną obsługą czasu letniego/zimowego DST).")
            ]
        },
        {
            version: "v2.1.1",
            date: "19.06.2026",
            changes: [
                qsTr("Zastąpiono słabo widoczną czarną ikonę emoji 📺 w pustym widoku eleganckim seledynowym monitorem wektorowym SVG High-DPI."),
                qsTr("Zwiększono czytelność pasków rejestratorów w oknie archiwum (wysokość zwiększona z 22px do 28px, powiększona czcionka z 9px do 11px, większa strzałka rozwijania)."),
                qsTr("Dodano pełny, dynamiczny efekt hover dla pasków rejestratorów z wyraźną zmianą kolorystyki tła, tekstu oraz ikon na seledynowy/biały.")
            ]
        },
        {
            version: "v2.1.0",
            date: "19.06.2026",
            changes: [
                qsTr("Zastąpiono tekstowe przyciski akcji na górnym pasku (Opcje, Nowe okno, Archiwum, Instrukcje) dedykowanymi, kolorowymi ikonami SVG z pomocniczymi dymkami (Tooltip)."),
                qsTr("Zastąpiono przełącznik statystyk interaktywną ikoną SVG odzwierciedlającą stan aktywności monitora systemowego."),
                qsTr("Ujednolicono przyciski wyboru siatki (1x1-9x9) do spójnych okrągłych przycisków 30x30px."),
                qsTr("Dodano pionową linię rozdzielającą (separator) sekcję opcji od sekcji wyboru siatki."),
                qsTr("Przebudowano przyciski widoków do eleganckiego, zaokrąglonego kształtu pigułki o wysokości 30px z zachowaniem marginesów bocznych."),
                qsTr("Wymuszono automatyczne wyświetlanie nazw widoków wielkimi literami (Uppercase)."),
                qsTr("Poprawiono czytelność i kontrast aktywnego przycisku widoku – ciemny tekst (#121214) na jasnym seledynowym tle."),
                qsTr("Ujednolicono i poprawiono ikony usuwania na liście rejestratorów i widoków oraz przycisk aktywacji presetu na ikony SVG z dymkami (Tooltip)."),
                qsTr("Zmniejszono odległości między przyciskami na górnym pasku w celu optymalizacji przestrzeni interfejsu."),
                qsTr("Przywrócono brakującą ikonę minimalizowania w oknie pomocniczym.")
            ]
        },
        {
            version: "v2.0.9-2 (Patch)",
            date: "19.06.2026",
            changes: [
                qsTr("Poprawka logowania i działania archiwum w oknach pomocniczych."),
                qsTr("Naprawa stanu przycisków siatki (1x1 vs 2x2) przy bezpośrednim otwieraniu archiwum z kamery.")
            ]
        },
        {
            version: "v2.0.9",
            date: "19.06.2026",
            changes: [
                qsTr("Dodano poprawną przestrzeń nazw XML w zapytaniach Hikvision ISAPI (eliminacja błędu 'Invalid XML Content' na nowszym oprogramowaniu układowym rejestratorów)."),
                qsTr("Naprawa obsługi paginacji wyników wyszukiwania (obsługa tagu searchResultPostion)."),
                qsTr("Przycisk 'Odśwież' w oknie archiwum pozwalający na ręczne wyczyszczenie pamięci podręcznej i ponowne pobranie danych o dostępności nagrań."),
                qsTr("Optymalizacja kolejki sieciowej (Prefetch) – ograniczenie pobierania wstecznego do 12 miesięcy, co eliminuje setki zbędnych zapytań o przedawnione nagrania i znacznie przyspiesza start odtwarzania.")
            ]
        },
        {
            version: "v2.0.7-8",
            date: "17.06.2026",
            changes: [
                qsTr("Asynchroniczna inicjalizacja SDK Hikvision w osobnym wątku, co całkowicie wyeliminowało zawieszanie się interfejsu (GUI Freeze) przy otwieraniu opcji."),
                qsTr("Bezpieczna wielowątkowa synchronizacja dostępu do metod SDK Hikvision.")
            ]
        },
        {
            version: "v2.0.6",
            date: "15.06.2026",
            changes: [
                qsTr("Oczyszczanie nazw pobieranych plików i zrzutów ekranu z adresów IP rejestratorów."),
                qsTr("Elegancki styl paska postępu pobierania w kolorze jasnoturkusowym (#00f5d4) z nałożonym wycentrowanym tekstem z czarnym obrysem."),
                qsTr("Obliczanie globalnego postępu pobierania (overallProgress) dla nagrań składających się z wielu części."),
                qsTr("Zmiana rozszerzenia plików tymczasowych pobierania z '.ps' na '.pspart'."),
                qsTr("Opcja i przycisk 'Pokazuj pola informacyjne tylko po najechaniu kursorem' w ustawieniach interfejsu użytkownika."),
                qsTr("Wizualna informacja o procesie wyszukiwania kamer w panelu konfiguracji (obracająca się ikona, blokowanie formularza, tekst 'Wyszukiwanie...')."),
                qsTr("Pełna wielojęzyczność (dodanie oficjalnego wsparcia dla języków polskiego i angielskiego)."),
                qsTr("Optymalizacja czasu uruchamiania okna pomocniczego – skrócenie startu z 3 sekund do poniżej 300 ms."),
                qsTr("Estetyczna stylizacja pustego pola w oknie pomocniczym ('Nie wybrano widoku') z seledynową ramką.")
            ]
        },
        {
            version: "v2.0.0",
            date: "05.06.2026",
            changes: [
                qsTr("Integracja z SDK Hikvision w trybie Live oraz odtwarzania archiwum."),
                qsTr("Odtwarzacz nagrań archiwalnych z wieloma kamerami naraz, automatycznie pozycjonowaną i centrowaną osią czasu."),
                qsTr("Wielowątkowy Monitor Systemowy (statystyki procesora, pamięci RAM, karty graficznej, pamięci VRAM oraz sieci)."),
                qsTr("Śledzenie wykorzystania pasma sieciowego w czasie rzeczywistym."),
                qsTr("Nowa ikona aplikacji w wysokiej rozdzielczości oraz dopracowany ciemny motyw interfejsu."),
                qsTr("Automatyczny skrypt budowania pakietu Pacman dla systemu Arch Linux.")
            ]
        }
    ]

    Settings {
        id: sideBarSettings
        fileName: Context.config.fileName
        category: "SideBar"
        property string windowDivision
        property string itemsState
    }

    function getRecorderName(ip) {
        try {
            var list = JSON.parse(rootWindow.hikvisionRecordersJson);
            for (var i = 0; i < list.length; ++i) {
                if (list[i].ip === ip) {
                    if (list[i].name && list[i].name.trim() !== "") {
                        return list[i].name;
                    }
                    break;
                }
            }
        } catch(e) {}
        return ip;
    }

    // Split Layout Container
    RowLayout {
        id: splitLayout
        anchors.fill: parent
        spacing: 0

        // Left Navigation Sidebar
        Rectangle {
            id: leftSidebar
            Layout.fillHeight: true
            width: 220
            color: "#0b0f13"

            // Right glow separator
            Rectangle {
                anchors.right: parent.right
                width: 1
                height: parent.height
                color: "#2a3540"
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 16

                // Logo/Header area
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Image {
                        source: "qrc:/images/256.png"
                        Layout.preferredWidth: leftSidebar.width * 2 / 3
                        Layout.preferredHeight: leftSidebar.width * 2 / 3
                        Layout.alignment: Qt.AlignHCenter
                        fillMode: Image.PreserveAspectFit
                    }

                    Text {
                        text: qsTr("KVision")
                        color: "#ffffff"
                        font {
                            pixelSize: 20
                            bold: true
                        }
                        horizontalAlignment: Text.AlignHCenter
                        Layout.fillWidth: true
                    }

                    Text {
                        text: qsTr("Wersja %1").arg(Qt.application.version)
                        color: "#00f5d4"
                        font {
                            pixelSize: 12
                            bold: true
                        }
                        horizontalAlignment: Text.AlignHCenter
                        Layout.fillWidth: true
                    }

                    Text {
                        text: qsTr("Oryginalny autor: Evgeny S. Maksimov")
                        color: "#8898a6"
                        font.pixelSize: 10
                        horizontalAlignment: Text.AlignHCenter
                        Layout.fillWidth: true
                    }

                    Text {
                        text: qsTr("Modyfikacja: arkanista (z pomocą AI)")
                        color: "#ff7a00"
                        font {
                            pixelSize: 10
                            bold: true
                        }
                        horizontalAlignment: Text.AlignHCenter
                        Layout.fillWidth: true
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: "#2a3540"
                }

                // Page selection buttons
                ColumnLayout {
                    id: tabsColumn
                    Layout.fillWidth: true
                    spacing: 8

                    property int activeIndex: 3

                    function selectTab(index) {
                        activeIndex = index;
                        pagesStack.currentIndex = index;
                        rootSideBar.resetPathChangesCheckbox();
                    }

                    // Viewport Page Button
                    Button {
                        id: btnViewport
                        visible: false
                        Layout.fillWidth: true
                        height: 40
                        hoverEnabled: true

                        background: Rectangle {
                            color: tabsColumn.activeIndex === 0 ? "#1c242c" : (btnViewport.hovered ? "#141a21" : "transparent")
                            radius: 6

                            // Active Glowing border
                            Rectangle {
                                anchors.left: parent.left
                                width: 3
                                height: parent.height
                                color: "#00f5d4"
                                visible: tabsColumn.activeIndex === 0
                            }
                        }

                        contentItem: RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            spacing: 12

                            Item {
                                implicitWidth: 14
                                implicitHeight: 14

                                Image {
                                    id: imgViewport
                                    source: "qrc:/images/menu-viewport.svg"
                                    anchors.fill: parent
                                    fillMode: Image.PreserveAspectFit
                                    layer.enabled: true
                                }

                                ColorOverlay {
                                    anchors.fill: imgViewport
                                    source: imgViewport
                                    color: tabsColumn.activeIndex === 0 ? "#00f5d4" : (btnViewport.hovered ? "white" : "#8898a6")
                                    cached: true
                                }
                            }

                            Text {
                                text: qsTr("Viewport%1").arg(rootSideBar.currentViewportIndex >= 0 ? qsTr(" #%1").arg(rootSideBar.currentViewportIndex + 1) : "")
                                color: tabsColumn.activeIndex === 0 ? "#00f5d4" : (btnViewport.hovered ? "white" : "#8898a6")
                                font {
                                    pixelSize: 12
                                    bold: tabsColumn.activeIndex === 0
                                }
                                Layout.fillWidth: true
                            }
                        }

                        onClicked: tabsColumn.selectTab(0)
                    }

                    // Tools Page Button
                    Button {
                        id: btnTools
                        visible: false
                        Layout.fillWidth: true
                        height: 40
                        hoverEnabled: true

                        background: Rectangle {
                            color: tabsColumn.activeIndex === 1 ? "#1c242c" : (btnTools.hovered ? "#141a21" : "transparent")
                            radius: 6

                            Rectangle {
                                anchors.left: parent.left
                                width: 3
                                height: parent.height
                                color: "#00f5d4"
                                visible: tabsColumn.activeIndex === 1
                            }
                        }

                        contentItem: RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            spacing: 12

                            Item {
                                implicitWidth: 14
                                implicitHeight: 14

                                Image {
                                    id: imgTools
                                    source: "qrc:/images/menu-tools.svg"
                                    anchors.fill: parent
                                    fillMode: Image.PreserveAspectFit
                                    layer.enabled: true
                                }

                                ColorOverlay {
                                    anchors.fill: imgTools
                                    source: imgTools
                                    color: tabsColumn.activeIndex === 1 ? "#00f5d4" : (btnTools.hovered ? "white" : "#8898a6")
                                    cached: true
                                }
                            }

                            Text {
                                text: qsTr("Tools")
                                color: tabsColumn.activeIndex === 1 ? "#00f5d4" : (btnTools.hovered ? "white" : "#8898a6")
                                font {
                                    pixelSize: 12
                                    bold: tabsColumn.activeIndex === 1
                                }
                                Layout.fillWidth: true
                            }
                        }

                        onClicked: tabsColumn.selectTab(1)
                    }

                    // Recorders Page Button
                    Button {
                        id: btnRecorders
                        Layout.fillWidth: true
                        height: 40
                        hoverEnabled: true

                        background: Rectangle {
                            color: tabsColumn.activeIndex === 2 ? "#1c242c" : (btnRecorders.hovered ? "#141a21" : "transparent")
                            radius: 6

                            Rectangle {
                                anchors.left: parent.left
                                width: 3
                                height: parent.height
                                color: "#00f5d4"
                                visible: tabsColumn.activeIndex === 2
                            }
                        }

                        contentItem: RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            spacing: 12

                            Item {
                                implicitWidth: 14
                                implicitHeight: 14

                                Image {
                                    id: imgRecorders
                                    source: "qrc:/images/menu-recorders.svg"
                                    anchors.fill: parent
                                    fillMode: Image.PreserveAspectFit
                                    layer.enabled: true
                                }

                                ColorOverlay {
                                    anchors.fill: imgRecorders
                                    source: imgRecorders
                                    color: tabsColumn.activeIndex === 2 ? "#00f5d4" : (btnRecorders.hovered ? "white" : "#8898a6")
                                    cached: true
                                }
                            }

                            Text {
                                text: qsTr("Recorders")
                                color: tabsColumn.activeIndex === 2 ? "#00f5d4" : (btnRecorders.hovered ? "white" : "#8898a6")
                                font {
                                    pixelSize: 12
                                    bold: tabsColumn.activeIndex === 2
                                }
                                Layout.fillWidth: true
                            }
                        }

                        onClicked: tabsColumn.selectTab(2)
                    }

                    // Presets Page Button
                    Button {
                        id: btnPresets
                        Layout.fillWidth: true
                        height: 40
                        hoverEnabled: true

                        background: Rectangle {
                            color: tabsColumn.activeIndex === 3 ? "#1c242c" : (btnPresets.hovered ? "#141a21" : "transparent")
                            radius: 6

                            Rectangle {
                                anchors.left: parent.left
                                width: 3
                                height: parent.height
                                color: "#00f5d4"
                                visible: tabsColumn.activeIndex === 3
                            }
                        }

                        contentItem: RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            spacing: 12

                            Item {
                                implicitWidth: 14
                                implicitHeight: 14

                                Image {
                                    id: imgPresets
                                    source: "qrc:/images/menu-presets.svg"
                                    anchors.fill: parent
                                    fillMode: Image.PreserveAspectFit
                                    layer.enabled: true
                                }

                                ColorOverlay {
                                    anchors.fill: imgPresets
                                    source: imgPresets
                                    color: tabsColumn.activeIndex === 3 ? "#00f5d4" : (btnPresets.hovered ? "white" : "#8898a6")
                                    cached: true
                                }
                            }

                            Text {
                                text: qsTr("Presets")
                                color: tabsColumn.activeIndex === 3 ? "#00f5d4" : (btnPresets.hovered ? "white" : "#8898a6")
                                font {
                                    pixelSize: 12
                                    bold: tabsColumn.activeIndex === 3
                                }
                                Layout.fillWidth: true
                            }
                        }

                        onClicked: tabsColumn.selectTab(3)
                    }

                    // General Settings Page Button
                    Button {
                        id: btnSettings
                        Layout.fillWidth: true
                        height: 40
                        hoverEnabled: true

                        background: Rectangle {
                            color: tabsColumn.activeIndex === 4 ? "#1c242c" : (btnSettings.hovered ? "#141a21" : "transparent")
                            radius: 6

                            Rectangle {
                                anchors.left: parent.left
                                width: 3
                                height: parent.height
                                color: "#00f5d4"
                                visible: tabsColumn.activeIndex === 4
                            }
                        }

                        contentItem: RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            spacing: 12

                            Item {
                                implicitWidth: 14
                                implicitHeight: 14

                                Image {
                                    id: imgSettings
                                    source: "qrc:/images/menu-settings.svg"
                                    anchors.fill: parent
                                    fillMode: Image.PreserveAspectFit
                                    layer.enabled: true
                                }

                                ColorOverlay {
                                    anchors.fill: imgSettings
                                    source: imgSettings
                                    color: tabsColumn.activeIndex === 4 ? "#00f5d4" : (btnSettings.hovered ? "white" : "#8898a6")
                                    cached: true
                                }
                            }

                            Text {
                                text: qsTr("Settings")
                                color: tabsColumn.activeIndex === 4 ? "#00f5d4" : (btnSettings.hovered ? "white" : "#8898a6")
                                font {
                                    pixelSize: 12
                                    bold: tabsColumn.activeIndex === 4
                                }
                                Layout.fillWidth: true
                            }
                        }

                        onClicked: tabsColumn.selectTab(4)
                    }

                    // Changelog Page Button
                    Button {
                        id: btnChangelog
                        Layout.fillWidth: true
                        height: 40
                        hoverEnabled: true

                        background: Rectangle {
                            color: tabsColumn.activeIndex === 5 ? "#1c242c" : (btnChangelog.hovered ? "#141a21" : "transparent")
                            radius: 6

                            Rectangle {
                                anchors.left: parent.left
                                width: 3
                                height: parent.height
                                color: "#00f5d4"
                                visible: tabsColumn.activeIndex === 5
                            }
                        }

                        contentItem: RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            spacing: 12

                            Item {
                                implicitWidth: 14
                                implicitHeight: 14

                                Image {
                                    id: imgChangelog
                                    source: "qrc:/images/menu-changelog.svg"
                                    anchors.fill: parent
                                    fillMode: Image.PreserveAspectFit
                                    layer.enabled: true
                                }

                                ColorOverlay {
                                    anchors.fill: imgChangelog
                                    source: imgChangelog
                                    color: tabsColumn.activeIndex === 5 ? "#00f5d4" : (btnChangelog.hovered ? "white" : "#8898a6")
                                    cached: true
                                }
                            }

                            Text {
                                text: qsTr("Changelog")
                                color: tabsColumn.activeIndex === 5 ? "#00f5d4" : (btnChangelog.hovered ? "white" : "#8898a6")
                                font {
                                    pixelSize: 12
                                    bold: tabsColumn.activeIndex === 5
                                }
                                Layout.fillWidth: true
                            }
                        }

                        onClicked: tabsColumn.selectTab(5)
                    }
                }

                Item {
                    Layout.fillHeight: true
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: rootSideBar.hasNewVersion
                    spacing: 6
                    Layout.alignment: Qt.AlignHCenter
                    Layout.bottomMargin: 4

                    Item {
                        implicitWidth: 32
                        implicitHeight: 32
                        Layout.alignment: Qt.AlignHCenter

                        // Glow Ring
                        Rectangle {
                            id: glowRing
                            anchors.centerIn: parent
                            width: 14
                            height: 14
                            radius: 7
                            color: "transparent"
                            border.color: "#2ecc71"
                            border.width: 1.5

                            NumberAnimation on scale {
                                from: 1.0
                                to: 2.2
                                duration: 1600
                                loops: Animation.Infinite
                                easing.type: Easing.OutQuad
                            }
                            OpacityAnimator on opacity {
                                from: 0.8
                                to: 0.0
                                duration: 1600
                                loops: Animation.Infinite
                                easing.type: Easing.OutQuad
                            }
                        }

                        // Core
                        Rectangle {
                            id: pulsingDot
                            anchors.centerIn: parent
                            width: 14
                            height: 14
                            radius: 7
                            color: "#2ecc71" // Green

                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                PropertyAnimation { to: 0.4; duration: 800; easing.type: Easing.InOutQuad }
                                PropertyAnimation { to: 1.0; duration: 800; easing.type: Easing.InOutQuad }
                            }
                        }
                    }

                    Text {
                        text: qsTr("Dostępna wersja: %1").arg(rootSideBar.newVersionString)
                        color: "#2ecc71"
                        font.pixelSize: 11
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        Layout.fillWidth: true
                    }
                }

                // Footer version link
                Text {
                    text: "<a href=\"https://github.com/arkanista/kvision\" style=\"color: #8898a6; text-decoration: none;\">GitHub Project</a>"
                    font.pixelSize: 11
                    textFormat: Text.RichText
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                    onLinkActivated: Qt.openUrlExternally(link)
                }
            }
        }

        // Right Stack Panel showing selected page
        StackLayout {
            id: pagesStack
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: 3

            onCurrentIndexChanged: {
                rootSideBar.resetPathChangesCheckbox();
            }

            // PAGE 0: Viewport settings
            ScrollView {
                id: page0ScrollView
                clip: true
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    id: page0Layout
                    x: 24
                    width: page0ScrollView.width - 48
                    spacing: 20

                    Text {
                        text: qsTr("Viewport Details")
                        color: "#00f5d4"
                        font {
                            pixelSize: 16
                            bold: true
                        }
                    }

                    // Placeholder when no viewport is active
                    Text {
                        text: qsTr("Please select a viewport in the main grid to customize its settings.")
                        color: "#8898a6"
                        font {
                            pixelSize: 13
                            italic: true
                        }
                        visible: rootSideBar.currentViewportIndex < 0
                        Layout.fillWidth: true
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 16
                        visible: rootSideBar.currentViewportIndex >= 0

                        Switch {
                            id: configUnlockSwitch
                            text: qsTr("Unlock config pane")
                            checked: false
                            palette.highlight: "#4CAF50"
                            Layout.fillWidth: true
                        }

                        GroupBox {
                            title: qsTr("Active Stream Connection")
                            Layout.fillWidth: true

                            background: Rectangle {
                                color: "#141a21"
                                border.color: "#2a3540"
                                border.width: 1
                                radius: 8
                            }
                            label: Text {
                                text: parent.title
                                color: "#00f5d4"
                                font.bold: true
                                font.pixelSize: 12
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 12

                                TextField {
                                    text: (rootSideBar.currentViewportIndex >= 0 && Utils.currentModel()) ? Utils.currentModel().get(rootSideBar.currentViewportIndex).url : ""
                                    placeholderText: qsTr("Primary Stream URL")
                                    selectByMouse: true
                                    enabled: configUnlockSwitch.checked && (Utils.currentModel() ? (!Utils.currentModel().isNvr && !Utils.currentModel().isNvrPreset) : true)
                                    Layout.fillWidth: true
                                    onEditingFinished: {
                                        if (rootSideBar.currentViewportIndex >= 0) {
                                            Utils.currentModel().get(rootSideBar.currentViewportIndex).url = text;
                                            Utils.currentModel().get(rootSideBar.currentViewportIndex).streamMode = 0;
                                        }
                                    }
                                }

                                TextField {
                                    text: (rootSideBar.currentViewportIndex >= 0 && Utils.currentModel()) ? Utils.currentModel().get(rootSideBar.currentViewportIndex).secondaryUrl : ""
                                    placeholderText: qsTr("Secondary Backup URL")
                                    selectByMouse: true
                                    enabled: configUnlockSwitch.checked && (Utils.currentModel() ? (!Utils.currentModel().isNvr && !Utils.currentModel().isNvrPreset) : true)
                                    Layout.fillWidth: true
                                    onEditingFinished: {
                                        if (rootSideBar.currentViewportIndex >= 0) {
                                            Utils.currentModel().get(rootSideBar.currentViewportIndex).secondaryUrl = text;
                                        }
                                    }
                                }
                            }
                        }

                        GroupBox {
                            title: qsTr("Audio & Rendering Options")
                            Layout.fillWidth: true

                            background: Rectangle {
                                color: "#141a21"
                                border.color: "#2a3540"
                                border.width: 1
                                radius: 8
                            }
                            label: Text {
                                text: parent.title
                                color: "#00f5d4"
                                font.bold: true
                                font.pixelSize: 12
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 12

                                Button {
                                    text: qsTr("Mute / Unmute Audio")
                                    enabled: configUnlockSwitch.checked && (rootSideBar.currentViewportIndex >= 0 && Utils.currentLayout() ? Utils.currentLayout().get(rootSideBar.currentViewportIndex).hasAudio : false)
                                    highlighted: !(rootSideBar.currentViewportIndex >= 0 && Utils.currentModel() && Utils.currentModel().get(rootSideBar.currentViewportIndex).volume > 0 || !viewportSettings.noUnmuteWhenFullScreen && Utils.currentLayout() && Utils.currentLayout().fullScreenIndex >= 0)
                                    Layout.fillWidth: true
                                    onClicked: {
                                        if (rootSideBar.currentViewportIndex >= 0) {
                                            if (Utils.currentModel().get(rootSideBar.currentViewportIndex).volume > 0) {
                                                Utils.currentModel().get(rootSideBar.currentViewportIndex).volume = 0;
                                            } else {
                                                Utils.currentModel().get(rootSideBar.currentViewportIndex).volume = 1;
                                            }
                                        }
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Text {
                                        text: qsTr("FFmpeg Options Override")
                                        color: "white"
                                        font.pixelSize: 11
                                    }

                                    TextField {
                                        text: (rootSideBar.currentViewportIndex >= 0 && Utils.currentModel()) ? getOptionsString(Utils.currentModel().get(rootSideBar.currentViewportIndex).avFormatOptions) : ""
                                        selectByMouse: true
                                        enabled: configUnlockSwitch.checked
                                        Layout.fillWidth: true
                                        onEditingFinished: {
                                            if (rootSideBar.currentViewportIndex >= 0) {
                                                var options = Utils.parseOptions(text);
                                                var defaultAVFormatOptions = layoutsCollectionSettings.toJSValue("defaultAVFormatOptions");

                                                if (Object.keys(options).length == Object.keys(defaultAVFormatOptions).length) {
                                                    for (var key in options) {
                                                        if (defaultAVFormatOptions[key] === undefined || String(defaultAVFormatOptions[key]) !== String(options[key])) {
                                                            Utils.currentModel().get(rootSideBar.currentViewportIndex).avFormatOptions = options;
                                                            return;
                                                        }
                                                    }
                                                    Utils.currentModel().get(rootSideBar.currentViewportIndex).avFormatOptions = {};
                                                } else {
                                                    Utils.currentModel().get(rootSideBar.currentViewportIndex).avFormatOptions = options;
                                                }
                                            }
                                        }

                                        function getOptionsString(options) {
                                            Object.assignDefault(options, layoutsCollectionSettings.toJSValue("defaultAVFormatOptions"));
                                            return Utils.stringifyOptions(options);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // PAGE 1: Tools & Layout Options
            ScrollView {
                id: page1ScrollView
                clip: true
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    id: page1Layout
                    x: 24
                    width: page1ScrollView.width - 48
                    spacing: 20

                    Text {
                        text: qsTr("Layout & Grid Tools")
                        color: "#00f5d4"
                        font {
                            pixelSize: 16
                            bold: true
                        }
                    }

                    Switch {
                        id: toolsUnlockSwitch
                        text: qsTr("Unlock tools pane")
                        checked: false
                        palette.highlight: "#4CAF50"
                        Layout.fillWidth: true
                    }

                    GroupBox {
                        title: qsTr("Window Division")
                        enabled: toolsUnlockSwitch.checked && !(Utils.currentLayout() && Utils.currentLayout().fullScreenIndex >= 0)
                        Layout.fillWidth: true

                        background: Rectangle {
                            color: "#141a21"
                            border.color: "#2a3540"
                            border.width: 1
                                radius: 8
                        }
                        label: Text {
                            text: parent.title
                            color: "#00f5d4"
                            font.bold: true
                            font.pixelSize: 12
                        }

                        GridLayout {
                            columns: 3
                            anchors.fill: parent
                            rowSpacing: 8
                            columnSpacing: 8

                            ListModel {
                                id: divisionModel

                                ListElement { size: "1x1" }
                                ListElement { size: "2x2" }
                                ListElement { size: "3x3" }
                                ListElement { size: "4x4" }
                                ListElement { size: "5x5" }
                                ListElement { size: "6x6" }
                                ListElement { size: "7x7" }
                                ListElement { size: "8x8" }
                                ListElement { size: "9x9" }

                                Component.onCompleted: {
                                    fromJSValue(sideBarSettings.windowDivision);
                                    divisionModel.dataChanged.connect(() => {
                                        sideBarSettings.windowDivision = JSON.stringify(toJSValue());
                                    });
                                }

                                function fromJSValue(model) {
                                    var arr;
                                    try {
                                        if (!model.isEmpty()) {
                                            arr = JSON.parse(model);
                                        }
                                    } catch(err) {
                                        Utils.log_error(qsTr("Error reading configuration!"));
                                    }

                                    if (arr instanceof Array) {
                                        for (var i = 0; i < arr.length; ++i) {
                                            divisionModel.set(i, arr[i]);
                                        }
                                    }
                                }

                                function toJSValue() {
                                    var arr = [];
                                    for (var i = 0; i < divisionModel.count; ++i) {
                                        arr[i] = divisionModel.get(i);
                                    }
                                    return arr;
                                }
                            }

                            Repeater {
                                model: divisionModel
                                delegate: Item {
                                    id: divisionItem
                                    implicitWidth: 100
                                    implicitHeight: 36
                                    Layout.fillWidth: true

                                    Keys.onEscapePressed: {
                                        event.accepted = divisionTextField.visible;
                                        divisionTextField.cancel();
                                    }
                                    Keys.onPressed: {
                                        if (event.key === Qt.Key_F2) {
                                            divisionTextField.edit();
                                        }
                                    }

                                    Button {
                                        text: size
                                        highlighted: Utils.currentModel() && Utils.currentModel().size === str2size(size)
                                        enabled: !generalSettings.lockGridSize
                                        anchors.fill: parent
                                        onClicked: {
                                            if (Utils.currentModel()) {
                                                Utils.currentModel().size = str2size(size);
                                            }
                                        }
                                        onPressAndHold: divisionTextField.edit()

                                        ToolTip.delay: Compact.toolTipDelay
                                        ToolTip.timeout: Compact.toolTipTimeout
                                        ToolTip.visible: hovered
                                        ToolTip.text: qsTr("Hold to edit division value")
                                    }

                                    TextField {
                                        id: divisionTextField
                                        visible: false
                                        anchors.fill: parent
                                        horizontalAlignment: TextInput.AlignHCenter
                                        selectByMouse: true
                                        onEditingFinished: {
                                            visible = false;
                                            if(str2size(text)) {
                                                size = text;
                                            }
                                        }

                                        function edit() {
                                            text = size;
                                            visible = true;
                                            forceActiveFocus();
                                        }
                                        function cancel() {
                                            text = size;
                                            visible = false;
                                        }
                                    }

                                    function str2size(str) {
                                        var separatorTr = qsTr("x");
                                        var regexp = new RegExp("^[1-9][x%1][1-9]$".arg(separatorTr));
                                        if (regexp.test(str)) {
                                            var size = str.split(new RegExp("[x%1]".arg(separatorTr)));
                                            return Qt.size(size[0], size[1]);
                                        }
                                        return null;
                                    }
                                }
                            }
                        }
                    }

                    GroupBox {
                        title: qsTr("Geometry Ratio")
                        enabled: toolsUnlockSwitch.checked
                        Layout.fillWidth: true

                        background: Rectangle {
                            color: "#141a21"
                            border.color: "#2a3540"
                            border.width: 1
                            radius: 8
                        }
                        label: Text {
                            text: parent.title
                            color: "#00f5d4"
                            font.bold: true
                            font.pixelSize: 12
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 10

                            RowLayout {
                                spacing: 12
                                Layout.fillWidth: true

                                Button {
                                    text: "16:9 Aspect Ratio"
                                    highlighted: Utils.currentModel() && Utils.currentModel().aspectRatio === Qt.size(16, 9)
                                    Layout.fillWidth: true
                                    onClicked: {
                                        if (Utils.currentModel()) {
                                            Utils.currentModel().aspectRatio = Qt.size(16, 9);
                                            setRootWindowRatio(Utils.currentModel().aspectRatio);
                                        }
                                    }
                                }
                                Button {
                                    text: "4:3 Aspect Ratio"
                                    highlighted: Utils.currentModel() && Utils.currentModel().aspectRatio === Qt.size(4, 3)
                                    Layout.fillWidth: true
                                    onClicked: {
                                        if (Utils.currentModel()) {
                                            Utils.currentModel().aspectRatio = Qt.size(4, 3);
                                            setRootWindowRatio(Utils.currentModel().aspectRatio);
                                        }
                                    }
                                }
                            }

                            Button {
                                text: qsTr("Toggle Full Screen")
                                highlighted: Context.config.fullScreen
                                Layout.fillWidth: true
                                onClicked: Context.config.fullScreen = !Context.config.fullScreen
                            }
                        }
                    }

                    GroupBox {
                        title: qsTr("Grid Operations")
                        enabled: toolsUnlockSwitch.checked
                        Layout.fillWidth: true

                        background: Rectangle {
                            color: "#141a21"
                            border.color: "#2a3540"
                            border.width: 1
                            radius: 8
                        }
                        label: Text {
                            text: parent.title
                            color: "#00f5d4"
                            font.bold: true
                            font.pixelSize: 12
                        }

                        RowLayout {
                            anchors.fill: parent
                            spacing: 10

                            Button {
                                text: qsTr("Merge Highlighted Cells")
                                enabled: Utils.currentLayout() ? Utils.currentLayout().mergeCells(true) : false
                                Layout.fillWidth: true
                                onClicked: if (Utils.currentLayout()) Utils.currentLayout().mergeCells()
                            }
                        }
                    }
                }
            }

            // PAGE 2: NVR Connection Recorders List
            ScrollView {
                id: page2ScrollView
                clip: true
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    id: recordersLayout
                    x: 24
                    width: page2ScrollView.width - 48
                    spacing: 20

                    Text {
                        text: qsTr("NVR / Hikvision Recorders Manager")
                        color: "#00f5d4"
                        font {
                            pixelSize: 16
                            bold: true
                        }
                    }

                    NvrSettingsPanel {
                        Layout.fillWidth: true
                    }
                }
            }

            // PAGE 3: Presets & Views list
            ScrollView {
                id: page3ScrollView
                clip: true
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    id: presetsLayout
                    x: 24
                    width: page3ScrollView.width - 48
                    spacing: 20

                    Text {
                        text: qsTr("Presets & Quick Layout Views")
                        color: "#00f5d4"
                        font {
                            pixelSize: 16
                            bold: true
                        }
                    }

                    // Group 1: General Camera Presets
                    GroupBox {
                        title: qsTr("ONVIF and RTSP Layout settings")
                        Layout.fillWidth: true

                        background: Rectangle {
                            color: "#141a21"
                            border.color: "#2a3540"
                            border.width: 1
                            radius: 8
                        }
                        label: Text {
                            text: parent.title
                            color: "#00f5d4"
                            font.bold: true
                            font.pixelSize: 12
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 4
                            spacing: 8

                            Repeater {
                                model: rootSideBar.regularIndices
                                delegate: RowLayout {
                                    id: presetRow
                                    spacing: 12
                                    Layout.fillWidth: true

                                    property var layout: layoutsCollectionModel.get(modelData)

                                    // Active preset indicator
                                    Rectangle {
                                        width: 4
                                        height: 24
                                        radius: 2
                                        color: stackLayout.currentIndex === modelData ? "#00f5d4" : "transparent"
                                    }

                                    // Editable preset name field
                                    TextField {
                                        id: nameField
                                        text: (presetRow.layout && presetRow.layout.name) ? presetRow.layout.name : ""
                                        placeholderText: qsTr("Layout %1").arg(index + 1)
                                        selectByMouse: true
                                        Layout.fillWidth: true
                                        color: "white"
                                        background: Rectangle {
                                            color: "#0f151b"
                                            radius: 4
                                            border.color: nameField.activeFocus ? "#ff7a00" : "#2a3540"
                                        }
                                        onEditingFinished: {
                                            if (presetRow.layout) {
                                                presetRow.layout.name = text;
                                            }
                                        }
                                    }

                                    // Visible Checkbox
                                    CheckBox {
                                        text: qsTr("Visible")
                                        checked: presetRow.layout ? presetRow.layout.visible : true
                                        onCheckedChanged: {
                                            if (presetRow.layout) {
                                                presetRow.layout.visible = checked;
                                            }
                                        }
                                        palette.highlight: "#00f5d4"
                                    }

                                    // Activate button
                                    Button {
                                        id: activateBtn
                                        implicitWidth: 28
                                        implicitHeight: 28
                                        highlighted: stackLayout.currentIndex === modelData
                                        onClicked: {
                                            stackLayout.currentIndex = modelData;
                                        }
                                        contentItem: Image {
                                            anchors.centerIn: parent
                                            width: 14
                                            height: 14
                                            source: {
                                                var colorStr = activateBtn.pressed ? "%23ffffff" : (activateBtn.highlighted ? "%23ffffff" : (activateBtn.hovered ? "%23ffffff" : "%238898a6"));
                                                return "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='" + colorStr + "' stroke-width='2.5' stroke-linecap='round' stroke-linejoin='round'><polygon points='6 3 20 12 6 21 6 3'></polygon></svg>";
                                            }
                                        }
                                        background: Rectangle {
                                            color: activateBtn.pressed ? "#cc121214" : (activateBtn.highlighted ? "#ff7a00" : (activateBtn.hovered ? "#3a4550" : "#1c242c"))
                                            radius: 14
                                            border.color: activateBtn.highlighted ? "#ff9e00" : (activateBtn.hovered ? "#8898a6" : "#2a3540")
                                            border.width: 1
                                        }
                                        ToolTip.delay: Compact.toolTipDelay
                                        ToolTip.timeout: Compact.toolTipTimeout
                                        ToolTip.visible: activateBtn.hovered
                                        ToolTip.text: qsTr("Aktywuj ten układ podglądu")
                                    }

                                    // Delete icon button
                                    Button {
                                        id: delPresetBtn
                                        implicitWidth: 28
                                        implicitHeight: 28
                                        visible: rootSideBar.regularIndices.length > 1
                                        contentItem: Image {
                                            anchors.centerIn: parent
                                            width: 14
                                            height: 14
                                            source: {
                                                var colorStr = delPresetBtn.hovered ? "%23ff4d4d" : "%238898a6";
                                                return "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='" + colorStr + "' stroke-width='2.5' stroke-linecap='round' stroke-linejoin='round'><polyline points='3 6 5 6 21 6'></polyline><path d='M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2'></path><line x1='10' y1='11' x2='10' y2='17'></line><line x1='14' y1='11' x2='14' y2='17'></line></svg>";
                                            }
                                        }
                                        background: Rectangle {
                                            color: delPresetBtn.pressed ? "#40ff0000" : (delPresetBtn.hovered ? "#20ff0000" : "transparent")
                                            radius: 14
                                            border.color: delPresetBtn.hovered ? "#ff4d4d" : "#2a3540"
                                            border.width: 1
                                        }

                                        onClicked: {
                                            presetDeleteDialog.index = modelData;
                                            presetDeleteDialog.open();
                                        }
                                        ToolTip.delay: Compact.toolTipDelay
                                        ToolTip.timeout: Compact.toolTipTimeout
                                        ToolTip.visible: delPresetBtn.hovered
                                        ToolTip.text: qsTr("Usuń ten układ podglądu")
                                    }
                                }
                            }

                            Button {
                                id: addPresetBtn
                                text: qsTr("Add Preset Layout")
                                Layout.fillWidth: true
                                implicitHeight: 32
                                onClicked: {
                                    var l = layoutsCollectionModel.append();
                                    l.size = Qt.size(3, 3);
                                }
                                background: Rectangle {
                                    color: addPresetBtn.pressed ? "#cc121214" : (addPresetBtn.hovered ? "#059669" : "#10b981")
                                    radius: 6
                                    border.color: addPresetBtn.hovered ? "#34d399" : "#059669"
                                    border.width: 1
                                }
                                contentItem: Text {
                                    text: addPresetBtn.text
                                    color: "#ffffff"
                                    font.bold: true
                                    font.pixelSize: 11
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
                    }

                    // Group 2: NVR Views (Only when NVR layouts configured)
                    GroupBox {
                        title: qsTr("NVR View Layouts")
                        visible: rootSideBar.nvrIndices.length > 0
                        Layout.fillWidth: true

                        background: Rectangle {
                            color: "#141a21"
                            border.color: "#2a3540"
                            border.width: 1
                            radius: 8
                        }
                        label: Text {
                            text: parent.title
                            color: "#00f5d4"
                            font.bold: true
                            font.pixelSize: 12
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 4
                            spacing: 8

                            Repeater {
                                model: rootSideBar.nvrIndices
                                delegate: RowLayout {
                                    id: nvrRow
                                    spacing: 12
                                    Layout.fillWidth: true

                                    property var layout: layoutsCollectionModel.get(modelData)

                                    Rectangle {
                                        width: 4
                                        height: 24
                                        radius: 2
                                        color: stackLayout.currentIndex === modelData ? "#00f5d4" : "transparent"
                                    }

                                    TextField {
                                        id: nvrNameField
                                        text: (nvrRow.layout && nvrRow.layout.name) ? nvrRow.layout.name : ""
                                        placeholderText: (nvrRow.layout && nvrRow.layout.nvrIp) ? getRecorderName(nvrRow.layout.nvrIp) : qsTr("NVR View")
                                        selectByMouse: true
                                        Layout.fillWidth: true
                                        color: "white"
                                        background: Rectangle {
                                            color: "#0f151b"
                                            radius: 4
                                            border.color: nvrNameField.activeFocus ? "#ff7a00" : "#2a3540"
                                        }
                                        onEditingFinished: {
                                            if (nvrRow.layout) {
                                                nvrRow.layout.name = text;
                                            }
                                        }
                                    }

                                    CheckBox {
                                        text: qsTr("Visible")
                                        checked: nvrRow.layout ? nvrRow.layout.visible : true
                                        onCheckedChanged: {
                                            if (nvrRow.layout) {
                                                nvrRow.layout.visible = checked;
                                            }
                                        }
                                        palette.highlight: "#00f5d4"
                                    }

                                    Button {
                                        id: activateBtnNvr
                                        implicitWidth: 28
                                        implicitHeight: 28
                                        highlighted: stackLayout.currentIndex === modelData
                                        onClicked: {
                                            stackLayout.currentIndex = modelData;
                                        }
                                        contentItem: Image {
                                            anchors.centerIn: parent
                                            width: 14
                                            height: 14
                                            source: {
                                                var colorStr = activateBtnNvr.pressed ? "%23ffffff" : (activateBtnNvr.highlighted ? "%23ffffff" : (activateBtnNvr.hovered ? "%23ffffff" : "%238898a6"));
                                                return "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='" + colorStr + "' stroke-width='2.5' stroke-linecap='round' stroke-linejoin='round'><polygon points='6 3 20 12 6 21 6 3'></polygon></svg>";
                                            }
                                        }
                                        background: Rectangle {
                                            color: activateBtnNvr.pressed ? "#cc121214" : (activateBtnNvr.highlighted ? "#ff7a00" : (activateBtnNvr.hovered ? "#3a4550" : "#1c242c"))
                                            radius: 14
                                            border.color: activateBtnNvr.highlighted ? "#ff9e00" : (activateBtnNvr.hovered ? "#8898a6" : "#2a3540")
                                            border.width: 1
                                        }
                                        ToolTip.delay: Compact.toolTipDelay
                                        ToolTip.timeout: Compact.toolTipTimeout
                                        ToolTip.visible: activateBtnNvr.hovered
                                        ToolTip.text: qsTr("Aktywuj ten widok kamer NVR")
                                    }

                                    Button {
                                        id: delNvrBtn
                                        implicitWidth: 28
                                        implicitHeight: 28
                                        contentItem: Image {
                                            anchors.centerIn: parent
                                            width: 14
                                            height: 14
                                            source: {
                                                var colorStr = delNvrBtn.hovered ? "%23ff4d4d" : "%238898a6";
                                                return "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='" + colorStr + "' stroke-width='2.5' stroke-linecap='round' stroke-linejoin='round'><polyline points='3 6 5 6 21 6'></polyline><path d='M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2'></path><line x1='10' y1='11' x2='10' y2='17'></line><line x1='14' y1='11' x2='14' y2='17'></line></svg>";
                                            }
                                        }
                                        background: Rectangle {
                                            color: delNvrBtn.pressed ? "#40ff0000" : (delNvrBtn.hovered ? "#20ff0000" : "transparent")
                                            radius: 14
                                            border.color: delNvrBtn.hovered ? "#ff4d4d" : "#2a3540"
                                            border.width: 1
                                        }

                                        onClicked: {
                                            nvrPresetDeleteDialog.index = modelData;
                                            nvrPresetDeleteDialog.open();
                                        }
                                        ToolTip.delay: Compact.toolTipDelay
                                        ToolTip.timeout: Compact.toolTipTimeout
                                        ToolTip.visible: delNvrBtn.hovered
                                        ToolTip.text: qsTr("Usuń ten widok kamer NVR")
                                    }
                                }
                            }
                        }
                    }

                    // Group 3: NVR Preset List
                    GroupBox {
                        title: qsTr("NVR Presets (Grid views)")
                        Layout.fillWidth: true

                        background: Rectangle {
                            color: "#141a21"
                            border.color: "#2a3540"
                            border.width: 1
                            radius: 8
                        }
                        label: Text {
                            text: parent.title
                            color: "#00f5d4"
                            font.bold: true
                            font.pixelSize: 12
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 4
                            spacing: 8

                            Repeater {
                                model: rootSideBar.nvrPresetIndices
                                delegate: RowLayout {
                                    id: nvrPresetRow
                                    spacing: 12
                                    Layout.fillWidth: true

                                    property var layout: layoutsCollectionModel.get(modelData)

                                    Rectangle {
                                        width: 4
                                        height: 24
                                        radius: 2
                                        color: stackLayout.currentIndex === modelData ? "#00f5d4" : "transparent"
                                    }

                                    TextField {
                                        id: nvrPresetNameField
                                        text: (nvrPresetRow.layout && nvrPresetRow.layout.name) ? nvrPresetRow.layout.name : ""
                                        placeholderText: qsTr("NVR Preset #%1").arg(index + 1)
                                        selectByMouse: true
                                        Layout.fillWidth: true
                                        color: "white"
                                        background: Rectangle {
                                            color: "#0f151b"
                                            radius: 4
                                            border.color: nvrPresetNameField.activeFocus ? "#ff7a00" : "#2a3540"
                                        }
                                        onEditingFinished: {
                                            if (nvrPresetRow.layout) {
                                                nvrPresetRow.layout.name = text;
                                            }
                                        }
                                    }

                                    CheckBox {
                                        text: qsTr("Visible")
                                        checked: nvrPresetRow.layout ? nvrPresetRow.layout.visible : true
                                        onCheckedChanged: {
                                            if (nvrPresetRow.layout) {
                                                nvrPresetRow.layout.visible = checked;
                                            }
                                        }
                                        palette.highlight: "#00f5d4"
                                    }

                                    Button {
                                        id: activateBtnNvrPreset
                                        implicitWidth: 28
                                        implicitHeight: 28
                                        highlighted: stackLayout.currentIndex === modelData
                                        onClicked: {
                                            stackLayout.currentIndex = modelData;
                                        }
                                        contentItem: Image {
                                            anchors.centerIn: parent
                                            width: 14
                                            height: 14
                                            source: {
                                                var colorStr = activateBtnNvrPreset.pressed ? "%23ffffff" : (activateBtnNvrPreset.highlighted ? "%23ffffff" : (activateBtnNvrPreset.hovered ? "%23ffffff" : "%238898a6"));
                                                return "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='" + colorStr + "' stroke-width='2.5' stroke-linecap='round' stroke-linejoin='round'><polygon points='6 3 20 12 6 21 6 3'></polygon></svg>";
                                            }
                                        }
                                        background: Rectangle {
                                            color: activateBtnNvrPreset.pressed ? "#cc121214" : (activateBtnNvrPreset.highlighted ? "#ff7a00" : (activateBtnNvrPreset.hovered ? "#3a4550" : "#1c242c"))
                                            radius: 14
                                            border.color: activateBtnNvrPreset.highlighted ? "#ff9e00" : (activateBtnNvrPreset.hovered ? "#8898a6" : "#2a3540")
                                            border.width: 1
                                        }
                                        ToolTip.delay: Compact.toolTipDelay
                                        ToolTip.timeout: Compact.toolTipTimeout
                                        ToolTip.visible: activateBtnNvrPreset.hovered
                                        ToolTip.text: qsTr("Aktywuj ten preset kamer NVR")
                                    }

                                    Button {
                                        id: delNvrPresetBtn
                                        implicitWidth: 28
                                        implicitHeight: 28
                                        contentItem: Image {
                                            anchors.centerIn: parent
                                            width: 14
                                            height: 14
                                            source: {
                                                var colorStr = delNvrPresetBtn.hovered ? "%23ff4d4d" : "%238898a6";
                                                return "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='" + colorStr + "' stroke-width='2.5' stroke-linecap='round' stroke-linejoin='round'><polyline points='3 6 5 6 21 6'></polyline><path d='M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2'></path><line x1='10' y1='11' x2='10' y2='17'></line><line x1='14' y1='11' x2='14' y2='17'></line></svg>";
                                            }
                                        }
                                        background: Rectangle {
                                            color: delNvrPresetBtn.pressed ? "#40ff0000" : (delNvrPresetBtn.hovered ? "#20ff0000" : "transparent")
                                            radius: 14
                                            border.color: delNvrPresetBtn.hovered ? "#ff4d4d" : "#2a3540"
                                            border.width: 1
                                        }

                                        onClicked: {
                                            nvrPresetDeleteDialog2.index = modelData;
                                            nvrPresetDeleteDialog2.open();
                                        }
                                        ToolTip.delay: Compact.toolTipDelay
                                        ToolTip.timeout: Compact.toolTipTimeout
                                        ToolTip.visible: delNvrPresetBtn.hovered
                                        ToolTip.text: qsTr("Usuń ten preset kamer NVR")
                                    }
                                }
                            }

                            Button {
                                id: addNvrPresetBtn
                                text: qsTr("Add NVR Preset")
                                Layout.fillWidth: true
                                implicitHeight: 32
                                onClicked: {
                                    var l = layoutsCollectionModel.append();
                                    l.size = Qt.size(2, 2);
                                    l.isNvrPreset = true;
                                    stackLayout.currentIndex = layoutsCollectionModel.count - 1;
                                }
                                background: Rectangle {
                                    color: addNvrPresetBtn.pressed ? "#cc121214" : (addNvrPresetBtn.hovered ? "#059669" : "#10b981")
                                    radius: 6
                                    border.color: addNvrPresetBtn.hovered ? "#34d399" : "#059669"
                                    border.width: 1
                                }
                                contentItem: Text {
                                    text: addNvrPresetBtn.text
                                    color: "#ffffff"
                                    font.bold: true
                                    font.pixelSize: 11
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
                    }
                }
            }

            // PAGE 4: General application settings
            ScrollView {
                id: page4ScrollView
                clip: true
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    id: page4Layout
                    x: 24
                    width: page4ScrollView.width - 48
                    spacing: 20

                    Text {
                        text: qsTr("System Settings")
                        color: "#00f5d4"
                        font {
                            pixelSize: 16
                            bold: true
                        }
                    }

                    GroupBox {
                        title: qsTr("General Settings")
                        Layout.fillWidth: true

                        background: Rectangle {
                            color: "#141a21"
                            border.color: "#2a3540"
                            border.width: 1
                            radius: 8
                        }
                        label: Text {
                            text: parent.title
                            color: "#00f5d4"
                            font.bold: true
                            font.pixelSize: 12
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 8

                            CheckBox {
                                text: qsTr("Allow running multiple application instances")
                                checked: !generalSettings.singleApplication
                                enabled: false
                                onCheckedChanged: generalSettings.singleApplication = !checked
                                Layout.fillWidth: true
                            }

                            Text {
                                text: qsTr("This option is disabled to prevent settings file write conflicts. To enable it (dangerous and not recommended!), set 'singleApplication=false' in the kvision.conf configuration file.")
                                color: "#8898a6"
                                font.pixelSize: 10
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: "#2a3540"
                            }

                            CheckBox {
                                text: qsTr("Check Hikvision NVR error status")
                                checked: NvrStatusManager.monitoringEnabled
                                onCheckedChanged: NvrStatusManager.monitoringEnabled = checked
                                Layout.fillWidth: true
                            }
                        }
                    }

                    GroupBox {
                        title: qsTr("Audio")
                        Layout.fillWidth: true

                        background: Rectangle {
                            color: "#141a21"
                            border.color: "#2a3540"
                            border.width: 1
                            radius: 8
                        }
                        label: Text {
                            text: parent.title
                            color: "#00f5d4"
                            font.bold: true
                            font.pixelSize: 12
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 8

                            CheckBox {
                                text: qsTr("Disable audio entirely")
                                checked: generalSettings.disableAudio
                                onCheckedChanged: generalSettings.disableAudio = checked
                                Layout.fillWidth: true
                            }

                            CheckBox {
                                text: qsTr("Maximizing camera to full screen does not unmute")
                                checked: viewportSettings.noUnmuteWhenFullScreen
                                onCheckedChanged: viewportSettings.noUnmuteWhenFullScreen = checked
                                Layout.fillWidth: true
                            }
                        }
                    }

                    GroupBox {
                        title: qsTr("Context Menu Settings")
                        Layout.fillWidth: true

                        background: Rectangle {
                            color: "#141a21"
                            border.color: "#2a3540"
                            border.width: 1
                            radius: 8
                        }
                        label: Text {
                            text: parent.title
                            color: "#00f5d4"
                            font.bold: true
                            font.pixelSize: 12
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 8

                            CheckBox {
                                text: qsTr("Enable right-click context menu")
                                checked: generalSettings.enableContextMenu
                                onCheckedChanged: generalSettings.enableContextMenu = checked
                                Layout.fillWidth: true
                            }

                            CheckBox {
                                text: qsTr("Allow swapping viewport places")
                                checked: generalSettings.allowSwappingViewports
                                enabled: generalSettings.enableContextMenu
                                onCheckedChanged: generalSettings.allowSwappingViewports = checked
                                Layout.fillWidth: true
                            }

                            CheckBox {
                                text: qsTr("Enable 'Remove camera' option")
                                checked: generalSettings.enableRemoveCamera
                                enabled: generalSettings.enableContextMenu
                                onCheckedChanged: generalSettings.enableRemoveCamera = checked
                                Layout.fillWidth: true
                            }

                            CheckBox {
                                text: qsTr("Allow changing viewport settings")
                                checked: generalSettings.enableChangeViewportSettings
                                enabled: generalSettings.enableContextMenu
                                onCheckedChanged: generalSettings.enableChangeViewportSettings = checked
                                Layout.fillWidth: true
                            }

                            CheckBox {
                                text: qsTr("Enable 'Stream selection' option")
                                checked: generalSettings.enableStreamSelection
                                enabled: generalSettings.enableContextMenu
                                onCheckedChanged: generalSettings.enableStreamSelection = checked
                                Layout.fillWidth: true
                            }
                        }
                    }

                    GroupBox {
                        title: qsTr("User Interface Settings")
                        Layout.fillWidth: true

                        background: Rectangle {
                            color: "#141a21"
                            border.color: "#2a3540"
                            border.width: 1
                            radius: 8
                        }
                        label: Text {
                            text: parent.title
                            color: "#00f5d4"
                            font.bold: true
                            font.pixelSize: 12
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 8

                            CheckBox {
                                text: qsTr("Show channel status in the top left corner of the viewport")
                                checked: viewSettings.showChannelStatus
                                onCheckedChanged: viewSettings.showChannelStatus = checked
                                Layout.fillWidth: true
                            }

                            CheckBox {
                                text: qsTr("Show camera info in the bottom left corner of the viewport")
                                checked: viewSettings.showCameraInfo
                                onCheckedChanged: viewSettings.showCameraInfo = checked
                                Layout.fillWidth: true
                            }

                            CheckBox {
                                text: qsTr("Show control icons in the bottom right corner of the viewport only when hovering")
                                checked: viewSettings.hoverControlIcons
                                onCheckedChanged: viewSettings.hoverControlIcons = checked
                                Layout.fillWidth: true
                            }

                            CheckBox {
                                text: qsTr("Show info fields only when hovering")
                                checked: viewSettings.showInfoOnHoverOnly
                                onCheckedChanged: viewSettings.showInfoOnHoverOnly = checked
                                Layout.fillWidth: true
                            }

                            CheckBox {
                                text: qsTr("Show top bar by default when opening window")
                                checked: viewSettings.showTopBarByDefault
                                onCheckedChanged: viewSettings.showTopBarByDefault = checked
                                Layout.fillWidth: true
                            }

                            CheckBox {
                                text: qsTr("Hide mouse cursor in Full Screen mode")
                                checked: viewSettings.hideCursorWhenFullScreen
                                onCheckedChanged: viewSettings.hideCursorWhenFullScreen = checked
                                Layout.fillWidth: true
                            }

                            CheckBox {
                                text: qsTr("Disable viewport zoom animation")
                                checked: viewSettings.disableViewportZoomAnimation
                                onCheckedChanged: viewSettings.disableViewportZoomAnimation = checked
                                Layout.fillWidth: true
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Text {
                                    text: qsTr("Language:")
                                    color: "white"
                                    font.pixelSize: 11
                                }

                                ComboBox {
                                    id: sidebarLanguageCombo
                                    Layout.fillWidth: true
                                    model: [
                                        { text: qsTr("System default"), value: "system" },
                                        { text: "English", value: "en" },
                                        { text: "Polski", value: "pl" }
                                    ]
                                    textRole: "text"

                                    background: Rectangle {
                                        implicitHeight: 32
                                        color: "#151d24"
                                        border.color: sidebarLanguageCombo.activeFocus ? "#ff7a00" : "#3a4550"
                                        border.width: 1
                                        radius: 6
                                    }

                                    contentItem: Text {
                                        text: sidebarLanguageCombo.displayText
                                        color: "#eeeeee"
                                        font {
                                            pixelSize: 11
                                            bold: true
                                        }
                                        verticalAlignment: Text.AlignVCenter
                                        leftPadding: 10
                                    }

                                    delegate: ItemDelegate {
                                        width: sidebarLanguageCombo.width
                                        height: 32
                                        contentItem: Text {
                                            text: modelData.text
                                            color: hovered ? "#00f5d4" : "#eeeeee"
                                            font {
                                                pixelSize: 11
                                                bold: true
                                            }
                                            verticalAlignment: Text.AlignVCenter
                                            leftPadding: 10
                                        }
                                        background: Rectangle {
                                            color: hovered ? "#2a3540" : "transparent"
                                            border.color: hovered ? "#00f5d4" : "transparent"
                                            border.width: 1
                                            radius: 4
                                        }
                                    }

                                    popup: Popup {
                                        y: sidebarLanguageCombo.height + 2
                                        width: sidebarLanguageCombo.width
                                        implicitHeight: sidebarLanguageCombo.popup.visible ? contentItem.implicitHeight : 0
                                        padding: 4

                                        contentItem: ListView {
                                            clip: true
                                            implicitHeight: contentHeight
                                            model: sidebarLanguageCombo.popup.visible ? sidebarLanguageCombo.delegateModel : null
                                            currentIndex: sidebarLanguageCombo.highlightedIndex

                                            ScrollIndicator.vertical: ScrollIndicator { }
                                        }

                                        background: Rectangle {
                                            color: "#151d24"
                                            border.color: "#ff7a00"
                                            border.width: 1
                                            radius: 6
                                        }
                                    }
                                    
                                    Component.onCompleted: {
                                        var lang = Context.getLanguage();
                                        for (var i = 0; i < model.length; ++i) {
                                            if (model[i].value === lang) {
                                                currentIndex = i;
                                                break;
                                            }
                                        }
                                    }
                                    
                                    onActivated: {
                                        var selectedLang = model[currentIndex].value;
                                        Context.setLanguage(selectedLang);
                                    }

                                    Connections {
                                        target: Context
                                        function onLanguageChanged() {
                                            var lang = Context.getLanguage();
                                            for (var i = 0; i < sidebarLanguageCombo.model.length; ++i) {
                                                if (sidebarLanguageCombo.model[i].value === lang) {
                                                    sidebarLanguageCombo.currentIndex = i;
                                                    break;
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Text {
                                    text: qsTr("Ogranicz liczbę okien pomocniczych do:")
                                    color: "white"
                                    font.pixelSize: 13
                                }

                                TextField {
                                    id: auxiliaryLimitField
                                    Layout.preferredWidth: 40
                                    Layout.preferredHeight: 30
                                    horizontalAlignment: TextInput.AlignHCenter
                                    selectByMouse: true
                                    text: generalSettings.auxiliaryLimit.toString()
                                    color: "white"
                                    font.pixelSize: 12
                                    maximumLength: 1
                                    validator: IntValidator { bottom: 0; top: 3 }
                                    background: Rectangle {
                                        color: "#0f151b"
                                        radius: 4
                                        border.color: auxiliaryLimitField.activeFocus ? "#ff7a00" : "#2a3540"
                                    }
                                    onTextChanged: {
                                        var val = parseInt(text);
                                        if (!isNaN(val) && val > 3) {
                                            text = "3";
                                        }
                                    }
                                    onEditingFinished: {
                                        var val = parseInt(text);
                                        if (!isNaN(val) && val >= 0 && val <= 3) {
                                            generalSettings.auxiliaryLimit = val;
                                        } else {
                                            text = generalSettings.auxiliaryLimit.toString();
                                        }
                                    }
                                }

                                Item {
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }

                    GroupBox {
                        title: qsTr("NVR Status Monitoring")
                        Layout.fillWidth: true

                        background: Rectangle {
                            color: "#141a21"
                            border.color: "#2a3540"
                            border.width: 1
                            radius: 8
                        }
                        label: Text {
                            text: parent.title
                            color: "#00f5d4"
                            font.bold: true
                            font.pixelSize: 12
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 8

                            CheckBox {
                                text: qsTr("Monitor offline status and login errors")
                                checked: NvrStatusManager.checkOffline
                                onCheckedChanged: NvrStatusManager.checkOffline = checked
                                Layout.fillWidth: true
                            }

                            CheckBox {
                                text: qsTr("Monitor CPU overload (>85%)")
                                checked: NvrStatusManager.checkCpu
                                onCheckedChanged: NvrStatusManager.checkCpu = checked
                                Layout.fillWidth: true
                            }

                            CheckBox {
                                text: qsTr("Monitor recorder hardware errors")
                                checked: NvrStatusManager.checkHw
                                onCheckedChanged: NvrStatusManager.checkHw = checked
                                Layout.fillWidth: true
                            }

                            CheckBox {
                                text: qsTr("Monitor hard disk faults/abnormalities")
                                checked: NvrStatusManager.checkHdd
                                onCheckedChanged: NvrStatusManager.checkHdd = checked
                                Layout.fillWidth: true
                            }

                            CheckBox {
                                text: qsTr("Monitor unformatted hard disks")
                                checked: NvrStatusManager.checkUnformatted
                                onCheckedChanged: NvrStatusManager.checkUnformatted = checked
                                Layout.fillWidth: true
                            }

                            CheckBox {
                                text: qsTr("Monitor full hard disks (loop coverage disabled)")
                                checked: NvrStatusManager.checkFull
                                onCheckedChanged: NvrStatusManager.checkFull = checked
                                Layout.fillWidth: true
                            }
                        }
                    }

                    GroupBox {
                        title: qsTr("Odtwarzanie")
                        Layout.fillWidth: true

                        background: Rectangle {
                            color: "#141a21"
                            border.color: "#2a3540"
                            border.width: 1
                            radius: 8
                        }
                        label: Text {
                            text: parent.title
                            color: "#00f5d4"
                            font.bold: true
                            font.pixelSize: 12
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 8

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Text {
                                    text: qsTr("Domyślnie rozpoczynaj odtwarzanie wstecz o tą liczbę sekund:")
                                    color: "white"
                                    font.pixelSize: 11
                                    wrapMode: Text.WordWrap
                                    Layout.fillWidth: true
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    TextField {
                                        id: playbackOffsetSecondsField
                                        Layout.preferredWidth: 100
                                        Layout.preferredHeight: 30
                                        selectByMouse: true
                                        text: generalSettings.playbackOffsetSeconds.toString()
                                        color: "white"
                                        font.pixelSize: 12
                                        maximumLength: 7
                                        validator: IntValidator { bottom: 0; top: 9999999 }
                                        background: Rectangle {
                                            color: "#0f151b"
                                            radius: 4
                                            border.color: playbackOffsetSecondsField.activeFocus ? "#ff7a00" : "#2a3540"
                                        }
                                        onEditingFinished: {
                                            var val = parseInt(text)
                                            if (!isNaN(val) && val >= 0) {
                                                generalSettings.playbackOffsetSeconds = val
                                            } else {
                                                text = generalSettings.playbackOffsetSeconds.toString()
                                            }
                                        }
                                    }

                                    Item {
                                        Layout.fillWidth: true
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Text {
                                    text: qsTr("Domyślny zakres osi czasu w odtwarzaniu, godziny:")
                                    color: "white"
                                    font.pixelSize: 11
                                    wrapMode: Text.WordWrap
                                    Layout.fillWidth: true
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    TextField {
                                        id: playbackTimelineHoursField
                                        Layout.preferredWidth: 60
                                        Layout.preferredHeight: 30
                                        selectByMouse: true
                                        text: generalSettings.playbackTimelineHours.toString()
                                        color: "white"
                                        font.pixelSize: 12
                                        maximumLength: 2
                                        validator: IntValidator { bottom: 1; top: 24 }
                                        background: Rectangle {
                                            color: "#0f151b"
                                            radius: 4
                                            border.color: playbackTimelineHoursField.activeFocus ? "#ff7a00" : "#2a3540"
                                        }
                                        onEditingFinished: {
                                            var val = parseInt(text)
                                            if (!isNaN(val) && val >= 1 && val <= 24) {
                                                generalSettings.playbackTimelineHours = val
                                            } else {
                                                text = generalSettings.playbackTimelineHours.toString()
                                            }
                                        }
                                    }

                                    Item {
                                        Layout.fillWidth: true
                                    }
                                }
                            }
                        }
                    }

                    GroupBox {
                        title: qsTr("Zapis")
                        Layout.fillWidth: true

                        background: Rectangle {
                            color: "#141a21"
                            border.color: "#2a3540"
                            border.width: 1
                            radius: 8
                        }
                        label: Text {
                            text: parent.title
                            color: "#00f5d4"
                            font.bold: true
                            font.pixelSize: 12
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 12

                            CheckBox {
                                id: activatePathChangesCheckbox
                                text: qsTr("Uaktywnij zmiany w tej sekcji")
                                checked: false
                                Layout.fillWidth: true
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 12
                                enabled: activatePathChangesCheckbox.checked
                                opacity: activatePathChangesCheckbox.checked ? 1.0 : 0.5

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Text {
                                        text: qsTr("Domyślna ścieżka stopklatek:")
                                        color: "white"
                                        font.pixelSize: 11
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        TextField {
                                            id: snapshotPathField
                                            Layout.fillWidth: true
                                            selectByMouse: true
                                            text: generalSettings.snapshotPath
                                            color: "white"
                                            font.pixelSize: 12
                                            background: Rectangle {
                                                color: "#0f151b"
                                                radius: 4
                                                border.color: snapshotPathField.activeFocus ? "#ff7a00" : "#2a3540"
                                            }
                                            onEditingFinished: {
                                                generalSettings.snapshotPath = text
                                                Context.mkpath(text)
                                            }
                                        }

                                        Button {
                                            id: btnBrowseSnapshot
                                            text: "..."
                                            Layout.preferredWidth: 32
                                            Layout.preferredHeight: 30
                                            contentItem: Text {
                                                text: btnBrowseSnapshot.text
                                                font.bold: true
                                                color: "white"
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                            }
                                            background: Rectangle {
                                                color: btnBrowseSnapshot.pressed ? "#2a3540" : (btnBrowseSnapshot.hovered ? "#3a4550" : "#222c36")
                                                radius: 4
                                                border.color: "#2a3540"
                                            }
                                            onClicked: {
                                                 var initial = snapshotPathField.text;
                                                 if (!Context.dirExists(initial)) {
                                                     initial = Context.homePath();
                                                 }
                                                 var selected = Context.selectFolder(qsTr("Wybierz folder dla stopklatek"), initial);
                                                 if (selected && selected !== "") {
                                                     generalSettings.snapshotPath = selected;
                                                     Context.mkpath(selected);
                                                 }
                                             }
                                        }
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Text {
                                        text: qsTr("Domyślna ścieżka nagrań:")
                                        color: "white"
                                        font.pixelSize: 11
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        TextField {
                                            id: videoPathField
                                            Layout.fillWidth: true
                                            selectByMouse: true
                                            text: generalSettings.videoPath
                                            color: "white"
                                            font.pixelSize: 12
                                            background: Rectangle {
                                                color: "#0f151b"
                                                radius: 4
                                                border.color: videoPathField.activeFocus ? "#ff7a00" : "#2a3540"
                                            }
                                            onEditingFinished: {
                                                generalSettings.videoPath = text
                                                Context.mkpath(text)
                                            }
                                        }

                                        Button {
                                            id: btnBrowseVideo
                                            text: "..."
                                            Layout.preferredWidth: 32
                                            Layout.preferredHeight: 30
                                            contentItem: Text {
                                                text: btnBrowseVideo.text
                                                font.bold: true
                                                color: "white"
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                            }
                                            background: Rectangle {
                                                color: btnBrowseVideo.pressed ? "#2a3540" : (btnBrowseVideo.hovered ? "#3a4550" : "#222c36")
                                                radius: 4
                                                border.color: "#2a3540"
                                            }
                                            onClicked: {
                                                 var initial = videoPathField.text;
                                                 if (!Context.dirExists(initial)) {
                                                     initial = Context.homePath();
                                                 }
                                                 var selected = Context.selectFolder(qsTr("Wybierz folder dla nagrań"), initial);
                                                 if (selected && selected !== "") {
                                                     generalSettings.videoPath = selected;
                                                     Context.mkpath(selected);
                                                 }
                                             }
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                CctvButton {
                                    text: qsTr("otwórz folder obrazów")
                                    isCeladon: true
                                    Layout.fillWidth: true
                                    onClicked: {
                                        var path = generalSettings.snapshotPath;
                                        Context.mkpath(path);
                                        Qt.openUrlExternally("file://" + path);
                                    }
                                }

                                CctvButton {
                                    text: qsTr("otwórz folder wideo")
                                    isCeladon: true
                                    Layout.fillWidth: true
                                    onClicked: {
                                        var path = generalSettings.videoPath;
                                        Context.mkpath(path);
                                        Qt.openUrlExternally("file://" + path);
                                    }
                                }
                            }
                        }
                    }

                    GroupBox {
                        title: qsTr("System Media Configuration")
                        Layout.fillWidth: true

                        background: Rectangle {
                            color: "#141a21"
                            border.color: "#2a3540"
                            border.width: 1
                            radius: 8
                        }
                        label: Text {
                            text: parent.title
                            color: "#00f5d4"
                            font.bold: true
                            font.pixelSize: 12
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 12

                            CheckBox {
                                id: activateMediaChangesCheckbox
                                text: qsTr("Uaktywnij zmiany w tej sekcji")
                                checked: false
                                Layout.fillWidth: true
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 12
                                enabled: activateMediaChangesCheckbox.checked
                                opacity: activateMediaChangesCheckbox.checked ? 1.0 : 0.5

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Text {
                                        text: qsTr("Default FFmpeg command-line options")
                                        color: "white"
                                        font.pixelSize: 11
                                    }

                                    TextField {
                                        id: defaultAVFormatOptionsField
                                        selectByMouse: true
                                        Layout.fillWidth: true
                                        color: "white"
                                        font.pixelSize: 12
                                        background: Rectangle {
                                            color: "#0f151b"
                                            radius: 4
                                            border.color: defaultAVFormatOptionsField.activeFocus ? "#ff7a00" : "#2a3540"
                                        }
                                        text: {
                                            var opts = "";
                                            var options = layoutsCollectionSettings.toJSValue("defaultAVFormatOptions");
                                            for (var key in options) {
                                                if (typeof options[key] === "string" || typeof options[key] === "number") {
                                                    opts += "-%1 %2 ".arg(key).arg(options[key]);
                                                }
                                            }
                                            return opts.trim();
                                        }
                                        onEditingFinished: {
                                            layoutsCollectionSettings.defaultAVFormatOptions = JSON.stringify(Utils.parseOptions(text));
                                        }
                                    }

                                    CctvButton {
                                        Layout.fillWidth: true
                                        isCeladon: true
                                        text: qsTr("Zaktualizuj wszystkie kamery")
                                        onClicked: {
                                            var opts = layoutsCollectionSettings.toJSValue("defaultAVFormatOptions");
                                            for (var i = 0; i < layoutsCollectionModel.count; ++i) {
                                                var layoutModel = layoutsCollectionModel.get(i);
                                                for (var j = 0; j < layoutModel.count; ++j) {
                                                    var item = layoutModel.get(j);
                                                    if (!item.ignoreGlobalAVFormatOptions) {
                                                        item.avFormatOptions = opts;
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // PAGE 5: Changelog
            ScrollView {
                id: page5ScrollView
                clip: true
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    id: page5Layout
                    x: 24
                    width: page5ScrollView.width - 48
                    spacing: 20

                    Text {
                        text: qsTr("Dziennik zmian (Changelog)")
                        color: "#00f5d4"
                        font {
                            pixelSize: 16
                            bold: true
                        }
                    }

                    Text {
                        text: qsTr("Historia ulepszeń, poprawek błędów i nowych funkcji w programie KVision.")
                        color: "#8898a6"
                        font.pixelSize: 13
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    // Repeater rendering each version entry beautifully
                    Repeater {
                        model: rootSideBar.changelogData
                        delegate: ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            Layout.bottomMargin: 16

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: modelData.version
                                    color: "#00f5d4"
                                    font {
                                        pixelSize: 14
                                        bold: true
                                    }
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: modelData.date
                                    color: "#8898a6"
                                    font.pixelSize: 12
                                }
                            }

                            // Divider line
                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: "#2a3540"
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Layout.leftMargin: 8

                                Repeater {
                                    model: modelData.changes
                                    delegate: RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Text {
                                            text: "•"
                                            color: "#00f5d4"
                                            font.pixelSize: 14
                                            Layout.alignment: Qt.AlignTop
                                        }
                                        Text {
                                            text: modelData
                                            color: "#eeeeee"
                                            font.pixelSize: 12
                                            wrapMode: Text.WordWrap
                                            Layout.fillWidth: true
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Modal dialogs declared safely at root scope
    ConfirmDialog {
        id: presetDeleteDialog
        title: qsTr("Confirm Deletion")
        iconSource: "qrc:/images/icon-trash.svg"
        message: {
            if (index >= 0 && index < layoutsCollectionModel.count) {
                var layout = layoutsCollectionModel.get(index);
                if (layout && layout.name && layout.name.trim() !== "") {
                    return qsTr("Are you sure you want to delete preset \"%1\"? This action is completely irreversible.").arg(layout.name);
                }
            }
            return qsTr("Are you sure you want to delete preset #%1? This action is completely irreversible.").arg(index + 1);
        }
        property int index: -1
        onAccepted: layoutsCollectionModel.remove(index)
    }

    ConfirmDialog {
        id: nvrPresetDeleteDialog
        title: qsTr("Confirm Deletion")
        iconSource: "qrc:/images/icon-trash.svg"
        message: {
            if (index >= 0 && index < layoutsCollectionModel.count) {
                var layout = layoutsCollectionModel.get(index);
                if (layout && layout.name && layout.name.trim() !== "") {
                    return qsTr("Are you sure you want to delete NVR view \"%1\"? This action is completely irreversible.").arg(layout.name);
                }
            }
            return qsTr("Are you sure you want to delete this NVR view layout? This action is completely irreversible.");
        }
        property int index: -1
        onAccepted: layoutsCollectionModel.remove(index)
    }

    ConfirmDialog {
        id: nvrPresetDeleteDialog2
        title: qsTr("Confirm Deletion")
        iconSource: "qrc:/images/icon-trash.svg"
        message: {
            if (index >= 0 && index < layoutsCollectionModel.count) {
                var layout = layoutsCollectionModel.get(index);
                if (layout && layout.name && layout.name.trim() !== "") {
                    return qsTr("Are you sure you want to delete NVR Preset \"%1\"? This action is completely irreversible.").arg(layout.name);
                }
            }
            return qsTr("Are you sure you want to delete this NVR Preset? This action is completely irreversible.");
        }
        property int index: -1
        onAccepted: layoutsCollectionModel.remove(index)
    }

    Connections {
        target: generalSettings
        function onSnapshotPathChanged() {
            snapshotPathField.text = generalSettings.snapshotPath;
        }
        function onVideoPathChanged() {
            videoPathField.text = generalSettings.videoPath;
        }
        function onAuxiliaryLimitChanged() {
            auxiliaryLimitField.text = generalSettings.auxiliaryLimit.toString();
        }
    }


}
