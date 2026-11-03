using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Mvc;
using ThermoGuard.Api.Models;
using ThermoGuard.Api.Services;

namespace ThermoGuard.Api.Controllers;

[ApiController]
[Tags("Alerts")]
[Route("api/alerts")]
public class AlertsController : ControllerBase
{
    private readonly DataStore _store;

    public AlertsController(DataStore store)
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

    [HttpGet]
    public IActionResult Get([FromQuery] string? state, [FromQuery] string? level, [FromQuery] int? device_id, [FromQuery] int page = 1)
    {
        var curUser = GetCurrentUser();
        if (curUser == null)
        {
            return Unauthorized(new { ok = false, error = "Vui lòng đăng nhập để xem thông báo cảnh báo." });
        }

        var isViewer = curUser.Role == "viewer";
        List<int>? allowedStationIds = null;
        HashSet<int>? allowedDeviceIds = null;

        if (isViewer)
        {
            allowedStationIds = _store.GetStationIdsForUser(curUser.Id);
            allowedDeviceIds = _store.Devices
                .Where(d => allowedStationIds.Contains(d.Id) || (d.StationId.HasValue && allowedStationIds.Contains(d.StationId.Value)))
                .Select(d => d.Id)
                .ToHashSet();

            foreach (var sid in allowedStationIds)
            {
                allowedDeviceIds.Add(sid);
            }
        }

        var list = _store.Alerts.AsEnumerable();

        if (isViewer && allowedDeviceIds != null)
        {
            list = list.Where(a => allowedDeviceIds.Contains(a.DeviceId));
        }

        if (device_id.HasValue)
        {
            var targetDevice = _store.GetDevice(device_id.Value) ?? _store.Devices.FirstOrDefault(d => d.StationId == device_id.Value);
            var targetId = targetDevice?.Id ?? device_id.Value;
            list = list.Where(a => a.DeviceId == device_id.Value || a.DeviceId == targetId);
        }

        if (state == "open")
        {
            list = list.Where(a => !a.IsResolved);
        }
        else if (state == "resolved")
        {
            list = list.Where(a => a.IsResolved);
        }

        if (!string.IsNullOrEmpty(level))
        {
            list = list.Where(a => string.Equals(a.Level, level, StringComparison.OrdinalIgnoreCase));
        }

        var all = list.ToList();
        var pageSize = 20;
        var rows = all.Skip((page - 1) * pageSize).Take(pageSize).Select(a =>
        {
            var dev = _store.GetDevice(a.DeviceId);
            var stId = dev?.StationId ?? a.DeviceId;
            var st = _store.GetStation(stId);
            return new
            {
                id = a.Id,
                device_id = a.DeviceId,
                station_id = stId,
                level = a.Level,
                type = a.Type,
                message = a.Message,
                device_name = dev?.Name ?? st?.Name ?? "Trạm Pico 2 W",
                device_code = dev?.DeviceCode ?? "PICO-01",
                profile = dev?.Profile ?? "cabinet",
                is_resolved = a.IsResolved,
                created_at = a.CreatedAt,
                resolved_at = a.ResolvedAt,
                acknowledged_at = a.IsResolved ? a.ResolvedAt : null,
                ack_name = (string?)null
            };
        }).ToList();

        var userScopeAlerts = _store.Alerts.AsEnumerable();
        if (isViewer && allowedDeviceIds != null)
        {
            userScopeAlerts = userScopeAlerts.Where(a => allowedDeviceIds.Contains(a.DeviceId));
        }
        var scopeAlertsList = userScopeAlerts.ToList();

        return Ok(new
        {
            ok = true,
            rows,
            alerts = rows,
            total = all.Count,
            page,
            pages = (int)Math.Ceiling(all.Count / (double)pageSize),
            counts = new
            {
                open_total = scopeAlertsList.Count(a => !a.IsResolved),
                open_danger = scopeAlertsList.Count(a => !a.IsResolved && string.Equals(a.Level, "danger", StringComparison.OrdinalIgnoreCase)),
                unack = scopeAlertsList.Count(a => !a.IsResolved),
                last24h = scopeAlertsList.Count
            }
        });
    }

    [HttpPost]
    public IActionResult Post([FromQuery] string? action, [FromBody] JsonObject? body)
    {
        var curUser = GetCurrentUser();
        if (curUser == null)
        {
            return Unauthorized(new { ok = false, error = "Vui lòng đăng nhập để thực hiện thao tác" });
        }

        var isViewer = curUser.Role == "viewer";
        HashSet<int>? allowedDeviceIds = null;
        if (isViewer)
        {
            var allowedStationIds = _store.GetStationIdsForUser(curUser.Id);
            allowedDeviceIds = _store.Devices
                .Where(d => allowedStationIds.Contains(d.Id) || (d.StationId.HasValue && allowedStationIds.Contains(d.StationId.Value)))
                .Select(d => d.Id)
                .ToHashSet();
            foreach (var sid in allowedStationIds) allowedDeviceIds.Add(sid);
        }

        var act = action?.ToLowerInvariant() ?? "";

        if (act == "resolve" || act == "ack")
        {
            var id = body?["id"]?.GetValue<int>() ?? 0;
            var alert = _store.Alerts.FirstOrDefault(a => a.Id == id);
            if (alert != null)
            {
                if (isViewer && allowedDeviceIds != null && !allowedDeviceIds.Contains(alert.DeviceId))
                {
                    return Forbid();
                }
                alert.IsResolved = true;
                alert.ResolvedAt = TimeHelper.VnNowStr;
            }
            return Ok(new { ok = true });
        }

        if (act == "ack_all")
        {
            foreach (var a in _store.Alerts)
            {
                if (isViewer && allowedDeviceIds != null && !allowedDeviceIds.Contains(a.DeviceId))
                {
                    continue;
                }
                a.IsResolved = true;
                a.ResolvedAt = TimeHelper.VnNowStr;
            }
            return Ok(new { ok = true });
        }

        return BadRequest(new { ok = false, error = "Hành động không hợp lệ" });
    }
}
