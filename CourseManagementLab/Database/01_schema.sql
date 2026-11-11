BEGIN;
CREATE SCHEMA course_lab;
SET search_path TO course_lab, public;
CREATE TABLE users (
 id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 email varchar(100) NOT NULL UNIQUE,
 display_name varchar(200) NOT NULL,
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE roles (id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY, name varchar(50) NOT NULL UNIQUE);
CREATE TABLE user_roles (
 user_id integer REFERENCES users(id), role_id integer REFERENCES roles(id), PRIMARY KEY(user_id, role_id)
);
CREATE TABLE admins (
 user_id integer PRIMARY KEY REFERENCES users(id), employee_code varchar(50) NOT NULL UNIQUE, position varchar(100) NOT NULL
);
CREATE TABLE customers (
 user_id integer PRIMARY KEY REFERENCES users(id), first_name varchar(100) NOT NULL, last_name varchar(100) NOT NULL, phone varchar(20)
);
CREATE TABLE programming_languages (id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY, name varchar(50) NOT NULL UNIQUE);
CREATE TABLE course_levels (id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY, name varchar(50) NOT NULL UNIQUE);
CREATE TABLE courses (
 id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 title varchar(200) NOT NULL CHECK (length(trim(title)) > 0), description text NOT NULL DEFAULT '',
 price numeric(10,2) NOT NULL CHECK(price >= 0),
 level_id integer NOT NULL REFERENCES course_levels(id), language_id integer NOT NULL REFERENCES programming_languages(id),
 is_deleted boolean NOT NULL DEFAULT false, deleted_at timestamptz, deleted_by integer REFERENCES users(id),
 updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_by integer NOT NULL REFERENCES users(id),
 search_document tsvector GENERATED ALWAYS AS (to_tsvector('simple', title || ' ' || description)) STORED,
 CHECK ((is_deleted AND deleted_at IS NOT NULL AND deleted_by IS NOT NULL) OR
        (NOT is_deleted AND deleted_at IS NULL AND deleted_by IS NULL))
);
CREATE TABLE lessons (
 id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY, course_id integer NOT NULL REFERENCES courses(id),
 title varchar(200) NOT NULL CHECK(length(trim(title)) > 0), video_url varchar(500) NOT NULL DEFAULT '',
 order_number integer NOT NULL CHECK(order_number > 0),
 is_deleted boolean NOT NULL DEFAULT false, deleted_at timestamptz, deleted_by integer REFERENCES users(id),
 updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_by integer NOT NULL REFERENCES users(id),
 CHECK ((is_deleted AND deleted_at IS NOT NULL AND deleted_by IS NOT NULL) OR
        (NOT is_deleted AND deleted_at IS NULL AND deleted_by IS NULL))
);
CREATE TABLE enrollments (
 id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 customer_id integer NOT NULL REFERENCES customers(user_id), course_id integer NOT NULL REFERENCES courses(id),
 agreed_price numeric(10,2) NOT NULL CHECK(agreed_price >= 0), enrolled_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_by integer NOT NULL REFERENCES users(id),
 UNIQUE(customer_id,course_id)
);
CREATE TABLE lesson_progress (
 id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 enrollment_id integer NOT NULL REFERENCES enrollments(id), lesson_id integer NOT NULL REFERENCES lessons(id),
 is_completed boolean NOT NULL DEFAULT false, completed_at timestamptz,
 updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_by integer NOT NULL REFERENCES users(id),
 UNIQUE(enrollment_id,lesson_id), CHECK(is_completed = (completed_at IS NOT NULL))
);
CREATE TABLE payments (
 id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY, enrollment_id integer NOT NULL UNIQUE REFERENCES enrollments(id),
 amount numeric(10,2) NOT NULL CHECK(amount >= 0), paid_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 recorded_by integer NOT NULL REFERENCES users(id)
);
CREATE TABLE reviews (
 id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY, enrollment_id integer NOT NULL UNIQUE REFERENCES enrollments(id),
 rating integer NOT NULL CHECK(rating BETWEEN 1 AND 5), body text NOT NULL,
 is_deleted boolean NOT NULL DEFAULT false, deleted_at timestamptz, deleted_by integer REFERENCES users(id),
 updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_by integer NOT NULL REFERENCES users(id),
 CHECK ((is_deleted AND deleted_at IS NOT NULL AND deleted_by IS NOT NULL) OR
        (NOT is_deleted AND deleted_at IS NULL AND deleted_by IS NULL))
);
CREATE TABLE certificates (
 id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY, enrollment_id integer NOT NULL UNIQUE REFERENCES enrollments(id),
 certificate_number varchar(100) NOT NULL UNIQUE, issued_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 issued_by integer NOT NULL REFERENCES users(id)
);
CREATE TABLE course_price_history (
 id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY, course_id integer NOT NULL REFERENCES courses(id),
 old_price numeric(10,2) NOT NULL, new_price numeric(10,2) NOT NULL,
 changed_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP, changed_by integer NOT NULL REFERENCES users(id)
);
CREATE TABLE course_history (
 id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY, course_id integer NOT NULL REFERENCES courses(id),
 operation varchar(20) NOT NULL, old_data jsonb, new_data jsonb NOT NULL,
 changed_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP, changed_by integer NOT NULL REFERENCES users(id)
);
CREATE INDEX ix_enrollments_customer ON enrollments USING btree(customer_id);
CREATE INDEX ix_courses_search ON courses USING gin(search_document) WHERE NOT is_deleted;
CREATE UNIQUE INDEX ux_lessons_active_order ON lessons(course_id,order_number) WHERE NOT is_deleted;
CREATE INDEX ix_price_history_course ON course_price_history(course_id,changed_at DESC);
