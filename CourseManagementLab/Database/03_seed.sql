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
