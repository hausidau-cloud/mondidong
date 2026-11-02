using Microsoft.AspNetCore.Mvc;

namespace ThermoGuard.Api.Controllers;

[ApiController]
[Route("api/time")]
public class TimeController : ControllerBase
{
    [HttpGet]
    public IActionResult GetTime()
    {
        return Ok(new
        {
            ok = true,
            now = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()
        });
    }
}
