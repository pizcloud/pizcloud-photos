/// An exception for the [ImageLoader] and the image providers
class ImageLoadingException implements Exception {
  final String message;
  const ImageLoadingException(this.message);
}
