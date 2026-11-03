using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace ThermoGuard.Api.Services;

public class SmsService
{
    private readonly IConfiguration _config;
    private static readonly HttpClient _http = new();

    public SmsService(IConfiguration config)
    {
        _config = config;
    }

    public async Task<(bool ok, string message)> SendOtpAsync(string phone, string code)
    {
        var token = _config["SpeedSMS:AccessToken"]?.Trim() ?? "";
        var enabled = _config.GetValue<bool>("SpeedSMS:Enabled", true);

        if (!enabled || string.IsNullOrWhiteSpace(token))
        {
            return (false, "SpeedSMS chưa được cấu hình AccessToken");
        }

        try
        {
            // Chuẩn hóa số điện thoại: 0855521052 -> 84855521052
            var cleanPhone = phone.Trim();
            if (cleanPhone.StartsWith("0"))
            {
                cleanPhone = "84" + cleanPhone[1..];
            }
            else if (!cleanPhone.StartsWith("84"))
            {
                cleanPhone = "84" + cleanPhone;
            }

            var content = $"Ma xac thuc OTP ThermoGuard cua ban la: {code}. Hieu luc trong 5 phut.";

            var request = new HttpRequestMessage(HttpMethod.Post, "https://api.speedsms.vn/index.php/sms/send");
            var authBytes = Encoding.ASCII.GetBytes($"{token}:x");
            request.Headers.Authorization = new AuthenticationHeaderValue("Basic", Convert.ToBase64String(authBytes));

            var deviceId = _config["SpeedSMS:DeviceId"]?.Trim() ?? "";
            var isGateway = !string.IsNullOrWhiteSpace(deviceId);
            var smsType = isGateway ? 5 : 2;
            var sender = isGateway ? deviceId : (_config["SpeedSMS:Sender"]?.Trim() ?? "");

            var payload = new
            {
                to = new[] { cleanPhone },
                content = content,
                sms_type = smsType,
                smsType = smsType,
                sender = sender
            };

            request.Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");

            var response = await _http.SendAsync(request);
            var resBody = await response.Content.ReadAsStringAsync();

            Console.WriteLine($"[SpeedSMS API] Phản hồi ({response.StatusCode}): {resBody}");

            if (response.IsSuccessStatusCode && resBody.Contains("\"status\":\"success\""))
            {
                return (true, "Tin nhắn SMS OTP đã được gửi thành công đến số " + cleanPhone);
            }
            else
            {
                return (false, $"SpeedSMS: {resBody}");
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[SpeedSMS Error] {ex.Message}");
            return (false, ex.Message);
        }
    }
}
