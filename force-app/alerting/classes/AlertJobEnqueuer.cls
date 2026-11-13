/**
 * @description Enqueues `SlackAlertJob`s. A seam over `System.enqueueJob`, so unit tests can
 * record what would be enqueued: a Queueable can't chain another in a test, and the 429 retry
 * is a delayed enqueue from inside the job.
 * @group Alerting
 */
public virtual with sharing class AlertJobEnqueuer {
  /** @description The longest delay `System.enqueueJob` accepts, in minutes. */
  public static final Integer MAX_DELAY_MINUTES = 10;

  @TestVisible
  private static AlertJobEnqueuer instance = new AlertJobEnqueuer();

  /**
   * @description The enqueuer in use.
   * @return The enqueuer; a recording subclass in unit tests.
   */
  public static AlertJobEnqueuer current() {
    return instance;
  }

  /**
   * @description Enqueues the job.
   * @param job The job.
   * @param delayMinutes 0 to run as soon as possible, up to `MAX_DELAY_MINUTES`.
   * @return The job Id.
   */
  public virtual Id enqueue(SlackAlertJob job, Integer delayMinutes) {
    return delayMinutes > 0 ? System.enqueueJob(job, delayMinutes) : System.enqueueJob(job);
  }
}
