using CourseManagementLab.Data;
namespace CourseManagementLab.Services;

public sealed class SchoolService(IUnitOfWork unit)
{
    public async Task<int> EnrollAndPay(int student,int course,decimal amount,int actor)
    {
        await unit.Begin();
        try
        {
            int enrollment=await unit.Enrollments.Create(student,course,actor);
            await unit.Payments.Register(enrollment,amount,actor);
            await unit.Commit();
            return enrollment;
        }
        catch
        {
            await unit.Rollback();
            throw;
        }
    }
}
