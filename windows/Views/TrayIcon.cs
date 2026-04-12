using System.Drawing;
using System.Windows.Forms;
using Ilko.Models;
using Ilko.ViewModels;
using Font = System.Drawing.Font;
using FontStyle = System.Drawing.FontStyle;

namespace Ilko.Views;

/// <summary>
/// 시스템 트레이 아이콘 — macOS MenuBarController.swift 와 동일 기능.
/// NotifyIcon(WinForms)을 WPF 앱에서 사용한다.
/// </summary>
public class TrayIcon : IDisposable
{
    private readonly NotifyIcon _notifyIcon;
    private readonly MainViewModel _vm;
    private readonly Action _showWindowCallback;

    public TrayIcon(MainViewModel viewModel, Action showWindow)
    {
        _vm = viewModel;
        _showWindowCallback = showWindow;

        _notifyIcon = new NotifyIcon
        {
            Text = "ILKO — 위치 기반 월페이퍼",
            Icon = SystemIcons.Application,
            Visible = true
        };

        _notifyIcon.DoubleClick += (_, _) => _showWindowCallback();

        _vm.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is nameof(MainViewModel.ActiveProfile)
                              or nameof(MainViewModel.Profiles))
                RebuildMenu();
        };

        _vm.ProfileManager.ProfilesChanged += RebuildMenu;

        RebuildMenu();
    }

    private void RebuildMenu()
    {
        var menu = new ContextMenuStrip();

        // 현재 활성 프로필명
        var header = new ToolStripLabel(_vm.ActiveProfile?.Name ?? "프로필 없음")
        {
            Font = new Font(SystemFonts.MenuFont ?? SystemFonts.DefaultFont, FontStyle.Bold)
        };
        menu.Items.Add(header);
        menu.Items.Add(new ToolStripSeparator());

        // 프로필 목록
        foreach (var profile in _vm.Profiles)
        {
            var p = profile; // closure capture
            var item = new ToolStripMenuItem(p.Name)
            {
                Checked = p.Id == _vm.ActiveProfile?.Id
            };
            item.Click += (_, _) => _vm.SelectProfile(p);
            menu.Items.Add(item);
        }

        menu.Items.Add(new ToolStripSeparator());

        var settingsItem = new ToolStripMenuItem("프로필 설정...");
        settingsItem.Click += (_, _) => _showWindowCallback();
        menu.Items.Add(settingsItem);

        var quitItem = new ToolStripMenuItem("종료");
        quitItem.Click += (_, _) =>
        {
            _notifyIcon.Visible = false;
            System.Windows.Application.Current.Shutdown();
        };
        menu.Items.Add(quitItem);

        _notifyIcon.ContextMenuStrip = menu;
    }

    public void Dispose()
    {
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
    }
}
