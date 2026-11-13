/**
 * @description Posts one batch of alerts to Slack with `chat.postMessage` (ADR 0006). Enqueued by
 * `SlackAlertSink`, because `IAlertSink.send` can run where a callout isn't allowed, such as the
 * `Log_Event__e` subscriber. It runs as the user who enqueued it: the Automated Process user for
 * subscriber alerts, which needs the `Slack_Alert_Sender` permission set (R2).
 *
 * Outcomes:
 * - 200 with `ok: true`: done.
 * - 429 on the first attempt: one copy is re-enqueued, delayed by `Retry-After` rounded up to
 *   minutes (1 to 10). A 429 on the second attempt drops the batch with a WARN (D7).
 * - Anything else (`ok: false`, another status, a transport or credential failure): a WARN, no
 *   retry. Slack ignores idempotency keys, so a resent POST could post twice.
 * - An uncaught exception or a limit failure: `SlackAlertFinalizer` logs what was lost (D16).
 *
 * Loop guard (D15): every failure is logged at WARN, never ERROR. Only ERROR entries raise
 * alerts, so a failed delivery can't raise another alert.
 * @group Alerting
 */
public with sharing class SlackAlertJob implements Queueable, Database.AllowsCallouts {
  /** @description The Named Credential for the Slack Web API. */
  public static final String NAMED_CREDENTIAL = 'Slack';
  /** @description The Web API method. */
  public static final String PATH = '/chat.postMessage';
  /** @description Attempts per batch: the first, plus one after a 429. */
  public static final Integer MAX_ATTEMPTS = 2;
  /** @description Starts every failure WARN, so failures are easy to find in `Log__c`. */
  public static final String FAILURE_PREFIX = 'Slack alert delivery failed: ';

  private static final Integer HTTP_TOO_MANY_REQUESTS = 429;
  private static final Integer SECONDS_PER_MINUTE = 60;

  @TestVisible
  private final List<Alert> alerts;
  @TestVisible
  private final String channel;
  @TestVisible
  private final Integer attempt;

  /**
   * @description A first attempt.
   * @param alerts The alerts; at least one, none null.
   * @param channel The channel ID or name.
   */
  public SlackAlertJob(List<Alert> alerts, String channel) {
    this(alerts, channel, 1);
  }

  @TestVisible
  private SlackAlertJob(List<Alert> alerts, String channel, Integer attempt) {
    this.alerts = alerts;
    this.channel = channel;
    this.attempt = attempt;
  }

  /**
   * @description Attaches the finalizer, then delivers.
   * @param context The Queueable context.
   */
  public void execute(QueueableContext context) {
    System.attachFinalizer(new SlackAlertFinalizer(alerts));
    deliver();
  }

  /** @description Sends the message and logs any failure at WARN. Never throws a handled failure. */
  @TestVisible
  private void deliver() {
    ILogger logger = (ILogger) Application.Service.newInstance(ILogger.class);
    try {
      String failure = send(logger);
      if (failure != null) {
        logger.warn(FAILURE_PREFIX + failure + ' ' + alerts.size() + ' alert(s) not sent (attempt ' + attempt + ').');
      }
    } finally {
      logger.flush();
    }
  }

  // Returns null when the batch was posted or handed to a retry, or the reason it failed.
  private String send(ILogger logger) {
    CalloutResponse response;
    try {
      ICalloutClient client = (ICalloutClient) Application.Service.newInstance(ICalloutClient.class);
      response = client.send(
        CalloutRequest.post(NAMED_CREDENTIAL, PATH).withJsonBody(SlackMessageBuilder.build(alerts, channel))
      );
    } catch (CalloutClientException failed) {
      return failed.getMessage() +
        '. If the cause is credential access, assign the Slack_Alert_Sender permission set to the running ' +
        UserInfo.getUserType() +
        ' user.';
    }
    if (response.getStatusCode() == HTTP_TOO_MANY_REQUESTS) {
      return retryLater(response, logger);
    }
    if (!response.isSuccess()) {
      return 'HTTP ' + response.getStatusCode() + '.';
    }
    String slackError = slackError(response.getBody());
    return slackError == null ? null : 'Slack returned ' + slackError + '.';
  }

  private String retryLater(CalloutResponse response, ILogger logger) {
    if (attempt >= MAX_ATTEMPTS) {
      return 'rate limited (HTTP 429) again after a retry.';
    }
    Integer delay = delayMinutes(response.getRetryAfterSeconds());
    try {
      AlertJobEnqueuer.current().enqueue(new SlackAlertJob(alerts, channel, attempt + 1), delay);
    } catch (Exception enqueueFailure) {
      return 'rate limited (HTTP 429), and the retry could not be enqueued: ' + enqueueFailure.getMessage();
    }
    logger.warn(
      'Slack rate limited ' + alerts.size() + ' alert(s) (HTTP 429); retrying once in ' + delay + ' minute(s).'
    );
    return null;
  }

  /**
   * @description The retry delay: `Retry-After` rounded up to whole minutes, from 1 to 10.
   * @param retryAfterSeconds The header value, or null.
   * @return The delay in minutes.
   */
  @TestVisible
  private static Integer delayMinutes(Integer retryAfterSeconds) {
    if (retryAfterSeconds == null || retryAfterSeconds <= 0) {
      return 1;
    }
    Integer minutes = (Integer) Math.ceil(retryAfterSeconds / (Decimal) SECONDS_PER_MINUTE);
    return Math.max(1, Math.min(minutes, AlertJobEnqueuer.MAX_DELAY_MINUTES));
  }

  // Slack answers most errors with HTTP 200 and {"ok": false, "error": "<code>"}.
  private static String slackError(String body) {
    try {
      Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
      if (parsed.get('ok') == true) {
        return null;
      }
      return parsed.get('error') == null ? 'ok: false with no error code' : String.valueOf(parsed.get('error'));
    } catch (Exception unreadable) {
      return 'a response that is not Slack JSON';
    }
  }
}
