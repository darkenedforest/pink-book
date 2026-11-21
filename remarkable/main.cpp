#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QHash>
#include <QJsonDocument>
#include <QQmlApplicationEngine>
#include <QRegularExpression>
#include <QSettings>
#include <memory>
#include <QVariantMap>
#include <QDebug>

class ReaderStore final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList books READ books CONSTANT)
    Q_PROPERTY(QString fontFamily READ fontFamily CONSTANT)
public:
    explicit ReaderStore(const QString &testSettingsFile = {})
        : m_settings(testSettingsFile.isEmpty()
              ? std::make_unique<QSettings>()
              : std::make_unique<QSettings>(testSettingsFile, QSettings::IniFormat))
    {}

    QVariantList books() const {
        return load(QStringLiteral("catalog.json")).toMap().value(QStringLiteral("books")).toList();
    }

    QString fontFamily() const {
        for (const QString &path : {QStringLiteral(":/content/Japanese.ttf"),
             QDir(QCoreApplication::applicationDirPath()).filePath(QStringLiteral("NotoSansJP-Regular.ttf"))}) {
            if (!QFile::exists(path))
                continue;
            const QStringList families = QFontDatabase::applicationFontFamilies(QFontDatabase::addApplicationFont(path));
            if (!families.isEmpty())
                return families.constFirst();
            qWarning() << "Could not load Japanese reading font:" << path;
        }
        const auto installed = QFontDatabase::families(QFontDatabase::Japanese);
        for (const QString &preferred : {QStringLiteral("Noto Sans CJK JP"), QStringLiteral("Noto Sans JP"),
                                         QStringLiteral("Yu Gothic UI"), QStringLiteral("Hiragino Sans")}) {
            if (installed.contains(preferred))
                return preferred;
        }
        if (installed.isEmpty())
            qWarning() << "No Japanese font found. See the reader README.";
        return installed.isEmpty() ? QFontDatabase::systemFont(QFontDatabase::GeneralFont).family()
                                   : installed.constFirst();
    }

    Q_INVOKABLE QVariantList chapter(const QString &file) const {
        static const QRegularExpression safeFile(QStringLiteral("^[a-zA-Z0-9_-]+\\.json$"));
        if (!safeFile.match(file).hasMatch())
            return {};
        if (m_chapters.contains(file)) {
            m_recent.removeAll(file);
        } else {
            auto parsed = load(file).toList();
            if (parsed.isEmpty())
                return {};
            if (m_recent.size() >= 3) {
                const QString evicted = m_recent.takeFirst();
                m_chapters.remove(evicted);
                m_pageLimits.remove(evicted);
            }
            m_chapters.insert(file, std::move(parsed));
        }
        m_recent.append(file);
        return m_chapters.value(file);
    }

    Q_INVOKABLE QVariantMap sentence(const QString &file, int index) const {
        const auto items = chapter(file);
        return index >= 0 && index < items.size() ? items.at(index).toMap() : QVariantMap{};
    }

    Q_INVOKABLE QVariantList pageBoundaries(const QString &file) const {
        const auto items = chapter(file);
        if (m_pageLimits.contains(file))
            return m_pageLimits.value(file);
        QVariantList limits{0};
        constexpr int partsPerPage = 52;
        int parts = 0;
        for (qsizetype i = 0; i < items.size(); ++i) {
            const int cost = qMax(1, int(items.at(i).toMap().value(QStringLiteral("parts")).toList().size()));
            if (parts && parts + cost > partsPerPage) {
                limits.append(int(i));
                parts = 0;
            }
            parts += cost;
        }
        if (!items.isEmpty()) {
            limits.append(int(items.size()));
            m_pageLimits.insert(file, limits);
        }
        return limits;
    }

    Q_INVOKABLE QVariant value(const QString &key, const QVariant &fallback) const {
        const QVariant stored = m_settings->value(key, fallback);
        return fallback.typeId() == QMetaType::Bool ? QVariant(stored.toBool()) : stored;
    }

    Q_INVOKABLE void setValue(const QString &key, const QVariant &value) {
        if (save(key, value))
            m_settings->sync();
    }

    Q_INVOKABLE void remember(const QString &book, const QString &chapter, int index,
                              double offset, int percent) {
        if (index < 0)
            return;
        const QString prefix = QStringLiteral("reading/") + book;
        const QString key = prefix + QLatin1Char('/') + chapter;
        bool changed = save(key + QStringLiteral("/offset"), qMax(0, qRound(offset)));
        changed |= save(key + QStringLiteral("/index"), index);
        changed |= save(key + QStringLiteral("/percent"), percent);
        changed |= save(prefix + QStringLiteral("/current"), chapter);
        changed |= save(QStringLiteral("lastBook"), book);
        changed |= save(QStringLiteral("lastChapter"), chapter);
        // Flush the checkpoint when scrolling settles, not just on clean exit.
        if (changed)
            m_settings->sync();
    }

    Q_INVOKABLE void sync() { m_settings->sync(); }

private:
    std::unique_ptr<QSettings> m_settings;
    mutable QHash<QString, QVariantList> m_chapters;
    mutable QHash<QString, QVariantList> m_pageLimits;
    mutable QStringList m_recent;

    bool save(const QString &key, const QVariant &value) {
        if (m_settings->value(key) == value)
            return false;
        m_settings->setValue(key, value);
        return true;
    }

    static QVariant load(const QString &fileName) {
        QFile file(QStringLiteral(":/content/") + fileName);
        if (!file.open(QIODevice::ReadOnly)) {
            qWarning() << "Could not open book content:" << fileName << file.errorString();
            return {};
        }
        QJsonParseError error{};
        const auto doc = QJsonDocument::fromJson(file.readAll(), &error);
        if (error.error != QJsonParseError::NoError)
            qWarning() << "Invalid book content:" << fileName << error.errorString();
        return doc.toVariant();
    }
};

int main(int argc, char **argv) {
    QGuiApplication app(argc, argv);
    QCoreApplication::setOrganizationName(QStringLiteral("PinkBook"));
    QCoreApplication::setApplicationName(QStringLiteral("Pink Book Reader"));

    const auto arguments = app.arguments();
    if (arguments.size() == 4 && arguments[1] == QStringLiteral("--check-progress")) {
        // CTest supplies an isolated file in its build tree. Exercise the
        // production persistence code in two separate executable launches.
        ReaderStore testStore(arguments[3]);
        if (arguments[2] == QStringLiteral("write")) {
            testStore.remember(QStringLiteral("kirihama"), QStringLiteral("ep02"), 104, 17, 22);
            testStore.remember(QStringLiteral("last-train"), QStringLiteral("ep08"), 87, 11, 16);
            testStore.setValue(QStringLiteral("translations"), true);
            return 0;
        }
        if (arguments[2] == QStringLiteral("read")) {
            const auto matches = [&](const char *key, const QVariant &expected) {
                const auto actual = testStore.value(QString::fromUtf8(key), QVariant{});
                return expected.typeId() == QMetaType::Int ? actual.toInt() == expected.toInt()
                                                          : actual.toString() == expected.toString();
            };
            return matches("lastBook", QStringLiteral("last-train"))
                    && matches("lastChapter", QStringLiteral("ep08"))
                    && matches("reading/last-train/current", QStringLiteral("ep08"))
                    && matches("reading/last-train/ep08/index", 87)
                    && matches("reading/last-train/ep08/offset", 11)
                    && matches("reading/last-train/ep08/percent", 16)
                    && matches("reading/kirihama/current", QStringLiteral("ep02"))
                    && matches("reading/kirihama/ep02/index", 104)
                    && testStore.value(QStringLiteral("translations"), false).toBool()
                   ? 0 : 1;
        }
        return 2;
    }

    ReaderStore store;
    if (arguments.contains(QStringLiteral("--check-content"))) {
        const auto books = store.books();
        if (books.isEmpty())
            return 1;
        for (const auto &book : books) {
            const auto chapters = book.toMap().value(QStringLiteral("chapters")).toList();
            if (chapters.isEmpty())
                return 1;
            for (const auto &chapter : chapters) {
                const auto entry = chapter.toMap();
                const QString file = entry.value(QStringLiteral("file")).toString();
                const int count = entry.value(QStringLiteral("sentenceCount")).toInt();
                const auto limits = store.pageBoundaries(file);
                if (count <= 0 || store.chapter(file).size() != count || limits.first().toInt() != 0
                    || limits.last().toInt() != count)
                    return 1;
                for (qsizetype i = 1; i < limits.size(); ++i)
                    if (limits[i].toInt() <= limits[i - 1].toInt())
                        return 1;
            }
        }
        qInfo() << "Verified all embedded books and chapters.";
        return 0;
    }

    QQmlApplicationEngine engine;
    engine.setInitialProperties({
        {QStringLiteral("store"), QVariant::fromValue(&store)},
        {QStringLiteral("paperDisplay"), QGuiApplication::platformName() == QStringLiteral("epaper")}
    });
    engine.load(QUrl(QStringLiteral("qrc:/Main.qml")));
    if (engine.rootObjects().isEmpty())
        return 1;
    return app.exec();
}

#include "main.moc"
