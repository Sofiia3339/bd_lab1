using Npgsql;
namespace CourseManagementLab.Data;

public interface IUnitOfWork : IAsyncDisposable
{
    ICourseRepository Courses { get; }
    ILessonRepository Lessons { get; }
    IEnrollmentRepository Enrollments { get; }
    IPaymentRepository Payments { get; }
    IReportRepository Reports { get; }
    Task Begin(); Task Commit(); Task Rollback();
}
public sealed class UnitOfWork : IUnitOfWork
{
    private readonly NpgsqlDataSource source;
    private NpgsqlConnection? connection;
    internal NpgsqlTransaction? Transaction { get; private set; }
    public ICourseRepository Courses { get; }
    public ILessonRepository Lessons { get; }
    public IEnrollmentRepository Enrollments { get; }
    public IPaymentRepository Payments { get; }
    public IReportRepository Reports { get; }
    public UnitOfWork(NpgsqlDataSource source)
    {
        this.source=source;
        Courses=new CourseRepository(this); Lessons=new LessonRepository(this);
        Enrollments=new EnrollmentRepository(this); Payments=new PaymentRepository(this); Reports=new ReportRepository(this);
    }
    internal async Task<NpgsqlConnection> Connection() => connection ??= await source.OpenConnectionAsync();
    public async Task Begin()
    {
        if(Transaction is not null) throw new InvalidOperationException("Транзакція вже відкрита");
        Transaction=await (await Connection()).BeginTransactionAsync();
    }
    public async Task Commit()
    {
        if(Transaction is null) throw new InvalidOperationException("Немає відкритої транзакції");
        await Transaction.CommitAsync();
        await Transaction.DisposeAsync(); Transaction=null;
    }
    public async Task Rollback()
    {
        if(Transaction is null) return;
        try { await Transaction.RollbackAsync(); }
        finally { await Transaction.DisposeAsync(); Transaction=null; }
    }
    public async ValueTask DisposeAsync()
    {
        await Rollback();
        if(connection is not null) await connection.DisposeAsync();
    }
}
