using System.ComponentModel.DataAnnotations.Schema;
using System.Text.Json.Serialization;

namespace ThermoGuard.Api.Models;

public static class TimeHelper
{
    public static DateTime VnNow => DateTime.UtcNow.AddHours(7);
    public static string VnNowStr => DateTime.UtcNow.AddHours(7).ToString("yyyy-MM-dd HH:mm:ss");
}

public class AppUser
{
    [JsonPropertyName("id")]
    public int Id { get; set; }

    [JsonPropertyName("username")]
    public string Username { get; set; } = "admin";

    [JsonPropertyName("password")]
    public string Password { get; set; } = "admin123";

    [JsonPropertyName("full_name")]
    public string FullName { get; set; } = "Quản trị viên";

    [JsonPropertyName("phone")]
    public string? Phone { get; set; } = "";

    [JsonPropertyName("email")]
    public string? Email { get; set; } = "";

    [JsonPropertyName("role")]
    public string Role { get; set; } = "admin"; // admin | viewer

    [JsonPropertyName("api_token")]
    public string? ApiToken { get; set; }

    [JsonPropertyName("token_expires")]
    public DateTime? TokenExpires { get; set; }

    [NotMapped]
    [JsonPropertyName("station_ids")]
    public List<int> StationIds { get; set; } = new();
}

public class StationAssignment
{
    [JsonPropertyName("id")]
    public int Id { get; set; }

    [JsonPropertyName("user_id")]
    public int UserId { get; set; }

    [JsonPropertyName("device_id")]
    public int DeviceId { get; set; }

    [JsonPropertyName("assigned_at")]
    public DateTime AssignedAt { get; set; } = TimeHelper.VnNow;
}


public class StationItem
{
    [JsonPropertyName("id")]
    public int Id { get; set; }

    [JsonPropertyName("name")]
    public string Name { get; set; } = "Trạm Giám Sát";

    [JsonPropertyName("location")]
    public string? Location { get; set; } = "Phòng Lab";

    [JsonPropertyName("description")]
    public string? Description { get; set; } = "Khu vực giám sát IoT";

    [JsonPropertyName("relay_label")]
    public string RelayLabel { get; set; } = "Bóng đèn 220V / Rơ-le";

    [System.ComponentModel.DataAnnotations.Schema.NotMapped]
    [JsonPropertyName("invite_code")]
    public string InviteCode { get; set; } = "";

    [JsonPropertyName("created_at")]
    public string CreatedAt { get; set; } = TimeHelper.VnNowStr;
}

public class Device
{
    [JsonPropertyName("id")]
    public int Id { get; set; }

    [JsonPropertyName("station_id")]
    public int? StationId { get; set; }

    [JsonPropertyName("device_code")]
    public string DeviceCode { get; set; } = "PICO-01";

    [JsonPropertyName("api_key")]
    public string ApiKey { get; set; } = "a1b2c3d4e5f60718293a4b5c6d7e8f90";

    [JsonPropertyName("name")]
    public string Name { get; set; } = "Trạm Giám Sát Pico 2 W";

    [JsonPropertyName("profile")]
    public string Profile { get; set; } = "cabinet"; // cabinet | aquarium | pharma

    [JsonPropertyName("location")]
    public string? Location { get; set; } = "Phòng Lab IoT";

    [JsonPropertyName("description")]
    public string? Description { get; set; } = "Hệ thống giám sát nhiệt độ, độ ẩm, que nước và ánh sáng";

    [JsonPropertyName("relay_label")]
    public string RelayLabel { get; set; } = "Đèn sưởi / Rơ-le";

    [JsonPropertyName("relay_mode")]
    public string RelayMode { get; set; } = "AUTO"; // AUTO | ON | OFF

    [JsonPropertyName("relay_state")]
    public int RelayState { get; set; } = 0; // 0: OFF, 1: ON

    [JsonPropertyName("status")]
    public string Status { get; set; } = "OFFLINE"; // OK | WARNING | DANGER | OFFLINE

    [JsonPropertyName("online")]
    public bool Online => Status != "OFFLINE";

    [JsonPropertyName("air_temp")]
    public double? AirTemp { get; set; }

    [JsonPropertyName("air_hum")]
    public double? AirHum { get; set; }

    [JsonPropertyName("dew_point")]
    public double? DewPoint { get; set; }

    [JsonPropertyName("probe_temp")]
    public double? ProbeTemp { get; set; }

    [NotMapped]
    [JsonPropertyName("pico_temp")]
    public double? PicoTemp { get; set; }

    [JsonPropertyName("light_raw")]
    public int LightRaw { get; set; } = 0;

    [JsonPropertyName("light_pct")]
    public int LightPct { get; set; } = 0;

    [JsonPropertyName("air_temp_max")]
    public double AirTempMax { get; set; } = 40.0;

    [JsonPropertyName("air_hum_max")]
    public double AirHumMax { get; set; } = 75.0;

    [JsonPropertyName("probe_temp_min")]
    public double ProbeTempMin { get; set; } = 0.0;

    [JsonPropertyName("probe_temp_max")]
    public double ProbeTempMax { get; set; } = 60.0;

    [JsonPropertyName("dew_margin")]
    public double DewMargin { get; set; } = 3.0;

    [JsonPropertyName("hysteresis")]
    public double Hysteresis { get; set; } = 1.5;

    [JsonPropertyName("offset_air")]
    public double OffsetAir { get; set; } = 0.0;

    [JsonPropertyName("offset_probe")]
    public double OffsetProbe { get; set; } = 0.0;

    [JsonPropertyName("offline_after")]
    public int OfflineAfter { get; set; } = 60;

    [JsonPropertyName("send_interval")]
    public int SendInterval { get; set; } = 3;

    [JsonPropertyName("rssi")]
    public int? Rssi { get; set; }

    [JsonPropertyName("last_seen")]
    public string? LastSeen { get; set; }

    [JsonPropertyName("firmware")]
    public string? Firmware { get; set; } = "pico2w-csharp-2.1";

    [JsonPropertyName("oled_msg")]
    public string? OledMsg { get; set; } = "";

    [JsonPropertyName("reason")]
    public string Reason { get; set; } = "";

    [JsonPropertyName("open_alerts")]
    public int OpenAlerts { get; set; } = 0;

    [JsonIgnore]
    public long LastTs { get; set; } = 0;

    [JsonIgnore]
    public DateTime? LastSeenTime { get; set; }
}

public class ReadingRecord
{
    [JsonPropertyName("id")]
    public long Id { get; set; }

    [JsonPropertyName("device_id")]
    public int DeviceId { get; set; }

    [JsonPropertyName("air_temp")]
    public double? AirTemp { get; set; }

    [JsonPropertyName("air_hum")]
    public double? AirHum { get; set; }

    [JsonPropertyName("dew_point")]
    public double? DewPoint { get; set; }

    [JsonPropertyName("probe_temp")]
    public double? ProbeTemp { get; set; }

    [NotMapped]
    [JsonPropertyName("pico_temp")]
    public double? PicoTemp { get; set; }

    [JsonPropertyName("light_pct")]
    public int LightPct { get; set; }

    [JsonPropertyName("relay_state")]
    public int RelayState { get; set; }

    [JsonPropertyName("status")]
    public string Status { get; set; } = "OK";

    [JsonPropertyName("rssi")]
    public int? Rssi { get; set; }

    [JsonPropertyName("recorded_at")]
    public string RecordedAt { get; set; } = TimeHelper.VnNowStr;
}

public class AlertItem
{
    [JsonPropertyName("id")]
    public int Id { get; set; }

    [JsonPropertyName("device_id")]
    public int DeviceId { get; set; }

    [JsonPropertyName("level")]
    public string Level { get; set; } = "WARNING"; // WARNING | DANGER

    [JsonPropertyName("type")]
    public string Type { get; set; } = ""; // AIR_TEMP_HIGH | PROBE_HIGH | OFFLINE

    [JsonPropertyName("message")]
    public string Message { get; set; } = "";

    [JsonPropertyName("is_resolved")]
    public bool IsResolved { get; set; } = false;

    [JsonPropertyName("created_at")]
    public string CreatedAt { get; set; } = TimeHelper.VnNowStr;

    [JsonPropertyName("resolved_at")]
    public string? ResolvedAt { get; set; }
}

public class RelayLogItem
{
    [JsonPropertyName("id")]
    public int Id { get; set; }

    [JsonPropertyName("action")]
    public string Action { get; set; } = "ON";

    [JsonPropertyName("source")]
    public string Source { get; set; } = "AUTO";

    [JsonPropertyName("reason")]
    public string Reason { get; set; } = "";

    [JsonPropertyName("full_name")]
    public string? FullName { get; set; }

    [JsonPropertyName("created_at")]
    public string CreatedAt { get; set; } = TimeHelper.VnNowStr;
}

public class IngestRequest
{
    [JsonPropertyName("device_code")]
    public string? DeviceCode { get; set; }

    [JsonPropertyName("ts")]
    public long Ts { get; set; }

    [JsonPropertyName("payload")]
    public string? Payload { get; set; }

    [JsonPropertyName("sig")]
    public string? Sig { get; set; }

    // Direct JSON payload fallback for easy testing
    [JsonPropertyName("api_key")]
    public string? ApiKey { get; set; }

    [JsonPropertyName("air_temp")]
    public double? AirTemp { get; set; }

    [JsonPropertyName("air_hum")]
    public double? AirHum { get; set; }

    [JsonPropertyName("probe_temp")]
    public double? ProbeTemp { get; set; }

    [JsonPropertyName("pico_temp")]
    public double? PicoTemp { get; set; }

    [JsonPropertyName("dew_point")]
    public double? DewPoint { get; set; }

    [JsonPropertyName("light_raw")]
    public int? LightRaw { get; set; }

    [JsonPropertyName("light_pct")]
    public int? LightPct { get; set; }

    [JsonPropertyName("relay_state")]
    public int? RelayState { get; set; }

    [JsonPropertyName("rssi")]
    public int? Rssi { get; set; }

    [JsonPropertyName("fw")]
    public string? Fw { get; set; }
}

public class OtpItem
{
    public string Phone { get; set; } = "";
    public string Code { get; set; } = "";
    public string Purpose { get; set; } = ""; // register | forgot_password
    public DateTime ExpiresAt { get; set; }
}

