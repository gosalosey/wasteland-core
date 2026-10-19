using System.Xml;
using CodeWalker.GameFiles;

// wlprops: export a game model to XML (reference only), or build XML -> GTA files.
//   wlprops export <gtaFolder> <modelName> <outDir>
//   wlprops build <inDir> <outDir>
//   wlprops dump <file.ydr|ytyp> <outDir>
if (args.Length < 1) { Console.WriteLine("usage: export|build|dump"); return 1; }

if (args[0] == "export")
{
    string gta = args[1], model = args[2].ToLowerInvariant(), outDir = args[3];
    Directory.CreateDirectory(outDir);
    GTA5Keys.LoadFromPath(gta, false, null);
    var rpf = new RpfManager();
    rpf.Init(gta, false, s => { }, e => Console.WriteLine("ERR " + e));
    int found = 0;
    foreach (var kv in rpf.EntryDict)
    {
        var name = Path.GetFileName(kv.Key);
        if (name == model + ".ydr" || name == model + ".ytyp" || name == model + ".ybn")
        {
            var entry = kv.Value as RpfFileEntry;
            if (entry == null) continue;
            var data = entry.File.ExtractFile(entry);
            var xml = MetaXml.GetXml(entry, data, out string fname, outDir);
            File.WriteAllText(Path.Combine(outDir, fname), xml);
            Console.WriteLine("exported " + kv.Key + " -> " + fname);
            found++;
        }
    }
    if (found == 0) Console.WriteLine("not found: " + model);
    return found > 0 ? 0 : 2;
}

if (args[0] == "materials")
{
    string gta = args[1];
    GTA5Keys.LoadFromPath(gta, false, null);
    var rpf = new RpfManager();
    rpf.Init(gta, false, s => { }, e => { });
    var data = rpf.GetFileData(@"update\update.rpf\common\data\materials\materials.dat") ?? rpf.GetFileData(@"common.rpf\data\materials\materials.dat");
    var text = System.Text.Encoding.UTF8.GetString(data);
    int i = 0;
    foreach (var line in text.Split('\n'))
    {
        var t = line.Trim();
        if (t.Length == 0 || t.StartsWith("#") || char.IsDigit(t[0])) continue;
        var name = t.Split(new[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries)[0];
        Console.WriteLine(i + " " + name); i++;
    }
    return 0;
}

if (args[0] == "build")
{
    string inDir = args[1], outDir = args[2];
    Directory.CreateDirectory(outDir);
    int bad = 0;
    foreach (var path in Directory.GetFiles(inDir, "*.xml"))
    {
        var fn = Path.GetFileName(path);
        var outName = fn.Substring(0, fn.Length - 4);
        MetaFormat fmt;
        if (outName.EndsWith(".ydr")) fmt = MetaFormat.Ydr;
        else if (outName.EndsWith(".ytd")) fmt = MetaFormat.Ytd;
        else if (outName.EndsWith(".ybn")) fmt = MetaFormat.Ybn;
        else if (outName.EndsWith(".ytyp")) fmt = MetaFormat.RSC;
        else continue;
        try
        {
            var doc = new XmlDocument();
            doc.Load(path);
            var data = XmlMeta.GetData(doc, fmt, Path.GetDirectoryName(path));
            if (data == null) { Console.WriteLine("FAILED " + fn); bad++; continue; }
            File.WriteAllBytes(Path.Combine(outDir, outName), data);
            Console.WriteLine("built " + outName + " (" + data.Length + " bytes)");
        }
        catch (Exception e) { Console.WriteLine("FAILED " + fn + ": " + e.Message); bad++; }
    }
    return bad == 0 ? 0 : 3;
}

if (args[0] == "dump")
{
    string file = args[1], outDir = args[2];
    Directory.CreateDirectory(outDir);
    var data = File.ReadAllBytes(file);
    var entry = RpfFile.CreateResourceFileEntry(ref data, 0);
    entry.Name = Path.GetFileName(file); entry.NameLower = entry.Name.ToLowerInvariant();
    data = ResourceBuilder.Decompress(data);
    var xml = MetaXml.GetXml(entry, data, out string fname, outDir);
    File.WriteAllText(Path.Combine(outDir, fname), xml);
    Console.WriteLine("dumped " + fname);
    return 0;
}
return 1;
