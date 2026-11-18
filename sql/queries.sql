-- =====================================================================
-- Метрики. Період задано літералами для наочності;
-- у реальному коді це параметри :date_from / :date_to.
-- Фільтр по occurred_at дозволяє Postgres читати лише потрібні партиції.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Перегляди товарів за день
--    views        — усі перегляди (з повторними)
--    unique_views — скільки різних сесій переглянули товар
-- ---------------------------------------------------------------------
SELECT
    date_trunc('day', occurred_at)::date  AS day,
    product_id,
    COUNT(*)                              AS views,
    COUNT(DISTINCT session_id)            AS unique_views
FROM events
WHERE event_type  = 'product_view'
  AND occurred_at >= '2026-11-01'
  AND occurred_at <  '2026-12-01'
GROUP BY day, product_id
ORDER BY day, views DESC;


-- ---------------------------------------------------------------------
-- 2. Конверсія «кошик → оплата» по сесіях
--    Знаменник: сесії, де було хоча б одне add_to_cart за період.
--    Чисельник: з них ті, де ПІСЛЯ першого add_to_cart була успішна оплата.
-- ---------------------------------------------------------------------
WITH carts AS (
    SELECT session_id, MIN(occurred_at) AS first_cart_at
    FROM events
    WHERE event_type  = 'add_to_cart'
      AND occurred_at >= '2026-11-01'
      AND occurred_at <  '2026-12-01'
    GROUP BY session_id
),
paid AS (
    SELECT DISTINCT c.session_id
    FROM carts c
    JOIN events e
      ON  e.session_id  = c.session_id
      AND e.event_type  = 'payment_succeeded'
      AND e.occurred_at >= c.first_cart_at
      AND e.occurred_at <  '2026-12-01'::timestamptz + interval '1 day'  -- даємо добу «хвоста» на оплату
)
SELECT
    (SELECT COUNT(*) FROM carts)                                     AS sessions_with_cart,
    (SELECT COUNT(*) FROM paid)                                      AS sessions_with_payment,
    ROUND(100.0 * (SELECT COUNT(*) FROM paid)
                / NULLIF((SELECT COUNT(*) FROM carts), 0), 2)        AS conversion_pct;


-- ---------------------------------------------------------------------
-- 3. Воронка по днях: перегляд → кошик → checkout → оплата
--    (унікальні сесії на кожному кроці; одна таблиця, один прохід)
-- ---------------------------------------------------------------------
SELECT
    date_trunc('day', occurred_at)::date                                        AS day,
    COUNT(DISTINCT session_id) FILTER (WHERE event_type = 'product_view')       AS viewed,
    COUNT(DISTINCT session_id) FILTER (WHERE event_type = 'add_to_cart')        AS added_to_cart,
    COUNT(DISTINCT session_id) FILTER (WHERE event_type = 'checkout_started')   AS started_checkout,
    COUNT(DISTINCT session_id) FILTER (WHERE event_type = 'payment_succeeded')  AS paid
FROM events
WHERE occurred_at >= '2026-11-01'
  AND occurred_at <  '2026-12-01'
GROUP BY day
ORDER BY day;


-- ---------------------------------------------------------------------
-- 4. (бонус) Наповнення агрегату daily_product_stats за вчора.
--    Ідемпотентно: повторний запуск перезаписує рядки, а не дублює.
-- ---------------------------------------------------------------------
INSERT INTO daily_product_stats (day, product_id, views, unique_views, add_to_carts)
SELECT
    occurred_at::date,
    product_id,
    COUNT(*)                   FILTER (WHERE event_type = 'product_view'),
    COUNT(DISTINCT session_id) FILTER (WHERE event_type = 'product_view'),
    COUNT(*)                   FILTER (WHERE event_type = 'add_to_cart')
FROM events
WHERE event_type IN ('product_view', 'add_to_cart')
  AND product_id IS NOT NULL
  AND occurred_at >= '2026-11-16'
  AND occurred_at <  '2026-11-17'
GROUP BY occurred_at::date, product_id
ON CONFLICT (day, product_id) DO UPDATE
SET views        = EXCLUDED.views,
    unique_views = EXCLUDED.unique_views,
    add_to_carts = EXCLUDED.add_to_carts;
