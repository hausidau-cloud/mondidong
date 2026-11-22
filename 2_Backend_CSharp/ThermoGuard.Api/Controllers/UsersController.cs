using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ThermoGuard.Api.Data;
using ThermoGuard.Api.Models;
using ThermoGuard.Api.Services;

namespace ThermoGuard.Api.Controllers;

[ApiController]
[Tags("Users")]
[Route("api/users")]
public class UsersController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly DataStore _store;

    public UsersController(AppDbContext db, DataStore store)
    {
        _db = db;
        _store = store;
    }

    private AppUser? GetCurrentUser()
    {
        var authHeader = Request.Headers.Authorization.ToString();
        if (authHeader.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
        {
            var token = authHeader["Bearer ".Length..].Trim();
            if (_store.ActiveSessions.TryGetValue(token, out var user)) return user;
        }
        return null;
    }

    /// <summary>
    /// GET /api/users: Lấy danh sách toàn bộ nhân sự kèm danh sách trạm phụ trách
    /// </summary>
    [HttpGet]
    public IActionResult GetAll()
    {
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
    /// POST /api/users: Thêm nhân viên mới (Viewer) và gán trạm giám sát ngay tại form
    /// </summary>
    [HttpPost]
    public IActionResult CreateUser([FromBody] UserCreateRequest req)
    {
        var cur = GetCurrentUser();
        if (cur != null && cur.Role != "admin") return Forbid();

        if (string.IsNullOrWhiteSpace(req.username) || string.IsNullOrWhiteSpace(req.password))
        {
            return BadRequest(new { ok = false, error = "Vui lòng nhập username và password" });
        }

        var uName = req.username.Trim();
        if (_db.Users.Any(u => u.Username.ToLower() == uName.ToLower()))
        {
            return BadRequest(new { ok = false, error = $"Tên đăng nhập '{uName}' đã tồn tại!" });
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

        _store.Users.RemoveAll(u => u.Id == newUser.Id);
        _store.Users.Add(newUser);

        if (req.station_ids != null && req.station_ids.Count > 0)
        {
            _store.SetUserStations(newUser.Id, req.station_ids, _db);
        }

        return Ok(new
        {
            ok = true,
            message = $"Đã tạo thành công nhân viên '{newUser.Username}' và phân công trạm!",
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
    /// GET /api/users/{id}/stations: Xem danh sách các trạm nhân viên {id} đang phụ trách
    /// </summary>
    [HttpGet("{id}/stations")]
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
    /// PUT /api/users/{id}/stations: Đổi danh sách trạm phân công cho nhân viên {id} (Admin only)
    /// </summary>
    [HttpPut("{id}/stations")]
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
    /// DELETE /api/users/{id}: Xóa tài khoản nhân viên (Admin only)
    /// </summary>
    [HttpDelete("{id}")]
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

        return Ok(new { ok = true, message = $"Đã xóa thành công nhân viên '{target.Username}'" });
    }

    /// <summary>
    /// PUT /api/users/profile: Cập nhật email nhận cảnh báo và họ tên của tài khoản hiện tại
    /// </summary>
    [HttpPut("profile")]
    public IActionResult UpdateProfile([FromBody] System.Text.Json.Nodes.JsonObject? body)
    {
        var cur = GetCurrentUser();
        if (cur == null) return Unauthorized(new { ok = false, error = "Vui lòng đăng nhập" });

        var email = body?["email"]?.ToString().Trim();
        var fullName = body?["full_name"]?.ToString().Trim();

        var dbUser = _db.Users.Find(cur.Id);
        if (dbUser != null)
        {
            if (!string.IsNullOrWhiteSpace(email)) dbUser.Email = email;
            if (!string.IsNullOrWhiteSpace(fullName)) dbUser.FullName = fullName;
            _db.SaveChanges();
        }

        var storeUser = _store.Users.FirstOrDefault(u => u.Id == cur.Id);
        if (storeUser != null)
        {
            if (!string.IsNullOrWhiteSpace(email)) storeUser.Email = email;
            if (!string.IsNullOrWhiteSpace(fullName)) storeUser.FullName = fullName;
        }

        if (!string.IsNullOrWhiteSpace(email)) cur.Email = email;
        if (!string.IsNullOrWhiteSpace(fullName)) cur.FullName = fullName;

        return Ok(new
        {
            ok = true,
            message = "Cập nhật thông tin nhận thông báo thành công",
            user = cur
        });
    }

    /// <summary>
    /// POST /api/users/test-alert-email: Gửi email cảnh báo vi phạm ngưỡng thử nghiệm tới Gmail
    /// </summary>
    [HttpPost("test-alert-email")]
    public async Task<IActionResult> TestAlertEmail([FromServices] EmailService emailService, [FromBody] System.Text.Json.Nodes.JsonObject? body)
    {
        var cur = GetCurrentUser();
        var targetEmail = body?["email"]?.ToString()?.Trim() ?? cur?.Email;

        if (string.IsNullOrWhiteSpace(targetEmail) || !targetEmail.Contains("@"))
        {
            return BadRequest(new { ok = false, error = "Vui lòng cung cấp địa chỉ Gmail hợp lệ để nhận cảnh báo" });
        }

        var (ok, msg) = await emailService.SendAlertEmailAsync(
            targetEmail,
            cur?.FullName ?? "Quản trị viên",
            "Trạm Giám Sát Phòng Lab (PICO-01)",
            "DANGER",
            "HOT",
            "Nhiệt độ phòng vượt ngưỡng an toàn: 41.5°C (Ngưỡng tối đa cho phép: 40.0°C)!",
            41.5,
            78.0,
            TimeHelper.VnNowStr
        );

        return Ok(new { ok, message = msg });
    }
}
