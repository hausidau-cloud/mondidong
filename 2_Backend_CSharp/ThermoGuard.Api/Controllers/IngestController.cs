using Microsoft.AspNetCore.Mvc;
using ThermoGuard.Api.Models;
using ThermoGuard.Api.Services;

namespace ThermoGuard.Api.Controllers;

[ApiController]
[Tags("Ingest")]
[Route("api/ingest")]
public class IngestController : ControllerBase
{
    private readonly DataStore _store;
    private readonly ILogger<IngestController> _logger;

    public IngestController(DataStore store, ILogger<IngestController> logger)
    {
        _store = store;
        _logger = logger;
    }

    [HttpPost]
    public IActionResult Ingest([FromBody] IngestRequest req)
    {
        var clientIp = HttpContext.Connection.RemoteIpAddress?.ToString() ?? "127.0.0.1";
        var (ok, error, response) = _store.ProcessIngest(req, clientIp);

        if (!ok)
        {
            _logger.LogWarning("Ingest thất bại: {Error}", error);
            return StatusCode(403, new { ok = false, error });
        }

        return Ok(response);
    }
}
