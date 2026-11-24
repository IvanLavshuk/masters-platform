-- Проектная схема PostgreSQL. Реализация сервисов и миграций выполняется отдельно.
CREATE TABLE users (
 user_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 email varchar(254) UNIQUE, phone varchar(32) UNIQUE,
 password_hash text NOT NULL, role varchar(20) NOT NULL CHECK(role IN ('customer','executor','admin')),
 status varchar(20) NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 CHECK (email IS NOT NULL OR phone IS NOT NULL)
);
CREATE TABLE executors (
 executor_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 user_id bigint NOT NULL UNIQUE REFERENCES users(user_id), name varchar(200) NOT NULL,
 experience integer NOT NULL CHECK(experience>=0), city varchar(100) NOT NULL,
 service_area text NOT NULL, notify_consent boolean NOT NULL DEFAULT false,
 rating numeric(2,1) CHECK(rating BETWEEN 1 AND 5)
);
CREATE TABLE categories (category_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 name varchar(150) NOT NULL, is_active boolean NOT NULL DEFAULT true);
CREATE TABLE executor_categories (executor_id bigint REFERENCES executors,
 category_id bigint REFERENCES categories, PRIMARY KEY(executor_id,category_id));
CREATE TABLE orders (
 order_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 customer_id bigint NOT NULL REFERENCES users, category_id bigint REFERENCES categories,
 description text NOT NULL, location text NOT NULL, desired_date date,
 budget numeric(12,2) CHECK(budget>=0), status varchar(30) NOT NULL CHECK(status IN
 ('draft','published','assigned','in_progress','awaiting_confirmation','completed','canceled')),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE responses (
 response_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 order_id bigint NOT NULL REFERENCES orders, executor_id bigint NOT NULL REFERENCES executors,
 price numeric(12,2) NOT NULL CHECK(price>=0), term integer NOT NULL CHECK(term>0),
 comment text, status varchar(20) NOT NULL,
 UNIQUE(order_id,executor_id)
);
CREATE UNIQUE INDEX one_selected_executor ON responses(order_id) WHERE status='selected';
CREATE TABLE messages (message_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 order_id bigint NOT NULL REFERENCES orders, sender_id bigint NOT NULL REFERENCES users,
 text text NOT NULL, sent_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE order_status_history (
 history_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 order_id bigint NOT NULL REFERENCES orders, user_id bigint NOT NULL REFERENCES users,
 old_status varchar(30), new_status varchar(30) NOT NULL,
 changed_at timestamptz NOT NULL DEFAULT now(), reason varchar(500),
 CHECK (new_status<>'canceled' OR (reason IS NOT NULL AND length(btrim(reason)) BETWEEN 5 AND 500))
);
CREATE TABLE payments (
 payment_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 order_id bigint NOT NULL REFERENCES orders, customer_id bigint NOT NULL REFERENCES users,
 amount numeric(12,2) NOT NULL CHECK(amount>0), currency char(3) NOT NULL CHECK(currency='BYN'),
 status varchar(20) NOT NULL CHECK(status IN ('pending','succeeded','failed','canceled')),
 external_op_id varchar(200) UNIQUE, confirmation_url text,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX one_active_or_successful_payment ON payments(order_id)
 WHERE status IN ('pending','succeeded');
CREATE TABLE reviews (review_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 order_id bigint NOT NULL UNIQUE REFERENCES orders, score integer NOT NULL CHECK(score BETWEEN 1 AND 5),
 text text NOT NULL, created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE promotions (promotion_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 executor_id bigint NOT NULL REFERENCES executors, cost numeric(12,2) NOT NULL CHECK(cost>=0),
 start_date date NOT NULL, end_date date NOT NULL, CHECK(end_date>=start_date));
CREATE TABLE banners (banner_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 user_id bigint NOT NULL REFERENCES users, material text NOT NULL, link text NOT NULL,
 start_date date NOT NULL, end_date date NOT NULL, is_active boolean NOT NULL DEFAULT true,
 CHECK(end_date>=start_date));
CREATE TABLE payment_requests (
 request_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 caller_id varchar(100) NOT NULL, operation varchar(20) NOT NULL CHECK(operation IN ('create','cancel')),
 key varchar(64) NOT NULL CHECK(key ~ '^[A-Za-z0-9_-]{8,64}$'),
 request_hash char(64) NOT NULL, payment_id bigint REFERENCES payments,
 created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(caller_id,operation,key)
);
CREATE TABLE payment_delivery_jobs (
 event_id uuid PRIMARY KEY, payment_id bigint NOT NULL REFERENCES payments,
 payload jsonb NOT NULL, attempts integer NOT NULL DEFAULT 0 CHECK(attempts>=0),
 next_retry_at timestamptz NOT NULL DEFAULT now(), delivered_at timestamptz
);
CREATE TABLE processed_payment_events (
 event_id uuid PRIMARY KEY, payment_id bigint NOT NULL REFERENCES payments,
 order_id bigint NOT NULL REFERENCES orders, payload jsonb NOT NULL,
 request_hash char(64) NOT NULL, accepted_at timestamptz NOT NULL DEFAULT now()
);
-- Прикладные транзакции дополнительно проверяют роль, владельца, переходы статусов,
-- неизменность конечного состояния оплаты и допустимость отзыва только после completed.
-- Обязательное наличие специализации активного исполнителя проверяется приложением.
