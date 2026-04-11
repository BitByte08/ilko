using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using WinForms = System.Windows.Forms;

namespace Ilko.Services;

/// <summary>
/// WinForms Form → WorkerW child (GDI, SetParent 호환)
/// MFPlay(mfplay.dll) → EVR D3D9 COPY 모드로 HWND에 직접 렌더링
/// D3D9 COPY는 WorkerW 자식 창에서 정상 작동
/// </summary>
public class VideoWallpaperService : IDisposable
{
    // ── user32 ────────────────────────────────────────────────────────────
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    static extern IntPtr FindWindow(string cls, string? title);
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string? title);
    [DllImport("user32.dll")]
    static extern IntPtr SendMessageTimeout(IntPtr h, uint msg, IntPtr wp, IntPtr lp, uint f, uint t, out IntPtr r);
    [DllImport("user32.dll")]
    static extern bool EnumWindows(EnumWindowsProc fn, IntPtr lp);
    delegate bool EnumWindowsProc(IntPtr h, IntPtr lp);
    [DllImport("user32.dll")]
    static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")]
    static extern IntPtr SetParent(IntPtr child, IntPtr parent);
    [DllImport("user32.dll")]
    static extern int GetWindowLong(IntPtr h, int n);
    [DllImport("user32.dll")]
    static extern int SetWindowLong(IntPtr h, int n, int v);
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint f);
    [DllImport("user32.dll")]
    static extern bool ShowWindow(IntPtr h, int cmd);

    [StructLayout(LayoutKind.Sequential)]
    struct RECT { public int Left, Top, Right, Bottom; }

    const int  GWL_EXSTYLE      = -20;
    const int  WS_EX_NOACTIVATE = unchecked((int)0x08000000);
    const int  WS_EX_TOOLWINDOW = 0x00000080;
    const uint SWP_NOACTIVATE   = 0x0010;
    const uint SWP_NOZORDER     = 0x0004;
    const uint SWP_FRAMECHANGED = 0x0020;
    const int  SW_SHOWNOACTIVATE = 4;

    // ── mf / mfplay ───────────────────────────────────────────────────────
    const uint MF_VERSION = 0x00020070;

    [DllImport("mfplat.dll")]
    static extern int MFStartup(uint version, uint flags = 0);
    [DllImport("mfplat.dll")]
    static extern int MFShutdown();
    [DllImport("mfplay.dll", CharSet = CharSet.Unicode)]
    static extern int MFPCreateMediaPlayer(
        [MarshalAs(UnmanagedType.LPWStr)] string? url,
        [MarshalAs(UnmanagedType.Bool)] bool fStart,
        uint flags,
        IMFPMediaPlayerCallback? cb,
        IntPtr hwnd,
        out IMFPMediaPlayer ppPlayer);

    // ── COM interfaces ────────────────────────────────────────────────────
    [ComImport, Guid("A714590A-58AF-430A-85BF-44F5EC838D85"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMFPMediaPlayer
    {
        [PreserveSig] int Play();
        [PreserveSig] int Pause();
        [PreserveSig] int Stop();
        [PreserveSig] int FrameStep();
        [PreserveSig] int SetPosition(ref Guid guidPositionType, ref PROPVARIANT pv);
        [PreserveSig] int GetPosition(ref Guid guidPositionType, out PROPVARIANT pv);
        [PreserveSig] int GetDuration(ref Guid guidPositionType, out PROPVARIANT pv);
        [PreserveSig] int SetRate(float rate);
        [PreserveSig] int GetRate(out float rate);
        [PreserveSig] int GetSupportedRates([MarshalAs(UnmanagedType.Bool)] bool fwd, out float slow, out float fast);
        [PreserveSig] int GetState(out int state);
        [PreserveSig] int CreateMediaItemFromURL([MarshalAs(UnmanagedType.LPWStr)] string url, [MarshalAs(UnmanagedType.Bool)] bool fSync, uint dw, out IntPtr ppItem);
        [PreserveSig] int CreateMediaItemFromObject([MarshalAs(UnmanagedType.IUnknown)] object obj, [MarshalAs(UnmanagedType.Bool)] bool fSync, uint dw, out IntPtr ppItem);
        [PreserveSig] int SetMediaItem(IntPtr pItem);
        [PreserveSig] int ClearMediaItem();
        [PreserveSig] int GetMediaItem(out IntPtr ppItem);
        [PreserveSig] int GetVolume(out float v);
        [PreserveSig] int SetVolume(float v);
        [PreserveSig] int GetBalance(out float v);
        [PreserveSig] int SetBalance(float v);
        [PreserveSig] int GetMute([MarshalAs(UnmanagedType.Bool)] out bool mute);
        [PreserveSig] int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute);
        [PreserveSig] int GetNativeVideoSize(out System.Drawing.Size video, out System.Drawing.Size ar);
        [PreserveSig] int GetIdealVideoSize(out System.Drawing.Size min, out System.Drawing.Size max);
        [PreserveSig] int SetVideoSourceRect(ref MFVideoNormalizedRect r);
        [PreserveSig] int GetVideoSourceRect(out MFVideoNormalizedRect r);
        [PreserveSig] int SetAspectRatioMode(uint mode);
        [PreserveSig] int GetAspectRatioMode(out uint mode);
        [PreserveSig] int GetVideoWindow(out IntPtr hwnd);
        [PreserveSig] int UpdateVideo();
        [PreserveSig] int SetBorderColor(uint clr);
        [PreserveSig] int GetBorderColor(out uint clr);
        [PreserveSig] int InsertEffect([MarshalAs(UnmanagedType.IUnknown)] object fx, [MarshalAs(UnmanagedType.Bool)] bool optional);
        [PreserveSig] int RemoveEffect([MarshalAs(UnmanagedType.IUnknown)] object fx);
        [PreserveSig] int RemoveAllEffects();
        [PreserveSig] int Shutdown();
    }

    [ComImport, Guid("766C8FFB-5FDB-4FAE-A28D-B912996F51BC"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMFPMediaPlayerCallback
    {
        void OnMediaPlayerEvent(ref MFP_EVENT_HEADER pEventHeader);
    }

    [StructLayout(LayoutKind.Sequential)]
    struct MFP_EVENT_HEADER
    {
        public int    eEventType;
        public int    hrEvent;
        public IntPtr pMediaPlayer;
        public int    eState;
        public IntPtr pPropertyStore;
    }

    [StructLayout(LayoutKind.Explicit, Size = 16)]
    struct PROPVARIANT
    {
        [FieldOffset(0)] public ushort vt;
        [FieldOffset(8)] public long   llVal;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct MFVideoNormalizedRect { public float left, top, right, bottom; }

    const int    MFP_EVENT_TYPE_PLAYBACK_ENDED = 11;
    const ushort VT_I8 = 20;

    // ── 루프 콜백 ─────────────────────────────────────────────────────────
    [ClassInterface(ClassInterfaceType.None)]
    [ComVisible(true)]
    sealed class LoopCallback : IMFPMediaPlayerCallback
    {
        public IMFPMediaPlayer? Player;

        public void OnMediaPlayerEvent(ref MFP_EVENT_HEADER h)
        {
            if (h.eEventType != MFP_EVENT_TYPE_PLAYBACK_ENDED || Player is null) return;
            try
            {
                var g = Guid.Empty;
                var p = new PROPVARIANT { vt = VT_I8, llVal = 0 };
                Player.SetPosition(ref g, ref p);
                Player.Play();
            }
            catch (Exception ex) { Debug.WriteLine($"[VideoWallpaperService] loop error: {ex.Message}"); }
        }
    }

    // ── 상태 ──────────────────────────────────────────────────────────────
    record Item(WinForms.Form Form, IMFPMediaPlayer Player, LoopCallback Cb);
    readonly List<Item> _items = [];
    bool _mfStarted, _disposed;
    public bool IsActive => _items.Count > 0;

    // ── Play ──────────────────────────────────────────────────────────────
    public void Play(string videoPath)
    {
        Stop();

        if (!_mfStarted) { MFStartup(MF_VERSION); _mfStarted = true; }

        var workerW = GetOrCreateWorkerW();
        if (workerW == IntPtr.Zero) { Debug.WriteLine("[VideoWallpaperService] WorkerW 없음"); return; }

        GetWindowRect(workerW, out var wr);
        int ox = wr.Left, oy = wr.Top;

        foreach (WinForms.Screen screen in WinForms.Screen.AllScreens)
        {
            var b = screen.Bounds;

            var form = new WinForms.Form
            {
                FormBorderStyle = WinForms.FormBorderStyle.None,
                ShowInTaskbar   = false,
                BackColor       = System.Drawing.Color.Black,
                StartPosition   = WinForms.FormStartPosition.Manual,
                Location        = new System.Drawing.Point(-32000, -32000),
                Size            = new System.Drawing.Size(b.Width, b.Height),
            };
            form.Show();

            var ex = GetWindowLong(form.Handle, GWL_EXSTYLE);
            SetWindowLong(form.Handle, GWL_EXSTYLE, ex | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW);
            SetParent(form.Handle, workerW);
            SetWindowPos(form.Handle, IntPtr.Zero,
                b.X - ox, b.Y - oy, b.Width, b.Height,
                SWP_NOACTIVATE | SWP_NOZORDER | SWP_FRAMECHANGED);
            ShowWindow(form.Handle, SW_SHOWNOACTIVATE);

            var cb = new LoopCallback();
            var hr = MFPCreateMediaPlayer(videoPath, true, 0, cb, form.Handle, out var player);
            if (hr < 0)
            {
                Debug.WriteLine($"[VideoWallpaperService] MFPCreateMediaPlayer 실패: 0x{hr:X8}");
                form.Dispose();
                continue;
            }

            player.SetMute(true);
            cb.Player = player;
            _items.Add(new Item(form, player, cb));
            Debug.WriteLine($"[VideoWallpaperService] 재생: {Path.GetFileName(videoPath)} @ {b}");
        }
    }

    // ── Stop ──────────────────────────────────────────────────────────────
    public void Stop()
    {
        foreach (var item in _items)
        {
            try
            {
                item.Player.Stop();
                item.Player.Shutdown();
                Marshal.ReleaseComObject(item.Player);
                item.Form.Dispose();
            }
            catch (Exception ex) { Debug.WriteLine($"[VideoWallpaperService] 정리 실패: {ex.Message}"); }
        }
        _items.Clear();
    }

    // ── WorkerW ───────────────────────────────────────────────────────────
    static IntPtr GetOrCreateWorkerW()
    {
        var progman = FindWindow("Progman", null);
        if (progman == IntPtr.Zero) return IntPtr.Zero;
        SendMessageTimeout(progman, 0x052C, IntPtr.Zero, IntPtr.Zero, 0, 1000, out _);

        var dv = FindWindowEx(progman, IntPtr.Zero, "SHELLDLL_DefView", null);
        if (dv != IntPtr.Zero)
        {
            var ww = FindWindowEx(progman, dv, "WorkerW", null);
            if (ww != IntPtr.Zero) return ww;
        }

        IntPtr workerW = IntPtr.Zero;
        EnumWindows((h, _) =>
        {
            var d = FindWindowEx(h, IntPtr.Zero, "SHELLDLL_DefView", null);
            if (d != IntPtr.Zero) workerW = FindWindowEx(IntPtr.Zero, h, "WorkerW", null);
            return true;
        }, IntPtr.Zero);
        return workerW;
    }

    // ── Dispose ───────────────────────────────────────────────────────────
    public void Dispose()
    {
        if (_disposed) return;
        Stop();
        if (_mfStarted) { MFShutdown(); _mfStarted = false; }
        _disposed = true;
    }
}
