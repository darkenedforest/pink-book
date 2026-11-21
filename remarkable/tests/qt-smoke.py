"""Optional desktop click-through test. Run with Node and PySide6 Essentials installed."""
import json
import os
import subprocess
import sys
from pathlib import Path
from tempfile import TemporaryDirectory
from xml.sax.saxutils import escape, quoteattr

import PySide6
from PySide6.QtCore import Property, Slot, QObject, QUrl, Qt, QPoint, QPointF, QRectF, QResource, qInstallMessageHandler
from PySide6.QtGui import QGuiApplication, QWheelEvent
from PySide6.QtQml import QQmlApplicationEngine, QJSValue
from PySide6.QtQuick import QQuickItem, QQuickWindow
from PySide6.QtTest import QTest

repo = Path(__file__).resolve().parents[2]
workspace = TemporaryDirectory(prefix="pink-book-qt-smoke-")
workspace_path = Path(workspace.name)
data = workspace_path / "data"
resource = workspace_path / "book.rcc"
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
(workspace_path / "cache").mkdir()
os.environ["XDG_CACHE_HOME"] = str(workspace_path / "cache")
subprocess.run(["node", str(repo / "remarkable/tools/export-content.mjs"), str(repo), str(data)],
               check=True)
qt_root = Path(PySide6.__file__).resolve().parent
rcc = next((candidate for candidate in [
    qt_root / "Qt/libexec/rcc", qt_root / "Qt/bin/rcc",
    qt_root / "rcc.exe", qt_root / "Qt/libexec/rcc.exe",
] if candidate.is_file()), None)
if not rcc:
    sys.exit("Could not find the Qt rcc resource compiler in the PySide6 package.")
manifest = workspace_path / "cover.qrc"
covers = sorted((repo / "bookshelf").glob("*-cover.png"))
manifest.write_text(
    '<RCC><qresource prefix="/content">' +
    "".join(f'<file alias={quoteattr(path.name)}>{escape(str(path))}</file>' for path in covers) +
    "</qresource></RCC>",
    encoding="utf-8",
)
subprocess.run([str(rcc), "--binary", "-o", str(resource), str(manifest)], check=True)
messages = []
checkpoint = workspace_path / "settings.json"


def capture(_mode, _ctx, message):
    messages.append(message)
    print(message, file=sys.stderr)


qInstallMessageHandler(capture)


class Store(QObject):
    def __init__(self):
        super().__init__()
        self.state = json.loads(checkpoint.read_text(encoding="utf-8")) if checkpoint.exists() else {}
        self.synced = False
        self.catalog = json.loads((data / "catalog.json").read_text(encoding="utf-8"))
        self.chapters = {}

    @Property("QVariantList", constant=True)
    def books(self):
        return self.catalog["books"]

    @Property(str, constant=True)
    def fontFamily(self):
        return "Noto Sans CJK JP"

    def get_chapter(self, file):
        if file not in self.chapters:
            self.chapters[file] = json.loads((data / file).read_text(encoding="utf-8"))
        return self.chapters[file]

    @Slot(str, int, result="QVariantMap")
    def sentence(self, file, index):
        chapter = self.get_chapter(file)
        return chapter[index] if 0 <= index < len(chapter) else {}

    @Slot(str, result="QVariantList")
    def pageBoundaries(self, file):
        chapter = self.get_chapter(file)
        boundaries, parts = [0], 0
        for index, sentence in enumerate(chapter):
            size = max(1, len(sentence["parts"]))
            if parts and parts + size > 52:
                boundaries.append(index)
                parts = 0
            parts += size
        return [*boundaries, len(chapter)] if chapter else boundaries

    @Slot(str, "QVariant", result="QVariant")
    def value(self, key, fallback):
        return self.state.get(key, fallback)

    def persist(self):
        checkpoint.write_text(json.dumps(self.state), encoding="utf-8")

    @Slot(str, "QVariant")
    def setValue(self, key, value):
        self.state[key] = value
        self.persist()

    @Slot(str, str, int, float, int)
    def remember(self, book, chapter, index, offset, percent):
        self.state.update({
            "lastBook": book,
            "lastChapter": chapter,
            f"reading/{book}/current": chapter,
            f"reading/{book}/{chapter}/index": index,
            f"reading/{book}/{chapter}/offset": offset,
            f"reading/{book}/{chapter}/percent": percent,
        })
        self.persist()

    @Slot()
    def sync(self):
        self.synced = True
        self.persist()


app = QGuiApplication([])
app.setQuitOnLastWindowClosed(False)
assert QResource.registerResource(str(resource))


def start():
    store = Store()
    engine = QQmlApplicationEngine()
    engine.setInitialProperties({"store": store})
    engine.load(QUrl.fromLocalFile(str(repo / "remarkable/Main.qml")))
    assert engine.rootObjects(), "No QML root"
    win = engine.rootObjects()[0]
    assert isinstance(win, QQuickWindow)
    QTest.qWait(180)
    return store, engine, win


def items(item):
    for child in item.childItems():
        yield child
        yield from items(child)


def label(window, name):
    matches = []
    for item in items(window.contentItem()):
        if item.isVisible() and item.isEnabled() and item.property("text") == name:
            point = item.mapToScene(QPointF(item.width() / 2, item.height() / 2))
            if 0 < point.x() < window.width() and 0 < point.y() < window.height():
                matches.append(point.toPoint())
    assert matches, "Missing visible label: " + name
    # A book and one of its chapters can have the same title in the same view.
    return matches[-1]


def tap(name):
    QTest.mouseClick(win, Qt.LeftButton, Qt.NoModifier, label(win, name))
    QTest.qWait(180)


def tap_point(x, y):
    QTest.mouseClick(win, Qt.LeftButton, Qt.NoModifier, QPoint(round(x), round(y)))
    QTest.qWait(180)


def popup_item(name):
    item = win.findChild(QQuickItem, name)
    assert item is not None and item.isVisible(), name
    return item


def popup_rect():
    card = popup_item("lookupCard")
    return QRectF(card.x(), card.y(), card.width(), card.height())


def assert_inside_window(rect):
    inset = 10 * prop("unit")
    tolerance = 1
    assert rect.left() >= inset - tolerance
    assert rect.top() >= inset - tolerance
    assert rect.right() <= win.width() - inset + tolerance
    assert rect.bottom() <= win.height() - inset + tolerance


def prop(name):
    value = win.property(name)
    return value.toVariant() if isinstance(value, QJSValue) else value


def navigate_to_shelf():
    tap("‹ Chapters")
    tap("‹ Shelf")
    assert prop("screen") == "shelf"


def set_mode(label):
    tap("Aa")
    assert prop("showSettings")
    tap(label)
    if prop("showSettings"):
        tap("Done")


def swipe(from_x, to_x, y=570):
    QTest.mousePress(win, Qt.LeftButton, Qt.NoModifier, QPoint(from_x, y))
    for step in range(1, 9):
        x = from_x + (to_x - from_x) * step // 8
        QTest.mouseMove(win, QPoint(x, y), delay=20)
    QTest.mouseRelease(win, Qt.LeftButton, Qt.NoModifier, QPoint(to_x, y))
    QTest.qWait(220)


def wheel_down(steps=1):
    center = QPointF(400, 570)
    for _ in range(steps):
        app.sendEvent(win, QWheelEvent(center, center, QPoint(0, -300), QPoint(0, -480),
                                      Qt.NoButton, Qt.NoModifier, Qt.ScrollUpdate, False))
        QTest.qWait(150)
    QTest.qWait(330)


store, engine, win = start()
assert prop("screen") == "shelf"
assert [book["id"] for book in store.books] == ["kirihama", "shadow-shop", "last-train"]
tap("霧浜の秘密")
assert prop("screen") == "chapters"
tap("霧の中の民宿")
assert prop("screen") == "read"
assert prop("viewMode") == "paged"
chapter = prop("chapter")
assert chapter["sentenceCount"] == len(store.get_chapter(chapter["file"]))
assert prop("currentPage") == 0
first_page = prop("pageStart"), prop("pageEnd")
assert 0 == first_page[0] < first_page[1] < chapter["sentenceCount"]

lookup_state = (prop("currentPage"), prop("position"), prop("positionOffset"))
token_click = label(win, "朝")
tap_point(token_click.x(), token_click.y())
assert prop("lookup")["meaning"] == "morning"
assert label(win, "あさ")
anchor = prop("lookupAnchor")
card = popup_rect()
assert anchor.contains(QPointF(token_click)), (anchor, token_click)
assert card.top() > anchor.bottom(), (card, anchor)
assert abs(card.left() - 10 * prop("unit")) < 1, card
assert card.width() <= 340 * prop("unit")
assert_inside_window(card)
tap_point(card.right() - 5, card.bottom() - 5)
assert prop("lookup"), "Tapping inside the card must not dismiss it"
tap("Close")
assert not prop("lookup")
tap("ながら")
assert prop("lookup")["kind"] == "grammar"
assert "indicating a simultaneous action" in prop("lookup")["explanation"]
assert label(win, "GRAMMAR POINT")

# Control geometry for the viewport-edge case; the real click path above
# already checked that the anchor is captured from a displayed word.
assert win.setProperty("lookupAnchor", QRectF(win.width() - 18, win.height() - 44, 14, 36))
QTest.qWait(100)
anchor = prop("lookupAnchor")
card = popup_rect()
assert card.bottom() < anchor.top(), (card, anchor)
assert abs(card.right() - (win.width() - 10 * prop("unit"))) < 1, card
assert_inside_window(card)

entry = dict(prop("lookup"))
entry["explanation"] = (entry["explanation"] + " ") * 30
assert win.setProperty("lookup", engine.toScriptValue(entry))
QTest.qWait(100)
body = popup_item("lookupBody")
assert body.property("contentHeight") > body.height(), "Long grammar notes should scroll inside the card"
assert_inside_window(popup_rect())
center = body.mapToScene(QPointF(body.width() / 2, body.height() / 2))
app.sendEvent(win, QWheelEvent(center, center, QPoint(0, -300), QPoint(0, -480),
                                Qt.NoButton, Qt.NoModifier, Qt.ScrollUpdate, False))
QTest.qWait(200)
assert body.property("contentY") > 0, "Wheel input should scroll the note, not the reader"
del body

tap_point(3, 3)
assert not prop("lookup"), "Tapping outside should dismiss the note"
assert (prop("currentPage"), prop("position"), prop("positionOffset")) == lookup_state
tap("朝")
assert prop("lookup")["text"] == "朝"
assert popup_item("lookupBody").property("contentY") == 0
QTest.keyClick(win, Qt.Key_Escape)
QTest.qWait(180)
assert not prop("lookup")
assert prop("screen") == "read"
assert (prop("currentPage"), prop("position"), prop("positionOffset")) == lookup_state
tap("Aa")
assert prop("showSettings")
for toggle in ("Furigana", "Kana line", "English", "A+"):
    tap(toggle)
    assert (prop("pageStart"), prop("pageEnd")) == first_page
assert [prop("furigana"), prop("kana"), prop("translations"), prop("sizeStep")] == [False, True, True, 3]
tap("Done")
assert not prop("showSettings")
tap("Mark")
assert prop("bookmark") == 0
tap("Next ›")
assert prop("currentPage") == 1
assert prop("pageStart") == first_page[1]
assert prop("position") >= first_page[1]
swipe(220, 580)
assert prop("currentPage") == 0, "Right drag did not turn to the previous fixed page"
swipe(580, 220)
assert prop("currentPage") == 1, "Left drag did not turn to the next fixed page"
tap("Go to mark")
assert prop("currentPage") == 0
assert prop("position") == 0
navigate_to_shelf()
print("Kirihama anchored word/grammar notes, settings, stable pages, horizontal drag and bookmark passed", flush=True)

# Chapter ids repeat across books. Verify each exposes its own first sentence.
tap("影の店")
tap("真夜中の路地")
assert prop("chapter")["id"] == "ep01"
assert prop("book")["id"] == "shadow-shop"
assert prop("bookmark") == -1
tap("ねえ")
assert prop("lookup")["meaning"] == "hey (attention-getter)"
tap("Close")
navigate_to_shelf()

tap("最終電車")
tap("最終電車")
assert prop("chapter")["id"] == "ep01"
assert prop("book")["id"] == "last-train"
tap("時計")
assert prop("lookup")["meaning"] == "clock"
tap("Close")
set_mode("Scroll")
assert prop("viewMode") == "continuous"
before_scroll = prop("position")
wheel_down(3)
assert prop("position") > before_scroll

# Move the test to a few lines before the boundary, then cross it using the
# ordinary scrolling gesture. Starting there avoids hundreds of wheel events.
js_window = engine.newQObject(win)
chapter = prop("chapter")
near_end = chapter["sentenceCount"] - 4
result = js_window.property("openAt").callWithInstance(js_window, [
    engine.toScriptValue(prop("book")), engine.toScriptValue(chapter), QJSValue(near_end), QJSValue(0)
])
assert not result.isError(), result.toString()
QTest.qWait(330)
assert prop("chapter")["id"] == "ep01"
assert prop("position") >= near_end - 1
for _ in range(5):
    wheel_down()
    if prop("chapter")["id"] == "ep02":
        break
assert prop("chapter")["id"] == "ep02", "Continuous scrolling did not cross the chapter boundary"
assert prop("displayedRows") == sum(c["sentenceCount"] for c in prop("book")["chapters"])
del js_window, result
saved_position = prop("position")
saved_chapter = prop("chapter")["id"]
tap("Exit")
assert not win.isVisible()
assert store.synced
del win, engine, store

# A new engine and mock store read only the checkpoint on disk.
store, engine, win = start()
assert prop("screen") == "shelf"
tap("Continue reading  ›")
assert prop("screen") == "read"
assert prop("viewMode") == "continuous"
assert prop("book")["id"] == "last-train"
assert prop("chapter")["id"] == saved_chapter
assert prop("position") == saved_position
assert prop("translations")
set_mode("Pages")
assert prop("viewMode") == "paged"
assert prop("pageStart") <= saved_position < prop("pageEnd")
tap("Exit")
assert not win.isVisible()
assert store.synced
print("Shadow Shop, Last Train, cross-chapter scroll and restart resume passed", flush=True)
del win, engine, store
assert not messages, messages
QResource.unregisterResource(str(resource))
workspace.cleanup()
