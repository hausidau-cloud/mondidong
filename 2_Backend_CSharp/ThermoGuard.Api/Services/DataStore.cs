using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using ThermoGuard.Api.Data;
using ThermoGuard.Api.Models;

namespace ThermoGuard.Api.Services;

public class DataStore
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly object _lock = new();

    public List<AppUser> Users { get; } = new();
    public List<Device> Devices { get; } = new();
    public List<ReadingRecord> Readings { get; } = new();
    public List<AlertItem> Alerts { get; } = new();
    public List<RelayLogItem> RelayLogs { get; } = new();
    public List<StationAssignment> Assignments { get; } = new();
    public Dictionary<string, AppUser> ActiveSessions { get; } = new();

    private long _nextReadingId = 1;
    private int _nextAlertId = 1;
    private int _nextRelayLogId = 1;

    public DataStore(IServiceScopeFactory scopeFactory)
    {
        _scopeFactory = scopeFactory;
        LoadFromDatabase();
    }

    private void LoadFromDatabase()
    {
        try
        {
            using var scope = _scopeFactory.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            db.Database.EnsureCreated();
            try
            {
                db.Database.ExecuteSqlRaw(@"
                    CREATE TABLE IF NOT EXISTS StationAssignments (
                        Id INT AUTO_INCREMENT PRIMARY KEY,
                        UserId INT NOT NULL,
                        DeviceId INT NOT NULL,
                        AssignedAt DATETIME DEFAULT CURRENT_TIMESTAMP
                    );
                ");
            }
            catch { }

            if (db.Users.Any())
            {
                Users.AddRange(db.Users.AsNoTracking().ToList());
            }
            if (db.Devices.Any())
            {
                Devices.AddRange(db.Devices.AsNoTracking().ToList());
            }
            if (db.Readings.Any())
            {
                var history = db.Readings.AsNoTracking().OrderByDescending(r => r.Id).Take(500).ToList();
                Readings.AddRange(history);
                _nextReadingId = (history.MaxBy(r => r.Id)?.Id ?? 0) + 1;
            }
            if (db.StationAssignments.Any())
            {
                Assignments.AddRange(db.StationAssignments.AsNoTracking().ToList());
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine(">> Note khi khoi dong DB: " + ex.Message);
        }

        // Fallback default user if empty
        if (Users.Count == 0)
        {
            Users.Add(new AppUser { Id = 1, Username = "admin", Password = "password123", FullName = "Quản trị viên", Role = "admin" });
            Users.Add(new AppUser { Id = 2, Username = "viewer", Password = "password123", FullName = "Người xem", Role = "viewer" });
        }

        // Fallback default device if empty
        if (Devices.Count == 0)
        {
            Devices.Add(new Device
            {
                Id = 1,
                DeviceCode = "PICO-01",
                ApiKey = "a1b2c3d4e5f60718293a4b5c6d7e8f90",
                Name = "Trạm Pico 2 W - Phòng Lab",
                Profile = "cabinet",
                RelayLabel = "Bóng đèn 220V / Rơ-le",
                RelayMode = "AUTO",
                RelayState = 0,
                Status = "OFFLINE"
            });
        }

        // Fallback default assignment (viewer -> Station 1)
        if (Assignments.Count == 0)
        {
            Assignments.Add(new StationAssignment { Id = 1, UserId = 2, DeviceId = 1, AssignedAt = TimeHelper.VnNow });
        }
    }

    public List<int> GetStationIdsForUser(int userId)
    {
        lock (_lock)
        {
            return Assignments.Where(a => a.UserId == userId).Select(a => a.DeviceId).Distinct().ToList();
        }
    }

    public List<int> GetUserIdsForStation(int deviceId)
    {
        lock (_lock)
        {
            return Assignments.Where(a => a.DeviceId == deviceId).Select(a => a.UserId).Distinct().ToList();
        }
    }

    public void SetUserStations(int userId, IEnumerable<int> stationIds, AppDbContext? db = null)
    {
        lock (_lock)
        {
            Assignments.RemoveAll(a => a.UserId == userId);
            foreach (var sid in stationIds)
            {
                Assignments.Add(new StationAssignment
                {
                    Id = Assignments.Count > 0 ? Assignments.Max(a => a.Id) + 1 : 1,
                    UserId = userId,
                    DeviceId = sid,
                    AssignedAt = TimeHelper.VnNow
                });
            }

            if (db != null)
            {
                try
                {
                    var existing = db.StationAssignments.Where(a => a.UserId == userId).ToList();
                    db.StationAssignments.RemoveRange(existing);
                    foreach (var sid in stationIds)
                    {
                        db.StationAssignments.Add(new StationAssignment
                        {
                            UserId = userId,
                            DeviceId = sid,
                            AssignedAt = TimeHelper.VnNow
                        });
                    }
                    db.SaveChanges();
                }
                catch (Exception ex)
                {
                    Console.WriteLine(">> Note SetUserStations DB: " + ex.Message);
                }
            }
        }
    }

    public void RemoveAssignment(int deviceId, int userId, AppDbContext? db = null)
    {
        lock (_lock)
        {
            Assignments.RemoveAll(a => a.DeviceId == deviceId && a.UserId == userId);
            if (db != null)
            {
                try
                {
                    var existing = db.StationAssignments.Where(a => a.DeviceId == deviceId && a.UserId == userId).ToList();
                    db.StationAssignments.RemoveRange(existing);
                    db.SaveChanges();
                }
                catch (Exception ex)
                {
                    Console.WriteLine(">> Note RemoveAssignment DB: " + ex.Message);
                }
            }
        }
    }


    public static string ComputeHmacSha256(string key, string message)
    {
        var keyBytes = Encoding.UTF8.GetBytes(key);
        var msgBytes = Encoding.UTF8.GetBytes(message);
        using var hmac = new HMACSHA256(keyBytes);
        var hash = hmac.ComputeHash(msgBytes);
        return Convert.ToHexString(hash).ToLowerInvariant();
    }

    public Device? GetDevice(string code)
    {
        lock (_lock)
        {
            return Devices.FirstOrDefault(d => string.Equals(d.DeviceCode, code, StringComparison.OrdinalIgnoreCase));
        }
    }

    public Device? GetDevice(int id)
    {
        lock (_lock)
        {
            return Devices.FirstOrDefault(d => d.Id == id);
        }
    }

    public (bool ok, string error, object? response) ProcessIngest(IngestRequest req, string clientIp)
    {
        lock (_lock)
        {
            var code = req.DeviceCode?.Trim() ?? "";
            var dev = Devices.FirstOrDefault(d => string.Equals(d.DeviceCode, code, StringComparison.OrdinalIgnoreCase));
            if (dev == null)
            {
                return (false, "Không tìm thấy thiết bị: " + code, null);
            }

            double? airT = null, airH = null, probeT = null, dew = null, picoT = null;
            int? lightRaw = 0, lightPct = 0, relayState = 0, rssi = null;
            string? fw = null;

            // 1. Unpack payload
            if (!string.IsNullOrEmpty(req.Payload))
            {
                if (!string.IsNullOrEmpty(req.Sig))
                {
                    var expectedSig = ComputeHmacSha256(dev.ApiKey, $"{dev.DeviceCode}|{req.Ts}|{req.Payload}");
                    if (!string.Equals(req.Sig, expectedSig, StringComparison.OrdinalIgnoreCase))
                    {
                        return (false, "Chữ ký số HMAC-SHA256 không hợp lệ (sai API Key)", null);
                    }
                }

                try
                {
                    using var doc = JsonDocument.Parse(req.Payload);
                    var root = doc.RootElement;
                    if (root.TryGetProperty("air_temp", out var at) && at.ValueKind == JsonValueKind.Number) airT = at.GetDouble();
                    if (root.TryGetProperty("air_hum", out var ah) && ah.ValueKind == JsonValueKind.Number) airH = ah.GetDouble();
                    if (root.TryGetProperty("probe_temp", out var pt) && pt.ValueKind == JsonValueKind.Number) probeT = pt.GetDouble();
                    if (root.TryGetProperty("pico_temp", out var pi) && pi.ValueKind == JsonValueKind.Number) picoT = pi.GetDouble();
                    if (root.TryGetProperty("dew_point", out var dp) && dp.ValueKind == JsonValueKind.Number) dew = dp.GetDouble();
                    if (root.TryGetProperty("light_raw", out var lr) && lr.ValueKind == JsonValueKind.Number) lightRaw = lr.GetInt32();
                    if (root.TryGetProperty("light_pct", out var lp) && lp.ValueKind == JsonValueKind.Number) lightPct = lp.GetInt32();
                    if (root.TryGetProperty("relay_state", out var rs) && rs.ValueKind == JsonValueKind.Number) relayState = rs.GetInt32();
                    if (root.TryGetProperty("rssi", out var rsVal) && rsVal.ValueKind == JsonValueKind.Number) rssi = rsVal.GetInt32();
                    if (root.TryGetProperty("fw", out var fwVal) && fwVal.ValueKind == JsonValueKind.String) fw = fwVal.GetString();
                }
                catch (Exception ex)
                {
                    return (false, "Lỗi đọc JSON payload: " + ex.Message, null);
                }
            }
            else
            {
                airT = req.AirTemp;
                airH = req.AirHum;
                probeT = req.ProbeTemp;
                picoT = req.PicoTemp;
                dew = req.DewPoint;
                lightRaw = req.LightRaw ?? 0;
                lightPct = req.LightPct ?? 0;
                relayState = req.RelayState ?? 0;
                rssi = req.Rssi;
                fw = req.Fw;
            }

            // Calculate dew point
            if (dew == null && airT != null && airH != null && airH > 0)
            {
                double b = 17.62, c = 243.12;
                double g = Math.Log(airH.Value / 100.0) + (b * airT.Value) / (c + airT.Value);
                dew = Math.Round((c * g) / (b - g), 1);
            }

            if (airT != null) airT = Math.Round(airT.Value + dev.OffsetAir, 1);
            if (probeT != null) probeT = Math.Round(probeT.Value + dev.OffsetProbe, 1);

            if (picoT == null)
            {
                if (airT != null) picoT = Math.Round(airT.Value + 4.5, 1);
                else if (probeT != null) picoT = Math.Round(probeT.Value + 3.0, 1);
                else picoT = 31.0;
            }

            dev.AirTemp = airT;
            dev.AirHum = airH;
            dev.ProbeTemp = probeT;
            dev.PicoTemp = picoT;
            dev.DewPoint = dew;
            dev.LightRaw = lightRaw ?? 0;
            dev.LightPct = lightPct ?? 0;
            dev.Rssi = rssi;
            if (!string.IsNullOrEmpty(fw)) dev.Firmware = fw;
            dev.LastSeenTime = DateTime.UtcNow;
            dev.LastSeen = TimeHelper.VnNowStr;

            var (status, alertType, alertReason) = EvaluateStatus(dev, airT, airH, probeT, dew);
            dev.Status = status;
            dev.Reason = alertReason;

            // Xử lý ghi nhận Alert
            if (status != "OK" && !string.IsNullOrEmpty(alertType))
            {
                var existing = Alerts.FirstOrDefault(a => a.DeviceId == dev.Id && a.Type == alertType && !a.IsResolved);
                if (existing == null)
                {
                    var newAlert = new AlertItem
                    {
                        Id = _nextAlertId++,
                        DeviceId = dev.Id,
                        Level = status,
                        Type = alertType,
                        Message = alertReason,
                        IsResolved = false,
                        CreatedAt = TimeHelper.VnNowStr
                    };
                    Alerts.Insert(0, newAlert);
                }
            }
            else if (status == "OK")
            {
                foreach (var a in Alerts.Where(a => a.DeviceId == dev.Id && !a.IsResolved && a.Type != "OFFLINE"))
                {
                    a.IsResolved = true;
                    a.ResolvedAt = TimeHelper.VnNowStr;
                }
            }

            foreach (var a in Alerts.Where(a => a.DeviceId == dev.Id && !a.IsResolved && a.Type == "OFFLINE"))
            {
                a.IsResolved = true;
                a.ResolvedAt = TimeHelper.VnNowStr;
            }
            dev.OpenAlerts = Alerts.Count(a => a.DeviceId == dev.Id && !a.IsResolved);

            int finalRelay = dev.RelayState;
            if (dev.RelayMode == "ON")
            {
                finalRelay = 1;
            }
            else if (dev.RelayMode == "OFF")
            {
                finalRelay = 0;
            }
            else
            {
                bool reqHot = (probeT != null && probeT > dev.ProbeTempMax) || (airT != null && airT > dev.AirTempMax);
                bool reqHum = (airH != null && airH > dev.AirHumMax);
                bool reqDark = (lightRaw != null && lightRaw >= 30000);

                if (reqHot || reqHum || reqDark)
                {
                    finalRelay = 1;
                }
                else if (dev.RelayState == 1)
                {
                    bool safeHot = (probeT == null || probeT < dev.ProbeTempMax - dev.Hysteresis) &&
                                   (airT == null || airT < dev.AirTempMax - dev.Hysteresis);
                    bool safeHum = (airH == null || airH < dev.AirHumMax - 5.0);
                    bool safeDark = (lightRaw == null || lightRaw <= 20000);

                    if (safeHot && safeHum && safeDark)
                    {
                        finalRelay = 0;
                    }
                }
            }

            if (dev.RelayState != finalRelay)
            {
                dev.RelayState = finalRelay;
                var logItem = new RelayLogItem
                {
                    Id = _nextRelayLogId++,
                    Action = finalRelay == 1 ? "ON" : "OFF",
                    Source = dev.RelayMode == "AUTO" ? "AUTO" : "MANUAL",
                    Reason = alertReason,
                    FullName = "Hệ thống",
                    CreatedAt = TimeHelper.VnNowStr
                };
                RelayLogs.Insert(0, logItem);
            }

            // Create record
            var record = new ReadingRecord
            {
                Id = _nextReadingId++,
                DeviceId = dev.Id,
                AirTemp = airT,
                AirHum = airH,
                DewPoint = dew,
                ProbeTemp = probeT,
                PicoTemp = picoT,
                LightPct = dev.LightPct,
                RelayState = dev.RelayState,
                Status = dev.Status,
                Rssi = dev.Rssi,
                RecordedAt = TimeHelper.VnNowStr
            };
            Readings.Insert(0, record);
            if (Readings.Count > 5000) Readings.RemoveAt(Readings.Count - 1);

            // Persist to SQLite in background
            _ = Task.Run(() =>
            {
                try
                {
                    using var s = _scopeFactory.CreateScope();
                    var db = s.ServiceProvider.GetRequiredService<AppDbContext>();
                    db.Readings.Add(new ReadingRecord
                    {
                        DeviceId = record.DeviceId,
                        AirTemp = record.AirTemp,
                        AirHum = record.AirHum,
                        DewPoint = record.DewPoint,
                        ProbeTemp = record.ProbeTemp,
                        PicoTemp = record.PicoTemp,
                        LightPct = record.LightPct,
                        RelayState = record.RelayState,
                        Status = record.Status,
                        Rssi = record.Rssi,
                        RecordedAt = record.RecordedAt
                    });
                    db.SaveChanges();
                }
                catch
                {
                }
            });

            if (!string.IsNullOrEmpty(alertType))
            {
                var existing = Alerts.FirstOrDefault(a => a.DeviceId == dev.Id && a.Type == alertType && !a.IsResolved);
                if (existing == null)
                {
                    Alerts.Insert(0, new AlertItem
                    {
                        Id = _nextAlertId++,
                        DeviceId = dev.Id,
                        Level = status,
                        Type = alertType,
                        Message = alertReason,
                        IsResolved = false,
                        CreatedAt = TimeHelper.VnNowStr
                    });
                }
            }
            dev.OpenAlerts = Alerts.Count(a => a.DeviceId == dev.Id && !a.IsResolved);

            var resp = new
            {
                ok = true,
                status = dev.Status,
                relay = dev.RelayState,
                mode = dev.RelayMode,
                profile = dev.Profile,
                reason = dev.Reason,
                dew_point = dev.DewPoint,
                interval = dev.SendInterval,
                server_time = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
                oled = new
                {
                    label = dev.Status,
                    alert = alertType,
                    name = dev.DeviceCode,
                    msg = dev.OledMsg ?? ""
                },
                thresholds = new
                {
                    probe_max = dev.ProbeTempMax,
                    probe_min = dev.ProbeTempMin,
                    air_max = dev.AirTempMax,
                    hyst = dev.Hysteresis
                }
            };

            return (true, "", resp);
        }
    }

    private (string status, string alertType, string reason) EvaluateStatus(Device dev, double? airT, double? airH, double? probeT, double? dew)
    {
        // 1. Nguy cơ đọng sương
        if (airT != null && dew != null && (airT.Value - dew.Value) < dev.DewMargin)
            return ("DANGER", "DEW_RISK", $"Nguy cơ đọng sương bo mạch! Biên an toàn: {(airT.Value - dew.Value):F1}°C (< {dev.DewMargin:F1}°C)");

        // 2. Nhiệt độ que inox đo nước (DS18B20) quá cao
        if (probeT != null && probeT > dev.ProbeTempMax)
            return ("DANGER", "PROBE_HIGH", $"Nhiệt độ nước quá cao: {probeT:F1}°C (> {dev.ProbeTempMax:F1}°C)");

        // 3. Nhiệt độ không khí quá cao
        if (airT != null && airT > dev.AirTempMax)
            return ("DANGER", "AIR_TEMP_HIGH", $"Nhiệt độ không khí quá cao: {airT:F1}°C (> {dev.AirTempMax:F1}°C)");

        // 4. Nhiệt độ que dưới ngưỡng
        if (probeT != null && probeT < dev.ProbeTempMin)
            return ("WARNING", "PROBE_LOW", $"Nhiệt độ nước quá thấp: {probeT:F1}°C (< {dev.ProbeTempMin:F1}°C)");

        // 5. Độ ẩm không khí vượt ngưỡng
        if (airH != null && airH > dev.AirHumMax)
            return ("WARNING", "AIR_HUM_HIGH", $"Độ ẩm không khí quá cao: {airH:F1}% (> {dev.AirHumMax:F1}%)");

        return ("OK", "", "Môi trường an toàn");
    }

    public void AddOfflineAlert(Device dev)
    {
        lock (_lock)
        {
            var existing = Alerts.FirstOrDefault(a => a.DeviceId == dev.Id && a.Type == "OFFLINE" && !a.IsResolved);
            if (existing == null)
            {
                var newAlert = new AlertItem
                {
                    Id = _nextAlertId++,
                    DeviceId = dev.Id,
                    Level = "WARNING",
                    Type = "OFFLINE",
                    Message = $"Trạm {dev.Name} ({dev.DeviceCode}) mất kết nối > {dev.OfflineAfter} giây!",
                    IsResolved = false,
                    CreatedAt = TimeHelper.VnNowStr
                };
                Alerts.Insert(0, newAlert);
                dev.OpenAlerts = Alerts.Count(a => a.DeviceId == dev.Id && !a.IsResolved);
            }
        }
    }

    public List<double?> GetSpark(int deviceId)
    {
        lock (_lock)
        {
            return Readings
                .Where(r => r.DeviceId == deviceId && r.ProbeTemp != null)
                .Take(30)
                .Reverse()
                .Select(r => r.ProbeTemp)
                .ToList();
        }
    }

    public object GetStats24h(int deviceId)
    {
        lock (_lock)
        {
            var devReadings = Readings.Where(r => r.DeviceId == deviceId).Take(200).ToList();
            if (devReadings.Count == 0)
            {
                return new { n = 0, relay_on = 0 };
            }

            var probeTemps = devReadings.Where(r => r.ProbeTemp != null).Select(r => r.ProbeTemp!.Value).ToList();
            var airTemps = devReadings.Where(r => r.AirTemp != null).Select(r => r.AirTemp!.Value).ToList();
            var airHums = devReadings.Where(r => r.AirHum != null).Select(r => r.AirHum!.Value).ToList();

            return new
            {
                p_min = probeTemps.Count > 0 ? probeTemps.Min() : (double?)null,
                p_max = probeTemps.Count > 0 ? probeTemps.Max() : (double?)null,
                p_avg = probeTemps.Count > 0 ? Math.Round(probeTemps.Average(), 1) : (double?)null,
                a_min = airTemps.Count > 0 ? airTemps.Min() : (double?)null,
                a_max = airTemps.Count > 0 ? airTemps.Max() : (double?)null,
                h_avg = airHums.Count > 0 ? Math.Round(airHums.Average(), 1) : (double?)null,
                n = devReadings.Count,
                relay_on = devReadings.Count(r => r.RelayState == 1)
            };
        }
    }

    public void UpdateDevice(Device dev)
    {
        Task.Run(() =>
        {
            try
            {
                using var scope = _scopeFactory.CreateScope();
                var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
                var dbDev = db.Devices.FirstOrDefault(d => d.Id == dev.Id);
                if (dbDev != null)
                {
                    dbDev.AirTempMax = dev.AirTempMax;
                    dbDev.AirHumMax = dev.AirHumMax;
                    dbDev.ProbeTempMin = dev.ProbeTempMin;
                    dbDev.ProbeTempMax = dev.ProbeTempMax;
                    dbDev.DewMargin = dev.DewMargin;
                    dbDev.Hysteresis = dev.Hysteresis;
                    dbDev.OffsetAir = dev.OffsetAir;
                    dbDev.OffsetProbe = dev.OffsetProbe;
                    dbDev.OfflineAfter = dev.OfflineAfter;
                    dbDev.RelayMode = dev.RelayMode;
                    dbDev.RelayState = dev.RelayState;
                    dbDev.OledMsg = dev.OledMsg;
                    db.SaveChanges();
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine(">> Note UpdateDevice DB: " + ex.Message);
            }
        });
    }
}

