using Microsoft.EntityFrameworkCore;
using Microsoft.OpenApi.Models;
using Swashbuckle.AspNetCore.SwaggerGen;
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
builder.Services.AddSingleton<SmsService>();
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
    c.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = "ThermoGuard IoT API (C# .NET 9 + MySQL / SQL Server)",
        Version = "v1",
        Description = "API Backend cho trạm giám sát Raspberry Pi Pico 2 W và App di động Flutter"
    });
    c.DocumentFilter<SwaggerTagOrderFilter>();
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

// Redirect root "/" to "/swagger" so opening browser immediately shows Swagger (ẩn khỏi tài liệu Swagger)
app.MapGet("/", () => Results.Redirect("/swagger")).ExcludeFromDescription();

app.MapControllers();

Console.WriteLine("==================================================================");
Console.WriteLine(">> BACKEND C# (.NET 9) THERMOGUARD IOT KHOI DONG THANH CONG!");
Console.WriteLine(">> Database: " + (dbConn.Contains("clever-cloud") ? "Clever Cloud MySQL" : "SQL Server / SQLite"));
Console.WriteLine(">> Server dang lang nghe tren cong: " + (portEnv ?? "5000"));
Console.WriteLine("==================================================================");

app.Run();

/// <summary>
/// Bộ lọc sắp xếp danh mục API trên Swagger theo đúng thứ tự logic người dùng yêu cầu:
/// Auth -> Users -> Stations -> Devices -> Control -> Alerts -> Readings -> Ingest -> Time
/// </summary>
public class SwaggerTagOrderFilter : IDocumentFilter
{
    private static readonly string[] TagOrder =
    {
        "Auth",
        "Users",
        "Stations",
        "Devices",
        "Control",
        "Alerts",
        "Readings",
        "Ingest",
        "Time"
    };

    public void Apply(OpenApiDocument swaggerDoc, DocumentFilterContext context)
    {
        var tagDescriptions = new Dictionary<string, string>
        {
            ["Auth"] = "Xác thực tài khoản, kiểm tra phiên đăng nhập & đổi mật khẩu",
            ["Users"] = "Quản lý danh sách nhân sự (Viewer/Admin) & phân công trạm",
            ["Stations"] = "Quản lý trạm giám sát môi trường & nhân viên phụ trách",
            ["Devices"] = "Danh sách thiết bị phần cứng IoT (Pico 2 W / ESP32)",
            ["Control"] = "Điều khiển Relay (Bơm/Quạt/Sưởi), cài đặt ngưỡng & tin nhắn OLED",
            ["Alerts"] = "Lịch sử cảnh báo vượt ngưỡng & xác nhận xử lý sự cố",
            ["Readings"] = "Lịch sử dữ liệu cảm biến thời gian thực & dữ liệu vẽ biểu đồ",
            ["Ingest"] = "Cổng nạp dữ liệu tự động từ vi điều khiển IoT (HMAC-SHA256)",
            ["Time"] = "Đồng bộ thời gian chuẩn cho phần cứng (RTC Sync)"
        };

        swaggerDoc.Tags = TagOrder
            .Select(name => new OpenApiTag
            {
                Name = name,
                Description = tagDescriptions.TryGetValue(name, out var desc) ? desc : null
            })
            .ToList();

        // Sắp xếp lại danh sách Paths theo đúng thứ tự Tag
        var orderedPaths = new OpenApiPaths();
        foreach (var tag in TagOrder)
        {
            foreach (var path in swaggerDoc.Paths)
            {
                var match = path.Value.Operations.Values.Any(op => op.Tags.Any(t => t.Name == tag));
                if (match && !orderedPaths.ContainsKey(path.Key))
                {
                    orderedPaths.Add(path.Key, path.Value);
                }
            }
        }
        foreach (var path in swaggerDoc.Paths)
        {
            if (!orderedPaths.ContainsKey(path.Key))
            {
                orderedPaths.Add(path.Key, path.Value);
            }
        }
        swaggerDoc.Paths = orderedPaths;
    }
}
