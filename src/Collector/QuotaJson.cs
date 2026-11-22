using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;
using System.Web.Script.Serialization;

internal static class QuotaJson {
    private const int MaximumSnapshotBytes = 65536;
    private static readonly JavaScriptSerializer Serializer = new JavaScriptSerializer();
    private static readonly CultureInfo Invariant = CultureInfo.InvariantCulture;

    internal static StreamReader OpenSharedReader(string path) {
        return new StreamReader(File.Open(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete));
    }

    private static IDictionary<string, object> ReadObject(string path) {
        using (var reader = OpenSharedReader(path)) {
            if (reader.BaseStream.Length > MaximumSnapshotBytes) {
                throw new InvalidDataException("Quota snapshot exceeds the size limit.");
            }
            return ParseObject(reader.ReadToEnd());
        }
    }

    internal static IDictionary<string, object> ParseObject(string json) {
        try {
            return Serializer.DeserializeObject(json) as IDictionary<string, object>;
        } catch (ArgumentException) {
            return null;
        } catch (InvalidOperationException) {
            return null;
        }
    }

    internal static IDictionary<string, object> ReadObjectOrNull(string path) {
        try {
            return ReadObject(path);
        } catch (IOException) {
            return null;
        } catch (UnauthorizedAccessException) {
            return null;
        } catch (InvalidDataException) {
            return null;
        }
    }

    internal static FileStream OpenWriterLock(string path) {
        try {
            return new FileStream(path, FileMode.OpenOrCreate, FileAccess.Write, FileShare.None);
        } catch (IOException error) {
            const int SharingViolation = unchecked((int)0x80070020);
            if (error.HResult != SharingViolation) throw;
            return null;
        }
    }

    internal static void ReplaceFile(string path, object snapshot) {
        string pendingPath = path + ".pending";
        try {
            File.WriteAllText(pendingPath, Serializer.Serialize(snapshot), new UTF8Encoding(false));
            if (File.Exists(path)) {
                File.Replace(pendingPath, path, null);
            } else {
                File.Move(pendingPath, path);
            }
        } finally {
            File.Delete(pendingPath);
        }
    }

    internal static object Field(IDictionary<string, object> record, string name) {
        object value;
        return record != null && record.TryGetValue(name, out value) ? value : null;
    }

    internal static IDictionary<string, object> ObjectField(IDictionary<string, object> record, string name) {
        return Field(record, name) as IDictionary<string, object>;
    }

    internal static string Text(object value) {
        if (value is decimal) return ((decimal)value).ToString("G29", Invariant);
        return Convert.ToString(value, Invariant);
    }

    internal static long? Integer(object value) {
        long number;
        return long.TryParse(Text(value), NumberStyles.Integer, Invariant, out number) ? (long?)number : null;
    }

    internal static DateTimeOffset? Timestamp(object value) {
        DateTimeOffset timestamp;
        return DateTimeOffset.TryParse(Text(value), Invariant, DateTimeStyles.AssumeUniversal, out timestamp)
            ? (DateTimeOffset?)timestamp : null;
    }

    internal static DateTimeOffset? UnixSeconds(object value) {
        long? seconds = Integer(value);
        return seconds > 0 && seconds <= DateTimeOffset.MaxValue.ToUnixTimeSeconds()
            ? (DateTimeOffset?)DateTimeOffset.FromUnixTimeSeconds(seconds.Value) : null;
    }

    internal static string IsoTimestamp(DateTimeOffset? timestamp) {
        return timestamp.HasValue ? timestamp.Value.ToString("o", Invariant) : "";
    }
}
