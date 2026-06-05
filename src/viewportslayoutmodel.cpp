#include "viewportslayoutmodel.h"

ViewportsLayoutItem::ViewportsLayoutItem(QObject *parent)
    : QObject(parent)
{
    QMetaMethod changedMethod = QMetaMethod::fromSignal(&ViewportsLayoutItem::changed);
    for (int i = staticMetaObject.methodOffset(); i < staticMetaObject.methodCount(); ++i) {
        QMetaMethod method = staticMetaObject.method(i);
        if (method.methodType() == QMetaMethod::Signal && method != changedMethod) {
            connect(this, method, this, changedMethod);
        }
    }
}

ViewportsLayoutModel::ViewportsLayoutModel(QObject *parent)
    : QAbstractListModel(parent)
    , m_columns(0)
    , m_rows(0)
{
    const QMetaObject* meta = &ViewportsLayoutItem::staticMetaObject;
    for (int i = meta->propertyOffset(); i < meta->propertyCount(); ++i) {
        QMetaProperty property = meta->property(i);
        m_roleNames[Qt::UserRole + i] = property.name();
    }

    connect(this, &ViewportsLayoutModel::dataChanged, this, &ViewportsLayoutModel::changed);

    QMetaMethod changedMethod = QMetaMethod::fromSignal(&ViewportsLayoutModel::changed);
    for (int i = staticMetaObject.methodOffset(); i < staticMetaObject.methodCount(); ++i) {
        QMetaMethod method = staticMetaObject.method(i);
        if (method.methodType() == QMetaMethod::Signal && method != changedMethod) {
            connect(this, method, this, changedMethod);
        }
    }
}

int ViewportsLayoutModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) {
        return 0;
    }

    return m_columns * m_rows;
}

QVariant ViewportsLayoutModel::data(const QModelIndex &index, int role) const
{
    if (!hasIndex(index.row(), index.column())) {
        return {};
    }

    return get(index.row())->property(m_roleNames.value(role));
}

bool ViewportsLayoutModel::setData(const QModelIndex &index, const QVariant &value, int role)
{
    if (!hasIndex(index.row(), index.column())) {
        return false;
    }

    return get(index.row())->setProperty(m_roleNames.value(role), value);
}

ViewportsLayoutItem *ViewportsLayoutModel::set(int index, ViewportsLayoutItem *p)
{
    if (p == get(index)) {
        return p;
    }

    if (index >= 0 && index < m_items.size()) {
        m_items[index] = p;

        QModelIndex modelIndex = QAbstractListModel::index(index, 0);
        emit dataChanged(modelIndex, modelIndex);
    }

    return p;
}

void ViewportsLayoutModel::clear() {
    beginResetModel();
    m_items.clear();
    endResetModel();
}

void ViewportsLayoutModel::resize(int columns, int rows)
{
    int newActiveCount = rows * columns;
    int oldActiveCount = m_columns * m_rows;

    if (rows >= 0 && columns >= 0) {
        m_columns = columns;
        m_rows = rows;

        // Ensure m_items is at least as large as the maximum active size needed
        int maxNeeded = std::max(newActiveCount, m_items.size());
        if (maxNeeded > m_items.size()) {
            m_items.resize(maxNeeded);
        }

        if (newActiveCount > oldActiveCount) {
            beginInsertRows(QModelIndex(), oldActiveCount, newActiveCount - 1);
            normalize();
            endInsertRows();
        } else if (newActiveCount < oldActiveCount) {
            beginRemoveRows(QModelIndex(), newActiveCount, oldActiveCount - 1);
            normalize();
            endRemoveRows();
        } else {
            normalize();
        }
    }
}

void ViewportsLayoutModel::normalize()
{
    int count = m_columns * m_rows;

    // Resize (never shrink, only grow if m_items is smaller than active count)
    if (m_items.size() < count) {
        m_items.resize(count);
        emit sizeChanged(QSize(m_columns, m_rows));
    }

normalize:
    // Mormalize properties
    for (int index = 0; index < m_items.size(); ++index) {
        auto item = get(index);

        if (item == nullptr) {
            QQmlEngine *engine = qmlEngine(this);

            Q_ASSERT(engine != nullptr);

            item = new ViewportsLayoutItem(this);
            QQmlEngine::setContextForObject(item, engine->rootContext());

            connect(item, &ViewportsLayoutItem::changed, this, [=] {
                for (int i = 0; i < m_items.size(); ++i) {
                    if (item == m_items.at(i)) {
                        QModelIndex index = createIndex(i, 0);
                        emit reinterpret_cast<ViewportsLayoutModel *>(this)->dataChanged(index, index);
                    }
                }
            });

            set(index, item);
        } else {
            int span = 1;
            int columnSpan = clamp(item->property("columnSpan").toInt(), 1, m_columns - column(index));
            int rowSpan = clamp(item->property("rowSpan").toInt(), 1, m_rows - row(index));

            if (columnSpan != m_columns || rowSpan != m_rows) {
                span = std::min(rowSpan, columnSpan);
            }

            item->setProperty("columnSpan", span);
            item->setProperty("rowSpan", span);
            item->setProperty("visible", static_cast<int>(ViewportsLayoutItem::Visible::Visible));
            item->setProperty("volume", clamp(item->property("volume").toDouble(), 0.0, 1.0));
        }
    }

    for (int index = 0; index < m_items.size(); ++index) {
        auto item = get(index);

        if (item->property("visible").toInt() == static_cast<int>(ViewportsLayoutItem::Visible::Visible)) {
            int columnSpan = item->property("columnSpan").toInt();
            int rowSpan = item->property("rowSpan").toInt();

            // Iterate hidden elements
            for (int r = 0; r < rowSpan; ++r) {
                for (int c = 0; c < columnSpan; ++c) {
                    int hiddenIndex = dataIndex(column(index) + c, row(index) + r);
                    if (hiddenIndex != index) {
                        auto hiddenItem = get(hiddenIndex);
                        if (hiddenItem->property("visible").toInt() == static_cast<int>(ViewportsLayoutItem::Visible::Visible)) {
                            hiddenItem->setProperty("columnSpan", -c);
                            hiddenItem->setProperty("rowSpan", -r);
                            hiddenItem->setProperty("visible", static_cast<int>(ViewportsLayoutItem::Visible::Hidden));
                        } else {
                            // Span collision
                            item->setProperty("columnSpan", 1);
                            item->setProperty("rowSpan", 1);
                            goto normalize;
                        }
                    }
                }
            }
        }

        emit dataChanged(QModelIndex(), QModelIndex());
    }
}

void ViewportsLayoutModel::fromJSValue(const QVariantMap &model)
{
    QVariant val;

    if (model.contains("isNvr")) {
        setIsNvr(model.value("isNvr").toBool());
    }
    if (model.contains("nvrIp")) {
        setNvrIp(model.value("nvrIp").toString());
    }
    if (model.contains("isNvrPreset")) {
        setIsNvrPreset(model.value("isNvrPreset").toBool());
    }
    if (model.contains("name")) {
        setName(model.value("name").toString());
    }
    if (model.contains("visible")) {
        setVisible(model.value("visible").toBool());
    }

    if (model.contains("size")) {
        val = model.value("size");
        if (val.canConvert(QMetaType::QVariantMap)) {
            int width = val.toMap().value("width").toInt();
            int height = val.toMap().value("height").toInt();
            setSize(QSize(width, height));
        }
    }

    if (model.contains("aspectRatio")) {
        val = model.value("aspectRatio");
        if (val.canConvert(QMetaType::QVariantMap)) {
            int width = val.toMap().value("width").toInt();
            int height = val.toMap().value("height").toInt();
            setAspectRatio(QSize(width, height));
        }
    }

    if (model.contains("items")) {
        val = model.value("items");
    }
    if (val.canConvert(QMetaType::QVariantList)) {
        QVariantList items = val.toList();
        if (items.size() > m_items.size()) {
            m_items.resize(items.size());
        }
        normalize();
        for (int i = 0; i < std::min(m_items.size(), items.size()); ++i) {
            QHashIterator<int, QByteArray> role(m_roleNames);
            while (role.hasNext()) {
                role.next();

                QByteArray roleName = role.value();
                const char *name = roleName.constData();
                QVariantMap item = items.at(i).toMap();
                m_items.at(i)->setProperty(name, item.value(QString::fromUtf8(roleName)));
            }
        }
    }

    normalize();
}

QVariantMap ViewportsLayoutModel::toJSValue() const
{
    QVariantMap model;
    QVariantList items;

    for (int i = 0; i < m_items.size(); ++i) {
        QVariantMap item;
        if (get(i) != nullptr) {
            const QMetaObject* metaObject = get(i)->metaObject();
            for(int j = metaObject->propertyOffset(); j < metaObject->propertyCount(); ++j) {
                const char *name = metaObject->property(j).name();
                int hashKey = m_roleNames.key(name);
                if (hashKey) {
                    item[name] = get(i)->property(name);
                }
            }
            items.append(item);
        }
    }

    model["size"] = size();
    model["aspectRatio"] = m_aspectRatio;
    model["isNvr"] = isNvr();
    model["nvrIp"] = nvrIp();
    model["isNvrPreset"] = isNvrPreset();
    model["name"] = name();
    model["visible"] = visible();
    model["items"] = items;

    return model;
}

void ViewportsLayoutModel::setSize(const QSize &size)
{
    if (size == QSize(m_columns, m_rows)) {
        return;
    }

    resize(size.width(), size.height());

    emit sizeChanged(size);
}
