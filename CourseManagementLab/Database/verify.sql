BEGIN;
SET search_path TO course_lab, public;
DO $$
DECLARE v_course integer; v_other integer; v_enrollment integer; v_lesson integer; v_temp integer;
 v_before integer; v_time timestamptz;
BEGIN
 IF (SELECT count(*) FROM information_schema.tables WHERE table_schema='course_lab' AND table_type='BASE TABLE') <> 16 THEN
  RAISE EXCEPTION 'Очікується 16 таблиць'; END IF;
 CALL course_create('Перевірка транзакцій','Python перевірка',100,1,1,1,v_course);
 SELECT updated_at INTO v_time FROM courses WHERE id=v_course;
 CALL course_update(v_course,'Перевірка транзакцій','Python перевірка',110,1,1,1);
 IF (SELECT count(*) FROM course_price_history WHERE course_id=v_course)<>1 THEN RAISE EXCEPTION 'Не записана історія ціни'; END IF;
 IF NOT EXISTS(SELECT 1 FROM courses WHERE id=v_course AND updated_by=1 AND updated_at>v_time) THEN RAISE EXCEPTION 'Не оновлено аудит'; END IF;
 CALL course_update(v_course,'Перевірка транзакцій','Новий опис',110,1,1,1);
 IF (SELECT count(*) FROM course_price_history WHERE course_id=v_course)<>1 THEN RAISE EXCEPTION 'Зайва історія ціни'; END IF;
 BEGIN
  CALL course_delete(v_course,2);
  RAISE EXCEPTION USING ERRCODE='ZX001',MESSAGE='Студент отримав права адміністратора';
 EXCEPTION WHEN SQLSTATE 'ZX001' THEN RAISE; WHEN OTHERS THEN NULL; END;
 CALL lesson_save(0,v_course,'Урок A','',1,1);
 SELECT id INTO v_lesson FROM lessons WHERE course_id=v_course;
 CALL course_delete(v_course,1);
 IF EXISTS(SELECT 1 FROM v_catalog WHERE id=v_course) OR NOT EXISTS(SELECT 1 FROM courses WHERE id=v_course AND is_deleted) THEN
  RAISE EXCEPTION 'Помилка soft delete'; END IF;
 BEGIN
  CALL enrollment_create(3,v_course,1,v_temp);
  RAISE EXCEPTION USING ERRCODE='ZX001',MESSAGE='Запис на видалений курс дозволений';
 EXCEPTION WHEN SQLSTATE 'ZX001' THEN RAISE; WHEN OTHERS THEN NULL; END;
 CALL course_restore(v_course,1);
 IF NOT EXISTS(SELECT 1 FROM v_catalog WHERE id=v_course) THEN RAISE EXCEPTION 'Курс не відновлено'; END IF;
 SELECT count(*) INTO v_before FROM enrollments;
 BEGIN
  CALL enrollment_create(3,v_course,1,v_temp);
  CALL payment_register(v_temp,0,1);
  RAISE EXCEPTION USING ERRCODE='ZX001',MESSAGE='Некоректна оплата прийнята';
 EXCEPTION WHEN SQLSTATE 'ZX001' THEN RAISE; WHEN OTHERS THEN NULL; END;
 IF (SELECT count(*) FROM enrollments)<>v_before THEN RAISE EXCEPTION 'Запис не відкотився'; END IF;
 CALL enrollment_create(3,v_course,1,v_enrollment);
 CALL payment_register(v_enrollment,110,1);
 BEGIN
  CALL certificate_issue(v_enrollment,1);
  RAISE EXCEPTION USING ERRCODE='ZX001',MESSAGE='Сертифікат видано передчасно';
 EXCEPTION WHEN SQLSTATE 'ZX001' THEN RAISE; WHEN OTHERS THEN NULL; END;
 BEGIN
  CALL progress_complete(v_enrollment,1,3);
  RAISE EXCEPTION USING ERRCODE='ZX001',MESSAGE='Урок чужого курсу зараховано';
 EXCEPTION WHEN SQLSTATE 'ZX001' THEN RAISE; WHEN OTHERS THEN NULL; END;
 CALL progress_complete(v_enrollment,v_lesson,3);
 IF enrollment_progress(v_enrollment)<>100 THEN RAISE EXCEPTION 'Неправильний прогрес'; END IF;
 CALL certificate_issue(v_enrollment,1);
 CALL review_save(v_enrollment,4,'Тестовий відгук',3);
 IF course_rating(v_course)<>4 THEN RAISE EXCEPTION 'Неправильний рейтинг'; END IF;
 SELECT id INTO v_temp FROM reviews WHERE enrollment_id=v_enrollment;
 CALL review_delete(v_temp,1);
 IF course_rating(v_course)<>0 THEN RAISE EXCEPTION 'Видалений відгук враховується'; END IF;
 CALL lesson_delete(v_lesson,1);
 IF EXISTS(SELECT 1 FROM v_progress WHERE enrollment_id=v_enrollment) THEN RAISE EXCEPTION 'Видалений урок у прогресі'; END IF;
 CALL lesson_restore(v_lesson,1);
 IF enrollment_progress(v_enrollment)<>100 THEN RAISE EXCEPTION 'Прогрес після відновлення втрачений'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_indexes WHERE schemaname='course_lab' AND indexname='ix_courses_search' AND indexdef LIKE '%USING gin%') THEN
  RAISE EXCEPTION 'Немає GIN індексу'; END IF;
 RAISE NOTICE 'PASS: схема, аудит, історія цін, права, soft delete/restore, rollback, прогрес, сертифікат, відгуки та індекси';
END $$;
ROLLBACK;
