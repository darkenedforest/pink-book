import QtQuick
import QtQuick.Window

Window {
    id: root
    required property var store
    property bool paperDisplay: false
    width: paperDisplay ? Screen.width : 800
    height: paperDisplay ? Screen.height : 1050
    visible: true
    visibility: paperDisplay ? Window.FullScreen : Window.Windowed
    title: "Pink Book Reader"
    color: paper

    readonly property color paper: "#faf8f3"
    readonly property color ink: "#25221f"
    readonly property color muted: "#57504a"
    readonly property color accent: "#7c382d"
    readonly property color line: "#c7bfb1"
    readonly property color panel: "#eee9df"
    readonly property real unit: Math.max(0.85, Math.min(width / 750, height / 960, 2.2))
    readonly property real gutter: 35 * unit
    readonly property string jpFont: store.fontFamily

    readonly property var books: store.books
    property var book: null
    property var chapter: null
    property string viewMode: String(store.value("viewMode", "paged")) === "continuous" ? "continuous" : "paged"
    property var chapterOffsets: [0]
    property var pageBounds: [0]
    property int currentPage: 0
    readonly property int pageStart: Number(pageBounds[currentPage] || 0)
    readonly property int pageEnd: Number(pageBounds[currentPage + 1] || 0)
    readonly property int pageCount: Math.max(0, pageBounds.length - 1)
    readonly property int displayedRows: viewMode === "continuous" ?
        Number(chapterOffsets[chapterOffsets.length - 1]) : Math.max(0, pageEnd - pageStart)
    property string screen: "shelf"
    property var lookup: null
    property rect lookupAnchor: Qt.rect(0, 0, 0, 0)
    property bool showSettings: false
    property bool furigana: Boolean(store.value("furigana", true))
    property bool translations: Boolean(store.value("translations", false))
    property bool kana: Boolean(store.value("kana", false))
    property int sizeStep: Math.max(0, Math.min(5, Number(store.value("sizeStep", 2))))
    property real textSize: (24 + sizeStep * 4) * unit
    property string lastBook: String(store.value("lastBook", ""))
    property string lastChapter: String(store.value("lastChapter", ""))
    property int bookmark: -1
    property int position: 0
    property int progressRevision: 0
    property real positionOffset: -1
    property int positionPercent: -1
    property bool restoring: false
    property int chapterSerial: 0

    function chapterNumber(selected, id) {
        if (!selected || !id) return -1
        for (let i = 0; i < selected.chapters.length; i++)
            if (selected.chapters[i].id === id) return i
        return -1
    }

    function offsetsFor(selectedBook) {
        const offsets = [0]
        for (const c of selectedBook.chapters)
            offsets.push(offsets[offsets.length - 1] + Number(c.sentenceCount))
        return offsets
    }

    function positionKey() { return "reading/" + book.id + "/" + chapter.id }

    function selectPage(line) {
        for (let i = 0; i < pageCount; i++) {
            if (line < Number(pageBounds[i + 1])) { currentPage = i; return }
        }
        currentPage = Math.max(0, pageCount - 1)
    }

    function placeRow(row, offset) {
        pages.forceLayout()
        if (!displayedRows || row < 0 || row >= displayedRows) return
        pages.positionViewAtIndex(row, ListView.Beginning)
        const item = pages.itemAtIndex(row)
        const within = item ? Math.min(offset, Math.max(0, item.height - 1)) : 0
        if (within)
            pages.contentY = Math.min(pages.contentY + within,
                                    Math.max(pages.originY, pages.originY + pages.contentHeight - pages.height))
    }

    function openAt(nextBook, nextChapter, line, offset) {
        restoring = true
        const serial = ++chapterSerial
        pages.cancelFlick()
        const bookChanged = !book || book.id !== nextBook.id
        book = nextBook
        chapter = nextChapter
        if (bookChanged || chapterOffsets.length !== book.chapters.length + 1)
            chapterOffsets = offsetsFor(book)
        bookmark = Number(store.value("bookmark/" + book.id + "/" + chapter.id, -1))
        positionOffset = -1
        positionPercent = -1
        position = Math.max(0, Math.min(line, Number(chapter.sentenceCount) - 1))
        lastBook = book.id
        lastChapter = chapter.id
        let row
        if (viewMode === "continuous") {
            row = Number(chapterOffsets[chapterNumber(book, chapter.id)]) + position
        } else {
            pageBounds = store.pageBoundaries(chapter.file)
            selectPage(position)
            row = position - pageStart
        }
        screen = "read"
        Qt.callLater(function() {
            if (serial !== chapterSerial || screen !== "read") return
            placeRow(row, offset)
            restoring = false
            rememberPosition()
            pages.forceActiveFocus()
        })
    }

    function openChapter(nextBook, nextChapter) {
        rememberPosition()
        lookup = null
        showSettings = false
        const key = "reading/" + nextBook.id + "/" + nextChapter.id
        openAt(nextBook, nextChapter, Number(store.value(key + "/index", 0)),
               Number(store.value(key + "/offset", 0)))
    }

    function resumeChapter(selected) {
        // Re-evaluate bookshelf bindings when a new position is checkpointed.
        const version = progressRevision
        if (!selected) return null
        const id = String(store.value("reading/" + selected.id + "/current", ""))
        for (const c of selected.chapters)
            if (c.id === id) return c
        return null
    }

    function continueReading() {
        for (const b of books)
            if (b.id === lastBook)
                for (const c of b.chapters)
                    if (c.id === lastChapter) { openChapter(b, c); return }
    }

    function continueCaption() {
        for (const b of books)
            if (b.id === lastBook)
                for (const c of b.chapters)
                    if (c.id === lastChapter) return b.title + "  ·  " + c.subtitle
        return ""
    }

    function bookProgress(selected) {
        const current = resumeChapter(selected)
        if (!current) return selected.chapters.length + " chapters   ›"
        const chapterIndex = chapterNumber(selected, current.id)
        const percent = Number(store.value("reading/" + selected.id + "/" + current.id + "/percent", 0))
        return "Chapter " + (chapterIndex + 1) + " of " + selected.chapters.length + "   ·   " + percent + "% of chapter   ›"
    }

    function rowLocation(row) {
        if (row < 0 || !book || !chapter) return null
        if (viewMode === "paged")
            return {chapter: chapter, line: pageStart + row}
        for (let i = 0; i + 1 < chapterOffsets.length; i++) {
            if (row < chapterOffsets[i + 1])
                return {chapter: book.chapters[i], line: row - chapterOffsets[i]}
        }
        return null
    }

    function rowEntry(location) {
        return location ? store.sentence(location.chapter.file, location.line) : ({parts: []})
    }

    function topRow() {
        if (!displayedRows) return -1
        for (let dy = 1; dy <= 60 * unit; dy += Math.max(1, 5 * unit)) {
            const row = pages.indexAt(pages.contentX + 2, pages.contentY + dy)
            if (row >= 0) return row
        }
        if (viewMode === "paged") return Math.max(0, position - pageStart)
        const number = chapterNumber(book, chapter.id)
        return number >= 0 ? Number(chapterOffsets[number]) + position : 0
    }

    function rememberPosition() {
        if (screen !== "read" || restoring || !chapter) return
        const row = topRow()
        const location = rowLocation(row)
        if (!location) return
        const item = pages.itemAtIndex(row)
        const offset = item ? Math.max(0, Math.round(pages.contentY - item.y)) : 0
        const count = Number(location.chapter.sentenceCount)
        const finished = pages.atYEnd && (viewMode === "continuous" ||
                         (pageEnd === count && pages.contentY > pages.originY))
        const percent = finished ? 100 : Math.min(99, Math.floor(100 * location.line / Math.max(1, count)))
        const newChapter = location.chapter.id !== chapter.id
        if (!newChapter && location.line === position && offset === positionOffset && percent === positionPercent)
            return
        if (newChapter) {
            chapter = location.chapter
            bookmark = Number(store.value("bookmark/" + book.id + "/" + chapter.id, -1))
        }
        position = location.line
        positionOffset = offset
        positionPercent = percent
        lastBook = book.id
        lastChapter = chapter.id
        store.remember(book.id, chapter.id, position, offset, percent)
        ++progressRevision
    }

    function openBook(selected) {
        rememberPosition()
        ++chapterSerial
        chapterOffsets = offsetsFor(selected)
        book = selected
        screen = "chapters"
        lookup = null
        showSettings = false
        chapterList.positionViewAtBeginning()
    }

    function openLookup(target, entry) {
        pages.cancelFlick()
        rememberPosition()
        const token = target.mapToItem(lookupOverlay, 0, 0)
        const viewport = pages.mapToItem(lookupOverlay, 0, 0)
        const top = Math.max(token.y, viewport.y)
        const bottom = Math.min(token.y + target.height, viewport.y + pages.height)
        lookupAnchor = Qt.rect(token.x, top, target.width, Math.max(0, bottom - top))
        lookupBody.cancelFlick()
        lookupBody.contentY = 0
        lookup = entry
    }

    function back() {
        if (lookup) { lookup = null; return }
        if (showSettings) { showSettings = false; return }
        if (screen === "read") { openBook(book); return }
        screen = "shelf"
    }

    function canMove(direction) {
        if (!displayedRows || !chapter || restoring) return false
        if (viewMode === "continuous")
            return direction < 0 ? !pages.atYBeginning : !pages.atYEnd
        const n = chapterNumber(book, chapter.id)
        return direction < 0 ? currentPage > 0 || n > 0
                             : currentPage + 1 < pageCount || n + 1 < book.chapters.length
    }

    function page(direction) {
        if (screen !== "read" || lookup || showSettings || !canMove(direction)) return
        rememberPosition()
        if (viewMode === "continuous") {
            const bottom = Math.max(pages.originY, pages.originY + pages.contentHeight - pages.height)
            pages.cancelFlick()
            pages.contentY = Math.min(bottom, Math.max(pages.originY,
                pages.contentY + direction * Math.max(pages.height - 66 * unit, pages.height * 0.7)))
            rememberPosition()
            return
        }
        const targetPage = currentPage + direction
        if (targetPage >= 0 && targetPage < pageCount) {
            openAt(book, chapter, Number(pageBounds[targetPage]), 0)
        } else {
            const next = book.chapters[chapterNumber(book, chapter.id) + direction]
            const limits = direction < 0 ? store.pageBoundaries(next.file) : []
            openAt(book, next, direction < 0 ? Number(limits[limits.length - 2] || 0) : 0, 0)
        }
    }

    function toggleBookmark() {
        rememberPosition()
        if (!displayedRows) return
        bookmark = bookmark === position ? -1 : position
        store.setValue("bookmark/" + book.id + "/" + chapter.id, bookmark)
    }

    function gotoBookmark() {
        if (bookmark < 0 || bookmark >= Number(chapter.sentenceCount)) return
        openAt(book, chapter, bookmark, 0)
    }

    function updatePreference(name, value) {
        rememberPosition()
        const row = topRow()
        const offset = Math.max(0, positionOffset)
        if (name === "furigana") furigana = value
        if (name === "translations") translations = value
        if (name === "kana") kana = value
        if (name === "sizeStep") sizeStep = value
        store.setValue(name, value)
        if (screen === "read" && row >= 0) {
            const serial = chapterSerial
            Qt.callLater(function() {
                if (screen !== "read" || serial !== chapterSerial) return
                placeRow(row, offset)
                rememberPosition()
            })
        }
    }

    function changeMode(nextMode) {
        if (nextMode === viewMode) return
        rememberPosition()
        const line = position
        const offset = Math.max(0, positionOffset)
        viewMode = nextMode
        store.setValue("viewMode", nextMode)
        if (screen === "read") openAt(book, chapter, line, offset)
    }

    onClosing: { rememberPosition(); store.sync() }
    Timer {
        id: positionTimer
        interval: 170
        onTriggered: root.rememberPosition()
    }
    Shortcut { sequences: ["Escape", "Back"]; onActivated: root.back() }
    Shortcut { sequences: ["PgDown", "Right"]; onActivated: root.page(1) }
    Shortcut { sequences: ["PgUp", "Left"]; onActivated: root.page(-1) }

    Rectangle {
        id: header
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 72 * root.unit
        color: root.panel
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.line }
        ReaderButton {
            id: backButton
            unit: root.unit
            anchors { left: parent.left; leftMargin: root.gutter; verticalCenter: parent.verticalCenter }
            label: root.screen === "read" ? "‹ Chapters" : "‹ Shelf"
            visible: root.screen !== "shelf"
            onClicked: root.back()
        }
        Text {
            anchors {
                left: root.screen !== "shelf" ? backButton.right : parent.left
                leftMargin: root.screen !== "shelf" ? 16 * root.unit : root.gutter
                right: headerActions.left
                rightMargin: 14 * root.unit
                verticalCenter: parent.verticalCenter
            }
            text: root.screen === "shelf" ? "PINK BOOK  /  READER"
                  : root.screen === "chapters" ? root.book.title : root.chapter.title
            font.family: root.jpFont
            font.bold: true
            font.pixelSize: (root.screen === "shelf" ? 17 : 20) * root.unit
            color: root.ink
            elide: Text.ElideRight
        }
        Row {
            id: headerActions
            spacing: 9 * root.unit
            anchors { right: parent.right; rightMargin: root.gutter; verticalCenter: parent.verticalCenter }
            ReaderButton {
                unit: root.unit; label: "Aa"
                Accessible.name: "Reading settings"
                visible: root.screen === "read"
                marked: root.showSettings
                onClicked: root.showSettings = !root.showSettings
            }
            ReaderButton {
                unit: root.unit; label: "Exit"
                onClicked: root.close()
            }
        }
    }

    Flickable {
        id: shelf
        visible: root.screen === "shelf"
        anchors { top: header.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: width
        contentHeight: shelfColumn.implicitHeight + 75 * root.unit
        Column {
            id: shelfColumn
            width: parent.width - 2 * root.gutter
            x: root.gutter
            y: 34 * root.unit
            spacing: 15 * root.unit
            Text {
                text: "YOUR LIBRARY"
                color: root.accent
                font.bold: true
                font.letterSpacing: 1.8 * root.unit
                font.pixelSize: 13 * root.unit
            }
            Text {
                text: "Bookshelf"
                color: root.ink
                font.bold: true
                font.pixelSize: 42 * root.unit
            }
            Text {
                width: parent.width
                text: "Read offline. Tap Japanese words or grammar as you go."
                wrapMode: Text.WordWrap
                color: root.muted
                font.pixelSize: 17 * root.unit
            }
            Column {
                width: parent.width
                visible: root.lastBook.length > 0 && root.lastChapter.length > 0
                spacing: 6 * root.unit
                ReaderButton {
                    unit: root.unit
                    label: "Continue reading  ›"
                    marked: true
                    onClicked: root.continueReading()
                }
                Text {
                    width: parent.width
                    text: root.continueCaption()
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.family: root.jpFont
                    font.pixelSize: 16 * root.unit
                    color: root.muted
                }
            }
            Repeater {
                model: root.books
                delegate: Rectangle {
                    id: bookCard
                    required property var modelData
                    width: shelfColumn.width
                    height: Math.max(170 * root.unit, bookLabels.implicitHeight + 44 * root.unit)
                    color: bookTap.pressed ? root.panel : root.paper
                    border.color: root.line
                    radius: 8 * root.unit
                    Image {
                        anchors { left: parent.left; leftMargin: 18 * root.unit; verticalCenter: parent.verticalCenter }
                        width: 98 * root.unit
                        height: 132 * root.unit
                        source: bookCard.modelData.cover ? "qrc:/content/" + bookCard.modelData.cover : ""
                        fillMode: Image.PreserveAspectFit
                        sourceSize.width: 216
                    }
                    Column {
                        id: bookLabels
                        anchors {
                            left: parent.left; leftMargin: (bookCard.modelData.cover ? 132 : 22) * root.unit
                            right: parent.right; rightMargin: 22 * root.unit
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 7 * root.unit
                        Text {
                            text: bookCard.modelData.title
                            textFormat: Text.PlainText
                            width: parent.width; wrapMode: Text.Wrap
                            font.family: root.jpFont
                            color: root.ink; font.bold: true; font.pixelSize: 29 * root.unit
                        }
                        Text {
                            text: bookCard.modelData.subtitle || ""
                            textFormat: Text.PlainText
                            width: parent.width; wrapMode: Text.Wrap
                            color: root.muted; font.pixelSize: 17 * root.unit
                        }
                        Text {
                            text: root.bookProgress(bookCard.modelData)
                            width: parent.width
                            elide: Text.ElideRight
                            color: root.accent; font.bold: true; font.pixelSize: 14 * root.unit
                        }
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.title
                    Accessible.onPressAction: root.openBook(modelData)
                    MouseArea { id: bookTap; anchors.fill: parent; onClicked: root.openBook(bookCard.modelData) }
                }
            }
            Text {
                visible: !root.books.length
                text: "No books were bundled. Rebuild with the content exporter."
                color: root.accent
                width: parent.width; wrapMode: Text.Wrap
                font.pixelSize: 16 * root.unit
            }
        }
    }

    ListView {
        id: chapterList
        visible: root.screen === "chapters"
        anchors { top: header.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.book ? root.book.chapters : []
        spacing: 0
        header: Column {
            width: chapterList.width - 2 * root.gutter
            x: root.gutter
            topPadding: 27 * root.unit
            bottomPadding: 21 * root.unit
            spacing: 10 * root.unit
            ReaderButton {
                readonly property var savedChapter: root.resumeChapter(root.book)
                visible: savedChapter !== null
                unit: root.unit
                marked: true
                label: "Resume this book  ›"
                onClicked: root.openChapter(root.book, savedChapter)
            }
            Text {
                text: "CHAPTERS"
                color: root.accent
                font.bold: true; font.letterSpacing: 1.8 * root.unit; font.pixelSize: 13 * root.unit
            }
            Text {
                width: parent.width
                visible: !!text
                text: root.book ? root.book.synopsis || "" : ""
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: root.muted
                font.family: root.jpFont; font.pixelSize: 16 * root.unit
            }
        }
        delegate: Item {
            id: chapterRow
            required property var modelData
            required property int index
            width: chapterList.width
            height: Math.max(73 * root.unit, chapterLabels.implicitHeight + 22 * root.unit)
            Rectangle {
                anchors.fill: parent
                color: chapterTap.pressed ? root.panel : root.paper
            }
            Rectangle {
                x: root.gutter; width: parent.width - 2 * root.gutter
                height: 1; color: root.line
            }
            Text {
                x: root.gutter; anchors.verticalCenter: parent.verticalCenter
                text: String(chapterRow.index + 1).padStart(2, "0")
                color: root.accent; font.bold: true; font.pixelSize: 15 * root.unit
            }
            Column {
                id: chapterLabels
                x: root.gutter + 44 * root.unit
                width: parent.width - 2 * root.gutter - 72 * root.unit
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3 * root.unit
                Text {
                    text: chapterRow.modelData.title
                    width: parent.width; wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    font.family: root.jpFont
                    font.bold: true; font.pixelSize: 21 * root.unit; color: root.ink
                }
                Text {
                    text: chapterRow.modelData.subtitle || ""
                    visible: !!text
                    width: parent.width; wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    color: root.muted; font.pixelSize: 14 * root.unit
                }
            }
            Text {
                anchors { right: parent.right; rightMargin: root.gutter; verticalCenter: parent.verticalCenter }
                text: "›"; color: root.ink; font.pixelSize: 25 * root.unit
            }
            Accessible.role: Accessible.Button
            Accessible.name: modelData.title
            Accessible.onPressAction: root.openChapter(root.book, modelData)
            MouseArea {
                id: chapterTap
                anchors.fill: parent
                onClicked: root.openChapter(root.book, chapterRow.modelData)
            }
        }
    }

    ListView {
        id: pages
        visible: root.screen === "read"
        anchors { top: header.bottom; bottom: footer.top; left: parent.left; right: parent.right }
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: !root.lookup && !root.showSettings
        pixelAligned: true
        model: root.displayedRows
        spacing: 0
        reuseItems: true
        cacheBuffer: 240 * root.unit
        onMovementEnded: root.rememberPosition()
        onContentYChanged: {
            if (root.screen === "read" && !root.restoring && !moving)
                positionTimer.restart()
        }
        header: Item { height: 16 * root.unit; width: 1 }
        footer: Item { height: 24 * root.unit; width: 1 }
        DragHandler {
            enabled: root.viewMode === "paged" && !root.lookup && !root.showSettings
            target: null
            xAxis.enabled: true
            yAxis.enabled: false
            property real swipeDistance: 0
            onActiveTranslationChanged: if (active) swipeDistance = activeTranslation.x
            onActiveChanged: {
                if (!active) {
                    const distance = swipeDistance
                    swipeDistance = 0
                    if (Math.abs(distance) >= Math.max(58 * root.unit, pages.width * 0.13))
                        root.page(distance < 0 ? 1 : -1)
                }
            }
        }
        delegate: Item {
            id: passage
            required property int index
            readonly property var location: root.rowLocation(index)
            readonly property var modelData: root.rowEntry(location)
            width: pages.width
            height: passageColumn.implicitHeight + 10 * root.unit
            Column {
                id: passageColumn
                width: parent.width - 2 * root.gutter
                x: root.gutter
                spacing: 4 * root.unit
                Text {
                    visible: root.viewMode === "continuous" && passage.location !== null && passage.location.line === 0
                    text: visible ? passage.location.chapter.subtitle + "  /  " + passage.location.chapter.title : ""
                    topPadding: 14 * root.unit
                    bottomPadding: 8 * root.unit
                    width: parent.width; wrapMode: Text.Wrap
                    color: root.accent; font.bold: true
                    font.family: root.jpFont; font.pixelSize: 19 * root.unit
                    textFormat: Text.PlainText
                }
                Item {
                    visible: !!passage.modelData.sceneBreak && passage.index > 0
                    width: parent.width
                    height: 34 * root.unit
                    Rectangle {
                        anchors.centerIn: parent
                        width: 80 * root.unit; height: 1
                        color: root.line
                    }
                }
                Text {
                    text: passage.modelData.speaker || ""
                    visible: !!text
                    width: parent.width
                    color: root.accent
                    font.family: root.jpFont; font.bold: true
                    font.pixelSize: 15 * root.unit
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                }
                Flow {
                    id: japaneseLine
                    width: parent.width
                    spacing: 0
                    Repeater {
                        model: passage.modelData.parts
                        delegate: Item {
                            id: token
                            required property var modelData
                            readonly property bool tappable: modelData.kind !== "plain"
                            readonly property bool hasRuby: root.furigana && !!modelData.reading &&
                                /[\u3400-\u4dbf\u4e00-\u9fff々]/.test(modelData.text)
                            width: Math.min(japaneseLine.width, Math.max(1, surface.implicitWidth,
                                hasRuby ? rubyText.implicitWidth + 2 * root.unit : 0))
                            height: surface.height + (root.furigana ? root.textSize * 0.57 : 0) + 6 * root.unit
                            Accessible.role: Accessible.Button
                            Accessible.ignored: !tappable
                            Accessible.name: modelData.text
                            Accessible.onPressAction: token.open()
                            function open() {
                                if (!tappable) return
                                root.openLookup(token, modelData)
                            }
                            Column {
                                width: parent.width
                                Item {
                                    visible: root.furigana
                                    width: parent.width
                                    height: root.textSize * 0.57
                                    Text {
                                        id: rubyText
                                        anchors.centerIn: parent
                                        width: parent.width
                                        text: token.hasRuby ? token.modelData.reading : ""
                                        textFormat: Text.PlainText
                                        elide: Text.ElideRight
                                        horizontalAlignment: Text.AlignHCenter
                                        font.family: root.jpFont
                                        font.pixelSize: root.textSize * 0.46
                                        color: root.muted
                                    }
                                }
                                Text {
                                    id: surface
                                    width: parent.width
                                    text: token.modelData.text
                                    textFormat: Text.PlainText
                                    wrapMode: Text.WrapAnywhere
                                    horizontalAlignment: Text.AlignHCenter
                                    font.family: root.jpFont
                                    font.pixelSize: root.textSize
                                    font.underline: token.modelData.kind === "grammar"
                                    color: hit.pressed || token.modelData.kind === "grammar" ? root.accent : root.ink
                                }
                            }
                            MouseArea {
                                id: hit
                                enabled: token.tappable
                                anchors.fill: parent
                                onClicked: token.open()
                            }
                        }
                    }
                }
                Text {
                    text: passage.modelData.hiragana || ""
                    visible: root.kana && !!text
                    width: parent.width; wrapMode: Text.Wrap; textFormat: Text.PlainText
                    color: root.muted
                    font.family: root.jpFont; font.pixelSize: root.textSize * 0.62
                }
                Text {
                    text: passage.modelData.translation || ""
                    visible: root.translations && !!text
                    width: parent.width; wrapMode: Text.Wrap; textFormat: Text.PlainText
                    color: root.muted
                    font.family: root.jpFont; font.pixelSize: root.textSize * 0.62
                }
            }
        }
    }

    Text {
        anchors.centerIn: pages
        visible: root.screen === "read" && !root.displayedRows
        text: "This chapter could not be loaded."
        color: root.accent
        font.pixelSize: 18 * root.unit
    }

    Rectangle {
        id: footer
        visible: root.screen === "read"
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
        height: 69 * root.unit
        color: root.panel
        Rectangle { width: parent.width; height: 1; color: root.line }
        ReaderButton {
            id: prevButton
            anchors { left: parent.left; leftMargin: root.gutter; verticalCenter: parent.verticalCenter }
            unit: root.unit; label: "‹ Prev"
            enabled: root.canMove(-1)
            onClicked: root.page(-1)
        }
        ReaderButton {
            id: nextButton
            anchors { right: parent.right; rightMargin: root.gutter; verticalCenter: parent.verticalCenter }
            unit: root.unit; label: "Next ›"
            enabled: root.canMove(1)
            onClicked: root.page(1)
        }
        Row {
            anchors.centerIn: parent
            spacing: 10 * root.unit
            ReaderButton {
                unit: root.unit; label: root.bookmark === root.position ? "Marked" : "Mark"
                marked: root.bookmark === root.position && root.bookmark >= 0
                enabled: root.displayedRows > 0
                onClicked: root.toggleBookmark()
            }
            ReaderButton {
                unit: root.unit; label: "Go to mark"
                enabled: root.bookmark >= 0
                onClicked: root.gotoBookmark()
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.displayedRows > 0
                text: root.viewMode === "paged" ? (root.currentPage + 1) + " / " + root.pageCount
                                                 : Math.max(0, root.positionPercent) + "%"
                color: root.muted
                font.pixelSize: 15 * root.unit
            }
        }
    }

    Item {
        visible: root.showSettings
        anchors.fill: parent
        z: 10
        MouseArea { anchors.fill: parent; onClicked: root.showSettings = false }
        Rectangle {
            anchors { top: parent.top; topMargin: header.height + 8 * root.unit; right: parent.right; rightMargin: root.gutter }
            width: Math.min(parent.width - 2 * root.gutter, 420 * root.unit)
            height: options.implicitHeight + 40 * root.unit
            radius: 8 * root.unit
            color: root.paper; border.color: root.ink; border.width: 2
            MouseArea { anchors.fill: parent }
            Column {
                id: options
                anchors { left: parent.left; right: parent.right; margins: 20 * root.unit; verticalCenter: parent.verticalCenter }
                spacing: 12 * root.unit
                Text { text: "Reading settings"; color: root.ink; font.bold: true; font.pixelSize: 22 * root.unit }
                Flow {
                    width: parent.width
                    spacing: 7 * root.unit
                    ReaderButton {
                        unit: root.unit; label: "Furigana"; marked: root.furigana
                        onClicked: root.updatePreference("furigana", !root.furigana)
                    }
                    ReaderButton {
                        unit: root.unit; label: "Kana line"; marked: root.kana
                        onClicked: root.updatePreference("kana", !root.kana)
                    }
                    ReaderButton {
                        unit: root.unit; label: "English"; marked: root.translations
                        onClicked: root.updatePreference("translations", !root.translations)
                    }
                }
                Row {
                    spacing: 8 * root.unit
                    ReaderButton {
                        unit: root.unit; label: "Pages"; marked: root.viewMode === "paged"
                        onClicked: root.changeMode("paged")
                    }
                    ReaderButton {
                        unit: root.unit; label: "Scroll"; marked: root.viewMode === "continuous"
                        onClicked: root.changeMode("continuous")
                    }
                }
                Row {
                    spacing: 8 * root.unit
                    ReaderButton {
                        unit: root.unit; label: "A−"; enabled: root.sizeStep > 0
                        onClicked: root.updatePreference("sizeStep", root.sizeStep - 1)
                    }
                    ReaderButton {
                        unit: root.unit; label: "A+"; enabled: root.sizeStep < 5
                        onClicked: root.updatePreference("sizeStep", root.sizeStep + 1)
                    }
                    ReaderButton { unit: root.unit; label: "Done"; onClicked: root.showSettings = false }
                }
            }
        }
    }

    Item {
        id: lookupOverlay
        visible: !!root.lookup
        anchors.fill: parent
        z: 15
        // Like the web reader, dismiss without dimming or moving the page.
        MouseArea { anchors.fill: parent; onClicked: root.lookup = null }
        Rectangle {
            id: definition
            objectName: "lookupCard"
            readonly property real inset: 10 * root.unit
            readonly property real gap: 10 * root.unit
            readonly property real padding: 14 * root.unit
            readonly property real anchorTop: root.lookupAnchor.y
            readonly property real anchorBottom: anchorTop + root.lookupAnchor.height
            readonly property real roomAbove: anchorTop - gap - inset
            readonly property real roomBelow: parent.height - inset - anchorBottom - gap
            readonly property real desiredHeight: definitionHeader.height + lookupBody.contentHeight + 2 * padding
            readonly property bool below: desiredHeight <= roomBelow || roomBelow >= roomAbove
            readonly property real sideRoom: below ? roomBelow : roomAbove
            readonly property real viewportHeight: Math.max(0, parent.height - 2 * inset)
            readonly property real minimumHeight: definitionHeader.height + 2 * padding + 30 * root.unit
            readonly property real preferredY: below ? anchorBottom + gap : anchorTop - gap - height

            width: Math.max(0, Math.min(340 * root.unit, parent.width - 2 * inset))
            // Normally the note fits on one side. On very short windows, allow
            // it to overlap the anchor so the close button stays reachable.
            height: Math.min(desiredHeight, viewportHeight, sideRoom >= minimumHeight ? sideRoom : viewportHeight)
            x: Math.max(inset, Math.min(parent.width - inset - width,
                        root.lookupAnchor.x + root.lookupAnchor.width / 2 - width / 2))
            y: Math.max(inset, Math.min(parent.height - inset - height, preferredY))
            radius: 8 * root.unit
            color: root.paper
            border.color: root.line
            border.width: 1
            MouseArea { anchors.fill: parent }
            Item {
                id: definitionHeader
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: definition.padding }
                height: 36 * root.unit
                Text {
                    anchors { left: parent.left; right: closeLookup.left; rightMargin: 6 * root.unit; verticalCenter: parent.verticalCenter }
                    text: root.lookup && root.lookup.kind === "grammar" ? "GRAMMAR POINT" : "WORD LOOKUP"
                    color: root.accent
                    elide: Text.ElideRight
                    font.bold: true; font.letterSpacing: 1.0 * root.unit; font.pixelSize: 12 * root.unit
                }
                ReaderButton {
                    id: closeLookup
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    unit: root.unit; label: "Close"
                    onClicked: root.lookup = null
                }
            }
            Flickable {
                id: lookupBody
                objectName: "lookupBody"
                anchors {
                    top: definitionHeader.bottom; left: parent.left; right: parent.right; bottom: parent.bottom
                    leftMargin: definition.padding; rightMargin: definition.padding; bottomMargin: definition.padding
                }
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentWidth: width
                contentHeight: lookupText.implicitHeight
                Column {
                    id: lookupText
                    width: parent.width
                    spacing: 7 * root.unit
                    Repeater {
                        model: root.lookup ? [
                            root.lookup.text,
                            root.lookup.reading === root.lookup.text ? "" : root.lookup.reading,
                            root.lookup.meaning, root.lookup.explanation
                        ] : []
                        delegate: Text {
                            required property var modelData
                            required property int index
                            visible: !!modelData
                            text: modelData || ""
                            width: lookupText.width
                            wrapMode: Text.Wrap
                            textFormat: Text.PlainText
                            font.family: root.jpFont
                            font.pixelSize: (index === 0 ? 27 : index === 1 ? 18 : 16) * root.unit
                            font.bold: index === 0 || index === 2
                            color: index === 1 ? root.accent : root.ink
                        }
                    }
                }
            }
        }
    }
}
