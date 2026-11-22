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
    public List<StationItem> Stations { get; } = new();
    public List<ReadingRecord> Readings { get; } = new();
    public List<AlertItem> Alerts { get; } = new();
    public List<RelayLogItem> RelayLogs { get; } = new();
    public List<StationAssignment> Assignments { get; } = new();
    public List<RelayScheduleItem> Schedules { get; } = new();
    public List<TeamMessage> TeamMessages { get; } = new();
    public Dictionary<int, List<StationActuator>> StationActuators { get; } = new();
    public Dictionary<int, List<AutomationRule>> StationAutomations { get; } = new();
    public Dictionary<string, AppUser> ActiveSessions { get; } = new();
    public Dictionary<string, OtpItem> OtpStore { get; } = new();

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
            try
            {
                db.Database.ExecuteSqlRaw(@"
                    CREATE TABLE IF NOT EXISTS Stations (
                        Id INT AUTO_INCREMENT PRIMARY KEY,
                        Name VARCHAR(255) NOT NULL,
                        Location VARCHAR(255),
                        Description TEXT,
                        RelayLabel VARCHAR(255) DEFAULT 'Bóng đèn 220V / Rơ-le',
                        CreatedAt VARCHAR(50)
                    );
                ");
            }
            catch { }
            try
            {
                db.Database.ExecuteSqlRaw(@"
                    CREATE TABLE IF NOT EXISTS TeamMessages (
                        Id INT AUTO_INCREMENT PRIMARY KEY,
                        UserId INT NOT NULL,
                        SenderName VARCHAR(100) NOT NULL,
                        SenderRole VARCHAR(50) NOT NULL,
                        StationId INT NULL,
                        StationName VARCHAR(100) NULL,
                        Category VARCHAR(50) NOT NULL DEFAULT 'CHAT',
                        Content TEXT NOT NULL,
                        AttachedTelemetry VARCHAR(255) NULL,
                        CreatedAt VARCHAR(50) NOT NULL
                    );
                ");
            }
            catch { }
            try
            {
                db.Database.ExecuteSqlRaw("ALTER TABLE Devices ADD COLUMN StationId INT NULL;");
            }
            catch { }
            try
            {
                db.Database.ExecuteSqlRaw("ALTER TABLE Users ADD COLUMN Phone VARCHAR(20) NULL;");
            }
            catch { }
            try
            {
                db.Database.ExecuteSqlRaw("ALTER TABLE Users ADD COLUMN Email VARCHAR(255) NULL;");
            }
            catch { }
            try
            {
                db.Database.ExecuteSqlRaw("ALTER TABLE Alerts ADD COLUMN StationId INT NULL;");
            }
            catch { }
            try
            {
                db.Database.ExecuteSqlRaw("ALTER TABLE RelayLogs ADD COLUMN DeviceId INT NULL;");
            }
            catch { }
            try
            {
                db.Database.ExecuteSqlRaw("ALTER TABLE RelayLogs ADD COLUMN StationId INT NULL;");
            }
            catch { }
            try
            {
                db.Database.ExecuteSqlRaw("ALTER TABLE RelayLogs ADD COLUMN FullName VARCHAR(255) NULL;");
            }
            catch { }

            if (db.Users.Any())
            {
                Users.AddRange(db.Users.AsNoTracking().ToList());
            }
            if (db.Stations.Any())
            {
                Stations.AddRange(db.Stations.AsNoTracking().ToList());
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
            if (db.Alerts.Any())
            {
                var history = db.Alerts.AsNoTracking().OrderByDescending(a => a.Id).Take(500).ToList();
                Alerts.AddRange(history);
                _nextAlertId = (history.MaxBy(a => a.Id)?.Id ?? 0) + 1;
            }
            if (db.RelayLogs.Any())
            {
                var history = db.RelayLogs.AsNoTracking().OrderByDescending(r => r.Id).Take(500).ToList();
                RelayLogs.AddRange(history);
                _nextRelayLogId = (history.MaxBy(r => r.Id)?.Id ?? 0) + 1;
            }
            if (db.StationAssignments.Any())
            {
                Assignments.AddRange(db.StationAssignments.AsNoTracking().ToList());
            }
            if (db.TeamMessages.Any())
            {
                var history = db.TeamMessages.AsNoTracking().OrderByDescending(m => m.Id).Take(500).ToList();
                history.Reverse();
                TeamMessages.AddRange(history);
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine(">> Note khi khoi dong DB: " + ex.Message);
        }

        // Fallback default user if empty
        if (Users.Count == 0)
        {
            Users.Add(new AppUser { Id = 1, Username = "admin", Password = "password123", FullName = "Quản trị viên Hệ thống", Role = "admin" });
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
            string? locFromPayload = null;

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
                    if (root.TryGetProperty("location", out var locVal) && locVal.ValueKind == JsonValueKind.String) locFromPayload = locVal.GetString();
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

            if (picoT == null && !dev.DeviceCode.ToUpperInvariant().Contains("ESP"))
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
            if (req.Aqi.HasValue) dev.Aqi = req.Aqi.Value;
            if (req.GasPpm.HasValue) dev.GasPpm = req.GasPpm.Value;
            if (req.SoilHum.HasValue) dev.SoilHum = req.SoilHum.Value;
            if (req.WaterLevel.HasValue) dev.WaterLevel = req.WaterLevel.Value;
            dev.Rssi = rssi;
            if (!string.IsNullOrEmpty(fw)) dev.Firmware = fw;
            if (!string.IsNullOrEmpty(locFromPayload))
            {
                dev.Location = locFromPayload;
                if (dev.StationId.HasValue)
                {
                    var st = Stations.FirstOrDefault(s => s.Id == dev.StationId.Value);
                    if (st != null) st.Location = locFromPayload;
                }
            }
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
                        DeviceId = dev.Id,
                        StationId = dev.StationId ?? dev.Id,
                        Level = status,
                        Type = alertType,
                        Message = alertReason,
                        IsResolved = false,
                        CreatedAt = TimeHelper.VnNowStr
                    };
                    AddAlert(newAlert);
                }
            }
            else if (status == "OK")
            {
                ResolveAlertsForDevice(dev.Id, exceptType: "OFFLINE");
            }

            ResolveAlertsForDevice(dev.Id, onlyType: "OFFLINE");
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
                    DeviceId = dev.Id,
                    StationId = dev.StationId ?? dev.Id,
                    Action = finalRelay == 1 ? "ON" : "OFF",
                    Source = dev.RelayMode == "AUTO" ? "AUTO" : "MANUAL",
                    Reason = alertReason,
                    FullName = "Hệ thống",
                    CreatedAt = TimeHelper.VnNowStr
                };
                AddRelayLog(logItem);
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

            dev.OpenAlerts = Alerts.Count(a => a.DeviceId == dev.Id && !a.IsResolved);

            // Tự động đánh giá các kịch bản tự động hóa thông minh (Smart Routines)
            try
            {
                EvaluateAutomationRules(dev.StationId ?? dev.Id, record.AirTemp, record.AirHum, record.DewPoint, record.ProbeTemp, record.LightPct, dev.Aqi, dev.GasPpm, dev.SoilHum, dev.WaterLevel);
            }
            catch { }

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

    public void AddAlert(AlertItem alert)
    {
        lock (_lock)
        {
            if (alert.Id == 0)
            {
                alert.Id = _nextAlertId++;
            }
            Alerts.Insert(0, alert);
            if (Alerts.Count > 1000) Alerts.RemoveAt(Alerts.Count - 1);
        }

        Task.Run(async () =>
        {
            try
            {
                using var scope = _scopeFactory.CreateScope();
                var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
                db.Alerts.Add(new AlertItem
                {
                    DeviceId = alert.DeviceId,
                    StationId = alert.StationId,
                    Level = alert.Level,
                    Type = alert.Type,
                    Message = alert.Message,
                    IsResolved = alert.IsResolved,
                    CreatedAt = alert.CreatedAt,
                    ResolvedAt = alert.ResolvedAt
                });
                db.SaveChanges();

                // GỬI EMAIL CẢNH BÁO TỚI GMAIL CỦA CÁC TÀI KHOẢN ĐÃ ĐĂNG KÝ
                var emailService = scope.ServiceProvider.GetService<EmailService>();
                if (emailService != null)
                {
                    var dev = GetDevice(alert.DeviceId);
                    var stName = dev?.Name ?? $"Trạm #{alert.StationId}";

                    // Tập hợp ID của trạm / thiết bị xảy ra sự cố
                    var targetStationIds = new HashSet<int>();
                    if (alert.StationId.HasValue) targetStationIds.Add(alert.StationId.Value);
                    targetStationIds.Add(alert.DeviceId);
                    if (dev != null)
                    {
                        targetStationIds.Add(dev.Id);
                        if (dev.StationId.HasValue) targetStationIds.Add(dev.StationId.Value);
                    }

                    // Lấy tất cả tài khoản có Email hợp lệ từ cả DB và bộ nhớ RAM
                    var candidateUsers = db.Users.AsNoTracking().Where(u => !string.IsNullOrWhiteSpace(u.Email) && u.Email.Contains("@")).ToList();
                    foreach (var memUser in Users.Where(u => !string.IsNullOrWhiteSpace(u.Email) && u.Email.Contains("@")))
                    {
                        if (!candidateUsers.Any(c => c.Id == memUser.Id)) candidateUsers.Add(memUser);
                    }

                    // GỬI EMAIL THÔNG BÁO CHO TẤT CẢ CÁC TRẠM TỚI TOÀN BỘ TÀI KHOẢN ĐÃ ĐĂNG KÝ EMAIL
                    foreach (var u in candidateUsers)
                    {
                        Console.WriteLine($"[Alert Notification] >> Gửi cảnh báo trạm '{stName}' tới tài khoản: {u.Username} ({u.FullName}) <{u.Email}>");
                        await emailService.SendAlertEmailAsync(
                            u.Email!.Trim(),
                            u.FullName,
                            stName,
                            alert.Level,
                            alert.Type,
                            alert.Message,
                            dev?.AirTemp ?? dev?.ProbeTemp,
                            dev?.AirHum,
                            alert.CreatedAt
                        );
                    }
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine(">> Note AddAlert DB/Email: " + ex.Message);
            }
        });
    }

    public void ResolveAlertsForDevice(int deviceId, string? onlyType = null, string? exceptType = null)
    {
        List<int> alertIdsToUpdate;
        string resolvedTime = TimeHelper.VnNowStr;

        lock (_lock)
        {
            var query = Alerts.Where(a => a.DeviceId == deviceId && !a.IsResolved);
            if (!string.IsNullOrEmpty(onlyType))
                query = query.Where(a => a.Type == onlyType);
            if (!string.IsNullOrEmpty(exceptType))
                query = query.Where(a => a.Type != exceptType);

            var toResolve = query.ToList();
            if (toResolve.Count == 0) return;

            foreach (var a in toResolve)
            {
                a.IsResolved = true;
                a.ResolvedAt = resolvedTime;
            }
            alertIdsToUpdate = toResolve.Select(a => a.Id).ToList();
        }

        Task.Run(() =>
        {
            try
            {
                using var scope = _scopeFactory.CreateScope();
                var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
                var dbQuery = db.Alerts.Where(a => !a.IsResolved && (alertIdsToUpdate.Contains(a.Id) || a.DeviceId == deviceId));
                if (!string.IsNullOrEmpty(onlyType))
                    dbQuery = dbQuery.Where(a => a.Type == onlyType);
                if (!string.IsNullOrEmpty(exceptType))
                    dbQuery = dbQuery.Where(a => a.Type != exceptType);

                var dbAlerts = dbQuery.ToList();
                foreach (var da in dbAlerts)
                {
                    da.IsResolved = true;
                    da.ResolvedAt = resolvedTime;
                }
                db.SaveChanges();
            }
            catch (Exception ex)
            {
                Console.WriteLine(">> Note ResolveAlerts DB: " + ex.Message);
            }
        });
    }

    public void ResolveAlert(int alertId)
    {
        string resolvedTime = TimeHelper.VnNowStr;
        lock (_lock)
        {
            var alert = Alerts.FirstOrDefault(a => a.Id == alertId);
            if (alert != null)
            {
                alert.IsResolved = true;
                alert.ResolvedAt = resolvedTime;
            }
        }

        Task.Run(() =>
        {
            try
            {
                using var scope = _scopeFactory.CreateScope();
                var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
                var dbAlert = db.Alerts.FirstOrDefault(a => a.Id == alertId);
                if (dbAlert != null)
                {
                    dbAlert.IsResolved = true;
                    dbAlert.ResolvedAt = resolvedTime;
                    db.SaveChanges();
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine(">> Note ResolveAlert single DB: " + ex.Message);
            }
        });
    }

    public void ResolveAllAlerts(HashSet<int>? allowedDeviceIds = null)
    {
        string resolvedTime = TimeHelper.VnNowStr;
        List<int> ids;
        lock (_lock)
        {
            var list = Alerts.Where(a => !a.IsResolved);
            if (allowedDeviceIds != null)
            {
                list = list.Where(a => allowedDeviceIds.Contains(a.DeviceId));
            }
            var toResolve = list.ToList();
            foreach (var a in toResolve)
            {
                a.IsResolved = true;
                a.ResolvedAt = resolvedTime;
            }
            ids = toResolve.Select(a => a.Id).ToList();
        }

        Task.Run(() =>
        {
            try
            {
                using var scope = _scopeFactory.CreateScope();
                var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
                var dbAlerts = db.Alerts.Where(a => !a.IsResolved && ids.Contains(a.Id)).ToList();
                foreach (var da in dbAlerts)
                {
                    da.IsResolved = true;
                    da.ResolvedAt = resolvedTime;
                }
                db.SaveChanges();
            }
            catch (Exception ex)
            {
                Console.WriteLine(">> Note ResolveAllAlerts DB: " + ex.Message);
            }
        });
    }

    public void AddRelayLog(RelayLogItem log)
    {
        lock (_lock)
        {
            if (log.Id == 0)
            {
                log.Id = _nextRelayLogId++;
            }
            RelayLogs.Insert(0, log);
            if (RelayLogs.Count > 1000) RelayLogs.RemoveAt(RelayLogs.Count - 1);
        }

        Task.Run(() =>
        {
            try
            {
                using var scope = _scopeFactory.CreateScope();
                var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
                db.RelayLogs.Add(new RelayLogItem
                {
                    DeviceId = log.DeviceId,
                    StationId = log.StationId,
                    Action = log.Action,
                    Source = log.Source,
                    Reason = log.Reason,
                    FullName = log.FullName,
                    CreatedAt = log.CreatedAt
                });
                db.SaveChanges();
            }
            catch (Exception ex)
            {
                Console.WriteLine(">> Note AddRelayLog DB: " + ex.Message);
            }
        });
    }

    public void AddOfflineAlert(Device dev)
    {
        lock (_lock)
        {
            var existing = Alerts.FirstOrDefault(a => a.DeviceId == dev.Id && a.Type == "OFFLINE" && !a.IsResolved);
            if (existing != null) return;
        }

        var newAlert = new AlertItem
        {
            DeviceId = dev.Id,
            StationId = dev.StationId ?? dev.Id,
            Level = "WARNING",
            Type = "OFFLINE",
            Message = $"Trạm {dev.Name} ({dev.DeviceCode}) mất kết nối > {dev.OfflineAfter} giây!",
            IsResolved = false,
            CreatedAt = TimeHelper.VnNowStr
        };
        AddAlert(newAlert);
        lock (_lock)
        {
            dev.OpenAlerts = Alerts.Count(a => a.DeviceId == dev.Id && !a.IsResolved);
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

    public void AddDevice(Device dev)
    {
        lock (_lock)
        {
            Devices.RemoveAll(d => d.Id == dev.Id || string.Equals(d.DeviceCode, dev.DeviceCode, StringComparison.OrdinalIgnoreCase));
            Devices.Add(dev);
        }
    }

    public void DeleteDevice(int id)
    {
        lock (_lock)
        {
            Devices.RemoveAll(d => d.Id == id);
            Assignments.RemoveAll(a => a.DeviceId == id);
            Readings.RemoveAll(r => r.DeviceId == id);
            Alerts.RemoveAll(a => a.DeviceId == id);
        }
    }

    public StationItem? GetStation(int id)
    {
        lock (_lock)
        {
            return Stations.FirstOrDefault(s => s.Id == id);
        }
    }

    public void AddStation(StationItem s)
    {
        lock (_lock)
        {
            Stations.RemoveAll(x => x.Id == s.Id);
            Stations.Add(s);
        }
    }

    public void DeleteStation(int id)
    {
        lock (_lock)
        {
            Stations.RemoveAll(s => s.Id == id);
            // Unassign from any devices
            foreach (var d in Devices.Where(x => x.StationId == id))
            {
                d.StationId = null;
            }
        }
    }

    public string GenerateOtp(string phone, string purpose)
    {
        lock (_lock)
        {
            var cleanPhone = phone.Trim();
            var code = RandomNumberGenerator.GetInt32(100000, 999999).ToString();
            var key = $"{purpose.ToLower()}:{cleanPhone}";
            OtpStore[key] = new OtpItem
            {
                Phone = cleanPhone,
                Code = code,
                Purpose = purpose.ToLower(),
                ExpiresAt = DateTime.UtcNow.AddMinutes(5)
            };
            Console.WriteLine($"[SMS GATEWAY] >> Mã OTP ({purpose}) gửi tới SĐT {cleanPhone} là: {code} (Hiệu lực 5 phút)");
            return code;
        }
    }

    public bool VerifyOtp(string phone, string purpose, string code)
    {
        lock (_lock)
        {
            var cleanPhone = phone.Trim();
            var key = $"{purpose.ToLower()}:{cleanPhone}";
            if (OtpStore.TryGetValue(key, out var item))
            {
                if (DateTime.UtcNow <= item.ExpiresAt && item.Code == code.Trim())
                {
                    OtpStore.Remove(key); // Dùng 1 lần rồi hủy
                    return true;
                }
            }
            return false;
        }
    }

    public RelayScheduleItem AddSchedule(int stationId, int deviceId, string type, string targetMode, int minutes, string timeOfDay = "")
    {
        lock (_lock)
        {
            var s = new RelayScheduleItem
            {
                Id = Schedules.Count > 0 ? Schedules.Max(x => x.Id) + 1 : 1,
                StationId = stationId,
                DeviceId = deviceId,
                Type = type,
                TargetMode = targetMode.ToUpperInvariant(),
                DurationMinutes = minutes,
                TimeOfDay = timeOfDay,
                TriggerAt = DateTime.UtcNow.AddMinutes(minutes),
                Executed = false,
                CreatedAt = TimeHelper.VnNowStr
            };
            Schedules.Add(s);
            return s;
        }
    }

    public List<RelayScheduleItem> GetActiveSchedules(int stationId)
    {
        lock (_lock)
        {
            var now = DateTime.UtcNow;
            return Schedules.Where(s => s.StationId == stationId && !s.Executed && s.TriggerAt > now).ToList();
        }
    }

    public bool CancelSchedule(int scheduleId)
    {
        lock (_lock)
        {
            var s = Schedules.FirstOrDefault(x => x.Id == scheduleId);
            if (s != null)
            {
                Schedules.Remove(s);
                return true;
            }
            return false;
        }
    }

    public TeamMessage AddTeamMessage(TeamMessage msg)
    {
        lock (_lock)
        {
            msg.Id = TeamMessages.Count > 0 ? TeamMessages.Max(m => m.Id) + 1 : 1;
            msg.CreatedAt = TimeHelper.VnNowStr;
            TeamMessages.Add(msg);
        }

        Task.Run(() =>
        {
            try
            {
                using var scope = _scopeFactory.CreateScope();
                var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
                db.TeamMessages.Add(new TeamMessage
                {
                    UserId = msg.UserId,
                    SenderName = msg.SenderName,
                    SenderRole = msg.SenderRole,
                    StationId = msg.StationId,
                    StationName = msg.StationName,
                    Category = msg.Category,
                    Content = msg.Content,
                    AttachedTelemetry = msg.AttachedTelemetry,
                    ImageUrl = msg.ImageUrl,
                    CreatedAt = msg.CreatedAt
                });
                db.SaveChanges();
            }
            catch (Exception ex)
            {
                Console.WriteLine(">> Loi luu tin nhan vao DB: " + ex.Message);
            }
        });

        return msg;
    }

    public List<TeamMessage> GetTeamMessages(int? stationId = null, int limit = 50)
    {
        lock (_lock)
        {
            var query = TeamMessages.AsEnumerable();
            if (stationId.HasValue)
            {
                if (stationId.Value == 0)
                {
                    // Kenh Chung (toan he thong, khong gan voi tram cu the)
                    query = query.Where(m => m.StationId == null || m.StationId == 0);
                }
                else if (stationId.Value > 0)
                {
                    // Kenh rieng cua tram cu the
                    query = query.Where(m => m.StationId == stationId.Value);
                }
                // Neu stationId < 0 (vi du -1) thi tra ve tat ca cac kenh
            }
            return query.OrderByDescending(m => m.Id).Take(limit).Reverse().ToList();
        }
    }

    public bool DeleteTeamMessage(int id, int currentUserId, bool isAdmin)
    {
        TeamMessage? target = null;
        lock (_lock)
        {
            target = TeamMessages.FirstOrDefault(m => m.Id == id);
            if (target == null) return false;
            if (!isAdmin && target.UserId != currentUserId) return false;
            TeamMessages.Remove(target);
        }

        Task.Run(() =>
        {
            try
            {
                using var scope = _scopeFactory.CreateScope();
                var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
                var dbMsg = db.TeamMessages.FirstOrDefault(m => m.Id == id);
                if (dbMsg != null)
                {
                    db.TeamMessages.Remove(dbMsg);
                    db.SaveChanges();
                }
            }
            catch { }
        });

        return true;
    }

    public List<StationActuator> GetStationActuators(int stationId)
    {
        lock (StationActuators)
        {
            if (!StationActuators.TryGetValue(stationId, out var list) || list == null || list.Count == 0)
            {
                list = CreateDefaultActuators(stationId);
                StationActuators[stationId] = list;
            }
            return list.ToList();
        }
    }

    private static List<StationActuator> CreateDefaultActuators(int stationId)
    {
        var now = TimeHelper.VnNowStr;
        return new List<StationActuator>
        {
            new()
            {
                Id = "misting",
                Name = "Hệ thống Phun sương Vi khí hậu",
                Type = "MISTING",
                State = false,
                Mode = "AUTO",
                Level = 1,
                Icon = "water_drop",
                Description = "Bơm cao áp phun sương siêu mịn làm mát & tạo ẩm khi thời tiết hanh khô (Độ ẩm < 60%)",
                UpdatedAt = now
            },
            new()
            {
                Id = "fan",
                Name = "Quạt Thông gió Đối lưu Khí",
                Type = "FAN",
                State = false,
                Mode = "AUTO",
                Level = 2,
                Icon = "air",
                Description = "Quạt hút nhiệt xả khí nóng và đối lưu khí tươi, đẩy ẩm chống va chạm điểm sương",
                UpdatedAt = now
            },
            new()
            {
                Id = "light",
                Name = "Đèn Sưởi Bức xạ & Quang hợp",
                Type = "LIGHT",
                State = false,
                Mode = "AUTO",
                Level = 2,
                Icon = "lightbulb",
                Description = "Đèn nhiệt hồng ngoại sấy khô chống ngưng tụ ẩm và bổ sung quang phổ khi trời tối",
                UpdatedAt = now
            },
            new()
            {
                Id = "pump",
                Name = "Bơm Nước Tưới Nhỏ giọt & Tuần hoàn",
                Type = "PUMP",
                State = false,
                Mode = "MANUAL",
                Level = 1,
                Icon = "opacity",
                Description = "Van điện từ & máy bơm cấp nước tưới tự động hoặc tuần hoàn nước dinh dưỡng",
                UpdatedAt = now
            },
            new()
            {
                Id = "siren",
                Name = "Còi Hú Báo động & Đèn Chớp Khẩn cấp",
                Type = "SIREN",
                State = false,
                Mode = "AUTO",
                Level = 1,
                Icon = "emergency",
                Description = "Còi hú 105dB kết hợp đèn chớp strobe cảnh báo sự cố vi khí hậu tại hiện trường (DANGER)",
                UpdatedAt = now
            }
        };
    }

    public StationActuator? UpdateActuator(int stationId, string actuatorId, bool? state, string? mode, int? level, string? operatorName)
    {
        lock (StationActuators)
        {
            if (!StationActuators.TryGetValue(stationId, out var list) || list == null || list.Count == 0)
            {
                list = CreateDefaultActuators(stationId);
                StationActuators[stationId] = list;
            }

            var item = list.FirstOrDefault(a => a.Id.Equals(actuatorId, StringComparison.OrdinalIgnoreCase));
            if (item == null) return null;

            if (state.HasValue) item.State = state.Value;
            if (!string.IsNullOrWhiteSpace(mode)) item.Mode = mode.ToUpperInvariant();
            if (level.HasValue && level.Value >= 1 && level.Value <= 3) item.Level = level.Value;
            item.UpdatedAt = TimeHelper.VnNowStr;

            AddRelayLog(new RelayLogItem
            {
                DeviceId = stationId,
                StationId = stationId,
                Action = item.State ? $"{item.Id.ToUpperInvariant()}_ON" : $"{item.Id.ToUpperInvariant()}_OFF",
                Source = item.Mode == "AUTO" ? "AUTO" : "MANUAL",
                Reason = $"Điều khiển {item.Name} -> {(item.State ? "BẬT" : "TẮT")} (Chế độ {item.Mode}, Cấp {item.Level})",
                FullName = operatorName ?? "Kỹ thuật viên",
                CreatedAt = TimeHelper.VnNowStr
            });

            return item;
        }
    }

    public List<AutomationRule> GetStationAutomations(int stationId)
    {
        lock (StationAutomations)
        {
            if (!StationAutomations.TryGetValue(stationId, out var list) || list == null || list.Count == 0)
            {
                list = CreateDefaultAutomations(stationId);
                StationAutomations[stationId] = list;
            }
            return list.ToList();
        }
    }

    private static List<AutomationRule> CreateDefaultAutomations(int stationId)
    {
        var now = TimeHelper.VnNowStr;
        return new List<AutomationRule>
        {
            new AutomationRule
            {
                Id = $"auto_{stationId}_1",
                StationId = stationId,
                Name = "Hạ nhiệt khẩn cấp",
                Icon = "ac_unit",
                IsEnabled = true,
                ConditionType = "TEMP_GT",
                ThresholdValue = 38.0,
                ActionType = "ACTUATOR_ON",
                TargetId = "fan",
                TargetName = "Quạt thông gió",
                TargetLevel = 3,
                DurationSeconds = 120,
                CreatedAt = now
            },
            new AutomationRule
            {
                Id = $"auto_{stationId}_2",
                StationId = stationId,
                Name = "Bổ sung độ ẩm tự động",
                Icon = "water_drop",
                IsEnabled = true,
                ConditionType = "HUM_LT",
                ThresholdValue = 45.0,
                ActionType = "ACTUATOR_ON",
                TargetId = "misting",
                TargetName = "Phun sương",
                TargetLevel = 1,
                DurationSeconds = 20,
                CreatedAt = now
            },
            new AutomationRule
            {
                Id = $"auto_{stationId}_3",
                StationId = stationId,
                Name = "Sấy khô chống đọng sương",
                Icon = "shield",
                IsEnabled = true,
                ConditionType = "DEW_MARGIN_LT",
                ThresholdValue = 2.0,
                ActionType = "ACTUATOR_ON",
                TargetId = "light",
                TargetName = "Đèn sưởi bức xạ",
                TargetLevel = 2,
                DurationSeconds = 180,
                CreatedAt = now
            },
            new AutomationRule
            {
                Id = $"auto_{stationId}_4",
                StationId = stationId,
                Name = "Bơm tưới giải nhiệt",
                Icon = "eco",
                IsEnabled = false,
                ConditionType = "TEMP_GT",
                ThresholdValue = 36.5,
                ActionType = "ACTUATOR_ON",
                TargetId = "pump",
                TargetName = "Máy bơm tưới",
                TargetLevel = 1,
                DurationSeconds = 300,
                CreatedAt = now
            },
            new AutomationRule
            {
                Id = $"auto_{stationId}_5",
                StationId = stationId,
                Name = "Báo động quá nhiệt nguy hiểm",
                Icon = "warning",
                IsEnabled = true,
                ConditionType = "TEMP_GT",
                ThresholdValue = 42.0,
                ActionType = "ACTUATOR_ON",
                TargetId = "siren",
                TargetName = "Còi hú báo động",
                TargetLevel = 1,
                DurationSeconds = 5,
                CreatedAt = now
            },
            new AutomationRule
            {
                Id = $"auto_{stationId}_6",
                StationId = stationId,
                Name = "Tự động bật đèn khi trời tối",
                Icon = "lightbulb",
                IsEnabled = true,
                ConditionType = "LIGHT_LT",
                ThresholdValue = 20.0,
                ActionType = "ACTUATOR_ON",
                TargetId = "light",
                TargetName = "Đèn quang hợp & sưởi",
                TargetLevel = 2,
                DurationSeconds = 0,
                CreatedAt = now
            }
        };
    }

    public AutomationRule AddOrUpdateAutomation(AutomationRule rule)
    {
        lock (StationAutomations)
        {
            if (!StationAutomations.TryGetValue(rule.StationId, out var list) || list == null)
            {
                list = CreateDefaultAutomations(rule.StationId);
                StationAutomations[rule.StationId] = list;
            }

            var existing = list.FirstOrDefault(r => r.Id == rule.Id);
            if (existing != null)
            {
                existing.Name = rule.Name;
                existing.Icon = rule.Icon;
                existing.IsEnabled = rule.IsEnabled;
                existing.ConditionType = rule.ConditionType;
                existing.ThresholdValue = rule.ThresholdValue;
                existing.ActionType = rule.ActionType;
                existing.TargetId = rule.TargetId;
                existing.TargetName = rule.TargetName;
                existing.TargetLevel = rule.TargetLevel;
                existing.DurationSeconds = rule.DurationSeconds;
                return existing;
            }
            else
            {
                if (string.IsNullOrWhiteSpace(rule.Id))
                    rule.Id = $"rule_{Guid.NewGuid().ToString("N")[..8]}";
                rule.CreatedAt = TimeHelper.VnNowStr;
                list.Add(rule);
                return rule;
            }
        }
    }

    public bool ToggleAutomation(string ruleId, bool isEnabled)
    {
        lock (StationAutomations)
        {
            foreach (var list in StationAutomations.Values)
            {
                var rule = list.FirstOrDefault(r => r.Id == ruleId);
                if (rule != null)
                {
                    rule.IsEnabled = isEnabled;
                    return true;
                }
            }
            return false;
        }
    }

    public bool DeleteAutomation(string ruleId)
    {
        lock (StationAutomations)
        {
            foreach (var list in StationAutomations.Values)
            {
                var removed = list.RemoveAll(r => r.Id == ruleId);
                if (removed > 0) return true;
            }
            return false;
        }
    }

    public bool RunAutomationById(string ruleId, string operatorName)
    {
        AutomationRule? rule = null;
        lock (StationAutomations)
        {
            foreach (var list in StationAutomations.Values)
            {
                rule = list.FirstOrDefault(r => r.Id == ruleId);
                if (rule != null) break;
            }
        }

        if (rule == null) return false;
        return TriggerAutomationRule(rule, operatorName);
    }

    public bool TriggerAutomationRule(AutomationRule rule, string operatorName = "Hệ thống Tự động hóa")
    {
        lock (StationAutomations)
        {
            rule.LastTriggeredAt = TimeHelper.VnNowStr;
            rule.TriggerCount++;
        }

        if (rule.TargetId.Equals("relay", StringComparison.OrdinalIgnoreCase))
        {
            var isTurnOn = rule.ActionType == "RELAY_ON" || rule.ActionType == "ACTUATOR_ON";
            var dev = Devices.FirstOrDefault(d => d.StationId == rule.StationId) ?? GetDevice(rule.StationId);
            if (dev != null)
            {
                dev.RelayState = isTurnOn ? 1 : 0;
                dev.RelayMode = "AUTO";
                AddRelayLog(new RelayLogItem
                {
                    DeviceId = dev.Id,
                    StationId = dev.StationId,
                    Action = isTurnOn ? "RELAY_ON" : "RELAY_OFF",
                    Source = "AUTO",
                    Reason = $"Kịch bản tự động kích hoạt: {rule.Name}",
                    FullName = operatorName,
                    CreatedAt = TimeHelper.VnNowStr
                });
            }
        }
        else
        {
            var isTurnOn = rule.ActionType == "ACTUATOR_ON";
            UpdateActuator(rule.StationId, rule.TargetId, isTurnOn, "AUTO", rule.TargetLevel ?? 1, operatorName);

            if (isTurnOn && rule.DurationSeconds.HasValue && rule.DurationSeconds.Value > 0)
            {
                _ = Task.Run(async () =>
                {
                    try
                    {
                        await Task.Delay(rule.DurationSeconds.Value * 1000);
                        UpdateActuator(rule.StationId, rule.TargetId, false, "AUTO", rule.TargetLevel ?? 1, $"Tự động tắt sau {rule.DurationSeconds.Value}s ({rule.Name})");
                    }
                    catch { }
                });
            }
        }

        return true;
    }

    public void EvaluateAutomationRules(int stationId, double? airTemp, double? airHum, double? dewPoint, double? probeTemp, int? lightPct = null, int? aqi = null, int? gasPpm = null, double? soilHum = null, int? waterLevel = null)
    {
        if (!airTemp.HasValue && !airHum.HasValue && !lightPct.HasValue && !aqi.HasValue && !gasPpm.HasValue && !soilHum.HasValue && !waterLevel.HasValue) return;
        var aTemp = airTemp ?? probeTemp ?? 0.0;
        var aHum = airHum ?? 0.0;
        var dPoint = dewPoint ?? aTemp;
        var dewMargin = aTemp - dPoint;

        List<AutomationRule> toTrigger = new();
        lock (StationAutomations)
        {
            if (!StationAutomations.TryGetValue(stationId, out var list) || list == null || list.Count == 0)
            {
                list = CreateDefaultAutomations(stationId);
                StationAutomations[stationId] = list;
            }

            var now = DateTimeOffset.UtcNow;

            foreach (var rule in list.Where(r => r.IsEnabled))
            {
                // Cooldown: at least duration or 30 seconds
                if (!string.IsNullOrEmpty(rule.LastTriggeredAt))
                {
                    if (DateTimeOffset.TryParse(rule.LastTriggeredAt, out var lastTime))
                    {
                        var cooldown = Math.Max(30, rule.DurationSeconds ?? 60);
                        if ((now - lastTime).TotalSeconds < cooldown)
                        {
                            continue;
                        }
                    }
                }

                bool triggered = false;
                switch (rule.ConditionType.ToUpperInvariant())
                {
                    case "TEMP_GT":
                        triggered = aTemp >= rule.ThresholdValue;
                        break;
                    case "TEMP_LT":
                        triggered = aTemp <= rule.ThresholdValue;
                        break;
                    case "HUM_GT":
                        triggered = aHum >= rule.ThresholdValue;
                        break;
                    case "HUM_LT":
                        triggered = aHum <= rule.ThresholdValue;
                        break;
                    case "LIGHT_LT":
                        triggered = (lightPct ?? 100) <= rule.ThresholdValue;
                        break;
                    case "LIGHT_GT":
                        triggered = (lightPct ?? 0) >= rule.ThresholdValue;
                        break;
                    case "DEW_MARGIN_LT":
                        triggered = dewMargin <= rule.ThresholdValue;
                        break;
                    case "GAS_GT":
                        triggered = (gasPpm ?? 45) >= rule.ThresholdValue;
                        break;
                    case "AQI_GT":
                        triggered = (aqi ?? 42) >= rule.ThresholdValue;
                        break;
                    case "WATER_LT":
                        triggered = (waterLevel ?? 80) <= rule.ThresholdValue;
                        break;
                    case "SOIL_LT":
                        triggered = (soilHum ?? 65.0) <= rule.ThresholdValue;
                        break;
                }

                if (triggered)
                {
                    toTrigger.Add(rule);
                }
            }
        }

        foreach (var rule in toTrigger)
        {
            TriggerAutomationRule(rule, $"Kịch bản tự động kích hoạt: {rule.Name}");
        }
    }
}

