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

                // 1. Kiem tra hen gio dem nguoc & thoi gian bieu Ro-le (Smart Scheduler)
                List<Models.RelayScheduleItem> dueSchedules;
                lock (_store)
                {
                    dueSchedules = _store.Schedules.Where(s => !s.Executed && s.TriggerAt <= now).ToList();
                }

                foreach (var sched in dueSchedules)
                {
                    sched.Executed = true;
                    var dev = _store.GetDevice(sched.DeviceId) ?? _store.Devices.FirstOrDefault(d => d.StationId == sched.StationId);
                    if (dev != null)
                    {
                        dev.RelayMode = sched.TargetMode;
                        if (sched.TargetMode == "ON") dev.RelayState = 1;
                        else if (sched.TargetMode == "OFF") dev.RelayState = 0;

                        _store.AddRelayLog(new Models.RelayLogItem
                        {
                            DeviceId = dev.Id,
                            StationId = dev.StationId ?? dev.Id,
                            Action = sched.TargetMode,
                            Source = "SCHEDULER",
                            Reason = $"Thực thi hẹn giờ: Chuyển Rơ-le sang {sched.TargetMode} ({sched.DurationMinutes} phút)",
                            FullName = "Hệ thống Hẹn giờ (Smart Scheduler)",
                            CreatedAt = Models.TimeHelper.VnNowStr
                        });
                        _store.UpdateDevice(dev);
                        _logger.LogInformation("Smart Scheduler: Đã thực thi Rơ-le {Mode} cho trạm #{StationId}", sched.TargetMode, sched.StationId);
                    }
                }

                // 2. Kiem tra trang thai thiet bi mat ket noi (Offline Watchdog)
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
