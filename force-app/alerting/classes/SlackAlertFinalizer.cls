/**
 * @description Records the alerts a `SlackAlertJob` lost when it died with an uncaught exception
 * or a limit failure, which the job itself can't catch (D16, ADR 0006). It logs a WARN with the
 * cause and one WARN per lost alert, and doesn't retry: a failure that escaped the job is likely
 * to repeat, and could come after a successful post. The source entries are still in `Log__c`.
 *
 * WARN, never ERROR, so the record of a lost alert can't raise another alert (D15).
 * @group Alerting
 */
public with sharing class SlackAlertFinalizer implements Finalizer {
  private final List<Alert> alerts;

  /**
   * @description A finalizer for one job's alerts.
   * @param alerts The alerts the job was sending.
   */
  public SlackAlertFinalizer(List<Alert> alerts) {
    this.alerts = alerts;
  }

  /**
   * @description Logs the lost alerts when the job failed; does nothing when it succeeded.
   * @param context The finalizer context.
   */
  public void execute(FinalizerContext context) {
    if (context.getResult() != ParentJobResult.UNHANDLED_EXCEPTION) {
      return;
    }
    ILogger logger = (ILogger) Application.Service.newInstance(ILogger.class);
    try {
      Exception cause = context.getException();
      logger.warn(
        SlackAlertJob.FAILURE_PREFIX +
          'job ' +
          context.getAsyncApexJobId() +
          ' stopped with ' +
          (cause == null ? 'an unknown error' : cause.getTypeName() + ': ' + cause.getMessage()) +
          '. ' +
          alerts.size() +
          ' alert(s) not sent.'
      );
      for (Alert lost : alerts) {
        logger.warn('Unsent alert [' + lost.severity.name() + '] ' + lost.title);
      }
    } finally {
      logger.flush();
    }
  }
}
