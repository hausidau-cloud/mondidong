using Microsoft.AspNetCore.Mvc;
using ThermoGuard.Api.Services;

namespace ThermoGuard.Api.Controllers;

[ApiController]
[Tags("Readings")]
[Route("api/readings")]
public class ReadingsController : ControllerBase
{
    private readonly DataStore _store;

    public ReadingsController(DataStore store)
    {
        _store = store;
    }

    [HttpGet]
    public IActionResult Get(
        [FromQuery] int? device_id,
        [FromQuery] string? range,
        [FromQuery] string? mode,
        [FromQuery] int page = 1)
    {
        var devId = device_id ?? _store.Devices.FirstOrDefault()?.Id ?? 1;
        var targetDevice = _store.GetDevice(devId) ?? _store.Devices.FirstOrDefault(d => d.StationId == devId);
        var resolvedDevId = targetDevice?.Id ?? devId;

        if (mode == "table")
        {
            var all = _store.Readings.Where(r => r.DeviceId == devId || r.DeviceId == resolvedDevId).ToList();
            var pageSize = 20;
            var rows = all.Skip((page - 1) * pageSize).Take(pageSize).ToList();

            return Ok(new
            {
                ok = true,
                rows,
                total = all.Count,
                page,
                pages = (int)Math.Ceiling(all.Count / (double)pageSize)
            });
        }

        // Series chart mode - Flutter expects:
        // series: { t: [...], air_temp: [...], air_hum: [...], dew_point: [...], probe_temp: [...], relay: [...] }
        // bucket: int
        var records = _store.Readings
            .Where(r => r.DeviceId == devId || r.DeviceId == resolvedDevId)
            .Take(60)
            .Reverse()
            .ToList();

        var tList = records.Select(r => r.RecordedAt).ToList();
        var airTempList = records.Select(r => r.AirTemp).ToList();
        var airHumList = records.Select(r => r.AirHum).ToList();
        var dewPointList = records.Select(r => r.DewPoint).ToList();
        var probeTempList = records.Select(r => r.ProbeTemp).ToList();
        var picoTempList = records.Select(r => r.PicoTemp).ToList();
        var lightList = records.Select(r => (double?)r.LightPct).ToList();
        var relayList = records.Select(r => r.RelayState == 1).ToList();

        return Ok(new
        {
            ok = true,
            bucket = 5,
            series = new
            {
                t = tList,
                air_temp = airTempList,
                air_hum = airHumList,
                dew_point = dewPointList,
                probe_temp = probeTempList,
                pico_temp = picoTempList,
                light = lightList,
                light_pct = lightList,
                relay = relayList
            }
        });
    }
}
