# Walkthrough: Dodanie Instrukcji Obsługi i Dziennika Zmian (Changelog)

Z sukcesem zaimplementowaliśmy i przetestowaliśmy dwie nowe, premium funkcjonalności w programie **CCTV Viewer 2**:
1. **Przycisk i Okno Instrukcji Obsługi (`📖 INSTRUKCJA` / `📖 INSTRUCTIONS`)** w oknie głównym oraz oknie pomocniczym.
2. **Zakładka Changelog (Dziennik zmian)** w panelu opcji sidebar z pełną historią wersji oraz wsparciem dla przyszłych aktualizacji.

Wszystkie nowe elementy są w pełni zlokalizowane i posiadają profesjonalne wersje językowe (polską i angielską).

---

## Wdrożone Zmiany

### 1. Przycisk i Okno Instrukcji Obsługi (Instructions Window)
* **[InstructionsWindow.qml](src/InstructionsWindow.qml)**: 
  * Utworzono nowe, estetyczne okno, które dynamicznie wczytuje instrukcję z zasobów (`qrc:/INSTRUKCJA.md` lub `qrc:/INSTRUCTIONS.md`) za pomocą asynchronicznego żądania `XMLHttpRequest`.
  * Zaimplementowano wbudowany, wydajny parser Markdown-to-HTML, który konwertuje nagłówki, bloki kodu, listy wypunktowane, pogrubienia oraz poziome linie na bogaty tekst HTML (RichText) ze stylowaniem pasującym do ciemnego motywu oraz turkusowych akcentów programu (`#00f5d4`).
* **Przycisk `📖 INSTRUKCJA`**:
  * Dodano przycisk w oknie głównym **[RootWindow.qml](src/RootWindow.qml)** oraz w oknie pomocniczym **[AuxiliaryWindow.qml](src/AuxiliaryWindow.qml)**.
  * Przycisk posiada zaokrąglone krawędzie, elegancki podświetlany turkusowy obrys po najechaniu myszą i płynną zmianę tła przy kliknięciu.

### 2. Dziennik Zmian (Changelog) w Opcjach
* **[SideBar.qml](src/SideBar.qml)**:
  * Dodano nową pozycję w menu bocznym (Sidebar) o nazwie **Changelog**.
  * Stworzono dedykowaną ikonę **[images/menu-changelog.svg](images/menu-changelog.svg)** i zarejestrowano ją w zasobach.
  * Zaimplementowano tablicę obiektów JS `changelogData`, która przechowuje ustrukturyzowane informacje o wszystkich wersjach programu (od `v2.0.0` do `v2.0.9-2 (Patch)`). Dzięki temu dodawanie kolejnych wersji w przyszłości sprowadza się do dopisania jednego obiektu do tablicy.
  * Zbudowano elegancki widok w oparciu o `ScrollView` i elementy `Repeater`, z dynamicznym wyliczaniem list ulepszeń i poprawek, podziałem linii separatorami oraz turkusowymi wyróżnieniami numerów wersji.

### 3. Pełne Tłumaczenie i Lokalizacja
* **[translations/cctv-viewer_pl_PL.ts](translations/cctv-viewer_pl_PL.ts)** oraz **[translations/cctv-viewer_en_US.ts](translations/cctv-viewer_en_US.ts)**:
  * Przetłumaczono wszystkie 31 nowo wyodrębnionych ciągów znaków.
  * Przetłumaczono nazwy opcji, opisy oraz wszystkie historyczne punkty z dziennika zmian dla obu języków.
  * Skonfigurowano ścieżkę instrukcji jako przetłumaczalny zasób: w polskiej lokalizacji ładuje się `qrc:/INSTRUKCJA.md`, a w angielskiej lokalizacji `qrc:/INSTRUCTIONS.md`.

---

## Dodatkowe Poprawki i Analiza (Click-and-Add & Skróty)

1. **Poprawka metody przypisywania kamer (Click-and-Add)**:
   * Przeanalizowano interakcję z listą kamer w oknie `NvrCamerasWindow.qml` i sprostowano opis przypisywania kamer do siatki. Program nie obsługuje przeciągania (drag and drop) dla przypisywania kamer, lecz intuicyjną metodę **Click-and-Add** (Kliknij i Przypisz):
     1. Użytkownik klika na dany viewport na siatce, aby go zaznaczyć.
     2. Następnie klika zieloną ikonę `+` na kaflu wybranej kamery na liście, co od razu przypisuje strumień do aktywnego viewportu.
   * Zaktualizowano ten opis w sekcji 2 (punkt 8) zarówno w polskim podręczniku (`INSTRUKCJA.md`), jak i angielskim (`INSTRUCTIONS.md`).

2. **Udostępnienie ukrytych skrótów klawiaturowych dla zaawansowanych użytkowników (Power-Users)**:
   * Dokonano pełnego przeglądu kodu QML (`RootWindow.qml` oraz `ViewportsLayout.qml`) pod kątem skrótów klawiszowych i obsługi klawiatury.
   * Wykryto i w pełni udokumentowano w sekcji 8.2 oraz sekcji 9 (Skróty) zaawansowane funkcje sterowania klawiaturą, które wcześniej były pominięte:
     * **Alt + Strzałka w lewo / Strzałka w prawo**: Szybkie przełączanie pomiędzy zdefiniowanymi presetami/widokami siatki.
     * **Strzałki (Góra/Dół/Lewo/Prawo)**: Płynna nawigacja i przemieszczanie aktywnego zaznaczenia (focusa) pomiędzy viewportami na siatce kamer.
     * **Shift + Strzałki**: Zaznaczanie wielu sąsiadujących kafelków w siatce jednocześnie za pomocą klawiatury (do scalania asymetrycznego `Merge Highlighted Cells`).
     * **Ctrl + N**: Oficjalne skrótowe otwieranie nowego okna pomocniczego (`Auxiliary Window`).
     * **F11**: Standardowe przełączanie trybu pełnoekranowego.
     * **Esc**: Wyjście z trybu pełnoekranowego lub usunięcie aktywnego zaznaczenia kafelka.

---

## Wizualne Udoskonalenie Przycisków (Delete & Activate) i Dodanie Tooltipów

W celu nadania aplikacji niezwykle profesjonalnego wyglądu, zrównaliśmy stylistykę wszystkich pobocznych przycisków usuwania oraz aktywacji z przyciskami paska górnego (precyzyjna linia outline 2.5px, pełna kołowość, ciemne tło z płynnymi przejściami):

1. **Przycisk Usuwania Rejestratora (`delBtn` w `NvrSettingsPanel.qml`)**:
   * Zaktualizowano grubość obrysu wbudowanej ikony SVG z domyślnej na `stroke-width='2.5'`.
   * Przycisk posiada zaokrąglone krawędzie (promień `15px` dla rozmiaru `30x30`), pasując idealnie do pozostałych okrągłych kontrolek.
   * Dodano polski tooltip za pomocą `qsTr("Usuń rejestrator z listy")`.

2. **Przyciski Aktywacji i Usuwania w Sidebarze (`SideBar.qml`)**:
   * **Ujednolicenie Ikony Usuwania we wszystkich listach**:
     - Wszystkie trzy przyciski usuwania w sidebarze (`delPresetBtn`, `delNvrBtn`, `delNvrPresetBtn`) zostały zaktualizowane, aby korzystały z tej samej pięknej ikony **inline SVG** o grubości obrysu `stroke-width='2.5'` zamiast pliku `icon-trash.svg`.
     - Ikona ta dynamicznie zmienia kolor z neutralnego szaroniebieskiego (`#8898a6`) na jaskrawoczerwony (`#ff4d4d`) po najechaniu kursorem myszy, zapewniając płynny i atrakcyjny efekt przejścia.
   * **Układy Podglądu (Grid view presets)**:
     - Zastąpiono tekstowy przycisk aktywacji w pełni okrągłą ikoną odtwarzania (trójkąt outline SVG z `stroke-width='2.5'`). Dodano tooltip `qsTr("Aktywuj ten układ podglądu")`.
     - Przycisk usuwania ujednolicono do w pełni okrągłego tła (promień `14px` przy `28x28`) i wyposażono w tooltip `qsTr("Usuń ten układ podglądu")`.
   * **Widoki kamer NVR (NVR Views)**:
     - Zastąpiono tekstowy przycisk aktywacji analogiczną ikoną play z tooltipem `qsTr("Aktywuj ten widok kamer NVR")`.
     - Przycisk usuwania ujednolicono (promień `14px`) i dodano tooltip `qsTr("Usuń ten widok kamer NVR")`.
     - Usunięto nieużywaną właściwość tekstową `text` z przycisku `activateBtnNvr`.
   * **Presety kamer NVR (NVR Presets)**:
     - Zastąpiono tekstowy przycisk aktywacji (`activateBtnNvrPreset`) okrągłą ikoną play z tooltipem `qsTr("Aktywuj ten preset kamer NVR")`.
     - Przycisk usuwania (`delNvrPresetBtn`) ujednolicono (promień `14px`) i dodano tooltip `qsTr("Usuń ten preset kamer NVR")`.

Wszystkie dodane tooltipy respektują preferencje językowe użytkownika (są ujęte w klauzule `qsTr(...)` i przygotowane do internacjonalizacji).

---

## Kompaktowy Układ Paska Górnego (Oszczędność Miejsca)

Zoptymalizowaliśmy wykorzystanie przestrzeni roboczej na górnym pasku narzędziowym zarówno w oknie głównym ([RootWindow.qml](file:///home/robert/cctv/cctv-viewer2/src/RootWindow.qml)), jak i oknie pomocniczym ([AuxiliaryWindow.qml](file:///home/robert/cctv/cctv-viewer2/src/AuxiliaryWindow.qml)):

1. **Zmniejszenie odstępów między elementami (`spacing`)**:
   - Główny odstęp w `RowLayout` paska górnego został zmniejszony z **`12` na `6`**.
   - Odstępy w zagnieżdżonych sekcjach siatek (rozmiary siatki, przycisk menu) oraz w sekcji wyboru widoków zostały zmniejszone z **`6` na `4`**.
2. **Optymalizacja marginesów bocznych (`anchors.margin`)**:
   - Lewy i prawy margines paska górnego zmniejszono z **`12` na `8`**, dzięki czemu przyciski idealnie wykorzystują całą dostępną szerokość ekranu.

Dzięki tym ulepszeniom pasek górny wygląda lżej, jest bardziej zbity i eliminuje ryzyko przepełnienia poziomego (overflow) na ekranach o mniejszej rozdzielczości.

---

## Nowy Wygląd Paska Górnego (Zamiana Tekstu na Okrągłe Ikony SVG)

Zgodnie z wymaganiami, wszystkie przyciski z tekstami w oknie głównym (**[RootWindow.qml](file:///home/robert/cctv/cctv-viewer2/src/RootWindow.qml)**) oraz oknie pomocniczym (**[AuxiliaryWindow.qml](file:///home/robert/cctv/cctv-viewer2/src/AuxiliaryWindow.qml)**) zostały zastąpione w pełni okrągłymi (rozmiar `30x30`, promień zaokrąglenia `15px`), profesjonalnymi ikonami SVG z delikatnym obrysem (outline) o grubości `stroke-width='2.5'` oraz estetycznymi tooltipami:

1. **Przycisk Opcje (`optionsButton`)**:
   - Tekst `⚙️ OPCJE` został zastąpiony nową, precyzyjnie narysowaną ikoną koła zębatego (gear/settings) SVG z ciepłym pomarańczowym podświetleniem (`#ff7a00`/`#ff9e00`) po najechaniu myszą.
   - Dodano tooltip: `qsTr("Opcje i ustawienia panelu bocznego")`.
2. **Przycisk Nowe Okno (`newWindowButton`)**:
   - Tekst `📺 NOWE OKNO` zastąpiono autorską ikoną SVG przedstawiającą nakładające się na siebie ekrany monitorów z płynną zmianą koloru z neutralnego szaroniebieskiego na jaskrawopomarańczowy (`#ff9e00`).
   - Dodano tooltip: `qsTr("Otwórz nowe okno pomocnicze")`.
3. **Przycisk Archiwum (`archiveButton`)** (tylko w oknie głównym):
   - Tekst `ARCHIVE` zastąpiono minimalistyczną, przestrzenną ikoną bazy danych/archiwum SVG w kolorze jasnego turkusu (`#00bfa5` / `#00f5d4` na hover).
   - Dodano tooltip: `qsTr("Archiwum nagrań i odtwarzacz")`.
4. **Przycisk Instrukcja (`instructionsButton`)**:
   - Tekst `INSTRUKCJA` zastąpiono symbolem otwartej księgi SVG, idealnie współgrającym z resztą paska (turkusowy akcent `#00f5d4` po najechaniu).
   - Dodano tooltip: `qsTr("Instrukcja obsługi programu")`.
5. **Dedykowana Ikona Statystyk (`systemStatsSwitch`)** (tylko w oknie głównym):
   - Klasyczny przełącznik suwakowy `📊 STATYSTYKI` został zastąpiony nowatorskim, okrągłym przyciskiem-ikoną SVG przedstawiającą słupki statystyk (bar chart).
   - Ikona **dynamicznie odzwierciedla stan włączenia/wyłączenia**:
     - Gdy statystyki są **wyłączone**: przycisk ma neutralny szaroniebieski kolor, a po najechaniu podświetla się na biało. Tooltip wyświetla tekst: `qsTr("Włącz statystyki zużycia zasobów")`.
     - Gdy statystyki są **włączone**: przycisk świeci piękną, intensywną zielenią (`#00ff66`), tło przyjmuje elegancki, półprzezroczysty zielony odcień (`#cc004d1a`), a tooltip wyświetla tekst: `qsTr("Wyłącz statystyki zużycia zasobów")`.
   - Przycisk zachowuje identyczną kompatybilność z dotychczasowymi powiązaniami właściwości (property bindings) w innych komponentach poprzez właściwość `checked`.

---

## Dedykowane Zachowanie Kursorów w Viewportach (Interaktywne Wskaźniki)

Aby poprawić wrażenia z obsługi programu (User Experience) i uczynić interfejs kafelków wideo bardziej intuicyjnym, wdrożyliśmy zaawansowane, dynamiczne sterowanie kursorami myszy w oknie podglądu na żywo (**[Player.qml](file:///home/robert/cctv/cctv-viewer2/src/Player.qml)**) oraz oknie odtwarzacza archiwum nagrań (**[PlaybackWindow.qml](file:///home/robert/cctv/cctv-viewer2/src/PlaybackWindow.qml)**):

1. **Wskaźnik rączki (`pointing hand`) nad przyciskami nakładki**:
   - Po najechaniu myszą na dowolną z okrągłych ikon sterowania w dolnym prawym rogu kafelka wideo (zrzut ekranu, archiwum nagrań, tryb 1:1, przybliżenie), kursor natychmiast zmienia się w profesjonalną **rączkę wskazującą** (`Qt.PointingHandCursor`).
   - Poprawiono strukturę warstw w **[Player.qml](file:///home/robert/cctv/cctv-viewer2/src/Player.qml)**, przenosząc przyciski sterujące z wewnątrz obszaru `playerHoverArea` do osobnego elementu jako jego rodzeństwo (sibling). Zapobiega to przejmowaniu/nadpisywaniu stanów kursorów przez nadrzędny element śledzący hover.

2. **Bezpieczne śledzenie stanu hover i eliminacja migotania**:
   - Wprowadzono nową, zintegrowaną właściwość QML `isHovered` w **[Player.qml](file:///home/robert/cctv/cctv-viewer2/src/Player.qml)**:
     ```qml
     readonly property bool isHovered: playerHoverArea.containsMouse || snapshotMouseAreaBtn.containsMouse || playbackMouseAreaBtn.containsMouse || oneToOneMouseAreaBtn.containsMouse || zoomMouseAreaBtn.containsMouse
     ```
   - Poprzez powiązanie widoczności przycisków oraz pozostałych plakietek informacyjnych (stream info, nazwa kamery) z nową właściwością `isHovered`, wyeliminowano problem gwałtownego migotania (flickeringu) interfejsu, gdy kursor przechodzi między podglądem wideo a przyciskami nakładki.

3. **4-kierunkowy kursor przemieszczania (`size all`) w trybie 1:1**:
   - Po aktywacji trybu **1:1 (piksel w piksel)**, gdy użytkownik najeżdża na kafel wideo (zarówno w widoku na żywo, jak i w archiwum), kursor automatycznie przybiera postać **4-kierunkowych strzałek** (`Qt.SizeAllCursor`).
   - Kursor ten stanowi jasną wizualną wskazówkę, że obraz wideo jest większy niż kafelek i można go swobodnie przesuwać/panoramić we wszystkich kierunkach.
   - Podczas rzeczywistego przeciągania obrazu (trzymanie wciśniętego środkowego przycisku myszy), kursor płynnie zmienia się w **zamkniętą dłoń** (`Qt.ClosedHandCursor`), co doskonale odwzorowuje fizyczny gest chwycenia i przesuwania płótna.

4. **Zachowanie w innych trybach**:
   - W trybie wyboru obszaru powiększenia (ROI Zoom Selection), kursor automatycznie przybiera postać **krzyżyka** (`Qt.CrossCursor`).
   - W standardowym trybie kursor zachowuje domyślny kształt strzałki systemowej (`Qt.ArrowCursor`).

---

## Wizualne Udoskonalenie Ikon w Viewportach (Ostre wektory SVG High-DPI i brak przepełnienia)

Aby zapewnić najwyższą jakość estetyczną, zaimplementowaliśmy i przetestowaliśmy ulepszoną grafikę ikon dla przycisków sterujących w nakładkach viewportów w widoku na żywo (`src/Player.qml`) oraz w oknie archiwum nagrań (`src/PlaybackWindow.qml`).

Rozwiązane zostały dwa kluczowe problemy zgłaszane przez użytkowników:
1. **Pikseloza i rozmycie ikon**:
   - Poprzednie wersje renderowały ikony SVG przy wymuszonym, niskim rozmiarze źródłowym `sourceSize: Qt.size(12, 12)` lub `Qt.size(15, 15)`. Wymuszało to na silniku Qt rasteryzację wektora do mikroskopijnych rozmiarów, dając w efekcie rozmyte ikony.
   - Nowe rozwiązanie definiuje `sourceSize: Qt.size(32, 32)` oraz `fillMode: Image.PreserveAspectFit` na elemencie `Image`. Dzięki temu grafika wektorowa SVG jest renderowana w wysokiej rozdzielczości (High-DPI), a następnie bezpiecznie i płynnie skalowana w dół przez silnik QML, dając nieskazitelnie ostry (Crisp HD) obraz.
2. **Wykraczanie ikon poza okrągłe obramowanie (Overflow)**:
   - Poprzednie ikony miały ręcznie przypisywane kotwice `anchors.centerIn: parent` oraz sztywne szerokości/wysokości, co powodowało błędy pozycjonowania i brak skalowalności.
   - Dodaliśmy wewnętrzny margines `padding: 5` do samych przycisków sterujących `Control` o wymiarach `24x24px`. To matematycznie ogranicza pole robocze ikony do wewnętrznego obszaru `14x14px`, gwarantując idealne centrowanie oraz całkowicie eliminując ryzyko wyjścia ikony poza okrągłe tło (`radius: 12`).

### Przeprojektowane Ikony SVG (Styling paska górnego)
Wszystkie ikony zostały przepisane na ultralekkie, jednolite i responsywne wektory inline SVG o grubości linii `stroke-width='2'` (pasującej do delikatnych ikon paska górnego):
- **Wykonaj stopklatkę (`snapshotBadge`)**: Precyzyjny aparat fotograficzny, zmieniający kolor na seledynowy (`#00f5d4`) przy najechaniu myszą lub na intensywny pomarańczowy (`#ff7a00`) podczas zapisywania zrzutu ekranu.
- **Archiwum nagrań (`playbackBadge`)**: Minimalistyczny, wyrazisty trójkąt odtwarzania (Play).
- **Tryb 1:1 (`oneToOneBadge`)**: Zastąpiono rozmyty, niskiej jakości tekst SVG `<text x='8' y='12.5'>1:1</text>` precyzyjnie wyrysowanymi ścieżkami wektorowymi (`<path d='M6 8.5L8 7v10M16 8.5L18 7v10'></path>`) oraz dwoma wektorowymi punktami dwukropka. Daje to perfekcyjnie ostry, spójny i niezależny od czcionek systemowych wygląd.
- **Powiększenie obszaru (`zoomBadge`)**: Delikatny wektor lupy z plusem (aktywacja wyboru) lub minusem (reset zoomu w kolorze jasnoczerwonym `#ff3333`).

---

## Wyniki Budowania i Weryfikacji

1. **Kompilacja CMake/Make**:
   - Projekt został pomyślnie skonfigurowany i skompilowany w katalogu `./build/` bez żadnych błędów.
   - Nowe/zmodyfikowane pliki QML skompilowały się pomyślnie w pamięci podręcznej QML.
   - Wszystkie testy przeszły pomyślnie.

---

## Naprawa Kompilacji Tłumaczeń i Polskich Opisów (v2.1.1-1)

### 1. Problem z cykliczną zależnością i brakiem regeneracji plików `.qm`
* **Diagnoza**: W konfiguracji CMake używano makra `qt5_create_translation` (które wywołuje pod spodem narzędzie `lupdate` w celu przeskanowania kodu źródłowego). Ponieważ pliki `.ts` oraz skompilowany plik zasobów `qrc_cctv-viewer_qmlcache.cpp` (lub `${RESOURCES}`) należały do celów docelowych binaru, generowanie kodu zasobów zależało od plików `.qm`, te z kolei od `.ts`, a te od skanowania źródeł (w tym wygenerowanego kodu zasobów). Tworzyło to **pętlę w grafie zależności (circular dependency)** w CMake.
* **Skutek**: Podczas kompilacji CMake porzucał część zależności, a pliki `.qm` (szczególnie angielski `cctv-viewer_en_US.qm`) nie były regenerowane automatycznie podczas budowania. W konsekwencji program oraz paczka Pacman korzystały z przestarzałych plików binarnych tłumaczeń, co powodowało wyświetlanie polskich tekstów źródłowych (np. w dzienniku zmian Changelog oraz tooltipach) w angielskiej lokalizacji.

### 2. Wdrożone Rozwiązanie
* **Poprawka w [CMakeLists.txt](file:///home/robert/cctv/cctv-viewer2/CMakeLists.txt)**:
  1. Usunięto problematyczne wywołania `qt5_create_translation` / `qt_create_translation` (które uruchamiały niepotrzebnie `lupdate` na każdym etapie kompilacji).
  2. Zastąpiono je asynchronicznymi i bezproblemowymi makrami **`qt5_add_translation`** / **`qt_add_translation`** (które uruchamiają wyłącznie `lrelease` kompilujący `.ts` do `.qm` bez skanowania kodu).
  3. Przeniesiono generowanie `QM_FILES` przed definicję `PROJ_FILES` i włączono `${QM_FILES}` bezpośrednio do listy źródeł binaru.
  4. Gwarantuje to w pełni **acykliczny łańcuch zależności**: `${TS_FILES}` -> `lrelease` -> `${QM_FILES}` -> `rcc` (zasoby) -> kompilacja binaru. Pliki `.qm` są teraz automatycznie kompilowane przy każdej zmianie w tłumaczeniach.
* **Przebudowa Paczki i Publikacja**:
  * Pomyślnie skompilowano i spakowano nową wersję pakietu Pacman za pomocą `makepkg -f` w katalogu `packaging/arch`.
  * Wypchnięto poprawki na repozytorium GitHub (gałąź `master`).
  * Podmieniono paczkę binarną `cctv-viewer2-2.1.1-1-x86_64.pkg.tar.zst` bezpośrednio w wydaniu **Tag v2.1.1** na GitHubie.

