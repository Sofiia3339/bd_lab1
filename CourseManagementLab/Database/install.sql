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

CREATE FUNCTION require_admin(p_actor integer) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM admins a JOIN user_roles ur ON ur.user_id=a.user_id JOIN roles r ON r.id=ur.role_id WHERE a.user_id=p_actor AND r.name='Admin') THEN
  RAISE EXCEPTION 'Потрібен користувач із роллю адміністратора';
 END IF;
END $$;
CREATE FUNCTION touch_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at := clock_timestamp(); RETURN NEW; END $$;
CREATE TRIGGER tr_courses_touch BEFORE UPDATE ON courses FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER tr_lessons_touch BEFORE UPDATE ON lessons FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER tr_enrollments_touch BEFORE UPDATE ON enrollments FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER tr_progress_touch BEFORE UPDATE ON lesson_progress FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER tr_reviews_touch BEFORE UPDATE ON reviews FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE FUNCTION audit_course() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO course_history(course_id,operation,old_data,new_data,changed_by)
 VALUES(NEW.id,CASE WHEN TG_OP='INSERT' THEN 'create' WHEN NEW.is_deleted AND NOT OLD.is_deleted THEN 'delete'
 WHEN NOT NEW.is_deleted AND OLD.is_deleted THEN 'restore' ELSE 'update' END,
 CASE WHEN TG_OP='UPDATE' THEN to_jsonb(OLD)-'search_document' ELSE NULL END,to_jsonb(NEW)-'search_document',NEW.updated_by);
 IF TG_OP='UPDATE' AND NEW.price IS DISTINCT FROM OLD.price THEN
  INSERT INTO course_price_history(course_id,old_price,new_price,changed_by) VALUES(NEW.id,OLD.price,NEW.price,NEW.updated_by);
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER tr_courses_audit AFTER INSERT OR UPDATE ON courses FOR EACH ROW EXECUTE FUNCTION audit_course();
CREATE FUNCTION enrollment_progress(p_enrollment integer) RETURNS numeric LANGUAGE sql STABLE AS $$
 SELECT COALESCE(round(100.0 * count(*) FILTER (WHERE lp.is_completed) / NULLIF(count(*),0),2),0)
 FROM enrollments e JOIN lessons l ON l.course_id=e.course_id AND NOT l.is_deleted
 LEFT JOIN lesson_progress lp ON lp.enrollment_id=e.id AND lp.lesson_id=l.id WHERE e.id=p_enrollment;
$$;
CREATE FUNCTION course_rating(p_course integer) RETURNS numeric LANGUAGE sql STABLE AS $$
 SELECT COALESCE(round(avg(r.rating),2),0) FROM reviews r JOIN enrollments e ON e.id=r.enrollment_id
 WHERE e.course_id=p_course AND NOT r.is_deleted;
$$;
CREATE PROCEDURE course_create(p_title text,p_description text,p_price numeric,p_level integer,p_language integer,p_actor integer,INOUT p_id integer)
LANGUAGE plpgsql AS $$ BEGIN
 PERFORM require_admin(p_actor);
 INSERT INTO courses(title,description,price,level_id,language_id,updated_by)
 VALUES(p_title,p_description,p_price,p_level,p_language,p_actor) RETURNING id INTO p_id;
END $$;
CREATE PROCEDURE course_update(p_id integer,p_title text,p_description text,p_price numeric,p_level integer,p_language integer,p_actor integer)
LANGUAGE plpgsql AS $$ BEGIN
 PERFORM require_admin(p_actor);
 UPDATE courses SET title=p_title,description=p_description,price=p_price,level_id=p_level,language_id=p_language,updated_by=p_actor
 WHERE id=p_id AND NOT is_deleted;
 IF NOT FOUND THEN RAISE EXCEPTION 'Активний курс не знайдено'; END IF;
END $$;
CREATE PROCEDURE course_delete(p_id integer,p_actor integer) LANGUAGE plpgsql AS $$ BEGIN
 PERFORM require_admin(p_actor);
 UPDATE courses SET is_deleted=true,deleted_at=clock_timestamp(),deleted_by=p_actor,updated_by=p_actor WHERE id=p_id AND NOT is_deleted;
 IF NOT FOUND THEN RAISE EXCEPTION 'Активний курс не знайдено'; END IF;
END $$;
CREATE PROCEDURE course_restore(p_id integer,p_actor integer) LANGUAGE plpgsql AS $$ BEGIN
 PERFORM require_admin(p_actor);
 UPDATE courses SET is_deleted=false,deleted_at=NULL,deleted_by=NULL,updated_by=p_actor WHERE id=p_id AND is_deleted;
 IF NOT FOUND THEN RAISE EXCEPTION 'Видалений курс не знайдено'; END IF;
END $$;
CREATE PROCEDURE lesson_save(p_id integer,p_course integer,p_title text,p_url text,p_order integer,p_actor integer)
LANGUAGE plpgsql AS $$ BEGIN
 PERFORM require_admin(p_actor);
 PERFORM 1 FROM courses WHERE id=p_course AND NOT is_deleted FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Активний курс не знайдено'; END IF;
 IF p_id=0 THEN
  INSERT INTO lessons(course_id,title,video_url,order_number,updated_by) VALUES(p_course,p_title,p_url,p_order,p_actor);
 ELSE
  UPDATE lessons SET title=p_title,video_url=p_url,order_number=p_order,updated_by=p_actor
  WHERE id=p_id AND course_id=p_course AND NOT is_deleted;
  IF NOT FOUND THEN RAISE EXCEPTION 'Активний урок не знайдено'; END IF;
 END IF;
END $$;
CREATE PROCEDURE lesson_delete(p_id integer,p_actor integer) LANGUAGE plpgsql AS $$ BEGIN
 PERFORM require_admin(p_actor);
 UPDATE lessons SET is_deleted=true,deleted_at=clock_timestamp(),deleted_by=p_actor,updated_by=p_actor WHERE id=p_id AND NOT is_deleted;
 IF NOT FOUND THEN RAISE EXCEPTION 'Активний урок не знайдено'; END IF;
END $$;
CREATE PROCEDURE lesson_restore(p_id integer,p_actor integer) LANGUAGE plpgsql AS $$ BEGIN
 PERFORM require_admin(p_actor);
 UPDATE lessons l SET is_deleted=false,deleted_at=NULL,deleted_by=NULL,updated_by=p_actor
 WHERE l.id=p_id AND l.is_deleted AND EXISTS(SELECT 1 FROM courses c WHERE c.id=l.course_id AND NOT c.is_deleted);
 IF NOT FOUND THEN RAISE EXCEPTION 'Урок не знайдено або його курс видалено'; END IF;
END $$;
CREATE PROCEDURE enrollment_create(p_customer integer,p_course integer,p_actor integer,INOUT p_id integer)
LANGUAGE plpgsql AS $$ DECLARE v_price numeric; BEGIN
 PERFORM require_admin(p_actor);
 SELECT price INTO v_price FROM courses WHERE id=p_course AND NOT is_deleted FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Курс недоступний для запису'; END IF;
 INSERT INTO enrollments(customer_id,course_id,agreed_price,updated_by) VALUES(p_customer,p_course,v_price,p_actor) RETURNING id INTO p_id;
END $$;
CREATE PROCEDURE payment_register(p_enrollment integer,p_amount numeric,p_actor integer)
LANGUAGE plpgsql AS $$ DECLARE v_price numeric; BEGIN
 PERFORM require_admin(p_actor);
 SELECT agreed_price INTO v_price FROM enrollments WHERE id=p_enrollment FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Запис на курс не знайдено'; END IF;
 IF p_amount IS DISTINCT FROM v_price THEN RAISE EXCEPTION 'Сума оплати має дорівнювати погодженій ціні %',v_price; END IF;
 INSERT INTO payments(enrollment_id,amount,recorded_by) VALUES(p_enrollment,p_amount,p_actor);
END $$;
CREATE PROCEDURE progress_complete(p_enrollment integer,p_lesson integer,p_actor integer)
LANGUAGE plpgsql AS $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM enrollments e JOIN lessons l ON l.course_id=e.course_id
 JOIN courses c ON c.id=e.course_id JOIN payments p ON p.enrollment_id=e.id
 WHERE e.id=p_enrollment AND l.id=p_lesson AND NOT l.is_deleted AND NOT c.is_deleted
 AND (e.customer_id=p_actor OR EXISTS(SELECT 1 FROM admins WHERE user_id=p_actor))) THEN
  RAISE EXCEPTION 'Немає доступу: перевірте оплату, користувача та належність уроку курсу';
 END IF;
 INSERT INTO lesson_progress(enrollment_id,lesson_id,is_completed,completed_at,updated_by)
 VALUES(p_enrollment,p_lesson,true,clock_timestamp(),p_actor)
 ON CONFLICT(enrollment_id,lesson_id) DO UPDATE SET is_completed=true,completed_at=EXCLUDED.completed_at,updated_by=p_actor;
END $$;
CREATE PROCEDURE review_save(p_enrollment integer,p_rating integer,p_body text,p_actor integer)
LANGUAGE plpgsql AS $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM enrollments e JOIN payments p ON p.enrollment_id=e.id JOIN courses c ON c.id=e.course_id
 WHERE e.id=p_enrollment AND e.customer_id=p_actor AND NOT c.is_deleted) THEN
  RAISE EXCEPTION 'Відгук може залишити студент оплаченого активного курсу'; END IF;
 INSERT INTO reviews(enrollment_id,rating,body,updated_by) VALUES(p_enrollment,p_rating,p_body,p_actor)
 ON CONFLICT(enrollment_id) DO UPDATE SET rating=p_rating,body=p_body,is_deleted=false,deleted_at=NULL,deleted_by=NULL,updated_by=p_actor;
END $$;
CREATE PROCEDURE review_delete(p_id integer,p_actor integer) LANGUAGE plpgsql AS $$ BEGIN
 PERFORM require_admin(p_actor);
 UPDATE reviews SET is_deleted=true,deleted_at=clock_timestamp(),deleted_by=p_actor,updated_by=p_actor WHERE id=p_id AND NOT is_deleted;
 IF NOT FOUND THEN RAISE EXCEPTION 'Відгук не знайдено'; END IF;
END $$;
CREATE PROCEDURE certificate_issue(p_enrollment integer,p_actor integer) LANGUAGE plpgsql AS $$ BEGIN
 PERFORM require_admin(p_actor);
 PERFORM 1 FROM enrollments e JOIN courses c ON c.id=e.course_id JOIN payments p ON p.enrollment_id=e.id
 WHERE e.id=p_enrollment AND NOT c.is_deleted FOR UPDATE OF e,c;
 IF NOT FOUND OR enrollment_progress(p_enrollment)<100 THEN RAISE EXCEPTION 'Сертифікат доступний після оплати та завершення всіх уроків'; END IF;
 INSERT INTO certificates(enrollment_id,certificate_number,issued_by) VALUES(p_enrollment,'COURSE-'||p_enrollment,p_actor);
END $$;
CREATE VIEW v_catalog AS
 SELECT c.id,c.title,c.description,c.price,c.level_id,c.language_id,cl.name AS level_name,pl.name AS language_name,
 c.updated_at,c.updated_by,u.display_name AS updated_by_name,c.search_document,course_rating(c.id) AS rating
 FROM courses c JOIN course_levels cl ON cl.id=c.level_id JOIN programming_languages pl ON pl.id=c.language_id
 JOIN users u ON u.id=c.updated_by WHERE NOT c.is_deleted;
CREATE VIEW v_course_admin AS
 SELECT c.id,c.title,c.description,c.price,c.level_id,c.language_id,c.is_deleted,c.deleted_at,c.deleted_by,
 c.updated_at,c.updated_by,u.display_name AS updated_by_name FROM courses c JOIN users u ON u.id=c.updated_by;
CREATE VIEW v_lessons AS SELECT l.*,c.title AS course_title,c.is_deleted AS course_deleted FROM lessons l JOIN courses c ON c.id=l.course_id;
CREATE VIEW v_students AS SELECT c.user_id AS id,u.display_name,u.email FROM customers c JOIN users u ON u.id=c.user_id;
CREATE VIEW v_admins AS SELECT a.user_id AS id,u.display_name FROM admins a JOIN users u ON u.id=a.user_id
 WHERE EXISTS(SELECT 1 FROM user_roles ur JOIN roles r ON r.id=ur.role_id WHERE ur.user_id=a.user_id AND r.name='Admin');
CREATE VIEW v_levels AS SELECT id,name FROM course_levels;
CREATE VIEW v_languages AS SELECT id,name FROM programming_languages;
CREATE VIEW v_enrollments AS
 SELECT e.id,e.customer_id,e.course_id,u.display_name AS student_name,c.title AS course_title,e.agreed_price,e.enrolled_at,
 c.is_deleted AS course_deleted,enrollment_progress(e.id) AS progress,p.amount AS paid_amount,
 cert.certificate_number,e.updated_at,e.updated_by FROM enrollments e JOIN users u ON u.id=e.customer_id
 JOIN courses c ON c.id=e.course_id LEFT JOIN payments p ON p.enrollment_id=e.id LEFT JOIN certificates cert ON cert.enrollment_id=e.id;
CREATE VIEW v_progress AS
 SELECT e.id AS enrollment_id,l.id AS lesson_id,l.title,l.order_number,COALESCE(lp.is_completed,false) AS is_completed,
 lp.completed_at FROM enrollments e JOIN lessons l ON l.course_id=e.course_id AND NOT l.is_deleted
 LEFT JOIN lesson_progress lp ON lp.enrollment_id=e.id AND lp.lesson_id=l.id;
CREATE VIEW v_price_history AS SELECT h.*,c.title,u.display_name AS changed_by_name
 FROM course_price_history h JOIN courses c ON c.id=h.course_id JOIN users u ON u.id=h.changed_by;
CREATE VIEW v_course_history AS SELECT h.*,c.title,u.display_name AS changed_by_name
 FROM course_history h JOIN courses c ON c.id=h.course_id JOIN users u ON u.id=h.changed_by;
CREATE VIEW v_reviews AS SELECT r.*,e.course_id,u.display_name AS student_name FROM reviews r
 JOIN enrollments e ON e.id=r.enrollment_id JOIN users u ON u.id=e.customer_id WHERE NOT r.is_deleted;

INSERT INTO users(email,display_name) VALUES
 ('admin@example.test','Адміністратор школи'),('sofia@example.test','Соболева Софія Юріївна'),('anna@example.test','Соболева Анна Юріївна');
INSERT INTO roles(name) VALUES('Admin'),('Student');
INSERT INTO user_roles VALUES(1,1),(2,2),(3,2);
INSERT INTO admins VALUES(1,'ADM-001','Адміністратор');
INSERT INTO customers VALUES(2,'Софія','Соболева','+380000000001'),(3,'Анна','Соболева','+380000000002');
INSERT INTO programming_languages(name) VALUES('Python'),('C#'),('JavaScript');
INSERT INTO course_levels(name) VALUES('Початковий'),('Середній'),('Просунутий');
DO $$ DECLARE v_id integer; BEGIN
 CALL course_create('Основи Python','Змінні, умови, цикли та функції Python',1200,1,1,1,v_id);
 CALL course_create('Розробка на C#','Класи, колекції та робота з базою даних',1800,2,2,1,v_id);
 CALL course_create('JavaScript для початківців','Основи JavaScript та взаємодія зі сторінкою',1500,1,3,1,v_id);
END $$;
CALL lesson_save(0,1,'Змінні та типи даних','https://example.test/python/1',1,1);
CALL lesson_save(0,1,'Умови та цикли','https://example.test/python/2',2,1);
CALL lesson_save(0,2,'Класи й об’єкти','https://example.test/csharp/1',1,1);
CALL lesson_save(0,2,'Колекції','https://example.test/csharp/2',2,1);
CALL lesson_save(0,3,'Змінні JavaScript','https://example.test/js/1',1,1);
DO $$ DECLARE v_id integer; BEGIN
 CALL enrollment_create(2,1,1,v_id);
 CALL payment_register(v_id,1200,1);
 CALL progress_complete(v_id,1,2);
 CALL progress_complete(v_id,2,2);
 CALL review_save(v_id,5,'Зрозумілі приклади та послідовні уроки.',2);
 CALL certificate_issue(v_id,1);
END $$;
CALL course_update(1,'Основи Python','Змінні, умови, цикли та функції Python',1300,1,1,1);
COMMIT;
