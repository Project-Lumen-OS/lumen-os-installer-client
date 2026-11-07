using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Input;
using System.Windows.Threading;
using LumenInstaller.Core;

namespace LumenInstaller;

// ------------------------------------------------------------------ display items
public sealed record DeviceItem(string Id, string Name, string Serial, string TransportText, string MatchText, string MatchTone,
                                string SystemText, string SystemTone, string FirmwareText, string FirmwareTone, string HintText,
                                string HintTone, bool IsSelected)
{
    public bool HasMatch => MatchText.Length > 0;
    public bool HasSystem => SystemText.Length > 0;
    public bool HasFirmware => FirmwareText.Length > 0;
    public bool HasHint => HintText.Length > 0;
}
public sealed record ProfileCard(string Id, string Name, string Detail, string ConnText, bool IsSelected);
public sealed record ReleaseItem(string Tag, string VersionText, bool Latest, bool Beta, string MetaText, bool IsSelected, bool Downloaded);
public sealed record PipelineItem(string Number, string Title, string Note, string State, bool First, bool Last)
{
    public bool HasNote => Note.Length > 0;
    public string LeftState => First ? "none" : (State is "done" or "cur" or "skip") ? "on" : "off";
    public string RightState => Last ? "none" : (State is "done" or "skip") ? "on" : "off";
}
public sealed record SummaryRow(string Key, string Value);

public enum GappsPlan { OnePass, AfterInstall, Unavailable }

public sealed class MainViewModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    public event Action<Prompt>? PromptRequested;
    public event Action? PromptWithdrawn;
    void Changed() => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(string.Empty));   // every binding re-reads

    public Loc L => Loc.Instance;
    readonly PlatformTools pt = new();
    readonly Detector detector;
    readonly InstallerRunner runner = new();
    readonly DispatcherTimer poll = new() { Interval = TimeSpan.FromSeconds(1.5) };
    bool scanning;

    public MainViewModel()
    {
        detector = new Detector(pt);
        Profiles = Core.Profiles.Load(Paths.BundledInstaller);
        Loc.Instance.LanguageChanged += () => { RebuildDevices(); Changed(); };
        poll.Tick += async (_, _) => await PollAsync();
        runner.Line += l => Log.Add(l);
        runner.PromptAsked += p =>
        {
            // the installer's "have you done the vbmeta step?": the client did it in this session, both slots confirmed
            // by fastboot and the result read back; the installer still checks it on its own before writing
            if (vbmetaDoneHere && p.Kind == PromptKind.YesNo && p.Question.Contains("vbmeta")) { runner.Answer("yes"); return; }
            PromptRequested?.Invoke(p);
        };
        runner.PromptGone += () => PromptWithdrawn?.Invoke();
        runner.Exited += OnExit;
        stateTimer.Tick += (_, _) => RefreshState();
        BuildCommands();
    }

    // ------------------------------------------------------------------ general
    public bool ModeChosen { get; private set; }
    public bool IsWelcome => !ModeChosen;
    public int Step { get; private set; }
    public bool IsPrepare => Step == -1;   // the preparation step comes before step 0 (the projector)
    public bool IsStep0 => Step == 0;
    public bool IsStep1 => Step == 1;
    public bool IsStep2 => Step == 2;
    public bool IsStep3 => Step == 3;
    public string? Busy { get; private set; }
    public bool IsBusy => Busy != null;
    public double BusyProgress { get; private set; }
    public bool BusyIndeterminate => BusyProgress <= 0;
    public List<Profile> Profiles { get; private set; }
    public string SupportedText => string.Join("   ·   ", Profiles.Select(p => $"{p.Name} {p.Model}"));

    // ------------------------------------------------------------------ step 1: the projector
    List<Device> devices = [];
    public ObservableCollection<DeviceItem> Devices { get; } = [];
    public bool NoDevices => devices.Count == 0;
    public string? SelectedDeviceId { get; private set; }
    public string? ManualProfileId { get; private set; }
    public string? ScanError { get; private set; }
    public bool HasScanError => ScanError != null;
    string serialInput = "";
    public string SerialInput
    {
        get => serialInput;
        set { serialInput = value; if (SerialResult.Length > 0) { SerialResult = ""; Changed(); } }   // the result belongs to the previous serial
    }
    public string SerialResult { get; private set; } = "";
    public string SerialTone { get; private set; } = "none";
    public bool HasSerialResult => SerialResult.Length > 0;
    public string WifiAddr { get; set; } = "";
    public string WifiMessage { get; private set; } = "";
    public bool HasWifiMessage => WifiMessage.Length > 0;
    /// Wi‑Fi (Play 6, Z9X HB) while no projector is found, and for a model that connects over Wi‑Fi.
    public bool ShowWifi => Profile?.Connection == Connection.Wifi || !DeviceFound;
    public int ManualTab { get; set; }
    public bool ManualSerialTab => ManualTab == 0;
    public bool ManualListTab => ManualTab == 1;

    public Device? SelectedDevice => devices.FirstOrDefault(d => d.Id == SelectedDeviceId);
    public Profile? Profile => Profiles.FirstOrDefault(p => p.Id == (SelectedDevice?.Match?.Id ?? ManualProfileId));
    public bool HasProfile => Profile != null;
    public bool ManualChosen => Profile != null && SelectedDevice?.Match == null;
    public string ManualChosenText => Profile == null ? "" : Loc.F("dev.manualchosen", Profile.Name, Profile.Model);
    /// A projector is really there right now (adb device or fastboot): everything that touches it needs this.
    public bool Connected => SelectedDevice is { State: "device" or "fastboot" } && SelectedDevice.Match?.Id == Profile?.Id;

    public List<ProfileCard> ProfileCards => Profiles.Select(p => new ProfileCard(p.Id, p.Name,
        Loc.F("dev.cardinfo", p.Model, p.FirmwareText), Loc.T(p.Connection == Connection.Usb ? "dev.byusb" : "dev.bywifi"), Profile?.Id == p.Id)).ToList();

    // ------------------------------------------------------------------ step 2: the system
    List<Release> releases = [];
    public bool ShowBeta { get; set; }
    public bool ReleasesLoading { get; private set; }
    public string? ReleasesError { get; private set; }
    public bool HasReleasesError => ReleasesError != null;
    public string? SelectedReleaseTag { get; private set; }
    public Workspace? Workspace { get; private set; }
    public bool HasWorkspace => Workspace != null;
    public bool NoWorkspace => Workspace == null;
    // one button on the system step: "Download" only when something must be downloaded, otherwise "Next"
    public bool ShowDownload => Workspace == null && !(SelectedRelease is { } r && Releases.IsDownloaded(r));
    public bool ShowSystemNext => !ShowDownload;
    public ICommand NextFromSystemCmd { get; private set; } = null!;
    public string WorkspaceText => Workspace == null ? "" : Loc.F("sys.ready", Path.GetFileName(Workspace.Image), Workspace.Dir);
    public double DownloadProgress { get; private set; }
    public string DownloadFile { get; private set; } = "";
    public bool IsDownloading { get; private set; }
    public string DownloadText => Loc.F("sys.downloading", DownloadFile, (int)(DownloadProgress * 100));
    CancellationTokenSource? downloadCts;

    List<Release> DeviceReleaseList => releases.Where(r => r.Device == Profile?.Id && (ShowBeta || !r.Prerelease)).ToList();
    Release? SelectedRelease => releases.FirstOrDefault(r => r.Tag == SelectedReleaseTag);
    // the latest release (and the chosen one) by default, older ones on request
    bool showOlder;
    public bool HasOlder => DeviceReleaseList.Count > 1;
    public string OlderText => showOlder ? Loc.T("sys.older.hide") : Loc.F("sys.older", DeviceReleaseList.Count - 1);
    public ICommand ToggleOlderCmd { get; private set; } = null!;
    public List<ReleaseItem> DeviceReleases => DeviceReleaseList.Select((r, i) => (r, i)).Where(x => showOlder || x.i == 0 || x.r.Tag == SelectedReleaseTag)
        .Select(x => new ReleaseItem(x.r.Tag, "Lumen OS " + x.r.Version, x.i == 0 && !x.r.Prerelease, x.r.Prerelease,
            $"{x.r.Tag}   {x.r.Published?.ToLocalTime():d}   {Loc.F("sys.imagesize", Size(x.r.Image?.Size ?? 0))}", x.r.Tag == SelectedReleaseTag, Releases.IsDownloaded(x.r))).ToList();
    public bool NoReleases => !ReleasesLoading && ReleasesError == null && DeviceReleaseList.Count == 0;

    // ------------------------------------------------------------------ step 3: Google
    public bool GappsEnabled { get; set; }
    public string? GappsFile { get; private set; }
    public bool GappsOk { get; private set; }
    public string GappsState { get; private set; } = "";
    public bool HasGappsState => GappsState.Length > 0 && !GappsBusy;
    public bool GappsBusy { get; private set; }
    public double GappsProgress { get; private set; }
    public string GappsPhase { get; private set; } = "";
    public string GappsProgressText => $"{GappsPhase}… {(int)(GappsProgress * 100)}%";

    public GappsZip? GappsZip
    {
        get
        {
            if (Profile == null) return null;
            return (Workspace != null ? Gapps.Allowed(Workspace.InstallerDir, Profile.GappsAllow) : null)
                   ?? Gapps.Allowed(Paths.BundledInstaller, Profile.GappsAllow);
        }
    }
    public bool HasGappsZip => GappsZip != null;
    public string GappsZipName => GappsZip?.Name ?? "";
    public string GappsZipMeta => GappsZip == null ? "" : $"{Size(GappsZip.Size)}    GMS {GappsZip.GmsVersion}    sha256 {GappsZip.Sha[..16]}…";

    bool ErofsAvailable => Workspace != null && File.Exists(Path.Combine(Workspace.InstallerDir, "tools", "erofs-utils", "windows-x64", "mkfs.erofs.exe"));

    /// How the add-on gets onto this projector with this installer on Windows:
    /// the Play 6 fills its partition on the projector (no erofs): one pass; the Z9X builds the add-on image on the
    /// computer for the one-pass install (erofs-utils, none shipped for Windows yet): the install, then 'gapps -Zip'
    /// (filled over adb); the Z9X HB needs erofs-utils for 'gapps' too: unavailable until the installer has them.
    public GappsPlan Plan => Profile?.Id switch
    {
        "play6" => GappsPlan.OnePass,
        "hb" => ErofsAvailable ? GappsPlan.OnePass : GappsPlan.Unavailable,
        _ => ErofsAvailable ? GappsPlan.OnePass : GappsPlan.AfterInstall,
    };
    public string PlanText => Plan switch { GappsPlan.OnePass => Loc.T("g.plan.one"), GappsPlan.AfterInstall => Loc.T("g.plan.after"), _ => Loc.T("g.plan.none") };
    public string PlanTone => Plan switch { GappsPlan.OnePass => "ok", GappsPlan.AfterInstall => "plain", _ => "bad" };
    public bool GappsWillInstall => Plan != GappsPlan.Unavailable && GappsEnabled && GappsOk;
    // Adding or removing the services on their own only makes sense on a projector that already runs Lumen OS.
    public bool LumenInstalled => SelectedDevice?.Lumen == true;
    public bool CanAddGapps => GappsOk && Connected && !Running && Plan != GappsPlan.Unavailable;
    public bool CanRemoveGapps => Connected && !Running && Plan != GappsPlan.Unavailable;

    // ------------------------------------------------------------------ step 4: install
    public ObservableCollection<LogLine> Log { get; } = [];
    public bool Running { get; private set; }
    public int? ExitCode { get; private set; }
    public string RunTitle { get; private set; } = "";
    public string InstallTitle => RunTitle.Length > 0 ? RunTitle : Loc.T("inst.title");
    Dictionary<string, string> state = [];
    readonly DispatcherTimer stateTimer = new() { Interval = TimeSpan.FromMilliseconds(700) };
    RunOptions? lastOptions;
    string? chainGapps;
    string? waitingGapps;   // the install is done; 'gapps -Zip' waits for Lumen OS on adb (the wipe turned debugging off)
    public bool WaitingGapps => waitingGapps != null && !Running;
    bool inGappsChain;
    int? gappsChainResult;
    bool isInstallRun;

    public bool ShowSummary => !Running && ExitCode == null && Log.Count == 0;
    public bool ShowRun => !ShowSummary;
    public bool ShowPipeline => isInstallRun;
    public bool ShowChainNote => inGappsChain && Running;
    public bool HasResult => ExitCode != null && !Running;
    /// The install stopped after the system was written: in this run the installer said "written" (its own line), and
    /// only the check after the first start failed. On a fresh Lumen OS that is expected: the wipe turned USB debugging
    /// off until the setup on the projector is done.
    public bool WrittenUnchecked => ExitCode is not null and not 0 && isInstallRun && !inGappsChain && gappsChainResult == null
        && Log.Any(l => l.Kind == LineKind.Ok && System.Text.RegularExpressions.Regex.Replace(l.Text, @"^\d\d:\d\d:\d\d\s+", "").Trim() is var b
                        && (b.StartsWith("✓ written") || b.StartsWith("✓ записано")));
    bool chainSkipped;
    public bool InstallDone { get; private set; }   // the install just finished: green step while its result is on screen   // the install stopped, so 'gapps -Zip' after it did not run
    public bool ResultOk => ExitCode == 0 || WrittenUnchecked;
    public bool ResultBad => ExitCode is not null and not 0 && !WrittenUnchecked;
    public string ResultTitle => Loc.T(WaitingGapps ? "inst.waitg" : WrittenUnchecked ? "inst.written" : ResultOk ? "inst.done" : "inst.stopped");
    public string ResultText
    {
        get
        {
            if (ExitCode is not int code) return "";
            if (WaitingGapps) return Loc.T("inst.waitg.text");
            if (WrittenUnchecked) return Loc.T("inst.written.text") + (chainSkipped ? "\n" + Loc.T("inst.written.google") : "");
            if (code == 0)
                return Loc.T(gappsChainResult == 0 || lastOptions?.GappsZip != null ? "inst.done.google" : "inst.done.text");
            var stop = Log.LastOrDefault(l => l.Kind == LineKind.Stop)?.Text;
            return stop != null ? System.Text.RegularExpressions.Regex.Replace(stop, @"^\d\d:\d\d:\d\d\s+", "") : Loc.F("inst.exitcode", code);
        }
    }
    public bool OfferGoogleAfter => ResultOk && isInstallRun && gappsChainResult == null && lastOptions?.GappsZip == null && !inGappsChain && waitingGapps == null;
    public ICommand SkipWaitingGappsCmd { get; private set; } = null!;
    public bool NotConnectedWarning => !Connected;
    public bool NeedsVbmeta => Profile?.Id is "z9x" or "hb";
    public bool VbOn => NeedsVbmeta && vbState == VbmetaState.On;
    public string RunningText => Loc.T(vbmetaRunning ? "vb.running" : "inst.running");
    public bool CanInstall => Profile != null && Workspace != null && !Running && Connected && (!GappsEnabled || (Plan != GappsPlan.Unavailable && GappsOk));
    public string InstallBlockedReason =>
        Profile == null ? Loc.T("block.noprofile") : Workspace == null ? Loc.T("block.nosystem") : !Connected ? Loc.T("block.nodevice") :
        GappsEnabled && Plan == GappsPlan.Unavailable ? Loc.T("block.nogapps") : GappsEnabled && !GappsOk ? Loc.T("block.gappsfile") : "";
    public bool HasBlockedReason => !Running && InstallBlockedReason.Length > 0;

    public List<SummaryRow> Summary => [
        new(Loc.T("sum.projector"), Profile == null ? "—" : $"{Profile.Name} ({Profile.Model})" + (SelectedDevice?.HwSerial is { } s ? " · " + s : "")),
        new(Loc.T("sum.connection"), SelectedDevice == null ? Loc.T("sum.notconnected") : SelectedDevice.Transport switch
            { Transport.Wifi => "Wi-Fi " + SelectedDevice.Serial, Transport.Usb => Loc.T("sum.usb"), _ => "fastboot" }),
        new(Loc.T("sum.system"), Workspace == null ? "—" : Path.GetFileName(Workspace.Image)),
        new(Loc.T("sum.google"), GoogleSummary),
    ];
    // ✓ the Google services go on in this install (with the system or right after it), ✕ they do not
    string GoogleSummary => GappsWillInstall ? "✓" : "✕";

    public List<PipelineItem> Pipeline
    {
        get
        {
            var steps = BaseSteps.Concat(chainGapps != null || waitingGapps != null || inGappsChain || gappsChainResult != null ? [("gapps", "step.gapps")] : Array.Empty<(string, string)>()).ToList();
            // skipped:wiped: after a wipe the installer does not wait for adb, the install went through
            bool Done(string k) => k == "gapps" ? gappsChainResult == 0 : state.GetValueOrDefault("step_" + k) is "done" or "skipped:wiped";
            var current = steps.FindIndex(s => !Done(s.Item1) && SkipNote(s.Item1) == null);
            return steps.Select((s, i) =>
            {
                var done = Done(s.Item1);
                var note = done ? null : SkipNote(s.Item1);
                var st = done ? "done" : note != null ? "skip" : Running && i == current ? "cur" : !Running && ExitCode is not null and not 0 && i == current ? "fail" : "todo";
                return new PipelineItem((i + 1).ToString(), Loc.T(s.Item2), note ?? "", st, i == 0, i == steps.Count - 1);
            }).ToList();
        }
    }

    IEnumerable<(string, string)> BaseSteps => Profile?.Id switch
    {
        "play6" => [("check", "step.check"), ("backup", "step.backup"), ("flash", "step.flash"), ("verify", "step.verify")],
        "hb" => [("check", "step.check"), ("backup", "step.backup"), ("vbmeta", "step.vbmeta"), ("blobs", "step.blobs"), ("flash", "step.flash"), ("verify", "step.verify")],
        _ => [("check", "step.check"), ("backup", "step.backup"), ("blobs", "step.blobs"), ("vbmeta", "step.vbmeta"), ("flash", "step.flash"), ("verify", "step.verify")],
    };

    string? SkipNote(string key)
    {
        // skipped:wiped (installers after 1.0.9): no check after a wipe, USB debugging is off on the fresh system
        if (state.GetValueOrDefault("step_" + key) == "skipped") return Loc.T(key == "backup" ? "skip.backup" : "skip.skipped");
        if (key == "blobs" && lastOptions?.NoBlobs == true && !state.ContainsKey("step_blobs")) return Loc.T("skip.noblobs");
        return null;
    }

    // ------------------------------------------------------------------ sidebar
    /// A projector is connected right now (adb or fastboot); without one the wizard does not go past step 1.
    public bool DeviceFound => SelectedDevice is { State: "device" or "fastboot" };
    public bool NoDeviceFound => !DeviceFound;
    // back is always open; forward needs the projector connected (the install button checks it again)
    public bool NotRunning => !Running;
    // ------------------------------------------------------------------ preparation (before step 0)
    public string PrepModel { get; private set; } = "z9x";
    public bool PrepZ9x => PrepModel == "z9x";
    public bool PrepPlay6 => PrepModel == "play6";
    public bool PrepHb => PrepModel == "hb";
    public bool TunerVisible => PrepModel != "hb";
    public bool TunerReady { get; private set; }
    public bool TunerNotReady => !TunerReady;
    public bool TunerDownloading { get; private set; }
    public bool TunerIdle => !TunerDownloading;
    public double TunerProgress { get; private set; }
    public string TunerMessage { get; private set; } = "";
    public string TunerTitle => "SystemUI Tuner " + Tuner.Version;
    public string TunerStickNote => Loc.F("tuner.stick", Tuner.StickName);
    // as in the install guides, "1. Подготовьте проектор", without the firmware item: the installer checks it itself
    public List<string> PrepSteps => (PrepModel switch
    {
        "play6" => new[] { Loc.T("prep.play6.wifi"), Loc.T("prep.play6.tuner"), Loc.T("prep.play6.ip"), Loc.T("prep.play6.cable") },
        "hb" => new[] { Loc.T("prep.hb.wifi"), Loc.T("prep.hb.debug"), Loc.T("prep.hb.ip") },
        _ => new[] { Loc.T("prep.z9x.wifi"), Loc.T("prep.z9x.tuner"), Loc.T("prep.z9x.reboot"), Loc.T("prep.z9x.cable") },
    }).Select((s, i) => $"{i + 1}.  {s}").ToList();

    async Task TunerDownloadAsync()
    {
        TunerDownloading = true; TunerMessage = ""; Changed();
        try
        {
            await Tuner.FetchAsync((d, t) => Application.Current.Dispatcher.BeginInvoke(() => { TunerProgress = t > 0 ? (double)d / t : 0; Changed(); }));
            TunerReady = true; TunerMessage = Loc.T("tuner.ok");
        }
        catch (Exception e) { TunerMessage = e.Message; }
        TunerDownloading = false; Changed();
    }

    void TunerSave()
    {
        var dlg = new Microsoft.Win32.OpenFolderDialog { Title = Loc.T("tuner.pick") };
        if (dlg.ShowDialog() != true) return;
        try { TunerMessage = Loc.F("tuner.saved", Tuner.CopyTo(dlg.FolderName)); }
        catch (Exception e) { TunerMessage = e.Message; }
        Changed();
    }

    public ICommand SetPrepModelCmd { get; private set; } = null!;
    public ICommand TunerDownloadCmd { get; private set; } = null!;
    public ICommand TunerSaveCmd { get; private set; } = null!;
    public ICommand TunerSourceCmd { get; private set; } = null!;
    public ICommand PrepGuideCmd { get; private set; } = null!;

    public bool Step1Enabled => Profile != null && !Running && (DeviceFound || Step >= 1);
    public bool Step2Enabled => Profile != null && !Running && (DeviceFound || Step >= 2);
    public bool Step3Enabled => Profile != null && Workspace != null && (DeviceFound || Step >= 3);
    public string Step0Sub => Profile == null ? "" : Profile.Name + (SelectedDevice?.HwSerial is { } s ? " · " + s : "");
    public string Step1Sub => Workspace == null ? "" : Path.GetFileName(Workspace.Image);
    public string Step2Sub => !GappsEnabled ? Loc.T("side.g.off") : Plan == GappsPlan.Unavailable ? Loc.T("side.g.na") :
        !GappsOk ? Loc.T("side.g.needfile") : Plan == GappsPlan.OnePass ? Loc.T("side.g.one") : Loc.T("side.g.after");
    public string Step3Sub => Running ? Loc.T("side.running") : InstallDone && !WaitingGapps ? Loc.T("side.done") : ExitCode == null ? "" : Loc.T(WaitingGapps ? "side.waitg" : WrittenUnchecked ? "side.written" : ExitCode == 0 ? "side.done" : "side.stopped");
    public bool MaintEnabled => Profile != null && Workspace != null && Connected && !Running;
    public bool StatusEnabled => Profile != null && Workspace != null && !Running;

    // ------------------------------------------------------------------ commands
    public ICommand ChooseRealCmd { get; private set; } = null!;
    public ICommand SetLangCmd { get; private set; } = null!;
    public ICommand GoStepCmd { get; private set; } = null!;
    public ICommand SelectDeviceCmd { get; private set; } = null!;
    public ICommand ChooseManualCmd { get; private set; } = null!;
    public ICommand ManualTabCmd { get; private set; } = null!;
    public ICommand IdentifySerialCmd { get; private set; } = null!;
    public ICommand ConnectWifiCmd { get; private set; } = null!;
    public ICommand FindOnNetworkCmd { get; private set; } = null!;
    public ICommand LoadReleasesCmd { get; private set; } = null!;
    public ICommand SelectReleaseCmd { get; private set; } = null!;
    public ICommand PrepareReleaseCmd { get; private set; } = null!;
    public ICommand CancelDownloadCmd { get; private set; } = null!;
    public ICommand PickLocalCmd { get; private set; } = null!;
    public ICommand DownloadGappsCmd { get; private set; } = null!;
    public ICommand PickGappsCmd { get; private set; } = null!;
    public ICommand AddGappsCmd { get; private set; } = null!;
    public ICommand RemoveGappsCmd { get; private set; } = null!;
    public ICommand StartInstallCmd { get; private set; } = null!;
    public ICommand StopCmd { get; private set; } = null!;
    public ICommand CopyLogCmd { get; private set; } = null!;
    public ICommand MaintCmd { get; private set; } = null!;
    public ICommand OpenGuideCmd { get; private set; } = null!;
    public ICommand OpenUrlCmd { get; private set; } = null!;
    public ICommand LeaveCmd { get; private set; } = null!;
    public ICommand GoogleAfterCmd { get; private set; } = null!;
    public ICommand ToggleGappsCmd { get; private set; } = null!;
    public ICommand ToggleBetaCmd { get; private set; } = null!;

    void BuildCommands()
    {
        ChooseRealCmd = new RelayCommand(async () => await ChooseRealAsync());
        SetLangCmd = new RelayCommand(p => Loc.Instance.SetLang((string)p!));
        GoStepCmd = new RelayCommand(p => GoStep(int.Parse((string)p!)));
        ToggleOlderCmd = new RelayCommand(() => { showOlder = !showOlder; Changed(); });
        NextFromSystemCmd = new RelayCommand(async () => { if (Workspace != null) GoStep(2); else await PrepareReleaseAsync(advance: true); });
        SetPrepModelCmd = new RelayCommand(p => { PrepModel = (string)p!; Changed(); });
        TunerDownloadCmd = new RelayCommand(async () => await TunerDownloadAsync());
        TunerSaveCmd = new RelayCommand(TunerSave);
        TunerSourceCmd = new RelayCommand(() => Open(Tuner.Source));
        PrepGuideCmd = new RelayCommand(() => { if (Profiles.FirstOrDefault(p => p.Id == PrepModel) is { } p) Open(p.GuideUrl(Loc.Instance.Lang)); });
        SelectDeviceCmd = new RelayCommand(p => { SelectedDeviceId = (string)p!; if (SelectedDevice?.Match != null) ManualProfileId = null; RebuildDevices(); Changed(); });
        ChooseManualCmd = new RelayCommand(p => { ManualProfileId = (string)p!; SelectedDeviceId = devices.FirstOrDefault(d => d.Match?.Id == ManualProfileId)?.Id; RebuildDevices(); Changed(); });
        ManualTabCmd = new RelayCommand(p => { ManualTab = int.Parse((string)p!); Changed(); });
        IdentifySerialCmd = new RelayCommand(IdentifySerial);
        ConnectWifiCmd = new RelayCommand(async () => await ConnectWifiAsync());
        FindOnNetworkCmd = new RelayCommand(async () => await FindOnNetworkAsync());
        LoadReleasesCmd = new RelayCommand(async () => await LoadReleasesAsync());
        SelectReleaseCmd = new RelayCommand(p =>
        {
            if (IsDownloading || ((string)p! == SelectedReleaseTag && Workspace != null)) return;
            SelectedReleaseTag = (string)p!; Workspace = null; Changed();
            if (SelectedRelease is { } r && Releases.IsDownloaded(r)) _ = PrepareReleaseAsync();
        });
        PrepareReleaseCmd = new RelayCommand(async () => await PrepareReleaseAsync());
        CancelDownloadCmd = new RelayCommand(() => downloadCts?.Cancel());
        PickLocalCmd = new RelayCommand(PickLocal);
        DownloadGappsCmd = new RelayCommand(async () => await DownloadGappsAsync());
        PickGappsCmd = new RelayCommand(PickGapps);
        AddGappsCmd = new RelayCommand(() => RunCommand("gapps", Loc.T("run.addgapps"), zip: GappsFile));
        RemoveGappsCmd = new RelayCommand(() => RunCommand("gapps", Loc.T("run.removegapps"), remove: true));
        StartInstallCmd = new RelayCommand(BeginInstall);
        StopCmd = new RelayCommand(() => { vbCts?.Cancel(); runner.Stop(); });
        CopyLogCmd = new RelayCommand(() => Clipboard.SetText(string.Join(Environment.NewLine, Log.Select(l => l.Text))));
        MaintCmd = new RelayCommand(p =>
        {
            var cmd = (string)p!;
            RunCommand(cmd, Loc.T("run." + cmd));
        });
        OpenGuideCmd = new RelayCommand(() => { if (Profile != null) Open(Profile.GuideUrl(Loc.Instance.Lang)); });
        OpenUrlCmd = new RelayCommand(p => Open((string)p!));
        LeaveCmd = new RelayCommand(Leave);
        SkipWaitingGappsCmd = new RelayCommand(() => { waitingGapps = null; Changed(); });
        GoogleAfterCmd = new RelayCommand(() => { GappsEnabled = true; RefreshGappsFile(); GoStep(2); });
        ToggleGappsCmd = new RelayCommand(() => { GappsEnabled = !GappsEnabled; if (GappsEnabled) RefreshGappsFile(); Changed(); });
        ToggleBetaCmd = new RelayCommand(() => { ShowBeta = !ShowBeta; AutoselectRelease(); Changed(); });
    }

    static void Open(string url) { try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); } catch { } }

    void GoStep(int s)
    {
        if (s >= 1 && (Profile == null || (!DeviceFound && s > Step))) return;
        if (s == 3 && Workspace == null) return;
        // leaving a finished run: the install step opens on its summary again
        if (Step == 3 && s != 3 && !Running && waitingGapps == null) { ExitCode = null; Log.Clear(); isInstallRun = false; InstallDone = false; }
        Step = s;
        if (s == 1) { AutoselectRelease(); if (releases.Count == 0) _ = LoadReleasesAsync(); }
        if (s == 2) RefreshGappsFile();
        Changed();
    }

    // ------------------------------------------------------------------ mode
    async Task ChooseRealAsync()
    {
        try
        {
            Busy = Loc.T("busy.pt"); BusyProgress = 0; Changed();
            await pt.EnsureAsync((d, t) => Application.Current.Dispatcher.Invoke(() => { BusyProgress = t > 0 ? (double)d / t : 0; Changed(); }));
            Busy = null; ModeChosen = true; Step = -1; Changed();
            _ = Task.Run(() => Tuner.Ready).ContinueWith(t => Application.Current.Dispatcher.Invoke(() => { TunerReady = t.Result; Changed(); }));
            poll.Start();
            await PollAsync();
        }
        catch (Exception e) { Busy = null; Changed(); ShowError(e.Message); }
    }

    void Leave()
    {
        poll.Stop();
        runner.Stop();
        ModeChosen = false; Log.Clear(); ExitCode = null; state = []; GappsEnabled = false; GappsFile = null; GappsOk = false; GappsState = "";
        ManualProfileId = null; SerialInput = ""; SerialResult = ""; Changed();
    }

    public static void ShowError(string m) => MessageBox.Show(m, "Lumen Installer", MessageBoxButton.OK, MessageBoxImage.Error);

    // ------------------------------------------------------------------ polling
    async Task PollAsync()
    {
        if (Running || scanning || !ModeChosen) return;
        scanning = true;
        try
        {
            devices = await detector.ScanAsync(Profiles);
            ScanError = null;
            if (SelectedDeviceId == null || devices.All(d => d.Id != SelectedDeviceId))
            {
                var d = devices.FirstOrDefault(x => x.Match != null && (ManualProfileId == null || x.Match.Id == ManualProfileId));
                SelectedDeviceId = d?.Id;
            }
        }
        catch (Exception e) { ScanError = e.Message; devices = []; }
        finally { scanning = false; }
        RebuildDevices();
        Changed();
        if (waitingGapps is { } zip && SelectedDevice is { State: "device", Lumen: true }) { waitingGapps = null; StartGappsChain(zip); return; }
        await RefreshVbmetaAsync();
    }

    // ------------------------------------------------------------------ the vbmeta step (Z9X, Z9X HB)
    VbmetaState? vbState;
    string vbKey = "";
    bool vbmetaDoneHere, vbmetaRunning;
    CancellationTokenSource? vbCts;

    /// Reads, without writing, whether the running slot still verifies the system (as the installer does); once per
    /// projector, and again after a run.
    async Task RefreshVbmetaAsync(bool force = false)
    {
        var key = $"{SelectedDeviceId}|{Profile?.Id}";
        if (!force && key == vbKey && vbState != null) return;
        vbKey = key;
        if (!NeedsVbmeta || SelectedDevice is not { State: "device" } d || Running) { vbState = null; Changed(); return; }
        vbState = await Vbmeta.StateAsync(pt, d.Serial, Profile!.Id);
        Changed();
    }

    async Task RunVbmetaAsync(bool thenInstall)
    {
        if (SelectedDevice is not { } d || Profile is not { } p || Running) return;
        Log.Clear(); state = []; ExitCode = null; lastOptions = null; isInstallRun = false;
        chainGapps = null; inGappsChain = false; gappsChainResult = null; waitingGapps = null;
        RunTitle = Loc.T("vb.title"); Running = true; vbmetaRunning = true;
        poll.Stop(); Changed();
        vbCts = new CancellationTokenSource();
        var ui = System.Windows.Application.Current.Dispatcher;
        void Add(string t, LineKind k) => ui.BeginInvoke(() => Log.Add(new LogLine(t, k)));
        var ok = false;
        try
        {
            var img = await Vbmeta.FetchAsync(vbCts.Token);
            Add(Loc.F("vb.ok.file", Vbmeta.Sha[..12]), LineKind.Ok);
            await Task.Run(() => Vbmeta.RunAsync(pt, img, d.Serial, d.HwSerial, d.Transport == Transport.Wifi ? d.Serial : null, p.Id, Add, vbCts.Token));
            ok = true;
        }
        catch (OperationCanceledException) { Add(Loc.T("vb.stopped"), LineKind.Stop); }
        catch (Exception e) { Add(Loc.F("vb.stop", e.Message), LineKind.Stop); }
        await ui.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.Background);   // the log lines first
        Running = false; vbmetaRunning = false;
        detector.ClearCache();
        await PollAsync();
        if (ok)
        {
            vbmetaDoneHere = true; vbState = VbmetaState.Off;
            if (thenInstall) { Log.Add(new LogLine("", LineKind.Info)); StartInstall(keepLog: true); return; }
            ExitCode = 0;
        }
        else { ExitCode = 1; await RefreshVbmetaAsync(force: true); }
        poll.Start();
        Changed();
    }

    string lastDevSig = "";
    void RebuildDevices()
    {
        var items = devices.Select(ToItem).ToList();
        var sig = string.Join("|", items);
        if (sig == lastDevSig) return;
        lastDevSig = sig;
        Devices.Clear();
        foreach (var i in items) Devices.Add(i);
    }

    DeviceItem ToItem(Device d)
    {
        var p = Profiles.FirstOrDefault(x => x.Id == d.Match?.Id);
        var name = p?.Name ?? Loc.T(d.State == "unauthorized" ? "dev.waiting" : "dev.unknown");
        var transport = d.Transport switch { Transport.Usb => "USB", Transport.Wifi => "Wi-Fi " + d.Serial, _ => "fastboot" };
        var match = d.Match == null ? "" : MatchText(d.Match);
        var system = d.Transport == Transport.Fastboot ? Loc.T("dev.fastbootmode") : d.Lumen ? "Lumen OS " + d.LumenVersion : d.Firmware != null ? Loc.T("dev.stock") : "";
        var fw = d.Firmware == null ? "" : Loc.F("dev.firmware", d.Firmware);
        string hint = "", hintTone = "warn";
        if (d.State == "unauthorized") hint = Loc.T("dev.allowdebug");
        else if (d.FirmwareOk == false && p != null) { hint = Loc.F("dev.badfw", p.FirmwareText); hintTone = "bad"; }
        else if (d.Match == null && d.State == "device") { hint = Loc.T("dev.notxgimi"); hintTone = "plain"; }
        return new DeviceItem(d.Id, name, d.HwSerial ?? d.Serial, transport, match, d.Match?.Warn == true ? "warn" : "ok", system, d.Lumen ? "ok" : "plain",
            fw, d.FirmwareOk == false ? "bad" : "plain", hint, hintTone, d.Id == SelectedDeviceId);
    }

    static string MatchText(DeviceMatch m) => m.By switch
    {
        MatchBy.Model => Loc.F("match.model", m.Value),
        MatchBy.Board => Loc.F("match.board", m.Value),
        MatchBy.Fastboot => Loc.F("match.fastboot", m.Value),
        _ => Loc.F("match.serial", m.Value) + (m.NoteKey != null ? " — " + Loc.T(m.NoteKey) : ""),
    };

    void IdentifySerial()
    {
        var s = SerialInput.Trim().ToUpperInvariant();
        // the serial of a projector that is already connected: that projector
        if (devices.FirstOrDefault(d => d.HwSerial?.ToUpperInvariant() == s && d.Match != null) is { } dev)
        {
            SelectedDeviceId = dev.Id; ManualProfileId = null;
            SerialResult = $"{Profiles.First(x => x.Id == dev.Match!.Id).Name}: {Loc.T("dev.serialconnected")}";
            SerialTone = "ok";
            RebuildDevices(); Changed();
            return;
        }
        var m = Core.Profiles.IdentifySerial(Profiles, s);
        if (m != null)
        {
            ManualProfileId = m.Id;
            SelectedDeviceId = devices.FirstOrDefault(d => d.Match?.Id == m.Id)?.Id;
            var p = Profiles.First(x => x.Id == m.Id);
            SerialResult = $"{p.Name}: {MatchText(m)}";
            SerialTone = m.Warn ? "warn" : "ok";
        }
        else { SerialResult = Loc.F("dev.serialunknown", s); SerialTone = "warn"; }
        RebuildDevices(); Changed();
    }

    async Task ConnectWifiAsync()
    {
        var addr = WifiAddr.Trim();
        if (addr.Length == 0) return;
        WifiMessage = Loc.F("wifi.connecting", addr); Changed();
        var r = await detector.ConnectAsync(addr);
        WifiMessage = r.Ok ? Loc.T("wifi.ok") : Loc.F("wifi.fail", r.Text);
        Changed();
        await PollAsync();
    }

    async Task FindOnNetworkAsync()
    {
        WifiMessage = Loc.T("wifi.searching"); Changed();
        var list = await detector.MdnsAsync();
        if (list.Count > 0) { WifiAddr = list[0]; WifiMessage = Loc.F("wifi.found", string.Join(", ", list)); }
        else WifiMessage = Loc.T("wifi.none");
        Changed();
    }

    // ------------------------------------------------------------------ releases
    async Task LoadReleasesAsync()
    {
        if (ReleasesLoading) return;
        ReleasesLoading = true; ReleasesError = null; Changed();
        try { releases = await Releases.ListAsync(); }
        catch (Exception e) { ReleasesError = e.Message; }
        ReleasesLoading = false;
        AutoselectRelease();
        Changed();
    }

    void AutoselectRelease()
    {
        if (SelectedRelease?.Device != Profile?.Id || SelectedRelease == null || (!ShowBeta && SelectedRelease.Prerelease))
        {
            // a release already on disk wins over a newer one that is not, so nothing is downloaded unasked
            SelectedReleaseTag = (DeviceReleaseList.FirstOrDefault(Releases.IsDownloaded) ?? DeviceReleaseList.FirstOrDefault())?.Tag;
            if (Workspace != null && Workspace.Device != Profile?.Id) Workspace = null;
        }
        if (Workspace == null && !IsDownloading && SelectedRelease is { } r && Releases.IsDownloaded(r)) _ = PrepareReleaseAsync();
    }

    public string DownloadButtonText => Loc.T("sys.download");

    async Task PrepareReleaseAsync(bool advance = false)
    {
        var rel = SelectedRelease;
        if (rel == null) return;
        downloadCts = new CancellationTokenSource();
        var have = Releases.IsDownloaded(rel);   // already on disk: no download, no progress bar
        IsDownloading = !have; DownloadProgress = 0; Changed();
        try
        {
            var ws = await Releases.PrepareAsync(rel, pt.ZipPath, (f, d, t) => Application.Current.Dispatcher.BeginInvoke(() =>
            {
                if (have) return;
                DownloadFile = f; DownloadProgress = t > 0 ? (double)d / t : 0; Changed();
            }), downloadCts.Token);
            Workspace = ws;
            Profiles = Core.Profiles.Load(ws.InstallerDir);
            if (advance && have) GoStep(2);   // a download stays on this step: its result is shown
        }
        catch (OperationCanceledException) { }
        catch (Exception e) { ReleasesError = e.Message; }
        IsDownloading = false; Changed();
    }

    void PickLocal()
    {
        var dlg = new Microsoft.Win32.OpenFolderDialog { Title = Loc.T("sys.pickfolder") };
        if (dlg.ShowDialog() != true) return;
        try { Workspace = Releases.Local(dlg.FolderName); SelectedReleaseTag = null; ReleasesError = null; }
        catch (Exception e) { ReleasesError = e.Message; }
        Changed();
    }

    // ------------------------------------------------------------------ Google services
    void RefreshGappsFile()
    {
        if (GappsZip is not { } z || GappsFile != null) return;
        var local = Gapps.LocalCopy(z);
        if (File.Exists(local) && new FileInfo(local).Length == z.Size) _ = VerifyGappsAsync(local);
    }

    async Task DownloadGappsAsync()
    {
        if (GappsZip is not { } z) return;
        GappsBusy = true; GappsPhase = Loc.F("g.downloading", z.Name); GappsProgress = 0; Changed();
        try
        {
            await Net.DownloadAsync(z.Url, Gapps.LocalCopy(z), z.Size, (d, t) => Application.Current.Dispatcher.BeginInvoke(() =>
            {
                GappsProgress = t > 0 ? (double)d / t : 0; Changed();
            }));
            await VerifyGappsAsync(Gapps.LocalCopy(z));
        }
        catch (Exception e) { GappsBusy = false; GappsOk = false; GappsState = Loc.F("g.dlfail", e.Message); Changed(); }
    }

    void PickGapps()
    {
        var dlg = new Microsoft.Win32.OpenFileDialog { Title = "MindTheGapps", Filter = "ZIP|*.zip" };
        if (dlg.ShowDialog() == true) _ = VerifyGappsAsync(dlg.FileName);
    }

    async Task VerifyGappsAsync(string file)
    {
        if (GappsZip is not { } z) return;
        GappsFile = file; GappsOk = false; GappsBusy = true; GappsPhase = Loc.T("g.checking"); GappsProgress = 0; Changed();
        string? why;
        try
        {
            why = await Task.Run(() => Gapps.Check(file, z, (d, t) => Application.Current.Dispatcher.BeginInvoke(() =>
            {
                GappsProgress = t > 0 ? (double)d / t : 0; Changed();
            })));
        }
        catch (Exception e) { why = e.Message; }
        GappsBusy = false; GappsOk = why == null;
        GappsState = why ?? Loc.F("g.fileok", z.Name);
        Changed();
    }

    // ------------------------------------------------------------------ running the installer
    RunOptions BaseOptions()
    {
        var o = new RunOptions { Lang = Loc.Instance.InstallerLang };
        if (Profile is not { } p) return o;
        o.Device = p.Id;
        if (SelectedDevice is { } d)
        {
            if (d.Transport == Transport.Wifi) o.Ip = d.Serial;
            else if (p.Connection == Connection.Usb) o.Serial = d.Serial;
        }
        else if (p.Connection == Connection.Wifi && WifiAddr.Trim().Length > 0) o.Ip = WifiAddr.Trim();
        if (Workspace != null) o.Image = Workspace.Image;
        return o;
    }

    /// "Start the install": on a projector that still verifies its system the client offers to do the vbmeta step first.
    void BeginInstall()
    {
        if (!CanInstall) return;
        if (VbOn)
        {
            if (MessageBox.Show(Loc.T("vb.ask.text") + (Profile?.Id == "hb" ? " " + Loc.T("vb.note.hb") : ""), Loc.T("vb.ask.title"), MessageBoxButton.OKCancel, MessageBoxImage.Information) != MessageBoxResult.OK) return;
            _ = RunVbmetaAsync(thenInstall: true);
            return;
        }
        StartInstall();
    }

    void StartInstall(bool keepLog = false)
    {
        InstallDone = false;
        if (!CanInstall) return;
        var o = BaseOptions();
        chainGapps = null; gappsChainResult = null; inGappsChain = false; waitingGapps = null;
        if (GappsWillInstall && GappsFile != null)
        {
            if (Plan == GappsPlan.OnePass) o.GappsZip = GappsFile; else chainGapps = GappsFile;
        }
        Run(o, Loc.T(o.GappsZip != null ? "run.install.google" : chainGapps != null ? "run.install.then" : "run.install"), install: true, keepLog: keepLog);
    }

    void RunCommand(string cmd, string title, string? zip = null, bool remove = false)
    {
        if (cmd != "status" && !Connected) { ShowError(Loc.T("block.nodevice")); return; }
        var o = BaseOptions();
        o.Command = cmd; o.Zip = zip; o.Remove = remove;
        chainGapps = null; inGappsChain = false; gappsChainResult = null; waitingGapps = null;
        Step = 3;
        Run(o, title, install: false);
    }

    void StartGappsChain(string zip)
    {
        var o = BaseOptions();
        o.Command = "gapps"; o.Zip = zip;
        inGappsChain = true;
        Log.Add(new LogLine("", LineKind.Info));
        Log.Add(new LogLine("──────── " + Loc.T("chain.sep") + " ────────", LineKind.Cmd));
        Run(o, RunTitle, install: true, keepLog: true);
    }

    void Run(RunOptions o, string title, bool install, bool keepLog = false)
    {
        if (Workspace is not { } ws || Running) return;
        if (!keepLog) { Log.Clear(); state = []; }
        ExitCode = null; RunTitle = title; lastOptions = o; isInstallRun = install;
        poll.Stop();
        try
        {
            runner.Start(ws.InstallerDir, o);
            Running = true;
            stateTimer.Start();
            RefreshState();
        }
        catch (Exception e) { ShowError(e.Message); poll.Start(); }
        Changed();
    }

    void OnExit(int code)
    {
        Running = false; ExitCode = code;
        chainSkipped = code != 0 && chainGapps != null;
        stateTimer.Stop(); RefreshState();
        detector.ClearCache();
        if (inGappsChain) { inGappsChain = false; gappsChainResult = code; }
        else if (code == 0 && chainGapps is { } zip) { chainGapps = null; waitingGapps = zip; }   // step 2 of 2, once Lumen OS is on adb (PollAsync)
        else chainGapps = null;
        // the system is on the projector: the step is green while its result is on screen
        if (isInstallRun && waitingGapps == null && (code == 0 || WrittenUnchecked)) InstallDone = true;
        poll.Start();
        Changed();
        _ = PollAsync();
    }

    void RefreshState()
    {
        if (Profile is not { } p) return;
        var s = InstallerRunner.ReadState(InstallerRunner.StateFile(p.Id, Paths.StateDir));
        if (s.Count != state.Count || s.Any(kv => state.GetValueOrDefault(kv.Key) != kv.Value)) { state = s; Changed(); }
    }

    public void Answer(string text) => runner.Answer(text);

    static string Size(long b) => b >= 1L << 30 ? $"{b / (double)(1L << 30):0.0} GB" : b >= 1L << 20 ? $"{b / (double)(1L << 20):0.0} MB" : $"{b / 1024.0:0} KB";
}
