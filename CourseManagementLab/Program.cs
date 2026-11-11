using System.Globalization;
using Npgsql;
using CourseManagementLab.Data;
using CourseManagementLab.Services;

CultureInfo.DefaultThreadCurrentCulture = CultureInfo.InvariantCulture;
CultureInfo.DefaultThreadCurrentUICulture = CultureInfo.InvariantCulture;
var builder = WebApplication.CreateBuilder(args);
builder.Services.AddControllersWithViews(options =>
    options.Filters.Add(new Microsoft.AspNetCore.Mvc.AutoValidateAntiforgeryTokenAttribute()));
builder.Services.AddSingleton(_ => NpgsqlDataSource.Create(builder.Configuration.GetConnectionString("DefaultConnection")!));
builder.Services.AddScoped<IUnitOfWork, UnitOfWork>();
builder.Services.AddScoped<SchoolService>();
var app = builder.Build();
app.UseExceptionHandler("/School/Error");
app.UseStaticFiles();
app.UseRouting();
app.MapControllerRoute("default", "{controller=School}/{action=Index}/{id?}");
app.Run();
