using Microsoft.EntityFrameworkCore;
using ThermoGuard.Api.Models;

namespace ThermoGuard.Api.Data;

public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options)
    {
    }

    public DbSet<AppUser> Users { get; set; } = null!;
    public DbSet<Device> Devices { get; set; } = null!;
    public DbSet<ReadingRecord> Readings { get; set; } = null!;
    public DbSet<AlertItem> Alerts { get; set; } = null!;
    public DbSet<RelayLogItem> RelayLogs { get; set; } = null!;
    public DbSet<StationAssignment> StationAssignments { get; set; } = null!;

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        // Configure Primary Keys
        modelBuilder.Entity<AppUser>().HasKey(u => u.Id);
        modelBuilder.Entity<Device>().HasKey(d => d.Id);
        modelBuilder.Entity<ReadingRecord>().HasKey(r => r.Id);
        modelBuilder.Entity<AlertItem>().HasKey(a => a.Id);
        modelBuilder.Entity<RelayLogItem>().HasKey(l => l.Id);
        modelBuilder.Entity<StationAssignment>().HasKey(s => s.Id);

        // Seed initial admin user
        modelBuilder.Entity<AppUser>().HasData(
            new AppUser
            {
                Id = 1,
                Username = "admin",
                Password = "password123",
                FullName = "Quản trị viên Hệ thống",
                Role = "admin"
            },
            new AppUser
            {
                Id = 2,
                Username = "viewer",
                Password = "password123",
                FullName = "Người xem",
                Role = "viewer"
            }
        );

        // Seed initial device PICO-01
        modelBuilder.Entity<Device>().HasData(
            new Device
            {
                Id = 1,
                DeviceCode = "PICO-01",
                ApiKey = "a1b2c3d4e5f60718293a4b5c6d7e8f90",
                Name = "Trạm Pico 2 W - Phòng Lab",
                Profile = "cabinet",
                Location = "Phòng Thực Nghiệm IoT",
                Description = "Giám sát nhiệt độ, độ ẩm SHT30, que inox DS18B20 và quang trở",
                RelayLabel = "Bóng đèn 220V / Rơ-le",
                RelayMode = "AUTO",
                RelayState = 0,
                Status = "OFFLINE",
                AirTempMax = 40.0,
                AirHumMax = 75.0,
                ProbeTempMin = 0.0,
                ProbeTempMax = 60.0,
                DewMargin = 3.0,
                Hysteresis = 1.5,
                SendInterval = 3,
                OfflineAfter = 60
            }
        );

        // Seed initial assignment: viewer -> Station 1
        modelBuilder.Entity<StationAssignment>().HasData(
            new StationAssignment
            {
                Id = 1,
                UserId = 2,
                DeviceId = 1,
                AssignedAt = new DateTime(2025, 1, 1, 0, 0, 0, DateTimeKind.Utc)
            }
        );
    }
}

