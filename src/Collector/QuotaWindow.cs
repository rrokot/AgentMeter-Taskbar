using System;
using System.Globalization;

internal enum QuotaPeriod {
    FiveHour,
    Weekly
}

internal sealed class QuotaWindow {
    private static readonly TimeSpan ClaudeFreshnessWithoutReset = TimeSpan.FromMinutes(15);

    internal readonly int UsedPercent;
    internal readonly DateTimeOffset? ResetAt;
    internal readonly DateTimeOffset? ObservedAt;
    internal readonly DateTimeOffset? FreshUntil;

    private QuotaWindow(int usedPercent, DateTimeOffset? resetAt, DateTimeOffset? observedAt) {
        UsedPercent = usedPercent;
        ResetAt = resetAt;
        ObservedAt = observedAt;
        if (observedAt.HasValue) {
            FreshUntil = resetAt ?? observedAt.Value.Add(ClaudeFreshnessWithoutReset);
        }
    }

    internal static QuotaWindow Parse(object percent, DateTimeOffset? resetAt, DateTimeOffset? observedAt = null) {
        double usedPercent;
        if (!double.TryParse(QuotaJson.Text(percent), NumberStyles.Float, CultureInfo.InvariantCulture, out usedPercent)
            || double.IsNaN(usedPercent) || double.IsInfinity(usedPercent) || usedPercent < 0) {
            return null;
        }
        return new QuotaWindow((int)Math.Floor(Math.Min(100, usedPercent)), resetAt, observedAt);
    }

    internal bool IsCurrent(DateTimeOffset now) {
        return (!ResetAt.HasValue || ResetAt > now) && (!FreshUntil.HasValue || FreshUntil > now);
    }
}
