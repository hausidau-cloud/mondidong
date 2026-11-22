using System.Net;
using System.Net.Mail;

namespace ThermoGuard.Api.Services;

public class EmailService
{
    private readonly IConfiguration _config;

    public EmailService(IConfiguration config)
    {
        _config = config;
    }

    public async Task<(bool ok, string message)> SendOtpEmailAsync(string toEmail, string code, string purpose = "register")
    {
        var smtpHost = _config["Email:SmtpHost"]?.Trim() ?? "smtp.gmail.com";
        var smtpPort = _config.GetValue<int>("Email:SmtpPort", 587);
        var senderEmail = _config["Email:SenderEmail"]?.Trim() ?? "";
        var senderPassword = _config["Email:SenderPassword"]?.Trim().Replace(" ", "") ?? "";
        var senderName = _config["Email:SenderName"]?.Trim() ?? "ThermoGuard IoT";

        if (string.IsNullOrWhiteSpace(senderEmail) || string.IsNullOrWhiteSpace(senderPassword))
        {
            return (false, "Chưa cấu hình SenderEmail và SenderPassword trong appsettings.json");
        }

        try
        {
            var actionText = purpose == "forgot_password" ? "đặt lại mật khẩu" : "đăng ký tài khoản";

            var mail = new MailMessage
            {
                From = new MailAddress(senderEmail, senderName),
                Subject = $"[ThermoGuard] Mã xác thực OTP {actionText}: {code}",
                IsBodyHtml = true,
                Body = $@"
<div style=""font-family: Arial, sans-serif; max-width: 500px; margin: 0 auto; padding: 25px; border-radius: 12px; background-color: #0F172A; color: #FFFFFF;"">
    <div style=""text-align: center; margin-bottom: 20px;"">
        <h2 style=""color: #38BDF8; margin: 0; font-size: 24px;"">ThermoGuard IoT</h2>
        <p style=""color: #94A3B8; font-size: 14px; margin-top: 5px;"">Hệ thống Giám sát & Cảnh báo Môi trường</p>
    </div>
    <div style=""background-color: #1E293B; border-radius: 10px; padding: 20px; text-align: center; border: 1px solid #334155;"">
        <p style=""color: #E2E8F0; font-size: 15px; margin-bottom: 15px;"">Mã xác thực OTP của bạn cho thao tác <b>{actionText}</b> là:</p>
        <div style=""font-size: 32px; font-weight: bold; letter-spacing: 6px; color: #38BDF8; padding: 12px 20px; background-color: #0F172A; border-radius: 8px; display: inline-block; border: 1px dashed #38BDF8;"">
            {code}
        </div>
        <p style=""color: #94A3B8; font-size: 13px; margin-top: 15px;"">Mã này có hiệu lực trong vòng <b>5 phút</b>. Vui lòng không chia sẻ mã này cho bất kỳ ai.</p>
    </div>
    <p style=""color: #64748B; font-size: 12px; text-align: center; margin-top: 20px;"">Đây là email tự động từ hệ thống ThermoGuard, vui lòng không trả lời email này.</p>
</div>"
            };

            mail.To.Add(toEmail.Trim());

            using var client = new SmtpClient(smtpHost, smtpPort)
            {
                EnableSsl = true,
                UseDefaultCredentials = false,
                Credentials = new NetworkCredential(senderEmail, senderPassword),
                Timeout = 4000
            };

            var sendTask = client.SendMailAsync(mail);
            var timeoutTask = Task.Delay(4000);
            var completed = await Task.WhenAny(sendTask, timeoutTask);
            if (completed == timeoutTask)
            {
                Console.WriteLine("[EmailService] >> SMTP connection timeout (likely blocked by cloud host firewall)");
                return (false, "SMTP connection timed out (cloud host blocked port 587)");
            }
            await sendTask;
            Console.WriteLine($"[EmailService] >> Đã gửi thành công OTP {code} tới email {toEmail}");
            return (true, $"Mã OTP đã được gửi đến email {toEmail}!");
        }
        catch (Exception ex)
        {
            var msg = ex.InnerException?.Message ?? ex.Message;
            Console.WriteLine($"[EmailService Error] >> {msg}");
            return (false, msg);
        }
    }

    public async Task<(bool ok, string message)> SendAlertEmailAsync(
        string toEmail,
        string recipientName,
        string stationName,
        string alertLevel,
        string alertType,
        string alertMessage,
        double? temp,
        double? hum,
        string time)
    {
        var smtpHost = _config["Email:SmtpHost"]?.Trim() ?? "smtp.gmail.com";
        var smtpPort = _config.GetValue<int>("Email:SmtpPort", 587);
        var senderEmail = _config["Email:SenderEmail"]?.Trim() ?? "";
        var senderPassword = _config["Email:SenderPassword"]?.Trim().Replace(" ", "") ?? "";
        var senderName = _config["Email:SenderName"]?.Trim() ?? "ThermoGuard IoT";

        if (string.IsNullOrWhiteSpace(senderEmail) || string.IsNullOrWhiteSpace(senderPassword))
        {
            return (false, "Chưa cấu hình tài khoản gửi Gmail SMTP trong appsettings.json");
        }

        try
        {
            var isDanger = alertLevel.Equals("DANGER", StringComparison.OrdinalIgnoreCase);
            var bannerColor = isDanger ? "#EF4444" : "#F59E0B";
            var bannerTitle = isDanger ? "🚨 CẢNH BÁO NGUY HIỂM KHẨN CẤP" : "⚠️ CẢNH BÁO VI PHẠM NGƯỠNG";

            var mail = new MailMessage
            {
                From = new MailAddress(senderEmail, senderName),
                Subject = $"[{alertLevel}] {stationName} vi phạm ngưỡng: {alertMessage}",
                IsBodyHtml = true,
                Body = $@"
<div style=""font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 0; border-radius: 14px; background-color: #0F172A; color: #FFFFFF; overflow: hidden; border: 1px solid #334155;"">
    <div style=""background-color: {bannerColor}; padding: 18px 24px; text-align: center;"">
        <h2 style=""color: #FFFFFF; margin: 0; font-size: 20px; letter-spacing: 0.5px;"">{bannerTitle}</h2>
        <p style=""color: rgba(255,255,255,0.9); font-size: 13px; margin: 4px 0 0 0;"">Hệ thống Giám sát Vi khí hậu & Cảnh báo Sớm ThermoGuard</p>
    </div>

    <div style=""padding: 24px;"">
        <p style=""font-size: 15px; color: #E2E8F0; margin-top: 0;"">Xin chào <b>{recipientName}</b>,</p>
        <p style=""font-size: 14px; color: #94A3B8; line-height: 1.5;"">
            Hệ thống phát hiện trạm giám sát của bạn đang xảy ra sự cố vượt ngưỡng an toàn cho phép. Dưới đây là thông tin chi tiết:
        </p>

        <div style=""background-color: #1E293B; border-radius: 10px; padding: 16px; margin: 18px 0; border: 1px solid #334155;"">
            <table style=""width: 100%; border-collapse: collapse; font-size: 13.5px;"">
                <tr>
                    <td style=""padding: 8px 0; color: #94A3B8; width: 140px;"">📍 Trạm giám sát:</td>
                    <td style=""padding: 8px 0; color: #FFFFFF; font-weight: bold;"">{stationName}</td>
                </tr>
                <tr>
                    <td style=""padding: 8px 0; color: #94A3B8;"">⚡ Mức độ:</td>
                    <td style=""padding: 8px 0; color: {bannerColor}; font-weight: bold;"">{alertLevel}</td>
                </tr>
                <tr>
                    <td style=""padding: 8px 0; color: #94A3B8;"">🚨 Chi tiết sự cố:</td>
                    <td style=""padding: 8px 0; color: #F1F5F9; font-weight: 600;"">{alertMessage}</td>
                </tr>
                {(temp.HasValue ? $@"<tr>
                    <td style=""padding: 8px 0; color: #94A3B8;"">🌡️ Nhiệt độ hiện thời:</td>
                    <td style=""padding: 8px 0; color: #38BDF8; font-weight: bold;"">{temp.Value:F1}°C</td>
                </tr>" : "")}
                {(hum.HasValue ? $@"<tr>
                    <td style=""padding: 8px 0; color: #94A3B8;"">💧 Độ ẩm không khí:</td>
                    <td style=""padding: 8px 0; color: #38BDF8; font-weight: bold;"">{hum.Value:F0}%</td>
                </tr>" : "")}
                <tr>
                    <td style=""padding: 8px 0; color: #94A3B8;"">⏱️ Thời gian ghi nhận:</td>
                    <td style=""padding: 8px 0; color: #CBD5E1;"">{time}</td>
                </tr>
            </table>
        </div>

        <div style=""background-color: rgba(56, 189, 248, 0.1); border-left: 4px solid #38BDF8; padding: 12px 16px; border-radius: 4px; margin-bottom: 20px;"">
            <p style=""margin: 0; font-size: 13px; color: #38BDF8; font-weight: bold;"">HÀNH ĐỘNG KHUYẾN NGHỊ:</p>
            <p style=""margin: 4px 0 0 0; font-size: 12.5px; color: #CBD5E1; line-height: 1.4;"">
                Vui lòng mở ứng dụng di động ThermoGuard để kiểm tra tình trạng vi khí hậu hiện trường, kích hoạt quạt đối lưu, phun sương làm mát hoặc ngắt rơ-le để bảo vệ thiết bị.
            </p>
        </div>
    </div>

    <div style=""background-color: #0A0F1D; padding: 14px 24px; text-align: center; border-top: 1px solid #1E293B;"">
        <p style=""color: #64748B; font-size: 11.5px; margin: 0;"">
            Email tự động gửi từ hệ thống ThermoGuard IoT tới <b>{toEmail}</b>. Vui lòng không phản hồi thư này.
        </p>
    </div>
</div>"
            };

            mail.To.Add(toEmail.Trim());

            using var client = new SmtpClient(smtpHost, smtpPort)
            {
                EnableSsl = true,
                UseDefaultCredentials = false,
                Credentials = new NetworkCredential(senderEmail, senderPassword),
                Timeout = 5000
            };

            var sendTask = client.SendMailAsync(mail);
            var timeoutTask = Task.Delay(5000);
            var completed = await Task.WhenAny(sendTask, timeoutTask);
            if (completed == timeoutTask)
            {
                Console.WriteLine($"[EmailService] >> Timeout gửi email cảnh báo tới {toEmail}");
                return (false, "Timeout kết nối máy chủ gửi email");
            }
            await sendTask;
            Console.WriteLine($"[EmailService] >> Đã gửi thành công email cảnh báo tới {toEmail}");
            return (true, $"Đã gửi email cảnh báo tới {toEmail}");
        }
        catch (Exception ex)
        {
            var msg = ex.InnerException?.Message ?? ex.Message;
            Console.WriteLine($"[EmailService Error] >> {msg}");
            return (false, msg);
        }
    }
}
