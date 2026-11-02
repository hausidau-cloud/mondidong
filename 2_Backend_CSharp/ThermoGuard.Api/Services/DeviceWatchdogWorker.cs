namespace ThermoGuard.Api.Services;

public class DeviceWatchdogWorker : BackgroundService
{
    private readonly DataStore _store;
    private readonly ILogger<DeviceWatchdogWorker> _logger;

    public DeviceWatchdogWorker(DataStore store, ILogger<DeviceWatchdogWorker> logger)
    {
        _store = store;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                var now = DateTime.UtcNow;
                foreach (var dev in _store.Devices)
                {
                    if (dev.LastSeenTime != null)
                    {
                        var elapsed = (now - dev.LastSeenTime.Value).TotalSeconds;
                        if (elapsed > dev.OfflineAfter && dev.Status != "OFFLINE")
                        {
                            dev.Status = "OFFLINE";
                            dev.Reason = $"Mất kết nối > {dev.OfflineAfter}s";
                            _store.AddOfflineAlert(dev);
                            _logger.LogWarning("Trạm {DeviceCode} mất kết nối!", dev.DeviceCode);
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Lỗi kiểm tra trạng thái thiết bị");
            }

            await Task.Delay(5000, stoppingToken);
        }
    }
}
