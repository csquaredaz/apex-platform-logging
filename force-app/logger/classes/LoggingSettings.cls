/**
 * @description The logger's configuration, read once per transaction from the `Default` row of
 * `Logging_Setting__mdt` (ADR 0004). A missing row or blank field falls back to a safe default,
 * so a bad configuration never stops the logger: enabled, DEBUG, a buffer of 50, and no Slack
 * channel (alerts are then logged, not sent).
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
    bufferSize = clampBufferSize(row == null ? null : row.Buffer_Size__c);
    slackChannel = row == null || String.isBlank(row.Slack_Channel__c) ? null : row.Slack_Channel__c.trim();
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

  private static Integer clampBufferSize(Decimal configured) {
    if (configured == null || configured < 1) {
      return DEFAULT_BUFFER_SIZE;
    }
    return Math.min(configured.intValue(), MAX_BUFFER_SIZE);
  }
}
