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
