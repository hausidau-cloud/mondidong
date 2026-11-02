# Stage 1: Build environment (.NET 9 SDK)
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src

# Copy project file and restore dependencies
COPY ["ThermoGuard.Api/ThermoGuard.Api.csproj", "ThermoGuard.Api/"]
RUN dotnet restore "ThermoGuard.Api/ThermoGuard.Api.csproj"

# Copy full source and publish release
COPY . .
WORKDIR "/src/ThermoGuard.Api"
RUN dotnet publish "ThermoGuard.Api.csproj" -c Release -o /app/publish /p:UseAppHost=false

# Stage 2: Runtime environment (.NET 9 ASP.NET)
FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS final
WORKDIR /app

COPY --from=build /app/publish .

EXPOSE 5000
EXPOSE 10000

ENTRYPOINT ["dotnet", "ThermoGuard.Api.dll"]
