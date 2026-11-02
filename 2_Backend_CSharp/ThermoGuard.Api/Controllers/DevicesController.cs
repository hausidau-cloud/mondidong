using Microsoft.AspNetCore.Mvc;
using ThermoGuard.Api.Models;
using ThermoGuard.Api.Services;

namespace ThermoGuard.Api.Controllers;

[ApiController]
[Route("api/devices")]
public class DevicesController : ControllerBase
{
    private readonly DataStore _store;

    public DevicesController(DataStore store)
    {
        _store = store;
    }

    [HttpGet]
    public IActionResult Get([FromQuery] int? id)
    {
        if (id.HasValue)
        {
            var dev = _store.GetDevice(id.Value);
            if (dev == null)
            {
                return NotFound(new { ok = false, error = "Không tìm thấy thiết bị" });
            }

            var devDict = BuildDevicePublic(dev);
            devDict["spark"] = _store.GetSpark(dev.Id);
            devDict["stats24h"] = _store.GetStats24h(dev.Id);
            devDict["relay_logs"] = _store.RelayLogs.Take(15).ToList();

            return Ok(new { ok = true, device = devDict });
        }

        var list = _store.Devices.Select(d =>
        {
            var item = BuildDevicePublic(d);
            item["spark"] = _store.GetSpark(d.Id);
            return item;
        }).ToList();

        return Ok(new { ok = true, devices = list });
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
            ["ingest_auth"] = "hmac"
        };
    }
}
