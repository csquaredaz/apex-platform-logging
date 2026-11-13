/**
 * @description Test data for the alerting tests: alerts, Slack responses, a recording enqueuer, a
 * finalizer context and an HTTP mock. No real Slack workspace, token or URL is used anywhere.
 * @group Testing
 */
@IsTest
public class AlertTestFixtures {
  /** @description The channel the tests post to; a made-up channel ID. */
  public static final String CHANNEL = 'C0TEST00001';

  /**
   * @description Critical alerts numbered from 1.
   * @param count The number of alerts.
   * @return `count` alerts titled `Shipment booking failed for order <n>`.
   */
  public static List<Alert> alerts(Integer count) {
    List<Alert> alerts = new List<Alert>();
    for (Integer i = 1; i <= count; i++) {
      alerts.add(
        new Alert(
          Alert.Severity.CRITICAL,
          'Shipment booking failed for order ' + i,
          'System.DmlException: Required field missing',
          'ShipmentService'
        )
      );
    }
    return alerts;
  }

  /**
   * @description Settings with a Slack channel.
   * @param channel The channel, or null.
   * @return An in-memory settings row.
   */
  public static Logging_Setting__mdt settingsWithChannel(String channel) {
    Logging_Setting__mdt row = LoggerTestFixtures.settings('DEBUG', 50);
    row.Slack_Channel__c = channel;
    return row;
  }

  /**
   * @description A Slack Web API response as `CalloutClient` returns it.
   * @param statusCode The HTTP status.
   * @param body The body.
   * @param retryAfter The `Retry-After` header, or null.
   * @return The response.
   */
  public static CalloutResponse response(Integer statusCode, String body, String retryAfter) {
    HttpResponse raw = new HttpResponse();
    raw.setStatusCode(statusCode);
    raw.setBody(body);
    if (retryAfter != null) {
      raw.setHeader('Retry-After', retryAfter);
    }
    return new CalloutResponse(raw, 1, 'test-correlation-id');
  }

  /** @description Records the jobs it would enqueue instead of enqueuing them. */
  public class RecordingEnqueuer extends AlertJobEnqueuer {
    /** @description The jobs, in order. */
    public final List<SlackAlertJob> jobs = new List<SlackAlertJob>();
    /** @description The delay of each job, in minutes. */
    public final List<Integer> delays = new List<Integer>();
    /** @description When set, `enqueue` throws it. */
    public Exception failure;

    /**
     * @description Records the job, or throws `failure`.
     * @param job The job.
     * @param delayMinutes The delay.
     * @return Null; nothing is enqueued.
     */
    public override Id enqueue(SlackAlertJob job, Integer delayMinutes) {
      if (failure != null) {
        throw failure;
      }
      jobs.add(job);
      delays.add(delayMinutes);
      return null;
    }
  }

  /**
   * @description Installs a recording enqueuer.
   * @return The enqueuer.
   */
  public static RecordingEnqueuer recordEnqueues() {
    RecordingEnqueuer enqueuer = new RecordingEnqueuer();
    AlertJobEnqueuer.instance = enqueuer;
    return enqueuer;
  }

  /**
   * @description Installs a `RecordingLogger` as the `ILogger` binding.
   * @return The logger.
   */
  public static RecordingLogger recordLogs() {
    RecordingLogger logger = new RecordingLogger();
    Application.Service.setMock(ILogger.class, logger);
    return logger;
  }

  /** @description A finalizer context with a chosen result. */
  public class FakeFinalizerContext implements FinalizerContext {
    private final ParentJobResult result;
    private final Exception failure;

    /**
     * @description A context.
     * @param result The parent job's result.
     * @param failure The parent job's exception, or null.
     */
    public FakeFinalizerContext(ParentJobResult result, Exception failure) {
      this.result = result;
      this.failure = failure;
    }

    /** @description @return A fake job Id. */
    public Id getAsyncApexJobId() {
      return FakeId.generate(AsyncApexJob.SObjectType);
    }

    /** @description @return The exception. */
    public Exception getException() {
      return failure;
    }

    /** @description @return A fake request Id. */
    public String getRequestId() {
      return 'test-request-id';
    }

    /** @description @return The result. */
    public ParentJobResult getResult() {
      return result;
    }
  }

  /** @description Answers every callout with one response and records the requests. */
  public class SlackHttpMock implements HttpCalloutMock {
    private final Integer statusCode;
    private final String body;
    /** @description The requests received, in order. */
    public final List<HttpRequest> requests = new List<HttpRequest>();

    /**
     * @description A mock.
     * @param statusCode The status to answer with.
     * @param body The body to answer with.
     */
    public SlackHttpMock(Integer statusCode, String body) {
      this.statusCode = statusCode;
      this.body = body;
    }

    /**
     * @description Records the request and answers it.
     * @param request The request.
     * @return The response.
     */
    public HttpResponse respond(HttpRequest request) {
      requests.add(request);
      HttpResponse response = new HttpResponse();
      response.setStatusCode(statusCode);
      response.setHeader('Content-Type', 'application/json');
      response.setBody(body);
      return response;
    }
  }
}
