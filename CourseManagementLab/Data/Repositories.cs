using Npgsql;
using CourseManagementLab.Models;
namespace CourseManagementLab.Data;

public abstract class Repository(UnitOfWork unit)
{
    protected async Task<NpgsqlCommand> Command(string sql, params object[] args)
    {
        var connection = await unit.Connection();
        var cmd = new NpgsqlCommand(sql, connection, unit.Transaction);
        foreach (var arg in args) cmd.Parameters.Add(new NpgsqlParameter { Value = arg });
        return cmd;
    }
    protected async Task<List<T>> Read<T>(string sql, Func<NpgsqlDataReader,T> map, params object[] args)
    {
        await using var cmd = await Command(sql,args);
        await using var reader = await cmd.ExecuteReaderAsync();
        var rows = new List<T>();
        while(await reader.ReadAsync()) rows.Add(map(reader));
        return rows;
    }
    protected async Task Execute(string sql, params object[] args)
    {
        await using var cmd = await Command(sql,args);
        await cmd.ExecuteNonQueryAsync();
    }
    protected async Task<int> NewId(string sql, params object[] args)
    {
        await using var cmd = await Command(sql,args);
        return Convert.ToInt32(await cmd.ExecuteScalarAsync());
    }
}
public interface ICourseRepository
{
    Task<List<CourseRow>> List(bool includeDeleted, string search = "");
    Task<CourseRow?> Get(int id);
    Task<int> Create(CourseForm form);
    Task Update(CourseForm form);
    Task Delete(int id,int actor);
    Task Restore(int id,int actor);
}
public sealed class CourseRepository(UnitOfWork unit) : Repository(unit), ICourseRepository
{
    private static CourseRow Map(NpgsqlDataReader r) => new(r.GetInt32(0),r.GetString(1),r.GetString(2),r.GetDecimal(3),
        r.GetInt32(4),r.GetInt32(5),r.GetBoolean(6),r.GetDateTime(7),r.GetString(8));
    public Task<List<CourseRow>> List(bool includeDeleted,string search="") => includeDeleted
        ? Read("SELECT id,title,description,price,level_id,language_id,is_deleted,updated_at,updated_by_name FROM course_lab.v_course_admin ORDER BY id",Map)
        : Read("SELECT id,title,description,price,level_id,language_id,false,updated_at,updated_by_name FROM course_lab.v_catalog WHERE $1='' OR search_document @@ plainto_tsquery('simple',$1) ORDER BY id",Map,search);
    public async Task<CourseRow?> Get(int id) => (await Read("SELECT id,title,description,price,level_id,language_id,is_deleted,updated_at,updated_by_name FROM course_lab.v_course_admin WHERE id=$1",Map,id)).FirstOrDefault();
    public Task<int> Create(CourseForm f) => NewId("CALL course_lab.course_create($1,$2,$3,$4,$5,$6,NULL::integer)",f.Title,f.Description ?? "",f.Price,f.LevelId,f.LanguageId,f.ActorId);
    public Task Update(CourseForm f) => Execute("CALL course_lab.course_update($1,$2,$3,$4,$5,$6,$7)",f.Id,f.Title,f.Description ?? "",f.Price,f.LevelId,f.LanguageId,f.ActorId);
    public Task Delete(int id,int actor) => Execute("CALL course_lab.course_delete($1,$2)",id,actor);
    public Task Restore(int id,int actor) => Execute("CALL course_lab.course_restore($1,$2)",id,actor);
}
public interface ILessonRepository
{
    Task<List<LessonRow>> List(int course);
    Task Save(int id,int course,string title,string url,int order,int actor);
    Task Delete(int id,int actor);
    Task Restore(int id,int actor);
}
public sealed class LessonRepository(UnitOfWork unit) : Repository(unit), ILessonRepository
{
    public Task<List<LessonRow>> List(int course) => Read("SELECT id,course_id,title,video_url,order_number,is_deleted FROM course_lab.v_lessons WHERE course_id=$1 ORDER BY order_number,id",
        r=>new LessonRow(r.GetInt32(0),r.GetInt32(1),r.GetString(2),r.GetString(3),r.GetInt32(4),r.GetBoolean(5)),course);
    public Task Save(int id,int course,string title,string url,int order,int actor) => Execute("CALL course_lab.lesson_save($1,$2,$3,$4,$5,$6)",id,course,title,url,order,actor);
    public Task Delete(int id,int actor) => Execute("CALL course_lab.lesson_delete($1,$2)",id,actor);
    public Task Restore(int id,int actor) => Execute("CALL course_lab.lesson_restore($1,$2)",id,actor);
}
public interface IEnrollmentRepository
{
    Task<List<EnrollmentRow>> List();
    Task<int> Create(int student,int course,int actor);
    Task<List<ProgressRow>> Progress(int id);
    Task Complete(int enrollment,int lesson,int actor);
    Task Review(int enrollment,int rating,string body,int actor);
    Task DeleteReview(int id,int actor);
    Task IssueCertificate(int enrollment,int actor);
}
public sealed class EnrollmentRepository(UnitOfWork unit) : Repository(unit), IEnrollmentRepository
{
    public Task<List<EnrollmentRow>> List() => Read("SELECT id,customer_id,course_id,student_name,course_title,agreed_price,progress,paid_amount,certificate_number,course_deleted FROM course_lab.v_enrollments ORDER BY id",
        r=>new EnrollmentRow(r.GetInt32(0),r.GetInt32(1),r.GetInt32(2),r.GetString(3),r.GetString(4),r.GetDecimal(5),r.GetDecimal(6),r.IsDBNull(7)?null:r.GetDecimal(7),r.IsDBNull(8)?null:r.GetString(8),r.GetBoolean(9)));
    public Task<int> Create(int student,int course,int actor) => NewId("CALL course_lab.enrollment_create($1,$2,$3,NULL::integer)",student,course,actor);
    public Task<List<ProgressRow>> Progress(int id) => Read("SELECT lesson_id,title,is_completed FROM course_lab.v_progress WHERE enrollment_id=$1 ORDER BY order_number",
        r=>new ProgressRow(r.GetInt32(0),r.GetString(1),r.GetBoolean(2)),id);
    public Task Complete(int enrollment,int lesson,int actor) => Execute("CALL course_lab.progress_complete($1,$2,$3)",enrollment,lesson,actor);
    public Task Review(int enrollment,int rating,string body,int actor) => Execute("CALL course_lab.review_save($1,$2,$3,$4)",enrollment,rating,body,actor);
    public Task DeleteReview(int id,int actor) => Execute("CALL course_lab.review_delete($1,$2)",id,actor);
    public Task IssueCertificate(int enrollment,int actor) => Execute("CALL course_lab.certificate_issue($1,$2)",enrollment,actor);
}
public interface IPaymentRepository { Task Register(int enrollment,decimal amount,int actor); }
public sealed class PaymentRepository(UnitOfWork unit) : Repository(unit), IPaymentRepository
{
    public Task Register(int enrollment,decimal amount,int actor) => Execute("CALL course_lab.payment_register($1,$2,$3)",enrollment,amount,actor);
}
public interface IReportRepository
{
    Task<List<Option>> Students(); Task<List<Option>> Admins(); Task<List<Option>> Levels(); Task<List<Option>> Languages();
    Task<List<HistoryRow>> History(); Task<List<AuditRow>> Audit(); Task<List<ReviewRow>> Reviews(int course);
}
public sealed class ReportRepository(UnitOfWork unit) : Repository(unit), IReportRepository
{
    public Task<List<Option>> Students() => Read("SELECT id,display_name FROM course_lab.v_students ORDER BY id",r=>new Option(r.GetInt32(0),r.GetString(1)));
    public Task<List<Option>> Admins() => Read("SELECT id,display_name FROM course_lab.v_admins ORDER BY id",r=>new Option(r.GetInt32(0),r.GetString(1)));
    public Task<List<Option>> Levels() => Read("SELECT id,name FROM course_lab.v_levels ORDER BY id",r=>new Option(r.GetInt32(0),r.GetString(1)));
    public Task<List<Option>> Languages() => Read("SELECT id,name FROM course_lab.v_languages ORDER BY id",r=>new Option(r.GetInt32(0),r.GetString(1)));
    public Task<List<HistoryRow>> History() => Read("SELECT id,title,old_price,new_price,changed_at,changed_by_name FROM course_lab.v_price_history ORDER BY id DESC",
        r=>new HistoryRow(r.GetInt32(0),r.GetString(1),r.GetDecimal(2),r.GetDecimal(3),r.GetDateTime(4),r.GetString(5)));
    public Task<List<AuditRow>> Audit() => Read("SELECT title,operation,changed_at,changed_by_name,old_data::text,new_data::text FROM course_lab.v_course_history ORDER BY id DESC LIMIT 30",
        r=>new AuditRow(r.GetString(0),r.GetString(1),r.GetDateTime(2),r.GetString(3),r.IsDBNull(4)?null:r.GetString(4),r.GetString(5)));
    public Task<List<ReviewRow>> Reviews(int course) => Read("SELECT id,student_name,rating,body FROM course_lab.v_reviews WHERE course_id=$1 ORDER BY id",r=>new ReviewRow(r.GetInt32(0),r.GetString(1),r.GetInt32(2),r.GetString(3)),course);
}
