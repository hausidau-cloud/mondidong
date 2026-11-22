using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Mvc;
using ThermoGuard.Api.Models;
using ThermoGuard.Api.Services;

namespace ThermoGuard.Api.Controllers;

[ApiController]
[Tags("Team Messages & Incident Reports")]
[Route("api/messages")]
public class MessagesController : ControllerBase
{
    private readonly DataStore _store;

    public MessagesController(DataStore store)
    {
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
    /// GET /api/messages: Lấy danh sách tin nhắn trao đổi & báo cáo sự cố (toàn hệ thống hoặc theo từng trạm)
    /// </summary>
    [HttpGet]
    public IActionResult GetMessages([FromQuery] int? station_id, [FromQuery] int limit = 50)
    {
        var list = _store.GetTeamMessages(station_id, limit <= 0 ? 50 : Math.Min(limit, 200));
        return Ok(new
        {
            ok = true,
            total = list.Count,
            messages = list
        });
    }

    /// <summary>
    /// POST /api/messages: Gửi tin nhắn trao đổi hoặc báo cáo sự cố vi khí hậu giữa các kỹ thuật viên / quản trị viên
    /// </summary>
    [HttpPost]
    public IActionResult SendMessage([FromBody] JsonObject? body)
    {
        var curUser = GetCurrentUser();
        if (curUser == null)
        {
            return Unauthorized(new { ok = false, error = "Vui lòng đăng nhập để gửi tin nhắn" });
        }

        var content = body?["content"]?.ToString().Trim();
        if (string.IsNullOrWhiteSpace(content))
        {
            return BadRequest(new { ok = false, error = "Nội dung tin nhắn không được để trống" });
        }

        int? stId = null;
        if (body?["station_id"] != null && int.TryParse(body["station_id"]!.ToString(), out int parsedStId))
        {
            stId = parsedStId;
        }

        string? stName = null;
        if (stId.HasValue && stId.Value > 0)
        {
            var st = _store.GetStation(stId.Value);
            var dev = _store.Devices.FirstOrDefault(d => d.StationId == stId.Value) ?? _store.GetDevice(stId.Value);
            stName = st?.Name ?? dev?.Name ?? $"Trạm #{stId.Value}";
        }

        var category = body?["category"]?.ToString().ToUpperInvariant() ?? "CHAT";
        if (category != "CHAT" && category != "INCIDENT" && category != "MAINTENANCE" && category != "RESOLVED")
        {
            category = "CHAT";
        }

        var telemetry = body?["attached_telemetry"]?.ToString()?.Trim();
        var imageUrl = body?["image_url"]?.ToString()?.Trim();

        var newMsg = new TeamMessage
        {
            UserId = curUser.Id,
            SenderName = curUser.FullName,
            SenderRole = curUser.Role,
            StationId = stId,
            StationName = stName,
            Category = category,
            Content = content,
            AttachedTelemetry = string.IsNullOrWhiteSpace(telemetry) ? null : telemetry,
            ImageUrl = string.IsNullOrWhiteSpace(imageUrl) ? null : imageUrl,
        };

        var created = _store.AddTeamMessage(newMsg);

        return Ok(new
        {
            ok = true,
            message = "Gửi tin nhắn thành công",
            data = created
        });
    }

    /// <summary>
    /// DELETE /api/messages/{id}: Xóa tin nhắn (Admin hoặc chính người gửi)
    /// </summary>
    [HttpDelete("{id}")]
    public IActionResult DeleteMessage(int id)
    {
        var curUser = GetCurrentUser();
        if (curUser == null)
        {
            return Unauthorized(new { ok = false, error = "Vui lòng đăng nhập" });
        }

        bool isAdmin = curUser.Role == "admin";
        bool success = _store.DeleteTeamMessage(id, curUser.Id, isAdmin);

        if (!success)
        {
            return BadRequest(new { ok = false, error = "Không tìm thấy tin nhắn hoặc bạn không có quyền xóa" });
        }

        return Ok(new
        {
            ok = true,
            message = "Đã xóa tin nhắn"
        });
    }
}
