package app.alextran.immich.background

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.provider.MediaStore
import android.util.Log
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequest
import androidx.work.WorkManager
import io.flutter.embedding.engine.FlutterEngineCache
import kotlin.math.roundToLong
import java.util.concurrent.TimeUnit

private const val TAG = "BackgroundWorkerApiImpl"

class BackgroundWorkerApiImpl(context: Context) : BackgroundWorkerFgHostApi {
  private val ctx: Context = context.applicationContext

  override fun enable() {
    enqueueMediaObserver(ctx)
  }

  override fun saveNotificationMessage(title: String, body: String) {
    BackgroundWorkerPreferences(ctx).updateNotificationConfig(title, body)
  }

  override fun configure(settings: BackgroundWorkerSettings) {
    BackgroundWorkerPreferences(ctx).updateSettings(settings)
    enqueueMediaObserver(ctx)
  }

  override fun getPowerStatus(): PowerStatus {
    val statusIntent = ctx.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
    val batteryStatus = statusIntent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
    val isCharging =
      batteryStatus == BatteryManager.BATTERY_STATUS_CHARGING ||
      batteryStatus == BatteryManager.BATTERY_STATUS_FULL

    val level = statusIntent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
    val scale = statusIntent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
    val batteryLevelPercent =
      if (level >= 0 && scale > 0) ((level * 100.0) / scale).roundToLong() else null

    val powerManager = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
    val isLowPowerMode =
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
        powerManager.isPowerSaveMode
      } else {
        false
      }

    return PowerStatus(
      isCharging = isCharging,
      batteryLevelPercent = batteryLevelPercent,
      isLowPowerMode = isLowPowerMode,
    )
  }

  override fun disable() {
    WorkManager.getInstance(ctx).apply {
      cancelUniqueWork(OBSERVER_WORKER_NAME)
      cancelUniqueWork(BACKGROUND_WORKER_NAME)
    }
    Log.i(TAG, "Cancelled background upload tasks")
  }

  companion object {
    private const val BACKGROUND_WORKER_NAME = "immich/BackgroundWorkerV1"
    private const val OBSERVER_WORKER_NAME = "immich/MediaObserverV1"
    const val ENGINE_CACHE_KEY = "pizcloud::background_worker::engine"


    fun enqueueMediaObserver(ctx: Context) {
      val settings = BackgroundWorkerPreferences(ctx).getSettings()
      val constraints = Constraints.Builder().apply {
        addContentUriTrigger(MediaStore.Images.Media.INTERNAL_CONTENT_URI, true)
        addContentUriTrigger(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, true)
        addContentUriTrigger(MediaStore.Video.Media.INTERNAL_CONTENT_URI, true)
        addContentUriTrigger(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, true)
        setTriggerContentUpdateDelay(settings.minimumDelaySeconds, TimeUnit.SECONDS)
        setTriggerContentMaxDelay(settings.minimumDelaySeconds * 10, TimeUnit.SECONDS)
        setRequiresCharging(settings.requiresCharging)
      }.build()

      val work = OneTimeWorkRequest.Builder(MediaObserver::class.java)
        .setConstraints(constraints)
        .build()
      WorkManager.getInstance(ctx)
        .enqueueUniqueWork(OBSERVER_WORKER_NAME, ExistingWorkPolicy.REPLACE, work)

      Log.i(
        TAG,
        "Enqueued media observer worker with name: $OBSERVER_WORKER_NAME and settings: $settings"
      )
    }

    fun enqueueBackgroundWorker(ctx: Context) {
      val constraints = Constraints.Builder().setRequiresBatteryNotLow(true).build()

      val work = OneTimeWorkRequest.Builder(BackgroundWorker::class.java)
        .setConstraints(constraints)
        .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 1, TimeUnit.MINUTES)
        .build()
      WorkManager.getInstance(ctx)
        .enqueueUniqueWork(BACKGROUND_WORKER_NAME, ExistingWorkPolicy.KEEP, work)

      Log.i(TAG, "Enqueued background worker with name: $BACKGROUND_WORKER_NAME")
    }

    fun isBackgroundWorkerRunning(): Boolean {
      // Easier to check if the engine is cached as we always cache the engine when starting the worker
      // and remove it when the worker is finished
      return FlutterEngineCache.getInstance().get(ENGINE_CACHE_KEY) != null
    }

    fun cancelBackgroundWorker(ctx: Context) {
      WorkManager.getInstance(ctx).cancelUniqueWork(BACKGROUND_WORKER_NAME)
      FlutterEngineCache.getInstance().remove(ENGINE_CACHE_KEY)

      Log.i(TAG, "Cancelled background upload task")
    }
  }
}
