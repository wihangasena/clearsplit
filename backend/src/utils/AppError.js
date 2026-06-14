/**
 * Operational error carrying an HTTP status code. Thrown by routes/services and
 * translated to a JSON response by the central error handler.
 */
export class AppError extends Error {
  constructor(statusCode, message) {
    super(message);
    this.name = 'AppError';
    this.statusCode = statusCode;
  }
}
