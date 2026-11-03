using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ThermoGuard.Api.Data;
using ThermoGuard.Api.Models;
using ThermoGuard.Api.Services;

namespace ThermoGuard.Api.Controllers;

public class UserCreateRequest
{
    public string username { get; set; } = "sinhvien";
    public string password { get; set; } = "123";
    public string full_name { get; set; } = "Nguyễn Văn Test";
    public string role { get; set; } = "viewer";
    public string? old { get; set; }
    public string? @new { get; set; }
    public List<int>? station_ids { get; set; }
}

public class UpdateStationsRequest
{
    public List<int> station_ids { get; set; } = new();
}

public class UserLoginRequest
{
    public string username { get; set; } = "admin";
    public string password { get; set; } = "password123";
}

public class PasswordChangeRequest
{
    public string old { get; set; } = "";
    public string @new { get; set; } = "";
}

public class SendOtpRequest
{
    public string phone { get; set; } = "";
    public string purpose { get; set; } = "register"; // register | forgot_password
}

public class UserRegisterRequest
{
    public string username { get; set; } = "";
    public string password { get; set; } = "";
    public string full_name { get; set; } = "";
    public string phone { get; set; } = "";
    public string? otp { get; set; }
}

public class ForgotPasswordRequest
{
    public string phone { get; set; } = "";
    public string otp { get; set; } = "";
    public string new_password { get; set; } = "";
}


[ApiController]
[Tags("Auth")]
[Route("api/auth")]
public class AuthController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly DataStore _store;
    private readonly SmsService _sms;

    public AuthController(AppDbContext db, DataStore store, SmsService sms)
    {
        _db = db;
        _store = store;
        _sms = sms;
    }

    /// <summary>
    /// GET /api/auth/me: Kiểm tra thông tin phiên đăng nhập của người dùng hiện tại
    /// </summary>
    [HttpGet("me")]
    public IActionResult GetMe()
    {
        var cur = GetCurrentUser();
        if (cur == null) return Unauthorized(new { ok = false, error = "Chưa đăng nhập" });
        return Ok(new
        {
            ok = true,
            user = new
            {
                id = cur.Id,
                username = cur.Username,
                full_name = cur.FullName,
                role = cur.Role,
                station_ids = _store.GetStationIdsForUser(cur.Id)
            }
        });
    }

    /// <summary>
    /// PUT /api/auth/password: Đổi mật khẩu tài khoản đang đăng nhập (Chuẩn RESTful PUT)
    /// </summary>
    [HttpPut("password")]
    public IActionResult ChangePassword([FromBody] PasswordChangeRequest req)
    {
        var cur = GetCurrentUser();
        if (cur == null) return Unauthorized(new { ok = false, error = "Chưa đăng nhập" });
        var userInDb = _db.Users.Find(cur.Id);
        if (userInDb == null || userInDb.Password != req.old)
        {
            return BadRequest(new { ok = false, error = "Mật khẩu cũ không đúng" });
        }
        if (string.IsNullOrWhiteSpace(req.@new))
        {
            return BadRequest(new { ok = false, error = "Mật khẩu mới không được để trống" });
        }
        userInDb.Password = req.@new.Trim();
        _db.SaveChanges();
        return Ok(new { ok = true, message = "Đổi mật khẩu thành công" });
    }

    [HttpGet]
    [ApiExplorerSettings(IgnoreApi = true)]
    public IActionResult Get([FromQuery] string? action)
    {
        // Nếu App Flutter gọi ?action=me -> trả về tài khoản hiện tại
        if (string.Equals(action, "me", StringComparison.OrdinalIgnoreCase))
        {
            var cur = GetCurrentUser() ?? _db.Users.AsNoTracking().FirstOrDefault();
            return Ok(new
            {
                ok = true,
                user = cur != null ? new
                {
                    id = cur.Id,
                    username = cur.Username,
                    full_name = cur.FullName,
                    role = cur.Role,
                    station_ids = _store.GetStationIdsForUser(cur.Id)
                } : null
            });
        }

        // Mặc định bấm Try it out trên Swagger -> Trả về tất cả tài khoản trong Database kèm trạm
        var allUsers = _db.Users.AsNoTracking().ToList().Select(u => new
        {
            id = u.Id,
            username = u.Username,
            full_name = u.FullName,
            role = u.Role,
            station_ids = _store.GetStationIdsForUser(u.Id)
        }).ToList();

        return Ok(new
        {
            ok = true,
            total = allUsers.Count,
            users = allUsers
        });
    }


    [HttpPost]
    [ApiExplorerSettings(IgnoreApi = true)]
    public IActionResult Post([FromQuery] string? action, [FromBody] UserCreateRequest req)
    {
        // 1. App Flutter đăng nhập bằng POST /api/auth?action=login
        if (string.Equals(action, "login", StringComparison.OrdinalIgnoreCase))
        {
            return LoginInternal(req.username, req.password);
        }

        // 2. Đổi mật khẩu ?action=password
        if (string.Equals(action, "password", StringComparison.OrdinalIgnoreCase))
        {
            var cur = GetCurrentUser();
            if (cur == null) return Unauthorized(new { ok = false, error = "Chưa đăng nhập" });
            var userInDb = _db.Users.Find(cur.Id);
            if (userInDb == null || userInDb.Password != req.old)
            {
                return BadRequest(new { ok = false, error = "Mật khẩu cũ không đúng" });
            }
            if (string.IsNullOrWhiteSpace(req.@new))
            {
                return BadRequest(new { ok = false, error = "Mật khẩu mới không được để trống" });
            }
            userInDb.Password = req.@new.Trim();
            _db.SaveChanges();
            return Ok(new { ok = true, message = "Đổi mật khẩu thành công" });
        }

        // 3. Mặc định trên Swagger POST /api/auth -> Tạo tài khoản mới vào SQL Server (SSMS)
        if (string.IsNullOrWhiteSpace(req.username) || string.IsNullOrWhiteSpace(req.password))
        {
            return BadRequest(new { ok = false, error = "Vui lòng nhập username và password" });
        }

        var uName = req.username.Trim();
        if (_db.Users.Any(u => u.Username.ToLower() == uName.ToLower()))
        {
            return BadRequest(new { ok = false, error = $"Tên đăng nhập '{uName}' đã tồn tại trong SQL Server!" });
        }

        var newUser = new AppUser
        {
            Id = 0,
            Username = uName,
            Password = req.password,
            FullName = string.IsNullOrWhiteSpace(req.full_name) ? uName : req.full_name.Trim(),
            Role = string.IsNullOrWhiteSpace(req.role) ? "viewer" : req.role.Trim().ToLowerInvariant()
        };

        _db.Users.Add(newUser);
        _db.SaveChanges();

        // Đồng bộ vào DataStore in-memory
        _store.Users.RemoveAll(u => u.Id == newUser.Id);
        _store.Users.Add(newUser);

        // Gán trạm nếu có truyền station_ids
        if (req.station_ids != null && req.station_ids.Count > 0)
        {
            _store.SetUserStations(newUser.Id, req.station_ids, _db);
        }

        return Ok(new
        {
            ok = true,
            message = $"Đã tạo thành công tài khoản '{newUser.Username}' và phân công trạm!",
            user = new
            {
                id = newUser.Id,
                username = newUser.Username,
                full_name = newUser.FullName,
                role = newUser.Role,
                station_ids = _store.GetStationIdsForUser(newUser.Id)
            }
        });
    }

    /// <summary>
    /// POST /api/auth/send-otp: Gửi mã OTP xác thực qua số điện thoại (Cho Đăng ký & Quên mật khẩu)
    /// </summary>
    [HttpPost("send-otp")]
    public async Task<IActionResult> SendOtp([FromBody] SendOtpRequest req)
    {
        var phone = req.phone?.Trim() ?? "";
        if (string.IsNullOrWhiteSpace(phone) || phone.Length < 9)
        {
            return BadRequest(new { ok = false, error = "Vui lòng nhập số điện thoại hợp lệ (tối thiểu 9-10 chữ số)" });
        }

        var purpose = string.Equals(req.purpose, "forgot_password", StringComparison.OrdinalIgnoreCase)
            ? "forgot_password"
            : "register";

        if (purpose == "register")
        {
            if (_db.Users.Any(u => u.Phone == phone))
            {
                return BadRequest(new { ok = false, error = $"Số điện thoại {phone} đã được đăng ký tài khoản khác trong hệ thống." });
            }
        }
        else if (purpose == "forgot_password")
        {
            var exists = _db.Users.Any(u => u.Phone == phone || u.Username.ToLower() == phone.ToLower());
            if (!exists)
            {
                return NotFound(new { ok = false, error = $"Số điện thoại {phone} chưa được liên kết với bất kỳ tài khoản nào." });
            }
        }

        var otpCode = _store.GenerateOtp(phone, purpose);

        // Gọi SpeedSMS để gửi tin nhắn SMS thật
        var (smsSent, smsMsg) = await _sms.SendOtpAsync(phone, otpCode);

        return Ok(new
        {
            ok = true,
            message = smsSent
                ? $"Mã OTP đã được gửi qua tin nhắn SMS tới số {phone}!"
                : $"Mã OTP ThermoGuard: {otpCode}",
            phone,
            purpose,
            sms_sent = smsSent,
            sms_detail = smsMsg,
            otp_demo = otpCode,
            expires_in = 300
        });
    }

    /// <summary>
    /// POST /api/auth/register: Đăng ký tài khoản nhân viên mới (Có xác thực OTP qua SĐT)
    /// </summary>
    [HttpPost("register")]
    public IActionResult Register([FromBody] UserRegisterRequest req)
    {
        if (string.IsNullOrWhiteSpace(req.username) || string.IsNullOrWhiteSpace(req.password))
        {
            return BadRequest(new { ok = false, error = "Vui lòng nhập tên đăng nhập và mật khẩu" });
        }

        var phone = req.phone?.Trim() ?? "";
        if (string.IsNullOrWhiteSpace(phone) || phone.Length < 9)
        {
            return BadRequest(new { ok = false, error = "Vui lòng nhập số điện thoại hợp lệ để nhận mã xác thực" });
        }

        // Kiểm tra mã OTP
        if (string.IsNullOrWhiteSpace(req.otp) || !_store.VerifyOtp(phone, "register", req.otp))
        {
            return BadRequest(new { ok = false, error = "Mã OTP không chính xác hoặc đã hết hạn (hiệu lực 5 phút). Vui lòng nhấn 'Gửi mã OTP' để nhận mã mới." });
        }

        var uName = req.username.Trim();
        if (_db.Users.Any(u => u.Username.ToLower() == uName.ToLower()))
        {
            return BadRequest(new { ok = false, error = $"Tên đăng nhập '{uName}' đã được sử dụng!" });
        }

        if (_db.Users.Any(u => u.Phone == phone))
        {
            return BadRequest(new { ok = false, error = $"Số điện thoại {phone} đã được đăng ký tài khoản khác!" });
        }

        var fullName = string.IsNullOrWhiteSpace(req.full_name) ? uName : req.full_name.Trim();

        var newUser = new AppUser
        {
            Id = 0,
            Username = uName,
            Password = req.password,
            FullName = fullName,
            Phone = phone,
            Role = "viewer" // Mặc định tài khoản tự đăng ký là nhân viên
        };

        _db.Users.Add(newUser);
        _db.SaveChanges();

        _store.Users.RemoveAll(u => u.Id == newUser.Id);
        _store.Users.Add(newUser);

        // Tự động cấp phiên đăng nhập
        var token = Guid.NewGuid().ToString("N");
        _store.ActiveSessions[token] = newUser;

        return Ok(new
        {
            ok = true,
            message = "Đăng ký tài khoản thành công!",
            token,
            user = new
            {
                id = newUser.Id,
                username = newUser.Username,
                full_name = newUser.FullName,
                phone = newUser.Phone,
                role = newUser.Role,
                station_ids = new List<int>()
            }
        });
    }

    /// <summary>
    /// POST /api/auth/forgot-password: Đặt lại mật khẩu qua mã OTP xác thực SĐT
    /// </summary>
    [HttpPost("forgot-password")]
    public IActionResult ForgotPassword([FromBody] ForgotPasswordRequest req)
    {
        var phone = req.phone?.Trim() ?? "";
        if (string.IsNullOrWhiteSpace(phone))
        {
            return BadRequest(new { ok = false, error = "Vui lòng nhập số điện thoại hoặc tên đăng nhập" });
        }

        if (string.IsNullOrWhiteSpace(req.new_password) || req.new_password.Trim().Length < 3)
        {
            return BadRequest(new { ok = false, error = "Mật khẩu mới phải có tối thiểu 3 ký tự" });
        }

        // Xác minh mã OTP
        if (string.IsNullOrWhiteSpace(req.otp) || !_store.VerifyOtp(phone, "forgot_password", req.otp))
        {
            return BadRequest(new { ok = false, error = "Mã OTP không chính xác hoặc đã hết hạn. Vui lòng bấm 'Gửi mã OTP' để nhận lại." });
        }

        var user = _db.Users.FirstOrDefault(u => u.Phone == phone);
        if (user == null)
        {
            // Thử tìm theo username nếu user nhập username
            user = _db.Users.FirstOrDefault(u => u.Username.ToLower() == phone.ToLower());
        }

        if (user == null)
        {
            return NotFound(new { ok = false, error = $"Không tìm thấy tài khoản liên kết với số điện thoại '{phone}'." });
        }

        user.Password = req.new_password.Trim();
        _db.SaveChanges();

        var storeUser = _store.Users.FirstOrDefault(u => u.Id == user.Id);
        if (storeUser != null) storeUser.Password = user.Password;

        return Ok(new
        {
            ok = true,
            message = $"Đặt lại mật khẩu cho tài khoản '{user.Username}' thành công! Vui lòng đăng nhập bằng mật khẩu mới.",
            username = user.Username
        });
    }

    /// <summary>
    /// POST /api/auth/login: Đăng nhập tài khoản
    /// </summary>
    [HttpPost("login")]
    public IActionResult Login([FromBody] UserLoginRequest req)
    {
        return LoginInternal(req.username, req.password);
    }

    private IActionResult LoginInternal(string username, string password)
    {
        var u = username.Trim().ToLowerInvariant();
        var user = _db.Users.FirstOrDefault(x => x.Username.ToLower() == u && x.Password == password);

        if (user == null)
        {
            return Unauthorized(new { ok = false, error = "Sai tên đăng nhập hoặc mật khẩu" });
        }

        var token = Guid.NewGuid().ToString("N");
        _store.ActiveSessions[token] = user;

        return Ok(new
        {
            ok = true,
            token,
            user = new
            {
                id = user.Id,
                username = user.Username,
                full_name = user.FullName,
                role = user.Role,
                station_ids = _store.GetStationIdsForUser(user.Id)
            }
        });
    }

    private string? GetBearerToken()
    {
        var authHeader = Request.Headers.Authorization.ToString();
        if (authHeader.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
        {
            return authHeader["Bearer ".Length..].Trim();
        }
        return null;
    }

    private AppUser? GetCurrentUser()
    {
        var token = GetBearerToken();
        if (!string.IsNullOrEmpty(token) && _store.ActiveSessions.TryGetValue(token, out var user))
        {
            return user;
        }
        return null;
    }
}

