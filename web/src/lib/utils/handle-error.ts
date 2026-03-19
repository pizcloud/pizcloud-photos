import { isHttpError } from '@immich/sdk';
import { toastManager } from '@immich/ui';

// pizcloud
type HandleErrorOptions = {
  preferServerMessage?: boolean;
};

type ServerErrorData = {
  statusCode?: number;
  message?: string;
  error?: string;
};

type DeleteErrorMessages = {
  fallback: string;
  demoAccountReadOnly: string;
  forbidden: string;
};

type UploadErrorMessages = {
  fallback: string;
  demoAccountReadOnly: string;
  forbidden: string;
};
// #pizcloud

function getServerErrorData(error: unknown): ServerErrorData | undefined { // pizcloud
  // pizcloud
  // if (!isHttpError(error)) {
  //   return;
  // }

  let data: unknown;
  let statusFromError: unknown;

  if (isHttpError(error)) {
    data = error.data;
    statusFromError = (error as { status?: unknown }).status;
  } else {
    // Support custom upload error from uploadRequest() -> ApiError(statusCode, details)
    const maybeApiError = error as { statusCode?: unknown; details?: unknown };
    if (typeof maybeApiError.statusCode !== 'number') {
      return;
    }

    data = maybeApiError.details;
    statusFromError = maybeApiError.statusCode;
    // #pizcloud
  }

  // errors for endpoints without return types aren't parsed as json
  if (typeof data === 'string') {
    try {
      data = JSON.parse(data);
    } catch {
      // Not a JSON string
    }
  }

  // pizcloud
  const statusFromData = (data as { statusCode?: unknown } | undefined)?.statusCode;
  const statusCode =
    typeof statusFromData === 'number'
      ? statusFromData
      : typeof statusFromError === 'number'
        ? statusFromError
        : undefined;

  const dataMessage = (data as { message?: unknown } | undefined)?.message;
  const dataError = (data as { error?: unknown } | undefined)?.error;
  const errorMessage = (error as { message?: unknown } | undefined)?.message;

  return {
    statusCode,
    message: typeof dataMessage === 'string' ? dataMessage : typeof errorMessage === 'string' ? errorMessage : undefined,
    error: typeof dataError === 'string' ? dataError : undefined,
  };
  // #pizcloud
}

// pizcloud
export function getServerErrorMessage(error: unknown) {
  return getServerErrorData(error)?.message;
}

export function getDeleteErrorMessage(error: unknown, messages: DeleteErrorMessages) {
  const serverErrorData = getServerErrorData(error);
  if (serverErrorData?.statusCode !== 403) {
    return { message: messages.fallback, preferServerMessage: true as const };
  }

  const errorMessage = serverErrorData.message?.toLowerCase() ?? '';
  const errorType = serverErrorData.error?.toLowerCase() ?? '';

  if (errorMessage.includes('demo account is read-only')) {
    return { message: messages.demoAccountReadOnly, preferServerMessage: false as const };
  }

  if (errorType === 'forbidden' || errorMessage.includes('forbidden')) {
    return { message: messages.forbidden, preferServerMessage: false as const };
  }

  return { message: messages.fallback, preferServerMessage: true as const };
}

export function getUploadErrorMessage(error: unknown, messages: UploadErrorMessages) {
  const serverErrorData = getServerErrorData(error);
  if (serverErrorData?.statusCode !== 403) {
    return { message: messages.fallback, preferServerMessage: true as const };
  }

  const errorMessage = serverErrorData.message?.toLowerCase() ?? '';
  const errorType = serverErrorData.error?.toLowerCase() ?? '';

  if (errorMessage.includes('demo account is read-only')) {
    return { message: messages.demoAccountReadOnly, preferServerMessage: false as const };
  }

  if (errorType === 'forbidden' || errorMessage.includes('forbidden')) {
    return { message: messages.forbidden, preferServerMessage: false as const };
  }

  return { message: messages.fallback, preferServerMessage: true as const };
}
// #pizcloud

export function handleError(error: unknown, message: string, options: HandleErrorOptions = {}) {
  if ((error as Error)?.name === 'AbortError') {
    return;
  }

  console.error(`[handleError]: ${message}`, error, (error as Error)?.stack);

  try {
    const { preferServerMessage = true } = options;

    // pizcloud: always prefer server message when available.
    // let serverMessage = getServerErrorMessage(error);
    let serverMessage = preferServerMessage ? getServerErrorMessage(error) : undefined;
    if (serverMessage) {
      serverMessage = `${String(serverMessage).slice(0, 75)}\n(Pizcloud Server Error)`;
    }

    const errorMessage = serverMessage || message;

    toastManager.danger(errorMessage);

    return errorMessage;
  } catch (error) {
    console.error(error);
    return message;
  }
}
