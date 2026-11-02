using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Mvc;
using ThermoGuard.Api.Services;

namespace ThermoGuard.Api.Controllers;

[ApiController]
[Route("api/alerts")]
public class AlertsController : ControllerBase
{
    private readonly DataStore _store;

    public AlertsController(DataStore store)
    {
        _store = store;
    }

    [HttpGet]
    public IActionResult Get([FromQuery] string? state, [FromQuery] string? level, [FromQuery] int page = 1)
    {
        var list = _store.Alerts.AsEnumerable();

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
            return new
            {
                id = a.Id,
                device_id = a.DeviceId,
                level = a.Level,
                type = a.Type,
                message = a.Message,
                device_name = dev?.Name ?? "Trạm Pico 2 W",
                device_code = dev?.DeviceCode ?? "PICO-01",
                profile = dev?.Profile ?? "cabinet",
                is_resolved = a.IsResolved,
                created_at = a.CreatedAt,
                resolved_at = a.ResolvedAt,
                acknowledged_at = a.IsResolved ? a.ResolvedAt : null,
                ack_name = (string?)null
            };
        }).ToList();

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
                open_total = _store.Alerts.Count(a => !a.IsResolved),
                open_danger = _store.Alerts.Count(a => !a.IsResolved && string.Equals(a.Level, "danger", StringComparison.OrdinalIgnoreCase)),
                unack = _store.Alerts.Count(a => !a.IsResolved),
                last24h = _store.Alerts.Count
            }
        });
    }

    [HttpPost]
    public IActionResult Post([FromQuery] string? action, [FromBody] JsonObject? body)
    {
        var act = action?.ToLowerInvariant() ?? "";

        if (act == "resolve" || act == "ack")
        {
            var id = body?["id"]?.GetValue<int>() ?? 0;
            var alert = _store.Alerts.FirstOrDefault(a => a.Id == id);
            if (alert != null)
            {
                alert.IsResolved = true;
                alert.ResolvedAt = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");
            }
            return Ok(new { ok = true });
        }

        if (act == "ack_all")
        {
            foreach (var a in _store.Alerts)
            {
                a.IsResolved = true;
                a.ResolvedAt = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");
            }
            return Ok(new { ok = true });
        }

        return BadRequest(new { ok = false, error = "Hành động không hợp lệ" });
    }
}
