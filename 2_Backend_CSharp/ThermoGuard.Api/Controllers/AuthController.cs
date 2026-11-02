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
    public List<int>? station_ids { get; set; }
}

public class UpdateStationsRequest
{
    public List<int> station_ids { get; set; } = new();
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
    /// GET /api/auth: Lấy toàn bộ danh sách tài khoản trong SQL Server kèm trạm phụ trách.
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
                    role = cur.Role,
                    station_ids = _store.GetStationIdsForUser(cur.Id)
                } : null
            });
        }

        // Mặc định bấm Try it out trên Swagger -> Trả về tất cả tài khoản trong Database kèm trạm
        var allUsers = _db.Users.AsNoTracking().ToList().Select(u => new
        {
            id = u.Id,
            username = u.Username,
            full_name = u.FullName,
            role = u.Role,
            station_ids = _store.GetStationIdsForUser(u.Id)
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

        // Đồng bộ vào DataStore in-memory
        _store.Users.RemoveAll(u => u.Id == newUser.Id);
        _store.Users.Add(newUser);

        // Gán trạm nếu có truyền station_ids
        if (req.station_ids != null && req.station_ids.Count > 0)
        {
            _store.SetUserStations(newUser.Id, req.station_ids, _db);
        }

        return Ok(new
        {
            ok = true,
            message = $"Đã tạo thành công tài khoản '{newUser.Username}' và phân công trạm!",
            user = new
            {
                id = newUser.Id,
                username = newUser.Username,
                full_name = newUser.FullName,
                role = newUser.Role,
                station_ids = _store.GetStationIdsForUser(newUser.Id)
            }
        });
    }

    /// <summary>
    /// DELETE /api/auth/users/{id} hoặc DELETE /api/users/{id}: Xóa tài khoản nhân viên (Admin only)
    /// </summary>
    [HttpDelete("users/{id}")]
    [HttpDelete("/api/users/{id}")]
    public IActionResult DeleteUser(int id)
    {
        var cur = GetCurrentUser();
        if (cur != null && cur.Role != "admin") return Forbid();

        var target = _db.Users.Find(id);
        if (target == null) return NotFound(new { ok = false, error = "Không tìm thấy người dùng" });
        if (target.Id == 1 || string.Equals(target.Username, "admin", StringComparison.OrdinalIgnoreCase))
        {
            return BadRequest(new { ok = false, error = "Không thể xóa tài khoản Quản trị viên tối cao!" });
        }

        _db.Users.Remove(target);
        var assigns = _db.StationAssignments.Where(a => a.UserId == id).ToList();
        _db.StationAssignments.RemoveRange(assigns);
        _db.SaveChanges();

        _store.Users.RemoveAll(u => u.Id == id);
        _store.Assignments.RemoveAll(a => a.UserId == id);

        return Ok(new { ok = true, message = $"Đã xóa thành công người dùng '{target.Username}'" });
    }

    /// <summary>
    /// GET /api/users/{id}/stations: Xem danh sách các trạm nhân viên {id} đang phụ trách
    /// </summary>
    [HttpGet("/api/users/{id}/stations")]
    public IActionResult GetUserStations(int id)
    {
        var stationIds = _store.GetStationIdsForUser(id);
        var stations = _store.Devices.Where(d => stationIds.Contains(d.Id)).Select(d => new
        {
            id = d.Id,
            device_code = d.DeviceCode,
            name = d.Name,
            location = d.Location,
            status = d.Status,
            online = d.Online,
            relay_label = d.RelayLabel,
            relay_state = d.RelayState
        }).ToList();

        return Ok(new { ok = true, user_id = id, total = stations.Count, stations });
    }

    /// <summary>
    /// PUT /api/users/{id}/stations: Cập nhật danh sách trạm phân công cho nhân viên {id} (Admin only)
    /// </summary>
    [HttpPut("/api/users/{id}/stations")]
    public IActionResult UpdateUserStations(int id, [FromBody] UpdateStationsRequest req)
    {
        var cur = GetCurrentUser();
        if (cur != null && cur.Role != "admin") return Forbid();

        var target = _db.Users.Find(id);
        if (target == null) return NotFound(new { ok = false, error = "Không tìm thấy người dùng" });

        _store.SetUserStations(id, req.station_ids ?? new List<int>(), _db);
        return Ok(new
        {
            ok = true,
            message = $"Đã cập nhật phân công trạm cho '{target.Username}'",
            station_ids = _store.GetStationIdsForUser(id)
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
                role = user.Role,
                station_ids = _store.GetStationIdsForUser(user.Id)
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

