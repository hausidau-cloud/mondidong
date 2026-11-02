using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ThermoGuard.Api.Data;
using ThermoGuard.Api.Models;
using ThermoGuard.Api.Services;

namespace ThermoGuard.Api.Controllers;

public class UserCreateRequest
{
    public string username { get; set; } = "sinhvien";
    public string password { get; set; } = "123";
    public string full_name { get; set; } = "Nguyễn Văn Test";
    public string role { get; set; } = "viewer";
    public string? old { get; set; }
    public string? @new { get; set; }
}

public class UserLoginRequest
{
    public string username { get; set; } = "admin";
    public string password { get; set; } = "password123";
}

[ApiController]
[Route("api/auth")]
public class AuthController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly DataStore _store;

    public AuthController(AppDbContext db, DataStore store)
    {
        _db = db;
        _store = store;
    }

    /// <summary>
    /// GET /api/auth: Lấy toàn bộ danh sách tài khoản trong SQL Server (SSMS).
    /// </summary>
    [HttpGet]
    public IActionResult Get([FromQuery] string? action)
    {
        // Nếu App Flutter gọi ?action=me -> trả về tài khoản hiện tại
        if (string.Equals(action, "me", StringComparison.OrdinalIgnoreCase))
        {
            var cur = GetCurrentUser() ?? _db.Users.AsNoTracking().FirstOrDefault();
            return Ok(new
            {
                ok = true,
                user = cur != null ? new
                {
                    id = cur.Id,
                    username = cur.Username,
                    full_name = cur.FullName,
                    role = cur.Role
                } : null
            });
        }

        // Mặc định bấm Try it out trên Swagger -> Trả về tất cả tài khoản trong Database
        var allUsers = _db.Users.AsNoTracking().Select(u => new
        {
            id = u.Id,
            username = u.Username,
            full_name = u.FullName,
            role = u.Role
        }).ToList();

        return Ok(new
        {
            ok = true,
            total = allUsers.Count,
            users = allUsers
        });
    }

    /// <summary>
    /// POST /api/auth: Đăng nhập (nếu ?action=login) hoặc Tạo tài khoản mới lưu trực tiếp vào SQL Server (SSMS)
    /// </summary>
    [HttpPost]
    public IActionResult Post([FromQuery] string? action, [FromBody] UserCreateRequest req)
    {
        // 1. App Flutter đăng nhập bằng POST /api/auth?action=login
        if (string.Equals(action, "login", StringComparison.OrdinalIgnoreCase))
        {
            return LoginInternal(req.username, req.password);
        }

        // 2. Đổi mật khẩu ?action=password
        if (string.Equals(action, "password", StringComparison.OrdinalIgnoreCase))
        {
            var cur = GetCurrentUser();
            if (cur == null) return Unauthorized(new { ok = false, error = "Chưa đăng nhập" });
            var userInDb = _db.Users.Find(cur.Id);
            if (userInDb == null || userInDb.Password != req.old)
            {
                return BadRequest(new { ok = false, error = "Mật khẩu cũ không đúng" });
            }
            if (string.IsNullOrWhiteSpace(req.@new))
            {
                return BadRequest(new { ok = false, error = "Mật khẩu mới không được để trống" });
            }
            userInDb.Password = req.@new.Trim();
            _db.SaveChanges();
            return Ok(new { ok = true, message = "Đổi mật khẩu thành công" });
        }

        // 3. Mặc định trên Swagger POST /api/auth -> Tạo tài khoản mới vào SQL Server (SSMS)
        if (string.IsNullOrWhiteSpace(req.username) || string.IsNullOrWhiteSpace(req.password))
        {
            return BadRequest(new { ok = false, error = "Vui lòng nhập username và password" });
        }

        var uName = req.username.Trim();
        if (_db.Users.Any(u => u.Username.ToLower() == uName.ToLower()))
        {
            return BadRequest(new { ok = false, error = $"Tên đăng nhập '{uName}' đã tồn tại trong SQL Server!" });
        }

        var newUser = new AppUser
        {
            Id = 0,
            Username = uName,
            Password = req.password,
            FullName = string.IsNullOrWhiteSpace(req.full_name) ? uName : req.full_name.Trim(),
            Role = string.IsNullOrWhiteSpace(req.role) ? "viewer" : req.role.Trim().ToLowerInvariant()
        };

        _db.Users.Add(newUser);
        _db.SaveChanges();

        return Ok(new
        {
            ok = true,
            message = $"Đã tạo thành công tài khoản '{newUser.Username}' và lưu vào SQL Server!",
            user = new
            {
                id = newUser.Id,
                username = newUser.Username,
                full_name = newUser.FullName,
                role = newUser.Role
            }
        });
    }

    /// <summary>
    /// POST /api/auth/login: Đăng nhập tài khoản
    /// </summary>
    [HttpPost("login")]
    public IActionResult Login([FromBody] UserLoginRequest req)
    {
        return LoginInternal(req.username, req.password);
    }

    private IActionResult LoginInternal(string username, string password)
    {
        var u = username.Trim().ToLowerInvariant();
        var user = _db.Users.FirstOrDefault(x => x.Username.ToLower() == u && x.Password == password);

        if (user == null)
        {
            return Unauthorized(new { ok = false, error = "Sai tên đăng nhập hoặc mật khẩu" });
        }

        var token = Guid.NewGuid().ToString("N");
        _store.ActiveSessions[token] = user;

        return Ok(new
        {
            ok = true,
            token,
            user = new
            {
                id = user.Id,
                username = user.Username,
                full_name = user.FullName,
                role = user.Role
            }
        });
    }

    private string? GetBearerToken()
    {
        var authHeader = Request.Headers.Authorization.ToString();
        if (authHeader.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
        {
            return authHeader["Bearer ".Length..].Trim();
        }
        return null;
    }

    private AppUser? GetCurrentUser()
    {
        var token = GetBearerToken();
        if (!string.IsNullOrEmpty(token) && _store.ActiveSessions.TryGetValue(token, out var user))
        {
            return user;
        }
        return null;
    }
}
