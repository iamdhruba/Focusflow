import 'package:dio/dio.dart';
import '../constants/api_constants.dart';
import '../storage/secure_storage.dart';

/// Singleton Dio HTTP client with:
/// - Automatic JWT Bearer token injection
/// - Token refresh on 401
/// - Centralized error handling
class ApiService {
  ApiService._internal();
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  late final Dio _dio;
  bool _initialized = false;

  /// Lazy-init guard. The first HTTP request triggers Dio creation if
  /// nobody called [init] explicitly. Keeps the singleton safe even if
  /// a future code path forgets the explicit init() — the symptom
  /// would otherwise be a `LateInitializationError: Field '_dio' has not
  /// been initialized` on first network call.
  void _ensureInitialized() {
    if (_initialized) return;
    init();
  }

  /// Must be called once at app startup after dotenv is loaded.
  void init() {
    if (_initialized) return;
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        connectTimeout: ApiConstants.connectTimeout,
        receiveTimeout: ApiConstants.receiveTimeout,
        headers: {'Content-Type': 'application/json'},
      ),
    );

    // ── Interceptors ──────────────────────────────────────────────────────────
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: _onRequest,
        onError: _onError,
      ),
    );
    _initialized = true;
  }

  // Inject access token into every request
  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await SecureStorage.getAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  // Auto-refresh on 401
  Future<void> _onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode == 401) {
      final refreshToken = await SecureStorage.getRefreshToken();
      if (refreshToken != null) {
        try {
          final response = await _dio.post(
            ApiConstants.refresh,
            data: {'refreshToken': refreshToken},
            options: Options(headers: {}), // Skip auth interceptor
          );
          final newToken = response.data['accessToken'] as String?;
          if (newToken != null) {
            await SecureStorage.saveAccessToken(newToken);
            // Retry original request
            err.requestOptions.headers['Authorization'] = 'Bearer $newToken';
            final retried = await _dio.fetch(err.requestOptions);
            return handler.resolve(retried);
          }
        } catch (_) {
          await SecureStorage.clearAll();
        }
      }
    }
    handler.next(err);
  }

  Dio get dio => _dio;

  // ── Convenience Methods ────────────────────────────────────────────────────

  Future<Response> get(String path, {Map<String, dynamic>? params}) {
    _ensureInitialized();
    return _dio.get(path, queryParameters: params);
  }

  Future<Response> post(String path, {dynamic data}) {
    _ensureInitialized();
    return _dio.post(path, data: data);
  }

  Future<Response> patch(String path, {dynamic data}) {
    _ensureInitialized();
    return _dio.patch(path, data: data);
  }

  Future<Response> put(String path, {dynamic data}) {
    _ensureInitialized();
    return _dio.put(path, data: data);
  }

  Future<Response> delete(String path) {
    _ensureInitialized();
    return _dio.delete(path);
  }

  /// Parse Dio errors into readable messages
  static String parseError(dynamic error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['message'] != null) {
        return data['message'].toString();
      }
      switch (error.type) {
        // Bug C copy fix (Nov 2025): the previous wording ("Check your
        // internet connection") blamed the user even when the issue was
        // a sleeping Render backend, a corporate firewall, or — most
        // commonly — a missing android.permission.INTERNET on the app.
        // The new messages acknowledge the more likely real cause (the
        // cloud service itself is starting up) and surface a retry
        // instruction instead of pointing fingers.
        case DioExceptionType.connectionTimeout:
          return 'Could not reach the FocusFlow cloud in time. Try again in a moment.';
        case DioExceptionType.receiveTimeout:
          return 'The server took too long to respond — it may be starting up. Try again shortly.';
        case DioExceptionType.connectionError:
          return 'Can\'t reach the FocusFlow cloud. The server may be waking up or your network may be blocking it. Try again in a few seconds.';
        default:
          return error.message ?? 'An unexpected error occurred.';
      }
    }
    return error.toString();
  }
}
