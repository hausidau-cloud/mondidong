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
    public DbSet<StationItem> Stations { get; set; } = null!;
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
        modelBuilder.Entity<StationItem>().HasKey(s => s.Id);
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
            }
        );
    }
}

