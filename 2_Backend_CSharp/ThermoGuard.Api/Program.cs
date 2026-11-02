using Microsoft.EntityFrameworkCore;
using ThermoGuard.Api.Data;
using ThermoGuard.Api.Services;

var builder = WebApplication.CreateBuilder(args);

// 1. Configure Kestrel to bind to all network interfaces on port 5000 (HTTP)
// This allows Raspberry Pi Pico 2 W, Android emulator, and Flutter Web to connect via LAN IP
builder.WebHost.ConfigureKestrel(options =>
{
    options.ListenAnyIP(5000);
});

// 2. Add SQL Server Database Context (SSMS) with SQLite fallback
var sqlServerConn = builder.Configuration.GetConnectionString("DefaultConnection") 
    ?? "Server=.;Database=ThermoGuardDB;Trusted_Connection=True;TrustServerCertificate=True;";

builder.Services.AddDbContext<AppDbContext>(options =>
{
    try
    {
        options.UseSqlServer(sqlServerConn);
    }
    catch
    {
        // Fallback to SQLite if SQL Server is not running
        options.UseSqlite("Data Source=thermoguard.db");
    }
});

// 3. Add services to container
builder.Services.AddSingleton<DataStore>();
builder.Services.AddHostedService<DeviceWatchdogWorker>();

builder.Services.AddControllers()
    .AddJsonOptions(options =>
    {
        options.JsonSerializerOptions.PropertyNamingPolicy = null;
    });

// 4. Add CORS to allow requests from Flutter (Web & Mobile)
builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowAll", policy =>
    {
        policy.AllowAnyOrigin()
              .AllowAnyMethod()
              .AllowAnyHeader();
    });
});

// 5. Swagger UI for automatic browser launch
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new()
    {
        Title = "ThermoGuard IoT API (C# .NET 9 + SQL Server)",
        Version = "v1",
        Description = "API Backend cho trạm giám sát Raspberry Pi Pico 2 W và App di động Flutter"
    });
});

var app = builder.Build();

// 6. Tự động tạo Database ThermoGuardDB trên SQL Server (SSMS) và seed dữ liệu nếu chưa có
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    try
    {
        db.Database.EnsureCreated();
        Console.WriteLine(">> Da kiem tra & khoi tao Database ThermoGuardDB tren SQL Server thanh cong!");
    }
    catch (Exception ex)
    {
        Console.WriteLine(">> Note SQL Server: " + ex.Message);
    }
}

// 7. Configure HTTP request pipeline
app.UseCors("AllowAll");

// Kích hoạt Swagger UI
app.UseSwagger();
app.UseSwaggerUI(c =>
{
    c.SwaggerEndpoint("/swagger/v1/swagger.json", "ThermoGuard API v1");
    c.RoutePrefix = "swagger";
});

// Redirect root "/" to "/swagger" so opening browser immediately shows Swagger
app.MapGet("/", () => Results.Redirect("/swagger"));

app.MapControllers();

Console.WriteLine("==================================================================");
Console.WriteLine(">> BACKEND C# (.NET 9 + SQL SERVER) THERMOGUARD IOT KHOI DONG THANH CONG!");
Console.WriteLine(">> Database SQL Server: ThermoGuardDB (Xem tren SSMS server '.')");
Console.WriteLine(">> Server dang lang nghe tren cong: HTTP 5000 (All IPs: 0.0.0.0:5000)");
Console.WriteLine(">> Giao dien Swagger API: http://localhost:5000/swagger");
Console.WriteLine("==================================================================");

app.Run();
