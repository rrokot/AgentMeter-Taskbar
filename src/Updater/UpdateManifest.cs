using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;

internal sealed class UpdateManifest {
    internal const int MaximumBytes = 16384;
    internal readonly Version Version;
    internal readonly string InstallerHash;

    private UpdateManifest(Version version, string installerHash) {
        Version = version;
        InstallerHash = installerHash;
    }

    internal static UpdateManifest Read(string manifestPath, string publicKeyPath) {
        string envelope;
        using (var reader = File.OpenText(manifestPath)) {
            if (reader.BaseStream.Length > MaximumBytes) throw new InvalidDataException("Update manifest is too large.");
            envelope = reader.ReadToEnd();
        }
        var serializer = new JavaScriptSerializer();
        var feed = serializer.Deserialize<Dictionary<string, object>>(envelope);
        byte[] payload = Convert.FromBase64String(RequiredText(feed, "payload"));
        byte[] signature = Convert.FromBase64String(RequiredText(feed, "signature"));
        using (var rsa = new RSACryptoServiceProvider()) {
            rsa.PersistKeyInCsp = false;
            rsa.FromXmlString(File.ReadAllText(publicKeyPath));
            if (!rsa.VerifyData(payload, CryptoConfig.MapNameToOID("SHA256"), signature)) {
                throw new InvalidDataException("Update signature verification failed.");
            }
        }

        var release = serializer.Deserialize<Dictionary<string, object>>(Encoding.UTF8.GetString(payload));
        Version version;
        string hash = RequiredText(release, "sha256");
        object schema;
        if (!release.TryGetValue("schema", out schema) || !(schema is int) || (int)schema != 1 ||
            !TryParseVersion(RequiredText(release, "version"), out version) ||
            !Regex.IsMatch(hash, @"\A[a-fA-F0-9]{64}\z")) {
            throw new InvalidDataException("Unsupported update manifest.");
        }
        return new UpdateManifest(version, hash);
    }

    internal void VerifyInstaller(string installerPath) {
        using (var file = File.OpenRead(installerPath))
        using (var sha256 = SHA256.Create()) {
            string actual = BitConverter.ToString(sha256.ComputeHash(file)).Replace("-", "");
            if (!string.Equals(actual, InstallerHash, StringComparison.OrdinalIgnoreCase)) {
                throw new InvalidDataException("Downloaded installer checksum verification failed.");
            }
        }
    }

    internal static bool TryParseVersion(string text, out Version version) {
        version = null;
        return text != null && Regex.IsMatch(text, @"\A[0-9]+\.[0-9]+\.[0-9]+\z") &&
            Version.TryParse(text, out version) && version.ToString() == text;
    }

    private static string RequiredText(Dictionary<string, object> fields, string key) {
        object value;
        if (fields == null || !fields.TryGetValue(key, out value) || !(value is string)) {
            throw new InvalidDataException("Invalid update manifest field: " + key);
        }
        return (string)value;
    }
}
