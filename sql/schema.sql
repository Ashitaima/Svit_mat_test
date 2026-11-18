-- =====================================================================
-- Схема БД для збору аналітичних подій e-commerce (PostgreSQL 14+)
-- =====================================================================

-- ---------------------------------------------------------------------
-- users — зареєстровані користувачі (зазвичай вже є в основній БД магазину)
-- ---------------------------------------------------------------------
CREATE TABLE users (
    id          BIGSERIAL    PRIMARY KEY,
    email       TEXT         NOT NULL UNIQUE,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- sessions — візит користувача. Створюється на першу подію з новим session_id.
-- user_id = NULL, поки користувач анонімний; заповнюється після логіну.
-- ---------------------------------------------------------------------
CREATE TABLE sessions (
    id            UUID         PRIMARY KEY,               -- генерується на клієнті
    user_id       BIGINT       REFERENCES users(id),      -- NULL для анонімів
    started_at    TIMESTAMPTZ  NOT NULL,
    last_seen_at  TIMESTAMPTZ  NOT NULL,
    user_agent    TEXT,
    ip            INET,
    utm_source    TEXT,
    utm_medium    TEXT,
    utm_campaign  TEXT
);
CREATE INDEX idx_sessions_user_id ON sessions (user_id);

-- ---------------------------------------------------------------------
-- orders + order_items — замовлення (джерело правди для грошей)
-- ---------------------------------------------------------------------
CREATE TABLE orders (
    id            BIGSERIAL      PRIMARY KEY,
    user_id       BIGINT         REFERENCES users(id),     -- NULL для гостьового замовлення
    session_id    UUID           REFERENCES sessions(id),  -- у якій сесії оформлено
    status        TEXT           NOT NULL DEFAULT 'created'
                  CHECK (status IN ('created', 'paid', 'payment_failed', 'cancelled', 'refunded')),
    total_amount  NUMERIC(12,2)  NOT NULL CHECK (total_amount >= 0),
    currency      CHAR(3)        NOT NULL,
    created_at    TIMESTAMPTZ    NOT NULL DEFAULT now(),
    paid_at       TIMESTAMPTZ
);
CREATE INDEX idx_orders_user_id    ON orders (user_id);
CREATE INDEX idx_orders_created_at ON orders (created_at);

CREATE TABLE order_items (
    order_id    BIGINT         NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id  BIGINT         NOT NULL,                   -- id з каталогу
    quantity    INT            NOT NULL CHECK (quantity > 0),
    unit_price  NUMERIC(12,2)  NOT NULL CHECK (unit_price >= 0),
    PRIMARY KEY (order_id, product_id)
);

-- ---------------------------------------------------------------------
-- events — сирий append-only лог подій. Найбільша таблиця.
-- Партиціонування по місяцях за occurred_at.
-- ---------------------------------------------------------------------
CREATE TABLE events (
    event_id     UUID         NOT NULL,                  -- генерує клієнт, ключ ідемпотентності
    event_type   TEXT         NOT NULL CHECK (event_type IN (
                     'product_view', 'add_to_cart', 'remove_from_cart',
                     'checkout_started', 'order_created',
                     'payment_succeeded', 'payment_failed')),
    occurred_at  TIMESTAMPTZ  NOT NULL,                  -- коли сталося (час клієнта)
    received_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),    -- коли прийняв сервер
    session_id   UUID         NOT NULL,
    user_id      BIGINT,                                 -- NULL для анонімів
    product_id   BIGINT,                                 -- для товарних подій
    order_id     BIGINT,                                 -- для подій замовлення/оплати
    page_url     TEXT,
    properties   JSONB        NOT NULL DEFAULT '{}',     -- специфічні поля типу події
    -- Унікальний ключ партиціонованої таблиці мусить містити ключ партиції.
    -- Повтор події має той самий occurred_at => потрапляє в ту саму партицію => дубль ловиться.
    PRIMARY KEY (event_id, occurred_at)
) PARTITION BY RANGE (occurred_at);

-- Свідомо НЕМАЄ foreign keys на events: таблиця приймає великий потік вставок,
-- події можуть приходити не по порядку, а перевірка FK на кожен INSERT дорога.
-- Зв'язки логічні: events.session_id -> sessions.id, events.user_id -> users.id,
-- events.order_id -> orders.id, events.product_id -> каталог.

-- Партиції створюються наперед (cron / pg_partman). Приклад:
CREATE TABLE events_2026_10 PARTITION OF events
    FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');
CREATE TABLE events_2026_11 PARTITION OF events
    FOR VALUES FROM ('2026-11-01') TO ('2026-12-01');
CREATE TABLE events_2026_12 PARTITION OF events
    FOR VALUES FROM ('2026-12-01') TO ('2027-01-01');
CREATE TABLE events_default PARTITION OF events DEFAULT;  -- страховка від «загублених» подій

-- Індекси під типові аналітичні запити (створюються на кожній партиції автоматично)
CREATE INDEX idx_events_type_time    ON events (event_type, occurred_at);
CREATE INDEX idx_events_session      ON events (session_id, occurred_at);
CREATE INDEX idx_events_product_time ON events (product_id, occurred_at) WHERE product_id IS NOT NULL;
CREATE INDEX idx_events_user         ON events (user_id) WHERE user_id IS NOT NULL;

-- ---------------------------------------------------------------------
-- daily_product_stats — попередньо агреговані метрики (наповнюється раз на добу/годину).
-- Дашборди читають звідси, а не сканують сирі events.
-- ---------------------------------------------------------------------
CREATE TABLE daily_product_stats (
    day           DATE    NOT NULL,
    product_id    BIGINT  NOT NULL,
    views         INT     NOT NULL DEFAULT 0,
    unique_views  INT     NOT NULL DEFAULT 0,  -- унікальні сесії
    add_to_carts  INT     NOT NULL DEFAULT 0,
    PRIMARY KEY (day, product_id)
);
