/**
 * @description `IAlertSink` adapter that sends alerts to Slack (Adapter, ADR 0006). `send` makes no
 * callout: it enqueues one `SlackAlertJob` per call, so it works in triggers, in the
 * `Log_Event__e` subscriber, and after DML. One call becomes one Slack message.
 *
 * Ships inactive (D5): the `DI_Binding.Slack_Alert_Sink` row is off until an admin has set the
 * bot token and the channel and activates it. Until then `IAlertSink` resolves to A's
 * `NoOpAlertSink`.
 *
 * Never throws (the `IAlertSink` contract). With no channel set, with no Queueable left in the
 * transaction, or when the enqueue fails, it logs a WARN and drops the alerts.
 *
 * Limits: one Queueable per non-empty call; no SOQL beyond cached custom metadata, no DML.
 * @group Alerting
 */
public with sharing class SlackAlertSink implements IAlertSink {
  /**
   * @description Enqueues one job that posts the alerts as one message.
   * @param alerts The alerts; null, empty and null entries are ignored.
   */
  public void send(List<Alert> alerts) {
    List<Alert> toSend = withoutNulls(alerts);
    if (toSend.isEmpty()) {
      return;
    }
    String failure = enqueue(toSend);
    if (failure != null) {
      ILogger logger = (ILogger) Application.Service.newInstance(ILogger.class);
      logger.warn(SlackAlertJob.FAILURE_PREFIX + failure + ' ' + toSend.size() + ' alert(s) not sent.');
      logger.flush();
    }
  }

  // Returns null when a job was enqueued, or the reason it wasn't.
  private static String enqueue(List<Alert> alerts) {
    String channel = LoggingSettings.current().slackChannel;
    if (channel == null) {
      return 'no channel is set in Logging_Setting__mdt.Default.Slack_Channel__c.';
    }
    if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
      return 'this transaction has no Queueable jobs left.';
    }
    try {
      AlertJobEnqueuer.current().enqueue(new SlackAlertJob(alerts, channel), 0);
      return null;
    } catch (Exception enqueueFailure) {
      return 'the job could not be enqueued: ' + enqueueFailure.getMessage();
    }
  }

  private static List<Alert> withoutNulls(List<Alert> alerts) {
    List<Alert> kept = new List<Alert>();
    if (alerts != null) {
      for (Alert candidate : alerts) {
        if (candidate != null) {
          kept.add(candidate);
        }
      }
    }
    return kept;
  }
}
