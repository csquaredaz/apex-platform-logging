/**
 * @description Unit tests for `SlackMessageBuilder`: block layout, severity markers, mrkdwn
 * escaping, Slack's text limits and the 50-block cap (ADR 0006).
 */
@IsTest
private class SlackMessageBuilderTest {
  private static List<Object> blocksOf(Map<String, Object> payload) {
    return (List<Object>) payload.get('blocks');
  }

  private static String textOf(Object block) {
    Map<String, Object> fields = (Map<String, Object>) block;
    if (fields.get('type') == 'context') {
      Map<String, Object> element = (Map<String, Object>) ((List<Object>) fields.get('elements'))[0];
      return (String) element.get('text');
    }
    return (String) ((Map<String, Object>) fields.get('text')).get('text');
  }

  private static String typeOf(Object block) {
    return (String) ((Map<String, Object>) block).get('type');
  }

  @IsTest
  static void build_oneAlert_headerSectionAndContext() {
    Map<String, Object> payload = SlackMessageBuilder.build(AlertTestFixtures.alerts(1), AlertTestFixtures.CHANNEL);

    List<Object> blocks = blocksOf(payload);
    Assert.areEqual(AlertTestFixtures.CHANNEL, payload.get('channel'), 'Channel');
    Assert.areEqual(3, blocks.size(), 'Header, section, context');
    Assert.areEqual('header', typeOf(blocks[0]), 'Header first');
    Assert.areEqual('1 alert', textOf(blocks[0]), 'Singular count');
    Assert.areEqual(
      ':rotating_light: *CRITICAL* Shipment booking failed for order 1\nSystem.DmlException: Required field missing',
      textOf(blocks[1]),
      'Section carries severity, title and detail'
    );
    Assert.areEqual('Source: ShipmentService', textOf(blocks[2]), 'Context carries the source');
    Assert.areEqual('[CRITICAL] Shipment booking failed for order 1', payload.get('text'), 'Notification text');
    Assert.areEqual(false, payload.get('unfurl_links'), 'No link previews');
  }

  @IsTest
  static void build_eachSeverity_usesItsMarker() {
    List<Alert> alerts = new List<Alert>{
      new Alert(Alert.Severity.WARNING, 'Disk', null, null),
      new Alert(Alert.Severity.INFO, 'Deploy', null, null)
    };

    List<Object> blocks = blocksOf(SlackMessageBuilder.build(alerts, AlertTestFixtures.CHANNEL));

    Assert.areEqual(':warning: *WARNING* Disk', textOf(blocks[1]), 'Warning marker, no detail line');
    Assert.areEqual(':information_source: *INFO* Deploy', textOf(blocks[3]), 'Info marker');
    Assert.areEqual('Source: unknown', textOf(blocks[2]), 'A blank source is named');
    Assert.areEqual('2 alerts', textOf(blocks[0]), 'Plural count');
  }

  @IsTest
  static void build_markupInText_isEscaped() {
    Alert hostile = new Alert(Alert.Severity.CRITICAL, '<!channel> & <https://example.com|click>', '<@U123>', 'a<b');

    List<Object> blocks = blocksOf(SlackMessageBuilder.build(new List<Alert>{ hostile }, AlertTestFixtures.CHANNEL));

    Assert.areEqual(
      ':rotating_light: *CRITICAL* &lt;!channel&gt; &amp; &lt;https://example.com|click&gt;\n&lt;@U123&gt;',
      textOf(blocks[1]),
      'A log message cannot mention or link'
    );
    Assert.areEqual('Source: a&lt;b', textOf(blocks[2]), 'The source is escaped too');
  }

  @IsTest
  static void build_longDetail_isCutToSlackLimit() {
    Alert verbose = new Alert(Alert.Severity.CRITICAL, 'Long', 'x'.repeat(5000), 'y'.repeat(5000));

    List<Object> blocks = blocksOf(SlackMessageBuilder.build(new List<Alert>{ verbose }, AlertTestFixtures.CHANNEL));

    Assert.areEqual(SlackMessageBuilder.MAX_TEXT_LENGTH, textOf(blocks[1]).length(), 'Section cut at 3,000');
    Assert.isTrue(textOf(blocks[1]).endsWith('...'), 'The cut is marked');
    Assert.areEqual(SlackMessageBuilder.MAX_TEXT_LENGTH, textOf(blocks[2]).length(), 'Context cut at 3,000');
  }

  @IsTest
  static void build_24Alerts_fitWithoutOverflow() {
    List<Object> blocks = blocksOf(SlackMessageBuilder.build(AlertTestFixtures.alerts(24), AlertTestFixtures.CHANNEL));

    Assert.areEqual(SlackMessageBuilder.MAX_ALERTS_SHOWN, 24, 'Two blocks per alert after the header');
    Assert.areEqual(49, blocks.size(), 'All 24 alerts shown');
    Assert.isTrue(textOf(blocks[48]).startsWith('Source:'), 'No overflow block');
  }

  @IsTest
  static void build_25Alerts_capsAt50BlocksWithOverflowCount() {
    List<Object> blocks = blocksOf(SlackMessageBuilder.build(AlertTestFixtures.alerts(25), AlertTestFixtures.CHANNEL));

    Assert.areEqual(SlackMessageBuilder.MAX_BLOCKS, blocks.size(), 'Exactly the Slack cap');
    Assert.areEqual('+1 more alerts not shown. Every alert is in Log__c.', textOf(blocks[49]), 'Overflow count');
    Assert.areEqual('25 alerts', textOf(blocks[0]), 'The header counts every alert');
  }

  @IsTest
  static void build_200Alerts_staysAt50Blocks() {
    Map<String, Object> payload = SlackMessageBuilder.build(AlertTestFixtures.alerts(200), AlertTestFixtures.CHANNEL);

    Assert.areEqual(SlackMessageBuilder.MAX_BLOCKS, blocksOf(payload).size(), 'Bulk stays under the cap');
    Assert.isTrue(textOf(blocksOf(payload)[49]).startsWith('+176 more'), '200 - 24 left out');
    Assert.areEqual(
      '[CRITICAL] Shipment booking failed for order 1 (+199 more)',
      payload.get('text'),
      'Notification counts the rest'
    );
    Assert.isTrue(JSON.serialize(payload).contains('"type":"header"'), 'Serialises to Slack JSON');
  }

  @IsTest
  static void escape_null_returnsEmpty() {
    Assert.areEqual('', SlackMessageBuilder.escape(null), 'Null-safe');
  }
}
