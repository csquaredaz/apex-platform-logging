/**
 * @description The logger's configuration, read once per transaction from the `Default` row of
 * `Logging_Setting__mdt` (ADR 0004). A missing row or blank field falls back to a safe default,
 * so a bad configuration never stops the logger: enabled, DEBUG, a buffer of 50, no Slack
 * channel (alerts are then logged, not sent), and retention on at 30 days (ADR 0007).
 *
 * A hierarchy custom setting would allow per-user levels; it's the recorded extension point.
 * @group Logging
 */
public with sharing class LoggingSettings {
  /** @description The `Logging_Setting__mdt` row the logger reads. */
  public static final String DEFAULT_ROW = 'Default';
  /** @description The buffer size when the row has none. */
  public static final Integer DEFAULT_BUFFER_SIZE = 50;
  /** @description The largest buffer size allowed. */
  public static final Integer MAX_BUFFER_SIZE = 500;
  /** @description The retention in days when the row has none. */
  public static final Integer DEFAULT_RETENTION_DAYS = 30;
  /** @description The longest retention allowed, in days (about ten years). */
  public static final Integer MAX_RETENTION_DAYS = 3650;

  private static final Map<String, Integer> RANK_BY_LEVEL = new Map<String, Integer>{
    'DEBUG' => 1,
    'INFO' => 2,
    'WARN' => 3,
    'ERROR' => 4
  };

  private static LoggingSettings current;

  /** @description False drops every entry. */
  public final Boolean isEnabled;
  /** @description Entries below this level are dropped. */
  public final LoggingLevel minimumLevel;
  /** @description Entries held before an automatic flush; between 1 and `MAX_BUFFER_SIZE`. */
  public final Integer bufferSize;
  /** @description The Slack channel alerts go to (ADR 0006); null when blank. */
  public final String slackChannel;
  /** @description False stops `LogRetentionBatch` deleting rows (ADR 0007). */
  public final Boolean isRetentionEnabled;
  /** @description Days a `Log__c` row is kept; between 1 and `MAX_RETENTION_DAYS`. */
  public final Integer retentionDays;

  /**
   * @description The settings for this transaction, read from metadata on first use.
   * @return The current settings; never null.
   */
  public static LoggingSettings current() {
    if (current == null) {
      current = new LoggingSettings(Logging_Setting__mdt.getInstance(DEFAULT_ROW));
    }
    return current;
  }

  /**
   * @description Test seam: custom metadata can't be inserted in a test, so a row is injected.
   * @param row The row to use; null means the defaults.
   */
  @TestVisible
  private static void useRow(Logging_Setting__mdt row) {
    current = new LoggingSettings(row);
  }

  @TestVisible
  private LoggingSettings(Logging_Setting__mdt row) {
    isEnabled = row == null || row.Is_Enabled__c;
    minimumLevel = row == null || !RANK_BY_LEVEL.containsKey(row.Minimum_Level__c)
      ? LoggingLevel.DEBUG
      : LoggingLevel.valueOf(row.Minimum_Level__c);
    bufferSize = clamp(row == null ? null : row.Buffer_Size__c, DEFAULT_BUFFER_SIZE, MAX_BUFFER_SIZE);
    slackChannel = row == null || String.isBlank(row.Slack_Channel__c) ? null : row.Slack_Channel__c.trim();
    isRetentionEnabled = row == null || row.Is_Retention_Enabled__c;
    retentionDays = clamp(row == null ? null : row.Retention_Days__c, DEFAULT_RETENTION_DAYS, MAX_RETENTION_DAYS);
  }

  /**
   * @description Whether an entry at this level is kept.
   * @param level The entry's level.
   * @return True when logging is enabled and the level is at or above the minimum.
   */
  public Boolean accepts(LoggingLevel level) {
    Integer rank = level == null ? null : RANK_BY_LEVEL.get(level.name());
    return isEnabled && rank != null && rank >= RANK_BY_LEVEL.get(minimumLevel.name());
  }

  // Blank or below 1 means the default; above the maximum means the maximum.
  private static Integer clamp(Decimal configured, Integer defaultValue, Integer maximum) {
    if (configured == null || configured < 1) {
      return defaultValue;
    }
    return Math.min(configured.intValue(), maximum);
  }
}
