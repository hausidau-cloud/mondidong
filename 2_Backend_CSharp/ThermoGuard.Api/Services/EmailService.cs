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
        var senderPassword = _config["Email:SenderPassword"]?.Trim() ?? "";
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
                Credentials = new NetworkCredential(senderEmail, senderPassword)
            };

            await client.SendMailAsync(mail);
            Console.WriteLine($"[EmailService] >> Đã gửi thành công OTP {code} tới email {toEmail}");
            return (true, $"Mã OTP đã được gửi đến email {toEmail}!");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[EmailService Error] >> {ex.Message}");
            return (false, ex.Message);
        }
    }
}
