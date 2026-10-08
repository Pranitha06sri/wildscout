import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

abstract class PhotoCapture {
  Future<XFile?> pick(ImageSource source);
  Future<XFile?> recover();
}

class DevicePhotoCapture implements PhotoCapture {
  final ImagePicker _picker = ImagePicker();
  @override
  Future<XFile?> pick(ImageSource source) => _picker.pickImage(
    source: source,
    maxWidth: 1280,
    maxHeight: 1280,
    imageQuality: 85,
    requestFullMetadata: false,
  );
  @override
  Future<XFile?> recover() async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    final response = await _picker.retrieveLostData();
    if (response.exception != null) throw response.exception!;
    return response.files?.firstOrNull;
  }
}
