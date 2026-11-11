using Microsoft.AspNetCore.Mvc;
using Npgsql;
using CourseManagementLab.Data;
using CourseManagementLab.Models;
using CourseManagementLab.Services;
namespace CourseManagementLab.Controllers;

public sealed class SchoolController(IUnitOfWork unit, SchoolService service) : Controller
{
    public async Task<IActionResult> Index(bool showDeleted=false,string search="")
    {
        return View(new Dashboard { Courses=await unit.Courses.List(showDeleted,search),
            Students=await unit.Reports.Students(),Admins=await unit.Reports.Admins(),
            Enrollments=await unit.Enrollments.List(),History=await unit.Reports.History(),Audit=await unit.Reports.Audit(),
            ShowDeleted=showDeleted,Search=search });
    }
    public async Task<IActionResult> Edit(int id=0)
    {
        var form=new CourseForm();
        if(id!=0)
        {
            var c=await unit.Courses.Get(id); if(c is null) return NotFound();
            if(c.IsDeleted) { TempData["Error"]="Спочатку відновіть курс."; return RedirectToAction(nameof(Index)); }
            form=new CourseForm { Id=c.Id,Title=c.Title,Description=c.Description,Price=c.Price,LevelId=c.LevelId,LanguageId=c.LanguageId };
        }
        await FormOptions(); return View(form);
    }
    private async Task FormOptions()
    {
        ViewBag.Levels=await unit.Reports.Levels(); ViewBag.Languages=await unit.Reports.Languages(); ViewBag.Admins=await unit.Reports.Admins();
    }
    [HttpPost]
    public async Task<IActionResult> Save(CourseForm form)
    {
        if(ModelState.IsValid)
        {
            try
            {
                if(form.Id==0) await unit.Courses.Create(form); else await unit.Courses.Update(form);
                TempData["Success"]="Курс збережено. Дата, автор та історія оновлені в базі даних.";
                return RedirectToAction(nameof(Index));
            }
            catch(PostgresException e) { ModelState.AddModelError("",e.MessageText); }
        }
        await FormOptions(); return View("Edit",form);
    }
    public async Task<IActionResult> Course(int id)
    {
        var course=await unit.Courses.Get(id); if(course is null) return NotFound();
        return View(new CoursePage { Course=course,Lessons=await unit.Lessons.List(id),Reviews=await unit.Reports.Reviews(id),Admins=await unit.Reports.Admins() });
    }
    public async Task<IActionResult> Enrollment(int id)
    {
        var enrollment=(await unit.Enrollments.List()).FirstOrDefault(e=>e.Id==id); if(enrollment is null) return NotFound();
        return View(new EnrollmentPage { Enrollment=enrollment,Lessons=await unit.Enrollments.Progress(id),Admins=await unit.Reports.Admins() });
    }
    private async Task<IActionResult> Change(Func<Task> action,string message,string destination="Index",int? id=null)
    {
        if(!ModelState.IsValid) { TempData["Error"]="Перевірте введені значення."; return RedirectToAction(destination,new {id}); }
        try { await action(); TempData["Success"]=message; }
        catch(PostgresException e) { TempData["Error"]=e.MessageText; }
        return RedirectToAction(destination,new {id});
    }
    [HttpPost] public Task<IActionResult> Delete(int id,int actorId) => Change(()=>unit.Courses.Delete(id,actorId),"Курс логічно видалено.");
    [HttpPost] public Task<IActionResult> Restore(int id,int actorId) => Change(()=>unit.Courses.Restore(id,actorId),"Курс відновлено.");
    [HttpPost] public Task<IActionResult> LessonSave(int id,int courseId,string title,string? videoUrl,int orderNumber,int actorId) =>
        Change(()=>unit.Lessons.Save(id,courseId,title??"",videoUrl??"",orderNumber,actorId),"Урок збережено.","Course",courseId);
    [HttpPost] public Task<IActionResult> LessonDelete(int id,int courseId,int actorId) => Change(()=>unit.Lessons.Delete(id,actorId),"Урок логічно видалено.","Course",courseId);
    [HttpPost] public Task<IActionResult> LessonRestore(int id,int courseId,int actorId) => Change(()=>unit.Lessons.Restore(id,actorId),"Урок відновлено.","Course",courseId);
    [HttpPost] public Task<IActionResult> Enroll(int studentId,int courseId,decimal amount,int actorId) =>
        Change(async()=>{ await service.EnrollAndPay(studentId,courseId,amount,actorId); },"Запис і оплату збережено однією транзакцією.");
    [HttpPost] public Task<IActionResult> Complete(int id,int lessonId,int actorId) => Change(()=>unit.Enrollments.Complete(id,lessonId,actorId),"Урок позначено виконаним.","Enrollment",id);
    [HttpPost] public Task<IActionResult> Review(int id,int rating,string body,int actorId) => Change(()=>unit.Enrollments.Review(id,rating,body??"",actorId),"Відгук збережено.","Enrollment",id);
    [HttpPost] public Task<IActionResult> ReviewDelete(int id,int courseId,int actorId) => Change(()=>unit.Enrollments.DeleteReview(id,actorId),"Відгук логічно видалено.","Course",courseId);
    [HttpPost] public Task<IActionResult> Certificate(int id,int actorId) => Change(()=>unit.Enrollments.IssueCertificate(id,actorId),"Сертифікат видано.","Enrollment",id);
    public IActionResult Error() => View();
}
