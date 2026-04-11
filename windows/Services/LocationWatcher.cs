using System.Diagnostics;
using System.Net.NetworkInformation;
using System.Text.RegularExpressions;

namespace Ilko.Services;

/// <summary>
/// 네트워크 변경을 감시하고, 게이트웨이 MAC이 바뀌면 이벤트를 발행한다.
/// macOS 버전의 LocationWatcher.swift 와 동일 기능.
///
/// 감지 방식:
///   1. NetworkChange.NetworkAddressChanged 이벤트 구독
///   2. 기본 게이트웨이 IP → arp -a로 MAC 조회
///   3. fallback: netsh wlan show interfaces → SSID
/// </summary>
public class LocationWatcher : IDisposable
{
    private string? _currentGatewayMAC;
    private CancellationTokenSource? _debounceCts;
    private readonly SynchronizationContext? _syncContext;

    public string? CurrentGatewayMAC => _currentGatewayMAC;

    /// <summary>게이트웨이 MAC이 변경되면 발생. UI 스레드에서 호출됨.</summary>
    public event Action<string?>? GatewayMACChanged;

    public LocationWatcher()
    {
        _syncContext = SynchronizationContext.Current;
    }

    public void Start()
    {
        NetworkChange.NetworkAddressChanged += OnNetworkChanged;
        // 초기 체크 (1.5초 디바운스)
        ScheduleCheck();
    }

    public void Stop()
    {
        NetworkChange.NetworkAddressChanged -= OnNetworkChanged;
        _debounceCts?.Cancel();
    }

    public void Refresh()
    {
        _debounceCts?.Cancel();
        _ = CheckNetworkAsync();
    }

    /// <summary>현재 게이트웨이 MAC을 즉시 반환 (UI 자동 채우기용).</summary>
    public string? GetCurrentNetworkId()
    {
        var ip = GetDefaultGatewayIP();
        if (ip == null) return null;
        return GetMACFromArp(ip);
    }

    public void Dispose()
    {
        Stop();
        _debounceCts?.Dispose();
    }

    private void OnNetworkChanged(object? sender, EventArgs e) => ScheduleCheck();

    private void ScheduleCheck()
    {
        _debounceCts?.Cancel();
        _debounceCts = new CancellationTokenSource();
        var token = _debounceCts.Token;

        Task.Run(async () =>
        {
            try
            {
                await Task.Delay(1500, token);
                if (!token.IsCancellationRequested)
                    await CheckNetworkAsync();
            }
            catch (TaskCanceledException) { }
        }, token);
    }

    private Task CheckNetworkAsync()
    {
        string? networkId = null;

        // 1차: 게이트웨이 IP → ARP로 MAC 조회
        var gatewayIp = GetDefaultGatewayIP();
        if (gatewayIp != null)
        {
            // ping으로 ARP 캐시 채우기
            PingGateway(gatewayIp);
            networkId = GetMACFromArp(gatewayIp);
        }

        // 2차: Wi-Fi SSID (fallback)
        if (networkId == null)
        {
            networkId = GetWiFiSSID();
        }

        if (networkId != _currentGatewayMAC)
        {
            Debug.WriteLine($"[LocationWatcher] 네트워크 변경: {_currentGatewayMAC ?? "null"} → {networkId ?? "null"}");
            _currentGatewayMAC = networkId;

            if (_syncContext != null)
                _syncContext.Post(_ => GatewayMACChanged?.Invoke(networkId), null);
            else
                GatewayMACChanged?.Invoke(networkId);
        }

        return Task.CompletedTask;
    }

    /// <summary>기본 게이트웨이 IP를 .NET API로 가져온다.</summary>
    private static string? GetDefaultGatewayIP()
    {
        try
        {
            foreach (var ni in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (ni.OperationalStatus != OperationalStatus.Up) continue;
                if (ni.NetworkInterfaceType is NetworkInterfaceType.Loopback
                    or NetworkInterfaceType.Tunnel) continue;

                var props = ni.GetIPProperties();
                foreach (var gw in props.GatewayAddresses)
                {
                    var addr = gw.Address.ToString();
                    if (addr != "0.0.0.0" && !addr.Contains(':')) // IPv4만
                        return addr;
                }
            }
        }
        catch { }
        return null;
    }

    /// <summary>ARP 캐시를 채우기 위해 ping 한번.</summary>
    private static void PingGateway(string ip)
    {
        try
        {
            using var ping = new Ping();
            ping.Send(ip, 1000);
        }
        catch { }
    }

    /// <summary>arp -a 명령으로 IP에 대한 MAC 주소를 조회.</summary>
    private static string? GetMACFromArp(string ip)
    {
        try
        {
            var psi = new ProcessStartInfo("arp", $"-a {ip}")
            {
                RedirectStandardOutput = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            using var proc = Process.Start(psi);
            if (proc == null) return null;
            var output = proc.StandardOutput.ReadToEnd();
            proc.WaitForExit();

            // "192.168.0.1     a4-b1-c2-d3-e4-f5     dynamic"
            var match = Regex.Match(output, @"([0-9a-fA-F]{2}[-:][0-9a-fA-F]{2}[-:][0-9a-fA-F]{2}[-:][0-9a-fA-F]{2}[-:][0-9a-fA-F]{2}[-:][0-9a-fA-F]{2})");
            if (match.Success)
            {
                // macOS 형식과 호환되도록 : 구분자로 통일
                return match.Value.Replace('-', ':').ToLowerInvariant();
            }
        }
        catch { }
        return null;
    }

    /// <summary>netsh wlan show interfaces → SSID 추출 (권한 불필요).</summary>
    private static string? GetWiFiSSID()
    {
        try
        {
            var psi = new ProcessStartInfo("netsh", "wlan show interfaces")
            {
                RedirectStandardOutput = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            using var proc = Process.Start(psi);
            if (proc == null) return null;
            var output = proc.StandardOutput.ReadToEnd();
            proc.WaitForExit();

            // "    SSID                   : MyNetwork"
            var match = Regex.Match(output, @"^\s*SSID\s*:\s*(.+)$", RegexOptions.Multiline);
            if (match.Success)
            {
                var ssid = match.Groups[1].Value.Trim();
                return string.IsNullOrEmpty(ssid) ? null : ssid;
            }
        }
        catch { }
        return null;
    }
}
