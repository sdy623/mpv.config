using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Windows.Forms;
using System.Collections.Generic;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

internal static class MpvAnimeLauncher
{
    private static readonly string Root = AppDomain.CurrentDomain.BaseDirectory;
    private static List<string> DiscRoots()
    {
        List<string> result = new List<string>();
        foreach (DriveInfo d in DriveInfo.GetDrives())
        {
            try { if (d.DriveType == DriveType.CDRom && d.IsReady && Directory.Exists(Path.Combine(d.Name, "BDMV"))) result.Add(d.Name); }
            catch (IOException) { }
        }
        return result;
    }

    private static string BdRoot(string path)
    {
        if (String.IsNullOrWhiteSpace(path) || path.Contains("://")) return null;
        string p = Path.GetFullPath(path);
        if (File.Exists(p) && Path.GetFileName(p).Equals("index.bdmv", StringComparison.OrdinalIgnoreCase)) p = Path.GetDirectoryName(p);
        if (Directory.Exists(p) && new DirectoryInfo(p).Name.Equals("BDMV", StringComparison.OrdinalIgnoreCase)) p = Directory.GetParent(p).FullName;
        return Directory.Exists(Path.Combine(p, "BDMV")) ? p : null;
    }

    private static bool IsMmt(string path)
    {
        if (path.StartsWith("mmt+http", StringComparison.OrdinalIgnoreCase)) return true;
        string p = path.Split('?')[0].ToLowerInvariant();
        return p.EndsWith(".mmts") || p.EndsWith(".mmt") || p.EndsWith(".tlv");
    }

    private static string Arguments(IEnumerable<string> args)
    {
        StringBuilder b = new StringBuilder();
        foreach (string arg in args) b.Append(Quote(arg)).Append(' ');
        return b.ToString();
    }

    private static ProcessStartInfo Player(IEnumerable<string> args)
    {
        string java = Path.Combine(Root, "runtime", "java8");
        string bdj = Path.Combine(Root, "runtime", "bdj", "libbluray-j2se-1.5.0.jar");
        string data = Path.Combine(Root, "portable_config", "bdj-data");
        Directory.CreateDirectory(Path.Combine(data, "cache"));
        Directory.CreateDirectory(Path.Combine(data, "persistent"));
        ProcessStartInfo psi = new ProcessStartInfo(Path.Combine(Root, "mpv.exe"), Arguments(args));
        psi.WorkingDirectory = Root;
        psi.UseShellExecute = false;
        psi.EnvironmentVariables["JAVA_HOME"] = java;
        psi.EnvironmentVariables["LIBBLURAY_CP"] = bdj;
        psi.EnvironmentVariables["LIBBLURAY_CACHE_ROOT"] = Path.Combine(data, "cache");
        psi.EnvironmentVariables["LIBBLURAY_PERSISTENT_ROOT"] = Path.Combine(data, "persistent");
        psi.EnvironmentVariables["PATH"] = Path.Combine(Root, "runtime", "tools") + ";" + Path.Combine(java, "bin") + ";" + psi.EnvironmentVariables["PATH"];
        return psi;
    }

    private static Process StartTool(string path, IEnumerable<string> args, bool input)
    {
        ProcessStartInfo psi = new ProcessStartInfo(path, Arguments(args));
        psi.WorkingDirectory = Root;
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        psi.RedirectStandardOutput = true;
        psi.RedirectStandardError = true;
        psi.RedirectStandardInput = input;
        Process p = Process.Start(psi);
        // Drain diagnostic output without retaining URLs or creating playback logs.
        p.ErrorDataReceived += delegate { };
        p.BeginErrorReadLine();
        return p;
    }

    private static void CloseOwned(Process p)
    {
        if (p == null) return;
        try { if (!p.HasExited) p.Kill(); } catch (InvalidOperationException) { }
        p.Dispose();
    }

    private static void PlayMmt(string source, List<string> options)
    {
        if (source.StartsWith("mmt+", StringComparison.OrdinalIgnoreCase)) source = source.Substring(4);
        Uri uri;
        bool network = Uri.TryCreate(source, UriKind.Absolute, out uri) && (uri.Scheme == "http" || uri.Scheme == "https");
        if (!network && !File.Exists(source)) throw new FileNotFoundException("找不到 MMT/TLV 文件；网络源请使用 HTTP 或 HTTPS 地址。");
        Process fetch = null, convert = null, player = null;
        try
        {
            string converter = Path.Combine(Root, "runtime", "mmt2ts", "mmt2ts.exe");
            convert = StartTool(converter, new [] { "-quiet", "-no-carousel", "-i", network ? "-" : Path.GetFullPath(source), "-o", "-" }, network);
            if (network)
            {
                fetch = StartTool(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "curl.exe"),
                    new [] { "--fail", "--location", "--silent", "--show-error", "--connect-timeout", "20", "--speed-time", "30", "--speed-limit", "1", "--url", source }, false);
                Process f = fetch, c = convert;
                Task.Run(delegate { try { f.StandardOutput.BaseStream.CopyTo(c.StandardInput.BaseStream, 131072); } catch (IOException) { } catch (ObjectDisposedException) { } finally { try { c.StandardInput.Close(); } catch { } } });
            }
            byte[] first = new byte[188 * 64];
            int count = convert.StandardOutput.BaseStream.Read(first, 0, first.Length);
            if (count == 0) throw new IOException("MMT 输入没有产生可播放的 TS 数据。请确认输入是有效的明文 MMT/TLV 流。");
            List<string> args = new List<string> { "--idle=no", "--keep-open=no", "--input-terminal=no", "--demuxer-lavf-format=mpegts", "--cache=yes", "--force-media-title=" + (network ? "NHK / MMT 直播" : Path.GetFileName(source)) };
            args.AddRange(options);
            args.Add("-");
            ProcessStartInfo psi = Player(args);
            psi.RedirectStandardInput = true;
            player = Process.Start(psi);
            player.StandardInput.BaseStream.Write(first, 0, count);
            Process cv = convert, pv = player;
            Task.Run(delegate { try { cv.StandardOutput.BaseStream.CopyTo(pv.StandardInput.BaseStream, 131072); } catch (IOException) { } catch (ObjectDisposedException) { } finally { try { pv.StandardInput.Close(); } catch { } } });
            player.WaitForExit();
        }
        finally { CloseOwned(player); CloseOwned(convert); CloseOwned(fetch); }
    }
    private static string Quote(string value)
    {
        StringBuilder result = new StringBuilder("\"");
        int slashes = 0;
        foreach (char c in value)
        {
            if (c == '\\') { slashes++; continue; }
            if (c == '"') { result.Append('\\', slashes * 2 + 1); result.Append(c); slashes = 0; continue; }
            result.Append('\\', slashes); slashes = 0; result.Append(c);
        }
        result.Append('\\', slashes * 2);
        return result.Append('"').ToString();
    }

    [STAThread]
    private static void Main(string[] args)
    {
        try
        {
            Application.EnableVisualStyles();
            if (args.Length > 0 && args[0] == "--list-bd-drives")
            {
                using (StreamWriter output = new StreamWriter(Console.OpenStandardOutput(), new UTF8Encoding(false)))
                    output.WriteLine(new JavaScriptSerializer().Serialize(DiscRoots()));
                return;
            }
            string root = Root;
            string player = Path.Combine(root, "mpv.exe");
            string java = Path.Combine(root, "runtime", "java8");
            string bdj = Path.Combine(root, "runtime", "bdj", "libbluray-j2se-1.5.0.jar");
            if (!File.Exists(player) || !File.Exists(bdj) || !File.Exists(Path.Combine(java, "bin", "server", "jvm.dll")))
                throw new FileNotFoundException("MPV / Java / BD-J 文件不完整，请保留整个播放器文件夹。");
            List<string> options = new List<string>();
            List<string> sources = new List<string>();
            string mmt = null, bd = null;
            foreach (string arg in args) { if (arg.StartsWith("--")) options.Add(arg); else sources.Add(arg); }
            if (options.Remove("--open-bd-drive"))
            {
                List<string> discs = DiscRoots();
                if (discs.Count == 0) throw new IOException("没有找到含 BDMV 的蓝光光盘。请放入光盘后重试。");
                if (discs.Count == 1) bd = discs[0];
                else
                {
                    using (FolderBrowserDialog dlg = new FolderBrowserDialog())
                    {
                        dlg.Description = "选择蓝光光驱"; dlg.SelectedPath = discs[0];
                        if (dlg.ShowDialog() != DialogResult.OK) return;
                        bd = BdRoot(dlg.SelectedPath);
                    }
                }
            }
            if (options.Remove("--open-bd-folder"))
            {
                using (FolderBrowserDialog dlg = new FolderBrowserDialog())
                {
                    dlg.Description = "选择蓝光原盘文件夹或 BDMV 文件夹";
                    if (dlg.ShowDialog() != DialogResult.OK) return;
                    bd = BdRoot(dlg.SelectedPath);
                    if (bd == null) throw new IOException("所选文件夹没有 BDMV 目录。");
                }
            }
            if (options.Remove("--open-bd-iso"))
            {
                using (OpenFileDialog dlg = new OpenFileDialog())
                {
                    dlg.Title = "打开蓝光 ISO"; dlg.Filter = "蓝光镜像 (*.iso)|*.iso";
                    if (dlg.ShowDialog() != DialogResult.OK) return;
                    bd = dlg.FileName;
                }
            }
            if (options.Remove("--mmt-source"))
            {
                if (sources.Count != 1) throw new ArgumentException("需要一个 MMT 文件或 HTTP(S) 地址。");
                mmt = sources[0]; sources.Clear();
            }
            if (sources.Count == 1)
            {
                if (IsMmt(sources[0])) { mmt = sources[0]; sources.Clear(); }
                else
                {
                    bd = BdRoot(sources[0]);
                    if (bd != null) sources.Clear();
                }
            }
            if (mmt != null) { PlayMmt(mmt, options); return; }
            if (bd != null) { options.Add("--bluray-device=" + bd); options.Add("--disc-menu=yes"); sources.Add("bd://menu"); }
            options.AddRange(sources);
            Process.Start(Player(options));
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, "MPV 动漫播放器", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
}
