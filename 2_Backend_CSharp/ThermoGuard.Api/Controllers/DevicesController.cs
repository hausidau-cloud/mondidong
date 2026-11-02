using Microsoft.AspNetCore.Mvc;
using ThermoGuard.Api.Models;
using ThermoGuard.Api.Services;

namespace ThermoGuard.Api.Controllers;

[ApiController]
[Route("api/devices")]
[Route("api/stations")]
public class DevicesController : ControllerBase
{
    private readonly DataStore _store;

    public DevicesController(DataStore store)
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
    public IActionResult Get([FromQuery] int? id)
    {
        var curUser = GetCurrentUser();
        List<int>? allowedStationIds = null;
        if (curUser != null && curUser.Role == "viewer")
        {
            allowedStationIds = _store.GetStationIdsForUser(curUser.Id);
        }

        if (id.HasValue)
        {
            if (allowedStationIds != null && !allowedStationIds.Contains(id.Value))
            {
                return Forbid();
            }

            var dev = _store.GetDevice(id.Value);
            if (dev == null)
            {
                return NotFound(new { ok = false, error = "Không tìm thấy thiết bị / trạm" });
            }

            var devDict = BuildDevicePublic(dev);
            devDict["spark"] = _store.GetSpark(dev.Id);
            devDict["stats24h"] = _store.GetStats24h(dev.Id);
            devDict["relay_logs"] = _store.RelayLogs.Take(15).ToList();

            return Ok(new { ok = true, device = devDict });
        }

        var source = _store.Devices.AsEnumerable();
        if (allowedStationIds != null)
        {
            source = source.Where(d => allowedStationIds.Contains(d.Id));
        }

        var list = source.Select(d =>
        {
            var item = BuildDevicePublic(d);
            item["spark"] = _store.GetSpark(d.Id);
            return item;
        }).ToList();

        return Ok(new { ok = true, total = list.Count, devices = list, stations = list });
    }

    [HttpGet("{id}/viewers")]
    public IActionResult GetViewers(int id)
    {
        var viewerIds = _store.GetUserIdsForStation(id);
        var viewers = _store.Users.Where(u => viewerIds.Contains(u.Id)).Select(u => new
        {
            id = u.Id,
            username = u.Username,
            full_name = u.FullName,
            role = u.Role
        }).ToList();

        return Ok(new { ok = true, station_id = id, total = viewers.Count, viewers });
    }

    [HttpDelete("{deviceId}/viewers/{userId}")]
    public IActionResult RemoveViewer(int deviceId, int userId, [FromServices] Data.AppDbContext db)
    {
        var cur = GetCurrentUser();
        if (cur != null && cur.Role != "admin") return Forbid();

        _store.RemoveAssignment(deviceId, userId, db);
        return Ok(new { ok = true, message = "Đã gỡ nhân viên khỏi trạm" });
    }

    private Dictionary<string, object?> BuildDevicePublic(Device d)
    {
        return new Dictionary<string, object?>
        {
            ["id"] = d.Id,
            ["device_code"] = d.DeviceCode,
            ["name"] = d.Name,
            ["profile"] = d.Profile,
            ["location"] = d.Location,
            ["description"] = d.Description,
            ["relay_label"] = d.RelayLabel,
            ["relay_mode"] = d.RelayMode,
            ["relay_state"] = d.RelayState,
            ["status"] = d.Status,
            ["online"] = d.Online,
            ["air_temp"] = d.AirTemp,
            ["air_hum"] = d.AirHum,
            ["dew_point"] = d.DewPoint,
            ["probe_temp"] = d.ProbeTemp,
            ["pico_temp"] = d.PicoTemp,
            ["light_raw"] = d.LightRaw,
            ["light_pct"] = d.LightPct,
            ["air_temp_max"] = d.AirTempMax,
            ["air_hum_max"] = d.AirHumMax,
            ["probe_temp_min"] = d.ProbeTempMin,
            ["probe_temp_max"] = d.ProbeTempMax,
            ["dew_margin"] = d.DewMargin,
            ["hysteresis"] = d.Hysteresis,
            ["offset_air"] = d.OffsetAir,
            ["offset_probe"] = d.OffsetProbe,
            ["offline_after"] = d.OfflineAfter,
            ["open_alerts"] = d.OpenAlerts,
            ["send_interval"] = d.SendInterval,
            ["rssi"] = d.Rssi,
            ["last_seen"] = d.LastSeen,
            ["firmware"] = d.Firmware,
            ["oled_msg"] = d.OledMsg,
            ["key_version"] = 1,
            ["ingest_auth"] = "hmac",
            ["viewer_ids"] = _store.GetUserIdsForStation(d.Id),
            ["viewers"] = _store.Users.Where(u => _store.GetUserIdsForStation(d.Id).Contains(u.Id)).Select(u => new
            {
                id = u.Id,
                username = u.Username,
                full_name = u.FullName,
                role = u.Role
            }).ToList()
        };
    }
}

