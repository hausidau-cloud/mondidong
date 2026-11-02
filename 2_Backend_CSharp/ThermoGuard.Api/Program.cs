using Microsoft.EntityFrameworkCore;
using ThermoGuard.Api.Data;
using ThermoGuard.Api.Services;

var builder = WebApplication.CreateBuilder(args);

// 1. Configure Kestrel to bind to dynamic PORT on Render (e.g. 10000) or 5000 locally
var portEnv = Environment.GetEnvironmentVariable("PORT");
builder.WebHost.ConfigureKestrel(options =>
{
    if (int.TryParse(portEnv, out var p))
    {
        options.ListenAnyIP(p);
    }
    else
    {
        options.ListenAnyIP(5000);
    }
});

// 2. Add Database Context: Support Clever Cloud MySQL, SQL Server SSMS, or SQLite fallback
var dbConn = builder.Configuration.GetConnectionString("DefaultConnection") 
    ?? Environment.GetEnvironmentVariable("MYSQL_CONN")
    ?? "Server=bol191hl1ezyl283t0tu-mysql.services.clever-cloud.com;Port=3306;Database=bol191hl1ezyl283t0tu;User=ulz3u54vgqg5l4vb;Password=G5Xlv1ibNHAhlx5blRZs;";

builder.Services.AddDbContext<AppDbContext>(options =>
{
    try
    {
        if (dbConn.Contains("3306") || dbConn.Contains("clever-cloud") || dbConn.Contains("User=") || dbConn.Contains("uid="))
        {
            options.UseMySql(dbConn, new MySqlServerVersion(new Version(8, 0, 36)), mySqlOptions =>
            {
                mySqlOptions.EnableRetryOnFailure(3, TimeSpan.FromSeconds(5), null);
            });
        }
        else if (dbConn.Contains("Trusted_Connection") || dbConn.Contains("TrustServerCertificate"))
        {
            options.UseSqlServer(dbConn);
        }
        else
        {
            options.UseSqlite("Data Source=thermoguard.db");
        }
    }
    catch
    {
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
        Title = "ThermoGuard IoT API (C# .NET 9 + MySQL / SQL Server)",
        Version = "v1",
        Description = "API Backend cho trạm giám sát Raspberry Pi Pico 2 W và App di động Flutter"
    });
});

var app = builder.Build();

// 6. Tự động kiểm tra & khởi tạo Database
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    try
    {
        db.Database.EnsureCreated();
        Console.WriteLine(">> Da kiem tra & khoi tao Database thanh cong!");
    }
    catch (Exception ex)
    {
        Console.WriteLine(">> Note Database EnsureCreated: " + ex.Message);
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
Console.WriteLine(">> BACKEND C# (.NET 9) THERMOGUARD IOT KHOI DONG THANH CONG!");
Console.WriteLine(">> Database: " + (dbConn.Contains("clever-cloud") ? "Clever Cloud MySQL" : "SQL Server / SQLite"));
Console.WriteLine(">> Server dang lang nghe tren cong: " + (portEnv ?? "5000"));
Console.WriteLine("==================================================================");

app.Run();
