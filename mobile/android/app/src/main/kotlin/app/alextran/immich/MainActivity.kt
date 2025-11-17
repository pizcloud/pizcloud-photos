package app.alextran.immich

import android.content.Context
import android.os.Build
import android.os.ext.SdkExtensions
import app.alextran.immich.background.BackgroundEngineLock
import app.alextran.immich.background.BackgroundWorkerApiImpl
import app.alextran.immich.background.BackgroundWorkerFgHostApi
import app.alextran.immich.background.BackgroundWorkerLockApi
import app.alextran.immich.connectivity.ConnectivityApi
import app.alextran.immich.connectivity.ConnectivityApiImpl
import app.alextran.immich.core.ImmichPlugin
import app.alextran.immich.images.ThumbnailApi
import app.alextran.immich.images.ThumbnailsImpl
import app.alextran.immich.sync.NativeSyncApi
import app.alextran.immich.sync.NativeSyncApiImpl26
import app.alextran.immich.sync.NativeSyncApiImpl30
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import androidx.core.content.ContextCompat
import android.content.pm.PackageManager
import android.Manifest

class MainActivity : FlutterFragmentActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    //New
    MethodChannel(
      flutterEngine.dartExecutor.binaryMessenger,
      "app.perms"
    ).setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
      when (call.method) {
        "mediaPermissionState" -> result.success(mediaPermissionState(this))
        else -> result.notImplemented()
      }
    }

    registerPlugins(this, flutterEngine)
  }

  companion object {
    fun registerPlugins(ctx: Context, flutterEngine: FlutterEngine) {
      val messenger = flutterEngine.dartExecutor.binaryMessenger
      val backgroundEngineLockImpl = BackgroundEngineLock(ctx)
      BackgroundWorkerLockApi.setUp(messenger, backgroundEngineLockImpl)
      val nativeSyncApiImpl =
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R || SdkExtensions.getExtensionVersion(Build.VERSION_CODES.R) < 1) {
          NativeSyncApiImpl26(ctx)
        } else {
          NativeSyncApiImpl30(ctx)
        }
      NativeSyncApi.setUp(messenger, nativeSyncApiImpl)
      ThumbnailApi.setUp(messenger, ThumbnailsImpl(ctx))
      BackgroundWorkerFgHostApi.setUp(messenger, BackgroundWorkerApiImpl(ctx))
      ConnectivityApi.setUp(messenger, ConnectivityApiImpl(ctx))

      flutterEngine.plugins.add(BackgroundServicePlugin())
      flutterEngine.plugins.add(HttpSSLOptionsPlugin())
      flutterEngine.plugins.add(backgroundEngineLockImpl)
      flutterEngine.plugins.add(nativeSyncApiImpl)
    }

    fun cancelPlugins(flutterEngine: FlutterEngine) {
      val nativeApi =
        flutterEngine.plugins.get(NativeSyncApiImpl26::class.java) as ImmichPlugin?
          ?: flutterEngine.plugins.get(NativeSyncApiImpl30::class.java) as ImmichPlugin?
      nativeApi?.detachFromEngine()
    }
  }
}


private fun granted(ctx: Context, perm: String): Boolean {
  return ContextCompat.checkSelfPermission(ctx, perm) == PackageManager.PERMISSION_GRANTED
}

/**
 * Android 14+: FULL: READ_MEDIA_IMAGES + READ_MEDIA_VIDEO,
 *               LIMITED: READ_MEDIA_VISUAL_USER_SELECTED,
 *               NONE: nothing.
 * Android 13  : FULL: READ_MEDIA_IMAGES hoặc READ_MEDIA_VIDEO,
 *               NONE: nothing.
 * ≤ Android 12: LEGACY: READ_EXTERNAL_STORAGE, NONE: nothing.
 */
private fun mediaPermissionState(ctx: Context): String {
  return when {
    Build.VERSION.SDK_INT >= 34 -> {
      val full = granted(ctx, Manifest.permission.READ_MEDIA_IMAGES) &&
                 granted(ctx, Manifest.permission.READ_MEDIA_VIDEO)
      if (full) "FULL"
      else if (granted(ctx, "android.permission.READ_MEDIA_VISUAL_USER_SELECTED")) "LIMITED"
      else "NONE"
    }
    Build.VERSION.SDK_INT >= 33 -> {
      val any = granted(ctx, Manifest.permission.READ_MEDIA_IMAGES) ||
                granted(ctx, Manifest.permission.READ_MEDIA_VIDEO)
      if (any) "FULL" else "NONE"
    }
    else -> {
      if (granted(ctx, Manifest.permission.READ_EXTERNAL_STORAGE)) "LEGACY" else "NONE"
    }
  }
}