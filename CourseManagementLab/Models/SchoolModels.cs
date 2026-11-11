using System.ComponentModel.DataAnnotations;
namespace CourseManagementLab.Models;

public record Option(int Id, string Name);
public record CourseRow(int Id, string Title, string Description, decimal Price, int LevelId, int LanguageId,
    bool IsDeleted, DateTime UpdatedAt, string UpdatedBy);
public record LessonRow(int Id, int CourseId, string Title, string VideoUrl, int OrderNumber, bool IsDeleted);
public record EnrollmentRow(int Id, int CustomerId, int CourseId, string StudentName, string CourseTitle,
    decimal AgreedPrice, decimal Progress, decimal? PaidAmount, string? CertificateNumber, bool CourseDeleted);
public record ProgressRow(int LessonId, string Title, bool IsCompleted);
public record HistoryRow(int Id, string Title, decimal OldPrice, decimal NewPrice, DateTime ChangedAt, string ChangedBy);
public record AuditRow(string Title, string Operation, DateTime ChangedAt, string ChangedBy, string? OldData, string NewData);
public record ReviewRow(int Id, string StudentName, int Rating, string Body);
public class CourseForm
{
    public int Id { get; set; }
    [Required, StringLength(200)] public string Title { get; set; } = "";
    public string Description { get; set; } = "";
    [Range(typeof(decimal), "0", "99999999.99")] public decimal Price { get; set; }
    [Range(1, int.MaxValue)] public int LevelId { get; set; } = 1;
    [Range(1, int.MaxValue)] public int LanguageId { get; set; } = 1;
    [Range(1, int.MaxValue)] public int ActorId { get; set; } = 1;
}
public class Dashboard
{
    public List<CourseRow> Courses { get; set; } = [];
    public List<Option> Students { get; set; } = [];
    public List<Option> Admins { get; set; } = [];
    public List<EnrollmentRow> Enrollments { get; set; } = [];
    public List<HistoryRow> History { get; set; } = [];
    public List<AuditRow> Audit { get; set; } = [];
    public bool ShowDeleted { get; set; }
    public string? Search { get; set; }
}
public class CoursePage
{
    public CourseRow Course { get; set; } = null!;
    public List<LessonRow> Lessons { get; set; } = [];
    public List<ReviewRow> Reviews { get; set; } = [];
    public List<Option> Admins { get; set; } = [];
}
public class EnrollmentPage
{
    public EnrollmentRow Enrollment { get; set; } = null!;
    public List<ProgressRow> Lessons { get; set; } = [];
    public List<Option> Admins { get; set; } = [];
}
