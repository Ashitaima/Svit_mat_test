-- Демо-дані для перевірки запитів з queries.sql
SET TIME ZONE 'UTC';

INSERT INTO users (id, email) VALUES (1, 'olena@example.com'), (2, 'petro@example.com');

INSERT INTO sessions (id, user_id, started_at, last_seen_at) VALUES
  ('11111111-1111-1111-1111-111111111111', 1,    '2026-11-16 10:00', '2026-11-16 10:20'),  -- купила
  ('22222222-2222-2222-2222-222222222222', NULL, '2026-11-16 11:00', '2026-11-16 11:05'),  -- кинув кошик
  ('33333333-3333-3333-3333-333333333333', 2,    '2026-11-17 09:00', '2026-11-17 09:30'),  -- купив
  ('44444444-4444-4444-4444-444444444444', NULL, '2026-11-17 12:00', '2026-11-17 12:01');  -- тільки дивився

INSERT INTO orders (id, user_id, session_id, status, total_amount, currency, created_at, paid_at) VALUES
  (1001, 1, '11111111-1111-1111-1111-111111111111', 'paid', 1598.00, 'UAH', '2026-11-16 10:15', '2026-11-16 10:16'),
  (1002, 2, '33333333-3333-3333-3333-333333333333', 'paid',  499.00, 'UAH', '2026-11-17 09:20', '2026-11-17 09:21');

INSERT INTO order_items VALUES (1001, 501, 2, 799.00), (1002, 502, 1, 499.00);

INSERT INTO events (event_id, event_type, occurred_at, session_id, user_id, product_id, order_id, properties) VALUES
  -- сесія 1: перегляд x2 -> кошик -> checkout -> замовлення -> оплата
  (gen_random_uuid(), 'product_view',      '2026-11-16 10:01', '11111111-1111-1111-1111-111111111111', 1, 501, NULL, '{"price": 799, "currency": "UAH"}'),
  (gen_random_uuid(), 'product_view',      '2026-11-16 10:03', '11111111-1111-1111-1111-111111111111', 1, 501, NULL, '{"price": 799, "currency": "UAH"}'),
  (gen_random_uuid(), 'add_to_cart',       '2026-11-16 10:05', '11111111-1111-1111-1111-111111111111', 1, 501, NULL, '{"quantity": 2, "price": 799, "currency": "UAH"}'),
  (gen_random_uuid(), 'checkout_started',  '2026-11-16 10:10', '11111111-1111-1111-1111-111111111111', 1, NULL, NULL, '{"cart_value": 1598, "items_count": 2}'),
  (gen_random_uuid(), 'order_created',     '2026-11-16 10:15', '11111111-1111-1111-1111-111111111111', 1, NULL, 1001, '{"total": 1598, "currency": "UAH"}'),
  (gen_random_uuid(), 'payment_succeeded', '2026-11-16 10:16', '11111111-1111-1111-1111-111111111111', 1, NULL, 1001, '{"amount": 1598, "currency": "UAH", "method": "card"}'),
  -- сесія 2: перегляд -> кошик, без оплати
  (gen_random_uuid(), 'product_view',      '2026-11-16 11:01', '22222222-2222-2222-2222-222222222222', NULL, 501, NULL, '{}'),
  (gen_random_uuid(), 'product_view',      '2026-11-16 11:02', '22222222-2222-2222-2222-222222222222', NULL, 502, NULL, '{}'),
  (gen_random_uuid(), 'add_to_cart',       '2026-11-16 11:03', '22222222-2222-2222-2222-222222222222', NULL, 502, NULL, '{"quantity": 1}'),
  -- сесія 3: кошик -> оплата
  (gen_random_uuid(), 'product_view',      '2026-11-17 09:05', '33333333-3333-3333-3333-333333333333', 2, 502, NULL, '{}'),
  (gen_random_uuid(), 'add_to_cart',       '2026-11-17 09:10', '33333333-3333-3333-3333-333333333333', 2, 502, NULL, '{"quantity": 1}'),
  (gen_random_uuid(), 'checkout_started',  '2026-11-17 09:15', '33333333-3333-3333-3333-333333333333', 2, NULL, NULL, '{}'),
  (gen_random_uuid(), 'order_created',     '2026-11-17 09:20', '33333333-3333-3333-3333-333333333333', 2, NULL, 1002, '{}'),
  (gen_random_uuid(), 'payment_succeeded', '2026-11-17 09:21', '33333333-3333-3333-3333-333333333333', 2, NULL, 1002, '{}'),
  -- сесія 4: лише перегляд
  (gen_random_uuid(), 'product_view',      '2026-11-17 12:00', '44444444-4444-4444-4444-444444444444', NULL, 501, NULL, '{}');

-- Перевірка дедуплікації: одна й та сама подія прийшла двічі (retry клієнта)
INSERT INTO events (event_id, event_type, occurred_at, session_id, product_id)
VALUES ('aaaaaaaa-0000-0000-0000-000000000001', 'product_view', '2026-11-17 12:00:30', '44444444-4444-4444-4444-444444444444', 503)
ON CONFLICT (event_id, occurred_at) DO NOTHING;
INSERT INTO events (event_id, event_type, occurred_at, session_id, product_id)
VALUES ('aaaaaaaa-0000-0000-0000-000000000001', 'product_view', '2026-11-17 12:00:30', '44444444-4444-4444-4444-444444444444', 503)
ON CONFLICT (event_id, occurred_at) DO NOTHING;   -- 0 rows: дубль проігноровано
