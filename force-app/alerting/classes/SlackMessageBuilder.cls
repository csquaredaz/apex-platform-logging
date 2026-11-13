/**
 * @description Builds the `chat.postMessage` payload for one batch of alerts (Builder, ADR 0006).
 * One message per batch: a header, then a `section` and a `context` block per alert.
 *
 * Slack accepts at most 50 blocks per message, so a message shows at most `MAX_ALERTS_SHOWN`
 * alerts (1 + 2 x 24 = 49 blocks). When there are more, one last `context` block says how many
 * were left out, which makes exactly 50. Every alert is still in `Log__c`.
 *
 * Text is escaped for Slack mrkdwn (`&`, `<`, `>`), so a log message can't inject a link or a
 * mention, and cut to Slack's limits. Pure: no SOQL, DML or callouts.
 * @group Alerting
 */
public with sharing class SlackMessageBuilder {
  /** @description Slack's limit on blocks in one message. */
  public static final Integer MAX_BLOCKS = 50;
  /** @description Alerts shown in one message; the rest are counted in the last block. */
  public static final Integer MAX_ALERTS_SHOWN = (MAX_BLOCKS - 2) / 2;
  /** @description Slack's limit on the text of a `section` or a `context` element. */
  public static final Integer MAX_TEXT_LENGTH = 3000;

  private static final Map<Alert.Severity, String> MARKER_BY_SEVERITY = new Map<Alert.Severity, String>{
    Alert.Severity.CRITICAL => ':rotating_light:',
    Alert.Severity.WARNING => ':warning:',
    Alert.Severity.INFO => ':information_source:'
  };

  /**
   * @description Builds the request body.
   * @param alerts The alerts; at least one, none null.
   * @param channel The channel ID or name.
   * @return A map that serialises to the `chat.postMessage` JSON body.
   */
  public static Map<String, Object> build(List<Alert> alerts, String channel) {
    return new Map<String, Object>{
      'channel' => channel,
      'text' => fallbackText(alerts),
      'blocks' => blocks(alerts),
      'unfurl_links' => false,
      'unfurl_media' => false
    };
  }

  private static List<Object> blocks(List<Alert> alerts) {
    List<Object> blocks = new List<Object>{ header(alerts.size()) };
    Integer shown = Math.min(alerts.size(), MAX_ALERTS_SHOWN);
    for (Integer i = 0; i < shown; i++) {
      blocks.add(section(alerts[i]));
      blocks.add(context('Source: ' + (String.isBlank(alerts[i].source) ? 'unknown' : escape(alerts[i].source))));
    }
    if (alerts.size() > shown) {
      blocks.add(context('+' + (alerts.size() - shown) + ' more alerts not shown. Every alert is in Log__c.'));
    }
    return blocks;
  }

  private static Map<String, Object> header(Integer count) {
    return new Map<String, Object>{
      'type' => 'header',
      'text' => new Map<String, Object>{ 'type' => 'plain_text', 'text' => count + (count == 1 ? ' alert' : ' alerts') }
    };
  }

  private static Map<String, Object> section(Alert alert) {
    String text = MARKER_BY_SEVERITY.get(alert.severity) + ' *' + alert.severity.name() + '* ' + escape(alert.title);
    if (String.isNotBlank(alert.detail)) {
      text += '\n' + escape(alert.detail);
    }
    return new Map<String, Object>{
      'type' => 'section',
      'text' => new Map<String, Object>{ 'type' => 'mrkdwn', 'text' => cut(text) }
    };
  }

  private static Map<String, Object> context(String text) {
    return new Map<String, Object>{
      'type' => 'context',
      'elements' => new List<Object>{ new Map<String, Object>{ 'type' => 'mrkdwn', 'text' => cut(text) } }
    };
  }

  // The notification preview, and what clients that can't render blocks show.
  private static String fallbackText(List<Alert> alerts) {
    String first = '[' + alerts[0].severity.name() + '] ' + alerts[0].title;
    return cut(alerts.size() == 1 ? first : first + ' (+' + (alerts.size() - 1) + ' more)');
  }

  /**
   * @description Escapes the three characters Slack mrkdwn treats as control characters.
   * @param text The text; may be null.
   * @return The escaped text, or an empty string for null.
   */
  @TestVisible
  private static String escape(String text) {
    return text == null ? '' : text.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;');
  }

  private static String cut(String text) {
    return text.abbreviate(MAX_TEXT_LENGTH);
  }
}
